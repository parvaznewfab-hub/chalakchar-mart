import 'package:cloud_firestore/cloud_firestore.dart';

/// UI-side placeholder for future social API dispatcher status.
///
/// Real Facebook/Instagram/WhatsApp/TikTok posting should run from Cloud
/// Functions, not from Flutter, because API tokens must stay server-side.
class SocialDispatcherService {
  SocialDispatcherService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> markReadyForServerProcessing(String queueId) async {
    final id = queueId.trim();
    if (id.isEmpty) return;

    await _db.collection('marketing_outbox').doc(id).set({
      'status': 'pending',
      'serverProcessingRequested': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> markManualReview(String queueId) async {
    final id = queueId.trim();
    if (id.isEmpty) return;

    await _db.collection('marketing_outbox').doc(id).set({
      'status': 'manual_review',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
