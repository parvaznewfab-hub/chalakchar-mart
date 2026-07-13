import 'package:cloud_firestore/cloud_firestore.dart';

/// Campaign analytics writer/reader.
///
/// This service is intentionally lightweight on Flutter side. Heavy analytics
/// aggregation should be handled by Cloud Functions.
class CampaignAnalyticsService {
  CampaignAnalyticsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> trackEvent({
    required String campaignId,
    required String eventType,
    String productId = '',
    String userId = '',
    Map<String, dynamic> data = const {},
  }) async {
    final cleanCampaignId = campaignId.trim();
    final cleanEventType = eventType.trim();

    if (cleanCampaignId.isEmpty || cleanEventType.isEmpty) return;

    await _db.collection('campaign_analytics').add({
      'campaignId': cleanCampaignId,
      'productId': productId.trim(),
      'userId': userId.trim(),
      'eventType': cleanEventType,
      'data': data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchCampaignEvents({
    String? campaignId,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('campaign_analytics');

    if (campaignId != null && campaignId.trim().isNotEmpty) {
      query = query.where('campaignId', isEqualTo: campaignId.trim());
    }

    return query.orderBy('createdAt', descending: true).limit(limit).snapshots();
  }
}
