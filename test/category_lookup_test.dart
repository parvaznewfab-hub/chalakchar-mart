import 'package:chalakchar_mart/utils/category_lookup.dart';
import 'package:chalakchar_mart/utils/category_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Category Manager writes `normalizedName` with normalizeCategoryKey;
/// functions/category/ensureCategoryExists.js looks categories up by the
/// same key. Examples below are the ones in functions/test/
/// categoryNormalize.test.js and ensureCategoryExists.test.js.
void main() {
  group('normalizeCategoryKey (same examples as the JS tests)', () {
    test('all case/spacing variants of a name normalize to the same key', () {
      const variants = ['Electronics', 'electronics', 'ELECTRONICS', ' Electronics ', 'Electronics  '];
      for (final v in variants) {
        expect(normalizeCategoryKey(v), 'electronics', reason: v);
      }
    });

    test('ensureCategoryExists reuse cases share the stored key', () {
      expect(normalizeCategoryKey('ELECTRONICS'), 'electronics');
      expect(normalizeCategoryKey('  Electronics  '), 'electronics');
    });

    test('collapses repeated internal whitespace', () {
      expect(normalizeCategoryKey('Mobile   Parts'), 'mobile parts');
    });

    test('empty/whitespace-only input returns empty string', () {
      expect(normalizeCategoryKey(''), '');
      expect(normalizeCategoryKey('   '), '');
      expect(normalizeCategoryKey(null), '');
    });

    test('"&" is kept, not folded to "and" (stored key format)', () {
      expect(normalizeCategoryKey('Home & Cleaning'), 'home & cleaning');
      expect(normalizeCategoryKey('Motherboard'), 'motherboard');
    });
  });

  // The real duplicate pair found on 2026-11-11.
  const legacy = 'GeLLBSq8Sf9GEEsl705y'; // Category Manager doc, no normalizedName
  const auto = 'ZUtH6a6P8BTeY1pZhLYv'; // ensureCategoryExists doc

  group('findCategoryNameClash', () {
    final docs = <CategoryDoc>[
      (id: legacy, data: {'name': 'Motherboard', 'isActive': true}),
      (id: 'mp', data: {'name': 'Mobile Parts', 'normalizedName': 'mobile parts', 'isActive': true}),
      (id: 'old', data: {'name': 'Toys', 'isActive': false, 'mergedInto': 'toys2'}),
    ];

    test('catches case/whitespace variants of a doc that has no normalizedName', () {
      expect(findCategoryNameClash(docs, '  MOTHERBOARD '), 'Motherboard');
      expect(findCategoryNameClash(docs, 'mobile   parts'), 'Mobile Parts');
    });

    test('a rename to its own name (any case) is not a clash', () {
      expect(findCategoryNameClash(docs, 'motherboard', excludeId: legacy), isNull);
    });

    test('merged-away docs never block a name', () {
      expect(findCategoryNameClash(docs, 'Toys'), isNull);
    });

    test('free name', () {
      expect(findCategoryNameClash(docs, 'Grocery'), isNull);
      expect(findCategoryNameClash(docs, '   '), isNull);
    });
  });

  group('resolveCategoryId', () {
    test('saved categoryId wins', () {
      final byId = {
        legacy: {'name': 'Motherboard', 'isActive': true},
        auto: {'name': 'Motherboard', 'normalizedName': 'motherboard', 'isActive': true},
      };
      expect(resolveCategoryId(byId, categoryId: legacy, categoryName: 'Motherboard'), legacy);
    });

    test('a merged-away id is followed to the doc it was merged into', () {
      final byId = {
        legacy: {'name': 'Motherboard', 'isActive': false, 'mergedInto': auto},
        auto: {'name': 'Motherboard', 'normalizedName': 'motherboard', 'isActive': true},
      };
      expect(resolveCategoryId(byId, categoryId: legacy), auto);
    });

    test('name-only product: matched by key, preferring active then normalizedName', () {
      final byId = {
        'aaa': {'name': 'Motherboard', 'isActive': false, 'normalizedName': 'motherboard'},
        legacy: {'name': 'Motherboard', 'isActive': true},
        auto: {'name': 'Motherboard', 'normalizedName': 'motherboard', 'isActive': true},
      };
      expect(resolveCategoryId(byId, categoryName: ' motherboard '), auto);
    });

    test('unknown id falls back to the name; nothing matching gives null', () {
      final byId = {
        auto: {'name': 'Motherboard', 'normalizedName': 'motherboard', 'isActive': true},
      };
      expect(resolveCategoryId(byId, categoryId: 'deleted', categoryName: 'Motherboard'), auto);
      expect(resolveCategoryId(byId, categoryName: 'Other'), isNull);
      expect(resolveCategoryId(byId), isNull);
    });

    test('a mergedInto loop does not hang', () {
      final byId = {
        'a': {'name': 'X', 'mergedInto': 'b'},
        'b': {'name': 'X', 'mergedInto': 'a'},
      };
      expect(resolveCategoryId(byId, categoryId: 'a'), isNull);
    });
  });
}
