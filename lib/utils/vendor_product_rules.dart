// Step H2: what the vendor's product save may write, mirroring
// firestore.rules (vendorProductCreateOk / vendorProductEditOk). The rules
// decide; this only builds payloads the rules accept and explains a refusal.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Rules: vendorImagesOk (at most 8) and vendorVariantsOk (at most 12).
const int kVendorMaxImages = 8;
const int kVendorMaxVariants = 12;

/// Changing any of these sends an approved product back to "pending"
/// (rules: vendorProductReviewKeys).
const List<String> kVendorReviewFields = [
  'name', 'category', 'categoryId', 'overview', 'image', 'imageUrl', 'images',
];

String _s(dynamic v) => (v ?? '').toString().trim();

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const <String>[];

/// True when [next] changes a field that needs a new admin review.
bool vendorReviewFieldsChanged(Map<String, dynamic> before, Map<String, dynamic> next) {
  for (final k in kVendorReviewFields) {
    if (!next.containsKey(k)) continue;
    if (k == 'images') {
      if (!listEquals(_strings(before['images']), _strings(next['images']))) return true;
    } else if (_s(before[k]) != _s(next[k])) {
      return true;
    }
  }
  return false;
}

/// A variant as the rules allow it: name / price / mrp / stock only.
Map<String, dynamic> vendorVariant({
  required String name,
  required double price,
  required double mrp,
  required int stock,
}) =>
    {'name': name.isEmpty ? 'Default' : name, 'price': price, 'mrp': mrp, 'stock': stock};

/// The update payload for the vendor's own product. [content] holds the
/// editable fields (name, category, categoryId, overview, image, imageUrl,
/// images, variants, price, piecePrice, oldPrice, mrp, unit, stock,
/// vendorName, shopName). [wantActive] is the vendor's show / hide choice.
///
/// - approved and nothing review-worthy changed: stays approved, the
///   vendor's show / hide choice applies;
/// - a review field changed: back to "pending" and hidden;
/// - not approved: stays hidden (only an admin publishes).
Map<String, dynamic> vendorProductUpdate({
  required Map<String, dynamic> before,
  required Map<String, dynamic> content,
  required bool wantActive,
}) {
  final status = _s(before['approvalStatus']).toLowerCase();
  final review = vendorReviewFieldsChanged(before, content);
  final out = <String, dynamic>{...content, 'updatedAt': FieldValue.serverTimestamp()};
  if (review) {
    out['approvalStatus'] = 'pending';
    out['isActive'] = false;
    out['isVisible'] = false;
  } else if (status == 'approved') {
    out['isActive'] = wantActive;
    out['isVisible'] = wantActive;
  } else {
    out['isActive'] = false;
    out['isVisible'] = false;
  }
  return out;
}

/// Bengali message for a failed vendor product save / toggle.
String vendorProductErrorBn(Object error) {
  final code = error is FirebaseException ? error.code : '';
  if (code == 'permission-denied') {
    return 'এই বদলের অনুমতি নেই। পণ্য অনুমোদন বা প্রকাশ শুধু admin করেন; '
        'ছবি শুধু নিজের দোকানের ফোল্ডার থেকে দেওয়া যায়; '
        'দোকান অনুমোদিত ও চালু না থাকলে পণ্য যোগ বা বদল করা যায় না।';
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return 'সংযোগ পাওয়া যাচ্ছে না। একটু পরে আবার চেষ্টা করুন।';
  }
  return 'পণ্য save করা গেল না। আবার চেষ্টা করুন।';
}
