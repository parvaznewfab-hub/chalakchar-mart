// 14b step H: small pure helpers for product reviews and admin referral
// decisions. The rules and the amounts are enforced by the Cloud Functions
// (functions/reviews, functions/referrals); these only shape the UI.

/// Same limit as submitProductReview (Unicode code points after trimming).
const int kReviewCommentMaxChars = 1000;

/// Order statuses that make a verified buyer (same list as the function).
const List<String> kReviewOrderStatuses = ['delivered', 'received', 'completed'];

/// Characters as the function counts them: code points, so a Bengali letter
/// and its vowel sign are two, an emoji is one.
int reviewCharCount(String text) => text.trim().runes.length;

/// settings/app.reviewReward; 2 when missing or not a number >= 0.
double reviewRewardFrom(dynamic value) {
  final n = value is num ? value.toDouble() : double.tryParse('${value ?? ''}'.trim());
  if (n == null || n.isNaN || n.isInfinite || n < 0) return 2;
  return n;
}

/// Client-side check, only to decide whether to show the "Write review"
/// button. The function checks again on the server.
bool orderMakesVerifiedBuyer(Map<String, dynamic> order, String productId) {
  final status = '${order['status'] ?? ''}'.trim().toLowerCase();
  if (!kReviewOrderStatuses.contains(status)) return false;
  final items = order['items'];
  if (items is! List) return false;
  return items.any((item) => item is Map && '${item['productId'] ?? ''}'.trim() == productId);
}

/// Message for a successful submitProductReview result.
String reviewResultMessage(Map<String, dynamic> result) {
  final created = result['created'] == true;
  final rewarded = result['rewarded'] is num ? (result['rewarded'] as num).toDouble() : 0.0;
  final reason = '${result['reason'] ?? ''}';
  if (!created) return 'Review updated.';
  if (rewarded > 0) {
    return 'Review submitted! ৳${rewarded.toStringAsFixed(0)} ChalakChar Cash added.';
  }
  if (reason == 'daily_limit') {
    return 'Review submitted. You already got Cash for 5 reviews today, so no Cash for this one.';
  }
  return 'Review submitted.';
}

/// Message for a failed review call (reason from the function's details).
String reviewErrorMessage(String? reason) {
  switch (reason) {
    case 'login':
      return 'Please login first.';
    case 'not_buyer':
      return 'Only buyers who received this product can review it.';
    case 'bad_rating':
      return 'Please choose 1 to 5 stars.';
    case 'comment_too_long':
      return 'Review is too long (max $kReviewCommentMaxChars characters).';
    case 'no_product':
      return 'This product is no longer available.';
    case 'blocked':
      return 'Your account is blocked.';
    case 'permission':
      return 'Only an admin can delete reviews.';
    default:
      return 'Review could not be saved now. Please try again.';
  }
}

/// Referral status in one form: pending / approved / rejected.
String referralStatusOf(dynamic value) {
  final s = '${value ?? ''}'.trim().toLowerCase();
  return s.isEmpty ? 'pending' : s;
}

/// The referred user's id: referredUserId (function), else refereeId (old docs).
String referralRefereeId(Map<String, dynamic> data) {
  final a = '${data['referredUserId'] ?? ''}'.trim();
  return a.isNotEmpty ? a : '${data['refereeId'] ?? ''}'.trim();
}

/// Same check as approveReferral / rejectReferral: wallet.edit (list or map)
/// or super admin, and not blocked. A plain admin is not enough.
bool canDecideReferralsFor(Map<String, dynamic>? user) {
  if (user == null) return false;
  if (user['isActive'] == false || user['isBanned'] == true) return false;
  const supers = ['superAdmin', 'super_admin'];
  final roles = user['roles'] is List ? (user['roles'] as List).map((e) => '$e') : const <String>[];
  if (supers.contains('${user['role']}') || roles.any(supers.contains)) return true;
  final granted = user['permissions'];
  if (granted is List) return granted.map((e) => '$e').contains('wallet.edit');
  if (granted is Map) return granted['wallet.edit'] == true;
  return false;
}

/// Why Approve is off on a referral card, or null when it may be pressed.
/// [usersLoaded]: the two user docs have been read (an error while reading
/// counts as loaded; approveReferral checks again on the server).
/// Reject is never blocked by this.
String? referralApproveBlockReason({
  required bool usersLoaded,
  required bool referrerMissing,
  required bool refereeMissing,
}) {
  if (!usersLoaded) return 'user-এর তথ্য দেখা হচ্ছে…';
  if (referrerMissing && refereeMissing) {
    return 'referrer আর referee দুজনেই মুছে গেছে, তাই অনুমোদন করা যাবে না। বাতিল করতে পারেন।';
  }
  if (referrerMissing) return 'referrer মুছে গেছে, তাই অনুমোদন করা যাবে না। বাতিল করতে পারেন।';
  if (refereeMissing) return 'referee মুছে গেছে, তাই অনুমোদন করা যাবে না। বাতিল করতে পারেন।';
  return null;
}

/// Bengali message for a failed approveReferral / rejectReferral call.
String referralErrorMessageBn(String? reason) {
  switch (reason) {
    case 'permission':
      return 'এই কাজের অনুমতি আপনার নেই (wallet.edit বা super admin লাগবে)।';
    case 'login':
      return 'আবার লগইন করুন।';
    case 'already_approved':
      return 'এই referral আগেই অনুমোদিত হয়েছে।';
    case 'already_rejected':
      return 'এই referral আগেই বাতিল হয়েছে।';
    case 'user_missing':
      return 'এই referral-এর একজন user আর নেই, তাই অনুমোদন করা যায় না। চাইলে বাতিল করুন।';
    case 'self':
      return 'নিজের referral নিজে অনুমোদন করা যায় না।';
    case 'not_found':
      return 'referral-টা খুঁজে পাওয়া যায়নি।';
    case 'bad_referral':
      return 'referral-এ user-এর id ঠিক নেই।';
    default:
      return 'এখন করা গেল না। একটু পরে আবার চেষ্টা করুন।';
  }
}
