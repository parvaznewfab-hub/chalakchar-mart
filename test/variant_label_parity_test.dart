import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/variant_display_name.dart';
import 'package:chalakchar_mart/utils/variant_selector_model.dart';

// Same fixture as functions/test/variantLabel.test.js — keeps the storefront
// label (Dart) and the backend dry-run report (JS) in agreement.
void main() {
  final cases = (jsonDecode(
          File('test/fixtures/variant_label_cases.json').readAsStringSync())
      as Map<String, dynamic>)['cases'] as List;

  for (final c in cases.cast<Map<String, dynamic>>()) {
    test(c['label'], () {
      final names = (c['names'] as List).cast<String>();
      expect(
        resolveVariantAttributeLabel(
          productAttributeName: c['productAttributeName'] as String?,
          subcategoryLabel: c['subcategoryLabel'] as String?,
          categoryLabel: c['categoryLabel'] as String?,
          variantValues: names.map(cleanVariantDisplayName),
        ),
        c['expect'],
      );
    });
  }

  test('isColourValue', () {
    expect(isColourValue('Rose Gold'), isTrue);
    expect(isColourValue('Black-Red'), isTrue);
    expect(isColourValue('Black Frame'), isFalse);
    expect(isColourValue('Light'), isFalse); // modifier alone
  });
}
