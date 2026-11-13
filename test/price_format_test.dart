import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/price_format.dart';

void main() {
  group('formatTaka', () {
    test('whole amounts get thousands separators and no decimals', () {
      expect(formatTaka(16603), '৳16,603');
      expect(formatTaka(16603.00), '৳16,603');
      expect(formatTaka(94780), '৳94,780');
      expect(formatTaka(137363), '৳137,363');
      expect(formatTaka(6), '৳6');
      expect(formatTaka(0), '৳0');
      expect(formatTaka(1000000), '৳1,000,000');
    });

    test('real fractions keep two decimals', () {
      expect(formatTaka(1850.5), '৳1,850.50');
      expect(formatTaka(0.75), '৳0.75');
      expect(formatTaka(12345.67), '৳12,345.67');
    });

    test('float noise rounds to the paisa first', () {
      expect(formatTaka(16602.999999), '৳16,603');
      expect(formatTaka(0.1 + 0.2), '৳0.30');
    });

    test('negative amounts put the sign before the symbol', () {
      expect(formatTaka(-40), '-৳40');
      expect(formatTaka(-1850.5), '-৳1,850.50');
    });
  });

  group('discountPercent', () {
    test('rounds to a whole percent', () {
      expect(discountPercent(94780, 137363), 31);
      expect(discountPercent(1850, 2050), 10);
    });

    test('is 0 without a real discount', () {
      expect(discountPercent(699, 699), 0);
      expect(discountPercent(6, 0), 0);
      expect(discountPercent(700, 699), 0);
      expect(discountPercent(1000, 1001), 0); // rounds to 0%
    });
  });
}
