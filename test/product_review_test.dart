import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/product_review.dart';

void main() {
  group('reviewCharCount (same count as submitProductReview)', () {
    test('trims and counts code points', () {
      expect(reviewCharCount('  abc  '), 3);
      expect(reviewCharCount('ভালো'), 4); // ভ া ল ো
      expect(reviewCharCount('👍'), 1);
      expect(reviewCharCount('ক' * 1000), kReviewCommentMaxChars);
    });
  });

  group('reviewRewardFrom', () {
    test('settings/app.reviewReward, else 2', () {
      expect(reviewRewardFrom(null), 2);
      expect(reviewRewardFrom(5), 5);
      expect(reviewRewardFrom('3'), 3);
      expect(reviewRewardFrom(0), 0);
      expect(reviewRewardFrom(-1), 2);
      expect(reviewRewardFrom('x'), 2);
    });
  });

  group('orderMakesVerifiedBuyer', () {
    final item = {'productId': 'p1', 'name': 'Case'};
    test('delivered / received / completed with the productId', () {
      expect(orderMakesVerifiedBuyer({'status': 'Delivered', 'items': [item]}, 'p1'), isTrue);
      expect(orderMakesVerifiedBuyer({'status': 'completed', 'items': [item]}, 'p1'), isTrue);
    });
    test('not pending, not by name', () {
      expect(orderMakesVerifiedBuyer({'status': 'pending', 'items': [item]}, 'p1'), isFalse);
      expect(
        orderMakesVerifiedBuyer({
          'status': 'delivered',
          'items': [
            {'productId': 'other', 'name': 'Case'}
          ]
        }, 'p1'),
        isFalse,
      );
    });
  });

  group('reviewResultMessage', () {
    test('rewarded, daily limit, edited', () {
      expect(reviewResultMessage({'created': true, 'rewarded': 2, 'reason': 'rewarded'}), contains('৳2'));
      expect(reviewResultMessage({'created': true, 'rewarded': 0, 'reason': 'daily_limit'}), contains('5 reviews today'));
      expect(reviewResultMessage({'created': false, 'rewarded': 0, 'reason': 'edited'}), 'Review updated.');
      expect(reviewResultMessage({'created': true, 'rewarded': 0, 'reason': 'already_rewarded_for_product'}),
          'Review submitted.');
    });
  });

  group('referrals', () {
    test('status in any letter case', () {
      expect(referralStatusOf('Pending'), 'pending');
      expect(referralStatusOf('APPROVED'), 'approved');
      expect(referralStatusOf(null), 'pending');
    });
    test('referee id from referredUserId, else refereeId', () {
      expect(referralRefereeId({'referredUserId': 'u2', 'refereeId': 'old'}), 'u2');
      expect(referralRefereeId({'refereeId': 'u3'}), 'u3');
      expect(referralRefereeId({}), '');
    });
    test('who may decide: wallet.edit or super admin, not a plain admin', () {
      expect(canDecideReferralsFor({'role': 'superAdmin'}), isTrue);
      expect(canDecideReferralsFor({'role': 'staff', 'permissions': ['wallet.edit']}), isTrue);
      expect(canDecideReferralsFor({'role': 'staff', 'permissions': {'wallet.edit': true}}), isTrue);
      expect(canDecideReferralsFor({'role': 'admin'}), isFalse);
      expect(canDecideReferralsFor({'role': 'superAdmin', 'isBanned': true}), isFalse);
      expect(canDecideReferralsFor(null), isFalse);
    });
    test('Approve is off for a deleted referrer / referee, and while loading', () {
      expect(referralApproveBlockReason(usersLoaded: true, referrerMissing: false, refereeMissing: false), isNull);
      expect(referralApproveBlockReason(usersLoaded: false, referrerMissing: false, refereeMissing: false), isNotNull);
      expect(referralApproveBlockReason(usersLoaded: true, referrerMissing: true, refereeMissing: false), contains('referrer মুছে গেছে'));
      expect(referralApproveBlockReason(usersLoaded: true, referrerMissing: false, refereeMissing: true), contains('referee মুছে গেছে'));
      expect(referralApproveBlockReason(usersLoaded: true, referrerMissing: true, refereeMissing: true), contains('দুজনেই'));
    });
    test('Bengali error messages', () {
      expect(referralErrorMessageBn('user_missing'), contains('user আর নেই'));
      expect(referralErrorMessageBn('permission'), contains('wallet.edit'));
      expect(referralErrorMessageBn('whatever'), contains('আবার চেষ্টা'));
    });
  });
}
