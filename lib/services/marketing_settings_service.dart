import 'package:cloud_firestore/cloud_firestore.dart';

/// Enterprise-ready marketing settings reader for ChalakChar Mart.
///
/// This service reads settings/app and normalizes:
/// - socialLinks
/// - socialApi
/// - marketingDefaults
///
/// It is safe for mobile, desktop and web.
/// UI should not call social APIs directly. Tokens are only stored/read here for
/// configuration awareness; Cloud Functions should do real API posting.
class MarketingSettings {
  final bool enabled;
  final bool pushNotification;
  final bool inAppNotification;
  final bool facebook;
  final bool instagram;
  final bool whatsapp;
  final bool messenger;
  final bool tiktok;

  final String audience;
  final String publishTime;
  final String captionTemplate;

  final Map<String, dynamic> socialApi;
  final Map<String, dynamic> socialLinks;

  const MarketingSettings({
    required this.enabled,
    required this.pushNotification,
    required this.inAppNotification,
    required this.facebook,
    required this.instagram,
    required this.whatsapp,
    required this.messenger,
    required this.tiktok,
    required this.audience,
    required this.publishTime,
    required this.captionTemplate,
    required this.socialApi,
    required this.socialLinks,
  });

  factory MarketingSettings.defaults() {
    return const MarketingSettings(
      enabled: true,
      pushNotification: true,
      inAppNotification: true,
      facebook: false,
      instagram: false,
      whatsapp: false,
      messenger: false,
      tiktok: false,
      audience: 'everyone',
      publishTime: 'immediately',
      captionTemplate: '🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}',
      socialApi: {},
      socialLinks: {},
    );
  }

  factory MarketingSettings.fromAppSettings(Map<String, dynamic> data) {
    final marketingDefaults = _map(data['marketingDefaults']);
    final socialApi = _map(data['socialApi']);
    final socialLinks = _map(data['socialLinks']);

    return MarketingSettings(
      enabled: _bool(marketingDefaults['enabled'] ?? data['autoMarketingEnabled'], true),
      pushNotification: _bool(marketingDefaults['pushNotification'] ?? data['defaultPushMarketing'], true),
      inAppNotification: _bool(marketingDefaults['inAppNotification'] ?? data['defaultInAppMarketing'], true),
      facebook: _bool(marketingDefaults['facebook'] ?? data['defaultFacebookQueue'], false),
      instagram: _bool(marketingDefaults['instagram'] ?? data['defaultInstagramQueue'], false),
      whatsapp: _bool(marketingDefaults['whatsapp'] ?? data['defaultWhatsappQueue'], false),
      messenger: _bool(marketingDefaults['messenger'] ?? data['defaultMessengerQueue'], false),
      tiktok: _bool(marketingDefaults['tiktok'] ?? data['defaultTiktokQueue'], false),
      audience: _text(marketingDefaults['audience'] ?? data['defaultMarketingAudience'], 'everyone'),
      publishTime: _text(marketingDefaults['publishTime'] ?? data['defaultMarketingPublishTime'], 'immediately'),
      captionTemplate: _text(
        marketingDefaults['captionTemplate'] ?? data['defaultMarketingCaption'],
        '🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}',
      ),
      socialApi: socialApi,
      socialLinks: socialLinks,
    );
  }

  Map<String, bool> defaultChannels() {
    return {
      'fcm': pushNotification,
      'push': pushNotification,
      'inApp': inAppNotification,
      'facebook': facebook,
      'instagram': instagram,
      'whatsapp': whatsapp,
      'messenger': messenger,
      'tiktok': tiktok,
    };
  }

  bool get hasFacebookApi =>
      _text(socialApi['facebookPageId']).isNotEmpty &&
      _text(socialApi['facebookPageAccessToken']).isNotEmpty;

  bool get hasInstagramApi =>
      _text(socialApi['instagramBusinessId']).isNotEmpty &&
      _text(socialApi['instagramAccessToken']).isNotEmpty;

  bool get hasWhatsappApi =>
      _text(socialApi['whatsappPhoneNumberId']).isNotEmpty &&
      _text(socialApi['whatsappAccessToken']).isNotEmpty;

  bool get hasMessengerApi =>
      _text(socialApi['messengerPageAccessToken']).isNotEmpty ||
      _text(socialApi['facebookPageAccessToken']).isNotEmpty;

  bool get hasTiktokApi =>
      _text(socialApi['tiktokClientKey']).isNotEmpty &&
      _text(socialApi['tiktokClientSecret']).isNotEmpty;

  Map<String, bool> apiStatus() {
    return {
      'facebook': hasFacebookApi,
      'instagram': hasInstagramApi,
      'whatsapp': hasWhatsappApi,
      'messenger': hasMessengerApi,
      'tiktok': hasTiktokApi,
    };
  }

  static String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}

class MarketingSettingsService {
  MarketingSettingsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static MarketingSettings? _cache;
  static DateTime? _cacheAt;

  static const Duration cacheDuration = Duration(minutes: 3);

  static Future<MarketingSettings> load({bool forceRefresh = false}) async {
    final now = DateTime.now();

    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < cacheDuration) {
      return _cache!;
    }

    try {
      final doc = await _db.collection('settings').doc('app').get();
      final settings = doc.exists
          ? MarketingSettings.fromAppSettings(doc.data() ?? {})
          : MarketingSettings.defaults();

      _cache = settings;
      _cacheAt = now;
      return settings;
    } catch (_) {
      return _cache ?? MarketingSettings.defaults();
    }
  }

  static void clearCache() {
    _cache = null;
    _cacheAt = null;
  }

  static Future<Map<String, dynamic>> rawAppSettings() async {
    final doc = await _db.collection('settings').doc('app').get();
    return doc.data() ?? <String, dynamic>{};
  }
}
