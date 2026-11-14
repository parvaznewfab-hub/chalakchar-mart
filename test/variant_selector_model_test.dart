import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/variant_selector_model.dart';

void main() {
  group('variantsShareOneImage', () {
    test('six variants sharing one image -> chips', () {
      expect(variantsShareOneImage(List.filled(6, 'https://x/a.jpg')), isTrue);
    });
    test('all missing -> chips', () {
      expect(variantsShareOneImage(['', ' ', '']), isTrue);
    });
    test('one image plus missing ones -> chips', () {
      expect(variantsShareOneImage(['https://x/a.jpg', '', 'https://x/a.jpg']),
          isTrue);
    });
    test('distinct images -> swatches', () {
      expect(variantsShareOneImage(['https://x/a.jpg', 'https://x/b.jpg']),
          isFalse);
    });
  });

  // resolveVariantAttributeLabel: see variant_label_parity_test.dart.

  group('gallery counter', () {
    test('Y counts images plus the video thumbnail', () {
      expect(
          galleryCounterLabel(
              selectedIndex: 0,
              imageCount: 5,
              hasVideo: true,
              showingOverride: false),
          'Item 1/6');
    });
    test('hidden when no thumbnail strip is rendered', () {
      expect(galleryThumbnailCount(imageCount: 1, hasVideo: false), 0);
      expect(
          galleryCounterLabel(
              selectedIndex: 0,
              imageCount: 1,
              hasVideo: false,
              showingOverride: false),
          isNull);
    });
    test('single image + video renders 2 thumbnails', () {
      expect(galleryThumbnailCount(imageCount: 1, hasVideo: true), 2);
    });
    test('hidden while a variant-only override image is showing', () {
      expect(
          galleryCounterLabel(
              selectedIndex: 2,
              imageCount: 4,
              hasVideo: false,
              showingOverride: true),
          isNull);
    });
  });
  group('mobile collapse', () {
    test('gridColumns', () {
      expect(gridColumns(availableWidth: 347, itemWidth: 76), 4);
      expect(gridColumns(availableWidth: 40, itemWidth: 76), 1);
    });
    test('9 options, 4 per row -> 7 shown + "+2 more"', () {
      expect(collapsedOptionCount(total: 9, perRow: 4, selectedIndex: 0), 7);
    });
    test('8 or fewer never collapse', () {
      expect(collapsedOptionCount(total: 8, perRow: 3, selectedIndex: 0), isNull);
    });
    test('fits in two rows -> no collapse', () {
      expect(collapsedOptionCount(total: 10, perRow: 5, selectedIndex: 0), isNull);
    });
    test('selected option past the fold -> show all', () {
      expect(collapsedOptionCount(total: 12, perRow: 4, selectedIndex: 7), isNull);
      expect(collapsedOptionCount(total: 12, perRow: 4, selectedIndex: 6), 7);
    });
  });
  group('variantDisplayOrder', () {
    List<String> ordered(List<String> v) =>
        [for (final i in variantDisplayOrder(v)) v[i]];
    test('Netac (real order) sorts ascending by size', () {
      expect(
          ordered(['4TB Black', '512GB Black', '256GB Black', '2TB Black',
              '1TB Black', '128GB Black']),
          ['128GB Black', '256GB Black', '512GB Black', '1TB Black',
              '2TB Black', '4TB Black']);
    });
    test('decimal and spaced sizes; ties keep original order', () {
      expect(ordered(['1 TB', '1.5TB', '500GB', '1TB']),
          ['500GB', '1 TB', '1TB', '1.5TB']);
    });
    test('non-size values follow, in their original order', () {
      expect(ordered(['2TB', 'Bundle', '256GB', '1TB']),
          ['256GB', '1TB', '2TB', 'Bundle']);
    });
    test('other values keep the original order', () {
      final v = ['15 256g No Face ID', '15 128g Face ID', 'Red', '2TB'];
      expect(ordered(v), v);
      expect(variantDisplayOrder([]), isEmpty);
    });
  });

  group('galleryStripLayout', () {
    test('never leaves a half-cut thumbnail', () {
      // Includes the arrow-reduced widths (column - 64px).
      for (final w in [162.8, 197.8, 226.8, 232.8, 260.0, 296.8, 331.0, 347.0, 420.0]) {
        final l = galleryStripLayout(width: w, count: 6);
        final used = l.visible * l.thumb + (l.visible - 1) * 10;
        expect(used, closeTo(w, 0.01), reason: 'width $w');
        expect(l.thumb, greaterThanOrEqualTo(64), reason: 'width $w');
        expect(l.thumb, lessThan(150), reason: 'width $w');
      }
    });
    test('800px desktop image column (~227px): 3 visible of 6', () {
      expect(galleryStripLayout(width: 226.8, count: 6).visible, 3);
    });
    test('few items use the full thumbnail size', () {
      final l = galleryStripLayout(width: 600, count: 3);
      expect(l.visible, 3);
      expect(l.thumb, 86);
    });
  });
  group('defaultVariantIndex', () {
    test('Netac stored order -> 128GB (first in-stock after sorting)', () {
      final v = ['4TB Black', '512GB Black', '256GB Black', '2TB Black', '1TB Black', '128GB Black'];
      expect(v[defaultVariantIndex(v, [3, 9, 9, 9, 9, 9])], '128GB Black');
    });
    test('skips out-of-stock sizes', () {
      final v = ['4TB', '128GB', '256GB'];
      expect(v[defaultVariantIndex(v, [5, 0, 2])], '256GB');
    });
    test('non-size values: first in-stock in stored order', () {
      final v = ['15Pro 1TB Face ID', '15 256g No Face ID'];
      expect(v[defaultVariantIndex(v, [0, 4])], '15 256g No Face ID');
    });
    test('all out of stock -> first in display order; empty -> -1', () {
      final v = ['2TB', '1TB'];
      expect(v[defaultVariantIndex(v, [0, 0])], '1TB');
      expect(defaultVariantIndex([], []), -1);
    });
  });
}
