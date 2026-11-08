import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/services/product_service.dart';

void main() {
  group('ProductService.normalizeVariants', () {
    test('id and variantId survive normalization', () {
      final result = ProductService.normalizeVariants([
        {'id': 'v1', 'variantId': 'v1', 'name': 'Red', 'price': 10, 'mrp': 12, 'stock': 5},
      ]);
      expect(result.single['id'], 'v1');
      expect(result.single['variantId'], 'v1');
    });

    test('preserves image, imageUrl, skuId, sourceSkuId when present', () {
      final result = ProductService.normalizeVariants([
        {
          'id': 'v1',
          'name': 'Red',
          'price': 10,
          'mrp': 12,
          'stock': 5,
          'skuId': 'sku-1',
          'sourceSkuId': 'source-1',
          'image': 'https://a/1.jpg',
          'imageUrl': 'https://a/1.jpg',
        },
      ]);
      final variant = result.single;
      expect(variant['skuId'], 'sku-1');
      expect(variant['sourceSkuId'], 'source-1');
      expect(variant['image'], 'https://a/1.jpg');
      expect(variant['imageUrl'], 'https://a/1.jpg');
    });

    test('remains backward compatible: no forced empty fields for manual/non-AliExpress variants', () {
      final result = ProductService.normalizeVariants([
        {'name': 'Default', 'price': 10, 'mrp': 12, 'stock': 5},
      ]);
      final variant = result.single;
      expect(variant.containsKey('image'), false);
      expect(variant.containsKey('imageUrl'), false);
      expect(variant.containsKey('skuId'), false);
      expect(variant.containsKey('sourceSkuId'), false);
      // Core fields still work normally.
      expect(variant['name'], 'Default');
      expect(variant['price'], 10.0);
      expect(variant['stock'], 5);
    });

    test('empty raw variants still produces a valid default variant', () {
      final result = ProductService.normalizeVariants(
        null,
        fallbackUnit: 'Default',
        fallbackPrice: 100,
        fallbackStock: 10,
      );
      expect(result.length, 1);
      expect(result.single['name'], 'Default');
      expect(result.single.containsKey('image'), false);
    });
  });
}
