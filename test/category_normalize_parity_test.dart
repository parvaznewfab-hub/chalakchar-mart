import 'dart:convert';
import 'dart:io';

import 'package:chalakchar_mart/utils/category_normalize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks lib/utils/category_normalize.dart against outputs produced by the
/// backend's functions/category/categoryNormalize.js. Regenerate the
/// fixture with:
///   node functions/scripts/generateCategoryNormalizeParityFixture.js
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/category_normalize_parity.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('fixture is not empty', () => expect(cases, isNotEmpty));

  for (final c in cases) {
    final label = c['label'] as String;
    final input = c['input'] as String;

    test('normalizeCategoryKey matches JS: $label', () {
      expect(normalizeCategoryKey(input), c['normalized']);
    });

    test('slugifyCategoryName matches JS: $label', () {
      expect(slugifyCategoryName(input), c['slug']);
    });
  }

  test('precomposed and decomposed nukta letters share one key', () {
    expect(normalizeCategoryKey('য়'), normalizeCategoryKey('য়'));
    expect(normalizeCategoryKey('ড়'), normalizeCategoryKey('ড়'));
    expect(normalizeCategoryKey('ঢ়'), normalizeCategoryKey('ঢ়'));
  });
}
