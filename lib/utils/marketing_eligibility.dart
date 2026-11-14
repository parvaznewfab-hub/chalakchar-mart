/// Why [product] must not be marketed, or null when it may be.
///
/// Mirrors functions/marketing/eligibility.js (marketingBlockReason). The
/// server re-checks this before dispatching any marketing_outbox item, so
/// this copy only gives the admin an immediate, clear error.
/// A missing approvalStatus counts as approved (legacy hand-made products).
String? marketingBlockReason(Map<String, dynamic>? product) {
  if (product == null) return 'product_missing';
  if (product['needsReview'] == true) return 'needs_review';
  final approval =
      (product['approvalStatus'] ?? '').toString().trim().toLowerCase();
  if ((approval.isEmpty ? 'approved' : approval) != 'approved') {
    return 'not_approved';
  }
  if (product['isActive'] == false ||
      product['isVisible'] == false ||
      product['isPublished'] == false) {
    return 'not_live';
  }
  return null;
}
