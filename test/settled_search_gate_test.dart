// A settled search decides on an AliExpress import only from a product list
// the Firestore server confirmed, never from the partial local cache, and
// never after a failed read.

import 'dart:io';

import 'package:chalakchar_mart/pages/user/search_page.dart';
import 'package:chalakchar_mart/utils/settled_search_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product(String name, String category) => {
      'name': name,
      'category': category,
      'isActive': true,
      'approvalStatus': 'approved',
    };

// What the server holds: hidden grocery items too (they count as matches).
final server = [
  product('Total LP Gas Cylinder 12 kg', 'LPG Gas Cylinder & Gas Stove'),
  product('Radhuni Panch Foran for Cooking', 'Cooking'),
  product('iPhone 12 LCD Display', 'Mobile Parts'),
];
// What the local cache held after the home page: shop products only.
final cache = [product('iPhone 12 LCD Display', 'Mobile Parts')];

/// Feeds the gate one list and returns whether an import would start
/// (null: no decision on this list).
bool? decide(
  SettledSearchGate gate,
  String query,
  List<Map<String, dynamic>> list, {
  bool fromCache = false,
  bool failed = false,
}) {
  final q = gate.take(currentQuery: query, fromCache: fromCache, failed: failed);
  if (q == null) return null;
  return shouldImportSearch(q, searchMatchCount(list, q));
}

void main() {
  for (final word in ['gas', 'cooking']) {
    test('"$word": empty cache list then server products -> no import', () {
      final gate = SettledSearchGate()..settle(word);
      expect(decide(gate, word, cache, fromCache: true), isNull, reason: 'cache list waits');
      expect(decide(gate, word, const [], fromCache: true), isNull, reason: 'still waiting');
      expect(gate.pending, word);
      expect(decide(gate, word, server), isFalse, reason: 'server has hidden matches');
      expect(gate.pending, isNull);
    });
  }

  test('a failed server read starts no import, even if a list comes later', () {
    final gate = SettledSearchGate()..settle('bluetooth speaker');
    expect(decide(gate, 'bluetooth speaker', const [], fromCache: true), isNull);
    expect(decide(gate, 'bluetooth speaker', const [], failed: true), isNull);
    expect(gate.pending, isNull);
    expect(decide(gate, 'bluetooth speaker', const []), isNull);
  });

  test('offline (only cache lists ever arrive) starts no import', () {
    final gate = SettledSearchGate()..settle('bluetooth speaker');
    for (var i = 0; i < 5; i++) {
      expect(decide(gate, 'bluetooth speaker', const [], fromCache: true), isNull);
    }
  });

  test('the server really has nothing -> import', () {
    final gate = SettledSearchGate()..settle('bluetooth speaker');
    expect(decide(gate, 'bluetooth speaker', cache, fromCache: true), isNull);
    expect(decide(gate, 'bluetooth speaker', server), isTrue);
  });

  test('server match -> no import; decided once', () {
    final gate = SettledSearchGate()..settle('iphone 12');
    expect(decide(gate, 'iphone 12', server), isFalse);
    expect(decide(gate, 'iphone 12', const []), isNull, reason: 'already decided');
  });

  test('a query the shopper has since changed is dropped', () {
    final gate = SettledSearchGate()..settle('bluetooth');
    expect(decide(gate, 'bluetooth speaker', const []), isNull);
    expect(gate.pending, isNull);
  });

  test('junk words never import even with no match', () {
    final gate = SettledSearchGate()..settle('ab');
    expect(decide(gate, 'ab', const []), isFalse);
  });

  test('search page waits for the server and drops on errors', () {
    final src = File('lib/pages/user/search_page.dart').readAsStringSync();
    expect(src, contains('includeMetadataChanges: true'));
    expect(src, contains('fromCache: snapshot.data!.metadata.isFromCache'));
    expect(src, contains('_settled.clear();'));
    expect(src, contains('shouldImportSearch(query, matchCount)'));
  });
}
