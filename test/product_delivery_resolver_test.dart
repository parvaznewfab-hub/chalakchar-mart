import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/product_delivery_resolver.dart';

void main() {
  group('ProductDeliveryResolver.resolve', () {
    // Fixed reference date so day-count tiers are deterministic. Noon avoids
    // any DST edge when adding whole days.
    final fixedNow = DateTime(2026, 12, 20, 12);

    test('no delivery fields at all returns none', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{});
      expect(result.hasEstimate, false);
    });

    test('deliveryMinDays/deliveryMaxDays produce a labeled estimate range', () {
      // 10–20 days from 20 Dec 2026 spans a month and a year end.
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryMinDays': 10,
        'deliveryMaxDays': 20,
      }, now: fixedNow);
      expect(result.hasEstimate, true);
      expect(result.isEstimateRange, true);
      expect(result.days, 20);
      expect(result.date, DateTime(2027, 1, 9, 12));
      // Min (30 Dec) has no year; max carries it. The label is the only
      // place the min date is exposed, so this pins both ends.
      expect(result.displayText, '30 Dec–9 Jan 2027');
      // isEstimateRange communicates the "estimate" label; callers prefix
      // the sentence themselves (see product_details_page.dart).
      expect(result.displayText, isNot(contains('Estimated delivery')));
    });

    test('equal min and max day range collapses to a single date, no dash', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryMinDays': 15,
        'deliveryMaxDays': 15,
      }, now: fixedNow);
      expect(result.isEstimateRange, true);
      expect(result.date, DateTime(2027, 1, 4, 12));
      expect(result.displayText, '4 Jan 2027');
    });

    test('estimatedDeliveryDate (exact) takes priority over a day range', () {
      final exactDate = DateTime.now().add(const Duration(days: 5));
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryDate': Timestamp.fromDate(exactDate),
        'deliveryMinDays': 10,
        'deliveryMaxDays': 20,
      });
      expect(result.isEstimateRange, false);
      expect(result.displayText, ProductDeliveryResolver.formatShortDate(exactDate));
    });

    test('day range takes priority over the old estimatedDeliveryMaxDate tier', () {
      final oldMaxDate = DateTime.now().add(const Duration(days: 30));
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryMaxDate': Timestamp.fromDate(oldMaxDate),
        'deliveryMinDays': 10,
        'deliveryMaxDays': 20,
      });
      expect(result.isEstimateRange, true);
    });

    test('estimatedDeliveryText is used verbatim when no dates/range exist', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryText': 'Delivery: Aug. 12 (estimated)',
      });
      expect(result.hasEstimate, true);
      expect(result.isEstimateRange, false);
      expect(result.displayText, 'Delivery: Aug. 12 (estimated)');
    });

    test('plain deliveryDays fallback still works for non-AliExpress products', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryDays': 7,
      }, now: fixedNow);
      expect(result.hasEstimate, true);
      expect(result.isEstimateRange, false);
      expect(result.days, 7);
      expect(result.date, DateTime(2026, 12, 27, 12));
      expect(result.displayText, '27 Dec 2026');
    });

    test('deliveryMinDays without deliveryMaxDays does not trigger the range tier', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryMinDays': 10,
        'deliveryDays': 7,
      });
      expect(result.isEstimateRange, false);
      expect(result.days, 7);
    });

    test('Firestore Timestamp, ISO string, and epoch int are all handled for estimatedDeliveryDate', () {
      final date = DateTime.utc(2026, 8, 12);

      final fromTimestamp = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryDate': Timestamp.fromDate(date),
      });
      final fromIso = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryDate': date.toIso8601String(),
      });
      final fromEpochMs = ProductDeliveryResolver.resolve(<String, dynamic>{
        'estimatedDeliveryDate': date.millisecondsSinceEpoch,
      });

      expect(fromTimestamp.displayText, '12 Aug 2026');
      expect(fromIso.displayText, '12 Aug 2026');
      expect(fromEpochMs.displayText, '12 Aug 2026');
    });
  });
}
