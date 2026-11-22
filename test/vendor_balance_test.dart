import 'package:chalakchar_mart/utils/vendor_balance.dart';
import 'package:chalakchar_mart/widgets/price_check_warning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VendorBalance (vendor_private only)', () {
    test('available = withdrawable minus pending requests, never below 0', () {
      final b = VendorBalance.from({'withdrawableBalance': 500, 'pendingBalance': 90, 'totalSales': 1000},
          requested: 200);
      expect(b.available, 300);
      expect(b.pendingOrders, 90);
      expect(b.canWithdraw, isTrue);
      expect(VendorBalance.from({'withdrawableBalance': 100}, requested: 150).available, 0);
      expect(VendorBalance.from({'withdrawableBalance': 100}, requested: 150).canWithdraw, isFalse);
    });

    test('debt: negative withdrawable, no withdraw', () {
      final b = VendorBalance.from({'withdrawableBalance': -90});
      expect(b.inDebt, isTrue);
      expect(b.available, 0);
      expect(b.canWithdraw, isFalse);
    });

    test('zero or missing: nothing to withdraw', () {
      expect(VendorBalance.from(null).canWithdraw, isFalse);
      expect(VendorBalance.from({'withdrawableBalance': 0}).canWithdraw, isFalse);
    });

    test('pending request total counts only pending', () {
      expect(
        pendingRequestTotal([
          {'status': 'pending', 'amount': 100},
          {'status': 'paid', 'amount': 50},
          {'status': 'PENDING', 'amount': '25'},
          {'status': 'rejected', 'amount': 10},
        ]),
        125,
      );
    });

    test('payout check: blocked at <= 0, when it does not cover the amount, or a bad amount', () {
      expect(payoutBlockedReason(withdrawable: 500, amount: 200), isNull);
      expect(payoutBlockedReason(withdrawable: 200, amount: 200), isNull);
      expect(payoutBlockedReason(withdrawable: 0, amount: 10), contains('no withdrawable'));
      expect(payoutBlockedReason(withdrawable: -90, amount: 10), contains('owes'));
      expect(payoutBlockedReason(withdrawable: 100, amount: 150), contains('more than'));
      expect(payoutBlockedReason(withdrawable: 100, amount: 0), isNotNull);
    });
  });

  group('priceCheck warning', () {
    test('only a failed check warns; missing (older orders) or ok: nothing', () {
      expect(priceCheckIssue(null), isNull);
      expect(priceCheckIssue({'ok': true, 'clientTotal': 1, 'serverTotal': 1}), isNull);
      final issue = priceCheckIssue({
        'ok': false,
        'clientTotal': 3,
        'serverTotal': 300,
        'mismatchedItems': [
          {'index': 0}
        ],
      })!;
      expect(issue.clientTotal, 3);
      expect(issue.serverTotal, 300);
      expect(issue.mismatchedItems, 1);
    });
  });
}
