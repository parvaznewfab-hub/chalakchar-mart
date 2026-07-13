import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TikTokPublishJob {
  final String jobId;
  final String productId;
  final String mediaType;
  final String status;
  final DateTime? createdAt;

  const TikTokPublishJob({
    required this.jobId,
    required this.productId,
    required this.mediaType,
    required this.status,
    this.createdAt,
  });

  factory TikTokPublishJob.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAtRaw = data['createdAt'];
    return TikTokPublishJob(
      jobId: doc.id,
      productId: (data['productId'] as String?) ?? '',
      mediaType: (data['mediaType'] as String?) ?? 'photo',
      status: (data['status'] as String?) ?? '',
      createdAt: createdAtRaw is Timestamp ? createdAtRaw.toDate() : null,
    );
  }
}

/// Review metadata only — see functions/tiktok/creatorInfo.js for exactly
/// which fields the backend is willing to return. Never a token.
class TikTokCreatorInfo {
  final String displayName;
  final String avatarUrl;
  final List<String> privacyLevelOptions;
  final bool commentDisabled;
  final bool duetDisabled;
  final bool stitchDisabled;
  final int? maxVideoPostDurationSec;
  final String mediaType;
  final bool auditRestricted;

  const TikTokCreatorInfo({
    required this.displayName,
    required this.avatarUrl,
    required this.privacyLevelOptions,
    required this.commentDisabled,
    required this.duetDisabled,
    required this.stitchDisabled,
    required this.maxVideoPostDurationSec,
    required this.mediaType,
    required this.auditRestricted,
  });

  factory TikTokCreatorInfo.fromMap(Map<dynamic, dynamic> map) {
    return TikTokCreatorInfo(
      displayName: (map['displayName'] as String?) ?? '',
      avatarUrl: (map['avatarUrl'] as String?) ?? '',
      privacyLevelOptions: (map['privacyLevelOptions'] as List?)?.cast<String>() ?? const [],
      commentDisabled: (map['commentDisabled'] as bool?) ?? false,
      duetDisabled: (map['duetDisabled'] as bool?) ?? false,
      stitchDisabled: (map['stitchDisabled'] as bool?) ?? false,
      maxVideoPostDurationSec: (map['maxVideoPostDurationSec'] as num?)?.toInt(),
      mediaType: (map['mediaType'] as String?) ?? 'photo',
      auditRestricted: (map['auditRestricted'] as bool?) ?? true,
    );
  }
}

/// Everything here is either a read of already admin-gated Firestore data
/// (tiktok_publish_jobs, marketing_outbox — both covered by existing rules)
/// or a callable that itself re-verifies admin auth server-side. Nothing in
/// this class ever constructs a TikTok API call directly.
class TikTokPublishService {
  TikTokPublishService._();
  static final TikTokPublishService instance = TikTokPublishService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<TikTokPublishJob>> watchPendingReviewJobs() {
    return _firestore
        .collection('tiktok_publish_jobs')
        .where('status', isEqualTo: 'pending_creator_review')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(TikTokPublishJob.fromDoc).toList());
  }

  /// Display only — the prepared caption/media for a product, straight from
  /// the existing marketing_outbox. Not sent back to the server on confirm;
  /// tiktokConfirmPublish reloads this itself.
  Future<Map<String, dynamic>?> loadOutboxPreview(String productId) async {
    final doc = await _firestore.collection('marketing_outbox').doc(productId).get();
    return doc.data();
  }

  /// Always a fresh network call — never cached, never reused as
  /// authorization for a later confirmPublish call.
  Future<TikTokCreatorInfo> fetchCreatorInfo(String jobId) async {
    final result = await _functions.httpsCallable('tiktokGetCreatorInfo').call(<String, dynamic>{'jobId': jobId});
    final data = result.data;
    return TikTokCreatorInfo.fromMap(data is Map ? data : const {});
  }

  /// Sends only identifiers + the admin's manual choices. Caption, media URL,
  /// product ownership, connectionId, and job state are never sent — the
  /// backend reloads all of that itself.
  Future<Map<String, dynamic>> confirmPublish({
    required String jobId,
    required String privacyLevel,
    required bool allowComment,
    required bool allowDuet,
    required bool allowStitch,
  }) async {
    final result = await _functions.httpsCallable('tiktokConfirmPublish').call(<String, dynamic>{
      'jobId': jobId,
      'privacyLevel': privacyLevel,
      'allowComment': allowComment,
      'allowDuet': allowDuet,
      'allowStitch': allowStitch,
    });
    final data = result.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> forceRepublish(String productId) async {
    await _functions.httpsCallable('tiktokForceRepublish').call(<String, dynamic>{'productId': productId});
  }
}
