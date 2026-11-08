import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/product_delivery_resolver.dart';

void main() {
  group('ProductDeliveryResolver.resolve', () {
    test('no delivery fields at all returns none', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{});
      expect(result.hasEstimate, false);
    });

    test('deliveryMinDays/deliveryMaxDays produce a labeled estimate range', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryMinDays': 10,
        'deliveryMaxDays': 20,
      });
      expect(result.hasEstimate, true);
      expect(result.isEstimateRange, true);
      expect(result.days, 20);

      final now = DateTime.now();
      final expectedMin = now.add(const Duration(days: 10));
      final expectedMax = now.add(const Duration(days: 20));
      expect(result.date!.day, expectedMax.day);
      expect(result.displayText, contains('–'));
      expect(
        result.displayText,
        contains(ProductDeliveryResolver.formatShortDate(expectedMax)),
      );
      expect(result.displayText, isNot(contains('Estimated delivery')));
      // isEstimateRange communicates the "estimate" label; callers prefix
      // the sentence themselves (see product_details_page.dart).
      expect(expectedMin.day <= expectedMax.day, true);
    });

    test('equal min and max day range collapses to a single date, no dash', () {
      final result = ProductDeliveryResolver.resolve(<String, dynamic>{
        'deliveryMinDays': 15,
        'deliveryMaxDays': 15,
      });
      expect(result.isEstimateRange, true);
      expect(result.displayText, isNot(contains('–')));
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
      });
      expect(result.hasEstimate, true);
      expect(result.isEstimateRange, false);
      expect(result.days, 7);
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
