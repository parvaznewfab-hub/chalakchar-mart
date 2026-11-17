// Search suggestions, search results, vendor shop and marketplace show only
// what the shop shows (isShopVisibleProduct). The old grocery items are
// isActive + approved but their category has no category doc, so they stay
// out everywhere; products in a switched-on category show as before.

import 'dart:io';

import 'package:chalakchar_mart/pages/user/search_page.dart';
import 'package:chalakchar_mart/utils/shop_visibility.dart';
import 'package:chalakchar_mart/widgets/global_web_header.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> product(
  String id,
  String name,
  String category, {
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'price': 500,
      'stock': 5,
      'isActive': true,
      'approvalStatus': 'approved',
      'vendorId': 'super_admin',
      ...extra,
    };

// Category docs that exist and are switched on (lower-cased).
const activeCategories = {'mobile parts', 'motherboard'};

final rice = product('g1', 'Miniket Rice 5kg', 'Rice');
final cookingOil = product('g2', 'Soybean Cooking Oil 1L', 'Cooking');
final lpg = product('g3', 'LPG Gas Cylinder 12kg', 'LPG');
final groceryOnMarketplace =
    product('g4', 'Rice Cooker Pot', 'Cooking', extra: {'vendorId': 'v1', 'isMarketplace': true});
final display = product('m1', 'iPhone 12 LCD Display Screen', 'Mobile Parts');
final board = product('m2', 'Motherboard For iPhone 12 128g', 'Motherboard');
final partOnMarketplace =
    product('m3', 'Samsung A52 Charging Flex Cable', 'Mobile Parts', extra: {'vendorId': 'v1', 'isMarketplace': true});

final all = [rice, cookingOil, lpg, groceryOnMarketplace, display, board, partOnMarketplace];
const grocery = {'g1', 'g2', 'g3', 'g4'};

List<String> ids(Iterable<Map<String, dynamic>> list) => [for (final p in list) p['id'] as String];

void main() {
  group('isShopVisibleProduct / shopVisibleOnly', () {
    test('an active product whose category has no category doc is not shown', () {
      for (final p in [rice, cookingOil, lpg, groceryOnMarketplace]) {
        expect(isShopVisibleProduct(p, activeCategories), isFalse, reason: p['name']);
      }
    });

    test('products in a switched-on category are shown, in their order', () {
      expect(ids(shopVisibleOnly(all, activeCategories, (p) => p)), ['m1', 'm2', 'm3']);
    });

    test('category match ignores case and spaces', () {
      final p = product('x', 'Back Glass', ' mobile PARTS ');
      expect(isShopVisibleProduct(p, activeCategories), isTrue);
    });

    test('inactive, unapproved, hidden or unpublished products stay out', () {
      for (final extra in <Map<String, dynamic>>[
        {'isActive': false},
        {'approvalStatus': 'pending'},
        {'isVisible': false},
        {'isPublished': false},
        {'hiddenReason': 'duplicate'},
      ]) {
        final p = product('x', 'iPhone 12 Battery', 'Mobile Parts', extra: extra);
        expect(isShopVisibleProduct(p, activeCategories), isFalse, reason: '$extra');
      }
    });

    test('needsReview does not hide a product (marketing gate only)', () {
      final p = product('x', 'iPhone 12 Battery', 'Mobile Parts', extra: {'needsReview': true});
      expect(isShopVisibleProduct(p, activeCategories), isTrue);
    });
  });

  group('header search suggestions', () {
    test('"cooking", "rice", "gas" suggest nothing', () {
      for (final q in ['cooking', 'rice', 'gas', 'Rice']) {
        expect(headerSuggestions(all, q, activeCategories), isEmpty, reason: q);
      }
    });

    test('a shop product is still suggested', () {
      final s = headerSuggestions(all, 'iphone 12', activeCategories);
      expect(s.map((e) => e['title']), ['iPhone 12 LCD Display Screen', 'Motherboard For iPhone 12 128g']);
      expect(s.first['subtitle'], 'Mobile Parts');
    });

    test('suggests by category name too, at most 8', () {
      final many = [for (var i = 0; i < 12; i++) product('p$i', 'Part $i', 'Mobile Parts')];
      expect(headerSuggestions(many, 'mobile parts', activeCategories), hasLength(8));
    });
  });

  group('search results', () {
    List<String> search({
      String query = '',
      bool onlyMarketplace = false,
      bool onlyPharmacy = false,
      String sort = 'relevance',
    }) =>
        ids(searchResults(
          all,
          (p) => p,
          activeCategoriesLower: activeCategories,
          query: query,
          onlyMarketplace: onlyMarketplace,
          onlyPharmacy: onlyPharmacy,
          sort: sort,
        ));

    test('an empty search lists only shop products', () {
      final result = search();
      expect(result.toSet(), {'m1', 'm2', 'm3'});
      expect(result.where(grocery.contains), isEmpty);
    });

    test('"cooking", "rice", "gas" find nothing', () {
      for (final q in ['cooking', 'rice', 'gas']) {
        expect(search(query: q), isEmpty, reason: q);
      }
    });

    test('a shop product is found as before, best match first', () {
      expect(search(query: 'iphone 12'), ['m1', 'm2']);
      expect(search(query: 'flex cable'), ['m3']);
    });

    test('marketplace and store filters only pick from shop products', () {
      expect(search(onlyMarketplace: true), ['m3']);
      expect(search(onlyPharmacy: true).toSet(), {'m1', 'm2'});
    });

    test('the search-miss count still sees hidden items (no AliExpress import for them)', () {
      // _handleSettledQuery counts with searchMatches over every active,
      // approved product, so "rice" is not a miss even though it is hidden.
      expect(all.where((p) => searchMatches(p, 'rice')).length, 2);
    });
  });

  group('vendor shop and marketplace', () {
    // Their Firestore streams can't run in a unit test; these pin the list
    // they show to the shared rule.
    test('vendor shop shows only shop products of that vendor', () {
      final vendorDocs = all.where((p) => p['vendorId'] == 'super_admin');
      expect(ids(shopVisibleOnly(vendorDocs, activeCategories, (p) => p)), ['m1', 'm2']);
    });

    test('marketplace shows no grocery item', () {
      final marketplaceDocs = all.where((p) => p['isMarketplace'] == true);
      expect(ids(shopVisibleOnly(marketplaceDocs, activeCategories, (p) => p)), ['m3']);
    });

    // One rule, no copies: each place filters through shop_visibility.dart
    // and none still lists by isActive alone.
    final places = {
      'lib/widgets/global_web_header.dart': 'headerSuggestions(',
      'lib/pages/user/search_page.dart': 'shopVisibleOnly(',
      'lib/pages/vendor/vendor_shop_page.dart': 'shopVisibleOnly(',
      'lib/widgets/marketplace_home_section.dart': 'shopVisibleOnly(',
      'lib/widgets/all_products_section.dart': 'shopVisibleOnly(',
    };
    for (final entry in places.entries) {
      test('${entry.key} uses the shared rule', () {
        final src = File(entry.key).readAsStringSync();
        expect(src, contains("utils/shop_visibility.dart'"));
        expect(src, contains(entry.value));
        expect(src, isNot(contains("p['isVisible'] != false")), reason: 'no copy of the rule');
        expect(src, isNot(contains('bool isShopVisibleProduct(')), reason: 'no copy of the rule');
      });
    }
  });
}
