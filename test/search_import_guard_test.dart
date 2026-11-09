import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/search_import_guard.dart';

void main() {
  group('normalizeSearchQuery / searchQueryKey', () {
    test('collapses whitespace and trims', () {
      expect(normalizeSearchQuery('  Redmi   Note 12 '), 'Redmi Note 12');
    });

    test('key is lowercased so case variants dedupe together', () {
      expect(searchQueryKey(' JBL  Speaker'), searchQueryKey('jbl speaker'));
    });
  });

  group('isImportableSearchQuery accepts real searches', () {
    for (final q in [
      'mouse',
      'jbl speaker',
      'redmi note 12 display',
      's21 main board flex',
      'ssd drive hdd 2.5 hard disk',
      'রেডমি নোট ১২ ডিসপ্লে',
      'a10',
    ]) {
      test(q, () => expect(isImportableSearchQuery(q), isTrue));
    }
  });

  group('isImportableSearchQuery rejects junk seen in searchImportLog', () {
    for (final q in [
      '',
      'ht',
      '1005',
      '1005009353445701',
      'https://www.aliexpress.com/item/1005012402680375.html',
      'www.aliexpress.com',
      'htm',
      'html',
      'html a',
      'html and usb hub',
      'html_and_usb_hub_f',
      '<div>',
      '!!!???',
      'aliexpress/item/1005009353445701',
      'x' * 201,
    ]) {
      test(q.length > 40 ? '${q.substring(0, 40)}…' : '"$q"',
          () => expect(isImportableSearchQuery(q), isFalse));
    }
  });
}
