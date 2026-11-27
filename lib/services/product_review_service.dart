import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/product_review.dart';

/// 14b step H: reviews and admin referral decisions go through Cloud
/// Functions only (the rules allow the client to read reviews, nothing more).
class ProductReviewService {
  ProductReviewService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'asia-south1');
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The caller's own review of [productId], or null.
  static Future<Map<String, dynamic>?> myReview(String productId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || productId.isEmpty) return null;
    final doc = await _db.collection('products').doc(productId).collection('reviews').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  /// Only to show or hide the "Write review" button; the function decides.
  static Future<bool> looksLikeVerifiedBuyer(String productId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || productId.isEmpty) return false;
    final orders = await _db.collection('orders').where('userId', isEqualTo: uid).get();
    return orders.docs.any((o) => orderMakesVerifiedBuyer(o.data(), productId));
  }

  /// Create or edit the caller's review. Returns the function's result
  /// ({created, rewarded, reason}); throws [ReviewCallError].
  static Future<Map<String, dynamic>> submit({
    required String productId,
    required int rating,
    required String comment,
  }) async {
    final data = await _call('submitProductReview', {
      'productId': productId,
      'rating': rating,
      'comment': comment.trim(),
    });
    return data;
  }

  /// Admin only (the function checks).
  static Future<void> delete({required String productId, required String userId}) async {
    await _call('deleteProductReview', {'productId': productId, 'userId': userId});
  }

  static Future<void> approveReferral(String referralId) async {
    await _call('approveReferral', {'referralId': referralId});
  }

  static Future<void> rejectReferral(String referralId) async {
    await _call('rejectReferral', {'referralId': referralId});
  }

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final result = await _functions.httpsCallable(name).call<dynamic>(data);
      final value = result.data;
      return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? '${details['reason'] ?? ''}' : '';
      throw ReviewCallError(reason.isEmpty ? e.code : reason, e.message);
    } catch (e) {
      throw ReviewCallError('internal', '$e');
    }
  }
}

class ReviewCallError implements Exception {
  final String reason;
  final String? message;
  const ReviewCallError(this.reason, [this.message]);

  @override
  String toString() => 'ReviewCallError($reason${message == null ? '' : ': $message'})';
}
