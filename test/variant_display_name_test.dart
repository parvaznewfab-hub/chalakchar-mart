import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/variant_display_name.dart';

void main() {
  group('cleanVariantDisplayName', () {
    test('strips a pipe-separated location suffix', () {
      expect(
        cleanVariantDisplayName('11 64g No Face ID | China Mainland'),
        '11 64g No Face ID',
      );
    });

    test('strips a slash-separated location suffix (this project\'s own join format)', () {
      expect(
        cleanVariantDisplayName('Blue 128GB / Spain'),
        'Blue 128GB',
      );
    });

    test('works for any location value without hardcoding a specific one', () {
      for (final location in [
        'China Mainland', 'CN', 'China', 'US Warehouse', 'Spain', 'France',
        'Russian Federation', 'Czech Republic',
      ]) {
        expect(cleanVariantDisplayName('Red 256GB | $location'), 'Red 256GB');
      }
    });

    test('leaves a name with no separator unchanged', () {
      expect(cleanVariantDisplayName('11 64g No Face ID'), '11 64g No Face ID');
    });

    test('does not split on a bare slash with no spaces (e.g. size codes)', () {
      expect(cleanVariantDisplayName('S/M/L'), 'S/M/L');
    });

    test('empty input returns empty', () {
      expect(cleanVariantDisplayName(''), '');
      expect(cleanVariantDisplayName('   '), '');
    });
  });
}
