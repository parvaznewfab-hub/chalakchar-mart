import 'package:chalakchar_mart/services/product_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Live case: imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165 (Netac SSD).
// variants[] is in AliExpress SKU order, so the 4TB SKU comes first; the
// card used to show its ৳47,546 instead of the 128GB ৳2,851.49.
Map<String, dynamic> netac() => {
      'id': 'imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165',
      'name': 'Netac SATA SSD',
      'price': 47546.14,
      'oldPrice': 68907.2,
      'unit': '4TB Black / China Mainland',
      'variants': [
        {'id': 'a', 'name': '4TB Black / China Mainland', 'price': 47546.14, 'mrp': 68907.2, 'stock': 3},
        {'id': 'b', 'name': '512GB Black / China Mainland', 'price': 7606.24, 'mrp': 11022.87, 'stock': 636},
        {'id': 'c', 'name': '1TB Black / China Mainland', 'price': 13583.64, 'mrp': 19686.02, 'stock': 0},
        {'id': 'd', 'name': '128GB Black / China Mainland', 'price': 2851.49, 'mrp': 4132.56, 'stock': 1337},
      ],
    };

void main() {
  group('display ("from") price', () {
    test('card price is the cheapest in-stock variant, not variants.first', () {
      final p = netac();
      expect(ProductService.getDisplayPrice(p), 2851.49);
      expect(ProductService.getDisplayMrp(p), 4132.56);
      expect(ProductService.hasPriceRange(p), isTrue);
    });

    test('a selected unit still gets its own price (product page / cart)', () {
      final p = netac();
      expect(ProductService.getDisplayPrice(p, unit: '4TB Black / China Mainland'), 47546.14);
      expect(ProductService.getDisplayPrice(p, unit: '512GB Black / China Mainland'), 7606.24);
    });

    test('normalized top-level fields follow the display variant', () {
      final n = ProductService.normalizeProductData(netac());
      expect(n['price'], 2851.49);
      expect(n['oldPrice'], 4132.56);
      expect(n['unit'], '128GB Black / China Mainland');
      // variants[] (what the cart charges) keeps its order.
      expect((n['variants'] as List).first['name'], '4TB Black / China Mainland');
    });

    test('in stock beats cheaper but sold out; all sold out -> cheapest', () {
      expect(
        ProductService.displayVariantOf([
          {'name': 'A', 'price': 10, 'stock': 0},
          {'name': 'B', 'price': 20, 'stock': 1},
        ])?['name'],
        'B',
      );
      expect(
        ProductService.displayVariantOf([
          {'name': 'A', 'price': 30, 'stock': 0},
          {'name': 'B', 'price': 20, 'stock': 0},
        ])?['name'],
        'B',
      );
      expect(ProductService.displayVariantOf([{'name': 'A', 'price': 0}]), isNull);
    });

    test('single-price products are not a "from" price', () {
      expect(
        ProductService.hasPriceRange({
          'price': 50,
          'variants': [
            {'name': '500ml', 'price': 50, 'stock': 3},
          ],
        }),
        isFalse,
      );
    });
  });
}
