import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/related_products.dart';

Map<String, dynamic> p(
  String id,
  String name, {
  String category = 'Mobile Parts',
  String subcategoryId = 'display',
  num price = 2000,
  num stock = 10,
  bool active = true,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'name': name,
      'category': category,
      'subcategoryId': subcategoryId,
      'price': price,
      'stock': stock,
      'isActive': active,
      'approvalStatus': 'approved',
      ...extra,
    };

const active = {'mobile parts', 'motherboard', 'computer accessories'};

void main() {
  final display12 = p('d12', 'iPhone 12 12 Pro LCD Display Screen Replacement');
  final board12 = p('b12', 'Motherboard For iPhone 12 64g/128g', category: 'Motherboard', subcategoryId: 'iphone');
  final display12all = p('d12all', 'OLED Screen for IPhone 12/12Pro/12ProMax LCD Display');
  final board12pm = p('b12pm', 'Motherboard For iPhone 12 Pro Max 128g', category: 'Motherboard', subcategoryId: 'iphone');
  final board12pm2 = p('b12pm2', 'Logic Board For iPhone 12 Pro Max With Face ID', category: 'Motherboard', subcategoryId: 'iphone');

  test('iPhone 12 Display: Pro Max boards never in the "this model" row', () {
    final all = [display12, board12, display12all, board12pm, board12pm2];
    final row = pickModelRow(
      current: display12,
      exactCandidates: all,
      seriesCandidates: all,
      activeCategoriesLower: active,
    )!;
    expect(row.title, 'এই মডেলের আরও পার্টস');
    expect(row.products.map((e) => e['id']), unorderedEquals(['b12', 'd12all']));
  });

  test('fewer than 2 exact -> series row titled with the series', () {
    final all = [display12, board12, board12pm, board12pm2];
    // Exact: only b12pm2 is a 12 Pro Max part (the 12/12Pro/12ProMax screen
    // is inactive) -> 1 -> series "iphone 12".
    final inactiveScreen = {...display12all, 'isActive': false};
    final row2 = pickModelRow(
      current: board12pm,
      exactCandidates: [board12pm, board12pm2, inactiveScreen],
      seriesCandidates: all,
      activeCategoriesLower: active,
    )!;
    expect(row2.title, 'iPhone 12 সিরিজের আরও পার্টস');
    expect(row2.products.map((e) => e['id']), unorderedEquals(['d12', 'b12', 'b12pm2']));
  });

  test('hidden when the series also has fewer than 2', () {
    final p30 = p('p30', 'for HUAWEI P30 Lite IPS LCD Display');
    expect(
      pickModelRow(current: p30, exactCandidates: [p30], seriesCandidates: [p30], activeCategoriesLower: active),
      isNull,
    );
  });

  test('no device model -> no model row', () {
    final ssd = p('ssd', 'Netac SSD 1TB SATA', category: 'Computer Accessories', subcategoryId: '');
    expect(
      pickModelRow(current: ssd, exactCandidates: [], seriesCandidates: [], activeCategoriesLower: active),
      isNull,
    );
  });

  test('shop visibility: inactive, unapproved, hidden, hiddenReason, inactive category dropped; needsReview kept', () {
    bool vis(Map<String, dynamic> x) => isShopVisibleProduct(x, active);
    expect(vis(p('a', 'x')), isTrue);
    expect(vis(p('a', 'x', extra: {'needsReview': true})), isTrue);
    expect(vis(p('a', 'x', active: false)), isFalse);
    expect(vis(p('a', 'x', extra: {'approvalStatus': 'draft'})), isFalse);
    expect(vis(p('a', 'x', extra: {'isVisible': false})), isFalse);
    expect(vis(p('a', 'x', extra: {'isPublished': false})), isFalse);
    expect(vis(p('a', 'x', extra: {'hiddenReason': 'health_removed'})), isFalse);
    expect(vis(p('a', 'x', category: 'Storage Devices')), isFalse);
  });

  test('similar row: same subcategory, nearest price, out of stock last, no repeats, max 12', () {
    final current = p('c', 'Netac SSD 1TB', category: 'Computer Accessories', subcategoryId: '', price: 3000);
    final candidates = [
      current,
      p('far', 'SSD far', category: 'Computer Accessories', subcategoryId: '', price: 9000),
      p('near', 'SSD near', category: 'Computer Accessories', subcategoryId: '', price: 3100),
      p('nearOut', 'SSD near no stock', category: 'Computer Accessories', subcategoryId: '', price: 3000, stock: 0),
      p('inRow1', 'SSD row1', category: 'Computer Accessories', subcategoryId: '', price: 3000),
      p('otherCat', 'Phone part', price: 3000),
      for (var i = 0; i < 20; i++)
        p('x$i', 'SSD $i', category: 'Computer Accessories', subcategoryId: '', price: 5000 + i),
    ];
    final row = pickSimilarRow(
      current: current,
      candidates: candidates,
      activeCategoriesLower: active,
      excludeIds: {'inRow1'},
    );
    final ids = row.map((e) => e['id']).toList();
    expect(ids.length, 12);
    expect(ids.first, 'near');
    expect(ids, isNot(contains('c')));
    expect(ids, isNot(contains('inRow1')));
    expect(ids, isNot(contains('otherCat')));
    expect(ids, isNot(contains('nearOut')), reason: '12 in-stock items fill the row first');
  });

  test('similar row uses subcategory when the product has one', () {
    final current = p('c', 'iPhone 12 display', subcategoryId: 'display');
    final row = pickSimilarRow(
      current: current,
      candidates: [p('same', 'A', subcategoryId: 'display'), p('usb', 'B', subcategoryId: 'usb')],
      activeCategoriesLower: active,
    );
    expect(row.map((e) => e['id']), ['same']);
  });

  test('displayModelName', () {
    expect(displayModelName('iphone 12'), 'iPhone 12');
    expect(displayModelName('iphone x'), 'iPhone X');
    expect(displayModelName('samsung a52'), 'Samsung A52');
    expect(displayModelName('huawei nova 4'), 'Huawei Nova 4');
    expect(displayModelName('huawei p30'), 'Huawei P30');
    expect(displayModelName('redmi note 10'), 'Redmi Note 10');
    expect(displayModelName('iphone se'), 'iPhone SE');
  });

  test('similar row: same brand first, then nearest price; no brand -> price only', () {
    final current = p('c', 'iPhone 12 12 Pro LCD Display', price: 2400);
    final candidates = [
      p('sam', 'LCD For Samsung Galaxy A14', price: 2390),
      p('ip8', 'LCD for iPhone 8 SE 2020', price: 2100),
      p('ip11', 'LCD for iPhone XR 11', price: 2600),
      p('hot', 'FOR Hotwav Cyber 7 LCD', price: 2400),
      p('ipOut', 'LCD for iPhone 6 Plus', price: 2400, stock: 0),
    ];
    final ids = pickSimilarRow(current: current, candidates: candidates, activeCategoriesLower: active)
        .map((e) => e['id'])
        .toList();
    expect(ids, ['ip11', 'ip8', 'hot', 'sam', 'ipOut']);
    final ssd = p('s', 'Netac SSD 1TB', price: 2400);
    expect(
      pickSimilarRow(current: ssd, candidates: candidates, activeCategoriesLower: active).map((e) => e['id']).take(2),
      ['hot', 'sam'],
    );
  });
}
