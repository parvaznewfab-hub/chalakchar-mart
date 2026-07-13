import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

/// The only 6 states the admin UI is allowed to render. Nothing outside this
/// enum — never a raw token, never a raw TikTok API status string.
enum TikTokConnectionStatus {
  notConnected,
  connecting,
  connected,
  tokenExpiring,
  authorizationRevoked,
  reconnectRequired,
}

class TikTokConnectionInfo {
  final TikTokConnectionStatus status;
  final String? connectionId;
  final DateTime? lastConnectedAt;

  const TikTokConnectionInfo({
    required this.status,
    this.connectionId,
    this.lastConnectedAt,
  });

  static const notConnected = TikTokConnectionInfo(status: TikTokConnectionStatus.notConnected);

  bool get isActionable => status == TikTokConnectionStatus.connected ||
      status == TikTokConnectionStatus.tokenExpiring ||
      status == TikTokConnectionStatus.authorizationRevoked ||
      status == TikTokConnectionStatus.reconnectRequired;
}

/// Talks only to: the tiktokOAuthStart / tiktokDisconnect callables, the
/// public (non-secret) fields on settings/app, and the sanitized
/// tiktok_connection_status projection. Never reads tiktok_connections,
/// tiktok_oauth_states, or tiktok_publish_jobs directly — Firestore rules
/// deny those to every client regardless, this class simply never tries.
class TikTokConnectionService {
  TikTokConnectionService._();
  static final TikTokConnectionService instance = TikTokConnectionService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final StreamController<TikTokConnectionInfo> _controller = StreamController<TikTokConnectionInfo>.broadcast();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  String? _watchedConnectionId;
  bool _manualConnecting = false;

  Stream<TikTokConnectionInfo> watchStatus() {
    _settingsSub ??= _firestore
        .collection('settings')
        .doc('app')
        .snapshots()
        .listen(_onSettingsSnapshot, onError: (_) {});
    return _controller.stream;
  }

  void _onSettingsSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final socialApiRaw = snap.data()?['socialApi'];
    final socialApi = socialApiRaw is Map ? socialApiRaw.cast<String, dynamic>() : <String, dynamic>{};
    final selectedId = (socialApi['selectedTikTokConnectionId'] as String?)?.trim();

    if (selectedId == null || selectedId.isEmpty) {
      _statusSub?.cancel();
      _statusSub = null;
      _watchedConnectionId = null;
      if (!_manualConnecting) {
        _controller.add(TikTokConnectionInfo.notConnected);
      }
      return;
    }

    if (selectedId != _watchedConnectionId) {
      _watchedConnectionId = selectedId;
      _statusSub?.cancel();
      _statusSub = _firestore
          .collection('tiktok_connection_status')
          .doc(selectedId)
          .snapshots()
          .listen((doc) => _onStatusSnapshot(selectedId, doc), onError: (_) {});
    }
  }

  void _onStatusSnapshot(String connectionId, DocumentSnapshot<Map<String, dynamic>> doc) {
    _manualConnecting = false;

    if (!doc.exists) {
      _controller.add(TikTokConnectionInfo.notConnected);
      return;
    }

    final data = doc.data() ?? <String, dynamic>{};
    final status = _parseStatus(data['connectionStatus'] as String?);
    final lastConnectedAtTs = data['lastConnectedAt'];
    final lastConnectedAt = lastConnectedAtTs is Timestamp ? lastConnectedAtTs.toDate() : null;

    _controller.add(TikTokConnectionInfo(
      status: status,
      connectionId: connectionId,
      lastConnectedAt: lastConnectedAt,
    ));
  }

  TikTokConnectionStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'connected':
        return TikTokConnectionStatus.connected;
      case 'token_expiring':
        return TikTokConnectionStatus.tokenExpiring;
      case 'authorization_revoked':
        return TikTokConnectionStatus.authorizationRevoked;
      case 'reconnect_required':
        return TikTokConnectionStatus.reconnectRequired;
      default:
        return TikTokConnectionStatus.notConnected;
    }
  }

  /// One-time re-read, for a manual "refresh" affordance in the UI. The live
  /// stream already updates automatically; this exists so the admin has an
  /// explicit way to force a check rather than only relying on the listener.
  Future<void> refreshNow() async {
    final settingsDoc = await _firestore.collection('settings').doc('app').get();
    _onSettingsSnapshot(settingsDoc);

    final connectionId = _watchedConnectionId;
    if (connectionId != null) {
      final statusDoc = await _firestore.collection('tiktok_connection_status').doc(connectionId).get();
      _onStatusSnapshot(connectionId, statusDoc);
    }
  }

  /// Read-only setup guidance: the backend's fixed, allowlisted OAuth
  /// callback URL, for display only. This is never editable from Flutter and
  /// never influences which URL the backend actually redirects to — that is
  /// a deploy-time server config (see functions/tiktok/config.js).
  Future<({String redirectUri, bool clientKeyConfigured})> fetchOAuthConfig() async {
    final result = await _functions.httpsCallable('tiktokGetOAuthConfig').call();
    final data = result.data;
    final map = data is Map ? data : const {};
    return (
      redirectUri: (map['redirectUri'] as String?) ?? '',
      clientKeyConfigured: (map['clientKeyConfigured'] as bool?) ?? false,
    );
  }

  /// Calls the backend for a TikTok authorize URL and opens it externally.
  /// The URL is constructed entirely server-side (functions/tiktok/oauth.js)
  /// — this method never builds a TikTok URL itself and never sees a client
  /// secret, access token, or authorization code.
  Future<void> startConnect() async {
    _manualConnecting = true;
    _controller.add(const TikTokConnectionInfo(status: TikTokConnectionStatus.connecting));

    try {
      final result = await _functions.httpsCallable('tiktokOAuthStart').call();
      final data = result.data;
      final authorizeUrl = data is Map ? data['authorizeUrl'] as String? : null;

      if (authorizeUrl == null || authorizeUrl.isEmpty) {
        throw Exception('No authorize URL returned.');
      }

      final uri = Uri.parse(authorizeUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('Could not open the TikTok authorization page.');
      }
    } catch (_) {
      _manualConnecting = false;
      rethrow;
    }
  }

  Future<void> disconnect({String? connectionId}) async {
    await _functions.httpsCallable('tiktokDisconnect').call(<String, dynamic>{
      if (connectionId != null) 'connectionId': connectionId,
    });
  }
}
