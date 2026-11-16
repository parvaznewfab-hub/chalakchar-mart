import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/device_model.dart';

// Same fixture as functions/test/deviceModel.test.js — the storefront (Dart)
// and the backend that stores modelKeys (JS) must agree.
void main() {
  final cases = (jsonDecode(File('test/fixtures/device_model_cases.json').readAsStringSync())
      as Map<String, dynamic>)['cases'] as List;

  for (final c in cases.cast<Map<String, dynamic>>()) {
    final name = c['name'] as String;
    test(name.length > 70 ? name.substring(0, 70) : name, () {
      final got = modelFieldsForName(name);
      expect(got.modelKeys, (c['modelKeys'] as List).cast<String>());
      expect(got.modelSeries, (c['modelSeries'] as List).cast<String>());
    });
  }

  test('iPhone 12 / 12 Pro / 12 Pro Max / 12 mini are four keys, one series', () {
    expect(modelFieldsForName('For iPhone 12 64g').modelKeys, ['iphone 12']);
    expect(modelFieldsForName('For iPhone 12 Pro 128g').modelKeys, ['iphone 12 pro']);
    expect(modelFieldsForName('For iPhone 12 Pro Max').modelKeys, ['iphone 12 pro max']);
    expect(modelFieldsForName('For iPhone 12 Mini').modelKeys, ['iphone 12 mini']);
    expect(modelFieldsForName('For iPhone 12 Pro Max').modelSeries, ['iphone 12']);
  });
}
