import 'package:chalakchar_mart/utils/marketing_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors functions/test/marketingSafety.test.js ("marketing eligibility").
void main() {
  test('needsReview / not approved / not live are blocked', () {
    expect(
      marketingBlockReason({'isActive': true, 'approvalStatus': 'approved', 'needsReview': true}),
      'needs_review',
    );
    expect(marketingBlockReason({'approvalStatus': 'draft'}), 'not_approved');
    expect(marketingBlockReason({'isActive': false}), 'not_live');
    expect(marketingBlockReason(null), 'product_missing');
  });

  test('reviewed, approved, live (or legacy without approvalStatus) may be marketed', () {
    expect(
      marketingBlockReason({'isActive': true, 'approvalStatus': 'approved', 'needsReview': false}),
      isNull,
    );
    expect(marketingBlockReason({'name': 'Vim 500ml'}), isNull);
  });
}
