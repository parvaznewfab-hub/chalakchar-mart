import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/safe_dropdown.dart';
import 'package:chalakchar_mart/widgets/safe_dropdown_field.dart';

const oldRounding = [
  DropdownChoice('none', 'Exact (2 decimals)'),
  DropdownChoice('00', 'Round up to whole amount'),
  DropdownChoice('99', 'End price with .99'),
];

Future<void> pumpField(WidgetTester tester, String? value, List<DropdownChoice> choices) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SafeDropdownField(label: 'Price Rounding', value: value, choices: choices, onChanged: (_) {}),
    ),
  ));
}

void main() {
  group('helpers', () {
    test('uniqueChoices keeps the first of each value', () {
      final u = uniqueChoices(const [DropdownChoice('a', 'A'), DropdownChoice('b', 'B'), DropdownChoice('a', 'A2')]);
      expect(u.map((c) => '${c.value}:${c.label}'), ['a:A', 'b:B']);
    });

    test('knownChoiceValue / isUnknownChoice', () {
      expect(knownChoiceValue('none', oldRounding), 'none');
      expect(knownChoiceValue('round', oldRounding), isNull);
      expect(isUnknownChoice('round', oldRounding), isTrue);
      expect(isUnknownChoice('', oldRounding), isFalse);
      expect(isUnknownChoice(null, oldRounding), isFalse);
    });

    test('putIfKnownChoice writes only valid values (also into an inferred Map<String, Object>)', () {
      final importSettings = {'autoPublish': true, 'exchangeRate': 1.0};
      final payload = <String, dynamic>{'importSettings': importSettings};
      putIfKnownChoice(payload['importSettings'] as Map<String, dynamic>, 'roundingMode', 'round', oldRounding);
      expect(importSettings.containsKey('roundingMode'), isFalse);
      putIfKnownChoice(payload['importSettings'] as Map<String, dynamic>, 'roundingMode', '99', oldRounding);
      expect(importSettings['roundingMode'], '99');
    });
  });

  group('SafeDropdownField never asserts', () {
    testWidgets('live value "round" that the list does not have: no selection, note shown', (tester) async {
      await pumpField(tester, 'round', oldRounding);
      expect(tester.takeException(), isNull);
      expect(find.text('অজানা মান: round'), findsOneWidget);
    });

    testWidgets('missing / empty value: no error, no note', (tester) async {
      await pumpField(tester, null, oldRounding);
      expect(tester.takeException(), isNull);
      await pumpField(tester, '', oldRounding);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('অজানা মান'), findsNothing);
    });

    testWidgets('the same value twice among the items', (tester) async {
      await pumpField(tester, '99', const [...oldRounding, DropdownChoice('99', 'duplicate')]);
      expect(tester.takeException(), isNull);
      expect(find.text('End price with .99'), findsOneWidget);
    });

    test('a plain DropdownButtonFormField with "round" asserts (the bug on the settings page)', () {
      expect(
        () => DropdownButtonFormField<String>(
          initialValue: 'round',
          items: [for (final c in oldRounding) DropdownMenuItem(value: c.value, child: Text(c.label))],
          onChanged: (_) {},
        ),
        throwsA(isA<AssertionError>().having(
            (e) => e.toString(), 'message', contains("There should be exactly one item with [DropdownButton]'s value: round"))),
      );
    });
  });
}
