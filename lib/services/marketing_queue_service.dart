import 'package:cloud_firestore/cloud_firestore.dart';

import 'marketing_settings_service.dart';

/// Central marketing queue service.
///
/// Compatible with both signatures:
///
/// Preferred:
/// await MarketingQueueService.enqueueProduct(
///   productId: id,
///   productData: payload,
///   settings: settings,
/// );
///
/// Also supported:
/// await MarketingQueueService.enqueueProduct(
///   productId: id,
///   product: payload,
///   channels: {...},
/// );
class MarketingQueueService {
  MarketingQueueService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static double _double(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static String _firstImage(Map<String, dynamic> product) {
    final images = product['images'];
    if (images is List) {
      for (final item in images) {
        final url = _text(item);
        if (url.startsWith('http')) return url;
      }
    }

    final image = _text(product['imageUrl'] ?? product['image']);
    return image.startsWith('http') ? image : '';
  }

  static String _price(Map<String, dynamic> product) {
    final direct = _double(product['price'] ?? product['piecePrice']);
    if (direct > 0) return direct.toStringAsFixed(0);

    final variants = product['variants'];
    if (variants is List && variants.isNotEmpty && variants.first is Map) {
      final first = Map<String, dynamic>.from(variants.first as Map);
      final price = _double(first['price'] ?? first['piecePrice']);
      if (price > 0) return price.toStringAsFixed(0);
    }

    return '';
  }

  static String _applyTemplate(
    String template,
    Map<String, dynamic> product,
    String productId,
  ) {
    final name = _text(product['name'] ?? product['title'], 'Product');
    final price = _price(product);
    final category = _text(product['category']);
    final productUrl = 'https://chalakcharmart.com/product/$productId';

    return template
        .replaceAll('{productName}', name)
        .replaceAll('{name}', name)
        .replaceAll('{price}', price)
        .replaceAll('{category}', category)
        .replaceAll('{productUrl}', productUrl);
  }

  static Map<String, bool> _normalizeChannels(
    Map<String, dynamic>? raw,
    MarketingSettings settings,
  ) {
    final defaults = settings.defaultChannels();
    if (raw == null || raw.isEmpty) return defaults;

    bool getBool(String key, bool fallback) {
      final value = raw[key];
      if (value == null) return fallback;
      if (value is bool) return value;
      final text = value.toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
      return fallback;
    }

    return {
      'fcm': getBool('fcm', defaults['fcm'] ?? true),
      'push': getBool('push', defaults['push'] ?? defaults['fcm'] ?? true),
      'inApp': getBool('inApp', defaults['inApp'] ?? true),
      'facebook': getBool('facebook', defaults['facebook'] ?? false),
      'instagram': getBool('instagram', defaults['instagram'] ?? false),
      'whatsapp': getBool('whatsapp', defaults['whatsapp'] ?? false),
      'messenger': getBool('messenger', defaults['messenger'] ?? false),
      'tiktok': getBool('tiktok', defaults['tiktok'] ?? false),
    };
  }

  static bool _hasSocial(Map<String, bool> channels) {
    return channels['facebook'] == true ||
        channels['instagram'] == true ||
        channels['whatsapp'] == true ||
        channels['messenger'] == true ||
        channels['tiktok'] == true;
  }

  static bool _hasAnyConfiguredSocialApi(
    MarketingSettings settings,
    Map<String, bool> channels,
  ) {
    if (channels['facebook'] == true && settings.hasFacebookApi) return true;
    if (channels['instagram'] == true && settings.hasInstagramApi) return true;
    if (channels['whatsapp'] == true && settings.hasWhatsappApi) return true;
    if (channels['messenger'] == true && settings.hasMessengerApi) return true;
    if (channels['tiktok'] == true && settings.hasTiktokApi) return true;
    return false;
  }

  static String _initialStatus({
    required String publishMode,
    required DateTime? scheduledAt,
    required Map<String, bool> channels,
    required MarketingSettings settings,
  }) {
    final normalizedPublishMode = publishMode.trim().toLowerCase();

    if (normalizedPublishMode == 'schedule' ||
        normalizedPublishMode == 'scheduled' ||
        scheduledAt != null) {
      return 'scheduled';
    }

    if (!_hasSocial(channels)) return 'fcm_inapp_ready';

    return _hasAnyConfiguredSocialApi(settings, channels)
        ? 'pending'
        : 'pending_social_api_credentials';
  }

  static Future<String> enqueueProduct({
    required String productId,

    /// Preferred parameter.
    Map<String, dynamic>? productData,

    /// Backward/alternate compatible parameter.
    Map<String, dynamic>? product,

    MarketingSettings? settings,
    Map<String, dynamic>? channels,
    String? audience,
    String? publishMode,
    DateTime? scheduledAt,
    String reason = 'new_product',
    String source = 'app',
    String? caption,
    bool merge = true,
  }) async {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) {
      throw Exception('productId is required for marketing queue');
    }

    final resolvedProduct = Map<String, dynamic>.from(productData ?? product ?? {});
    if (resolvedProduct.isEmpty) {
      throw Exception('productData/product is required for marketing queue');
    }

    final resolvedSettings = settings ?? await MarketingSettingsService.load();

    if (!resolvedSettings.enabled) {
      await _db.collection('marketing_logs').add({
        'type': 'product_marketing_queue_skipped',
        'productId': cleanProductId,
        'status': 'skipped',
        'reason': 'marketing_disabled_from_app_settings',
        'source': source,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return cleanProductId;
    }

    final resolvedChannels = _normalizeChannels(channels, resolvedSettings);
    final resolvedAudience = _text(audience, resolvedSettings.audience);
    final resolvedPublishMode = _text(
      publishMode,
      resolvedSettings.publishTime == 'immediately'
          ? 'now'
          : resolvedSettings.publishTime,
    );

    final productName = _text(
      resolvedProduct['name'] ?? resolvedProduct['title'],
      'Product',
    );

    final productUrl = 'https://chalakcharmart.com/product/$cleanProductId';
    final imageUrl = _firstImage(resolvedProduct);
    final price = _price(resolvedProduct);
    final category = _text(resolvedProduct['category']);

    final fallbackCaption = _applyTemplate(
      resolvedSettings.captionTemplate,
      resolvedProduct,
      cleanProductId,
    );

    final finalCaption = _text(
      caption,
      _text(
        resolvedProduct['marketingCaption'] ??
            resolvedProduct['facebookCaption'] ??
            resolvedProduct['whatsappCaption'],
        fallbackCaption,
      ),
    );

    final status = _initialStatus(
      publishMode: resolvedPublishMode,
      scheduledAt: scheduledAt,
      channels: resolvedChannels,
      settings: resolvedSettings,
    );

    final docRef = _db.collection('marketing_outbox').doc(cleanProductId);

    final payload = {
      'productId': cleanProductId,
      'productName': productName,
      'category': category,
      'imageUrl': imageUrl,
      'productUrl': productUrl,
      'price': price,
      'reason': reason,
      'audience': resolvedAudience,
      'publishMode': resolvedPublishMode,
      'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt),
      'channels': resolvedChannels,
      'captions': {
        'facebook': finalCaption,
        'instagram': finalCaption,
        'whatsapp': _text(resolvedProduct['whatsappCaption'], finalCaption),
        'messenger': _text(resolvedProduct['whatsappCaption'], finalCaption),
        'tiktok': finalCaption,
        'metaTitle': _text(resolvedProduct['metaTitle']),
        'metaDescription': _text(resolvedProduct['metaDescription']),
      },
      'status': status,
      'source': source,
      'apiStatus': resolvedSettings.apiStatus(),
      'retryCount': 0,
      'maxRetries': 3,
      'lastError': '',
      'lastApi': '',
      'note': _hasSocial(resolvedChannels)
          ? 'Queued from app. Cloud Functions should process social API channels.'
          : 'Push/In-App marketing queue created.',
      'updatedAt': FieldValue.serverTimestamp(),
      if (!merge) 'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set({
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: merge));

    await _db.collection('marketing_logs').add({
      'type': 'product_marketing_queue_created',
      'productId': cleanProductId,
      'productName': productName,
      'status': status,
      'channels': resolvedChannels,
      'audience': resolvedAudience,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return cleanProductId;
  }

  static Future<void> requestRetry(String queueId) async {
    final id = queueId.trim();
    if (id.isEmpty) return;

    await _db.collection('marketing_outbox').doc(id).set({
      'status': 'retry_requested',
      'retryRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> cancel(String queueId, {String reason = 'cancelled_by_admin'}) async {
    final id = queueId.trim();
    if (id.isEmpty) return;

    await _db.collection('marketing_outbox').doc(id).set({
      'status': 'cancelled',
      'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
