import 'package:chalakchar_mart/utils/chalakchar_cash.dart';
import 'package:chalakchar_mart/widgets/cash_check_warning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashSettingsFrom (same as functions/cash/cashCheck.js)', () {
    test('defaults: on, 100 per order', () {
      final s = cashSettingsFrom({});
      expect(s.enabled, isTrue);
      expect(s.maxPerOrder, 100);
    });
    test('enableAbdCash false switches it off; enableChalakCharCash wins', () {
      expect(cashSettingsFrom({'enableAbdCash': false}).enabled, isFalse);
      expect(cashSettingsFrom({'enableChalakCharCash': true, 'enableAbdCash': false}).enabled, isTrue);
      expect(cashSettingsFrom({'maxAbdCashRedeem': '50'}).maxPerOrder, 50);
      expect(cashSettingsFrom({'maxAbdCashRedeem': -3}).maxPerOrder, 0);
    });
  });

  group('usableCash', () {
    double u(double points, {double sub = 200, double coupon = 0, bool on = true, double max = 100}) =>
        usableCash(points: points, subtotal: sub, couponDiscount: coupon, enabled: on, maxPerOrder: max);
    test('smallest of points, limit and goods value', () {
      expect(u(50), 50);
      expect(u(500), 100);
      expect(u(500, sub: 80), 80);
      expect(u(500, sub: 80, coupon: 30), 50);
    });
    test('off or nothing left: 0', () {
      expect(u(500, on: false), 0);
      expect(u(0), 0);
      expect(u(500, sub: 20, coupon: 50), 0);
    });
  });

  group('cashCheckIssues (admin order card)', () {
    test('nothing for a passed or missing check', () {
      expect(cashCheckIssues(null).isEmpty, isTrue);
      expect(cashCheckIssues({'ok': true, 'totalOk': true}).isEmpty, isTrue);
    });
    test('total mismatch: both amounts, the exact owner wording', () {
      final i = cashCheckIssues({'ok': true, 'totalOk': false, 'clientGrandTotal': 70, 'serverGrandTotal': 160});
      expect(i.totalMessage, 'মোট দাম মেলে না: customer ৳70, হিসাবে ৳160। rider পাঠানোর আগে দেখুন।');
      expect(i.cashMessage, isNull);
    });
    test('Cash not taken: why', () {
      final i = cashCheckIssues({'ok': false, 'totalOk': true, 'claimed': 80, 'available': 50, 'reason': 'not_enough_points'});
      expect(i.cashMessage, contains('৳80'));
      expect(i.cashMessage, contains('৳50'));
      expect(cashCheckIssues({'ok': false, 'reason': 'over_limit', 'maxPerOrder': 100, 'claimed': 150}).cashMessage, contains('সর্বোচ্চ ৳100'));
    });
  });
}
