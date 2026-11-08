import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/variant_merge.dart';

void main() {
  group('mergeVariantEdit', () {
    test('preserves non-form metadata from the original variant', () {
      final original = {
        'id': 'v1',
        'variantId': 'v1',
        'skuId': 'sku-1',
        'sourceSkuId': 'source-1',
        'image': 'https://a/1.jpg',
        'imageUrl': 'https://a/1.jpg',
        'name': 'Old Name',
        'price': 10.0,
        'mrp': 12.0,
        'stock': 3,
      };
      final edited = {'name': 'New Name', 'price': 20.0, 'mrp': 25.0, 'stock': 7};

      final result = mergeVariantEdit(original, edited);

      expect(result['image'], 'https://a/1.jpg');
      expect(result['imageUrl'], 'https://a/1.jpg');
      expect(result['id'], 'v1');
      expect(result['variantId'], 'v1');
      expect(result['skuId'], 'sku-1');
      expect(result['sourceSkuId'], 'source-1');
    });

    test('edited (form) fields always win over stale original values', () {
      final original = {'name': 'Old Name', 'price': 10.0, 'mrp': 12.0, 'stock': 3, 'image': 'https://a/1.jpg'};
      final edited = {'name': 'New Name', 'price': 20.0, 'mrp': 25.0, 'stock': 7};

      final result = mergeVariantEdit(original, edited);

      expect(result['name'], 'New Name');
      expect(result['price'], 20.0);
      expect(result['mrp'], 25.0);
      expect(result['stock'], 7);
      // Non-form field untouched.
      expect(result['image'], 'https://a/1.jpg');
    });

    test('a null original (newly added row) does not inherit any metadata', () {
      final edited = {'name': 'Brand New', 'price': 5.0, 'mrp': 5.0, 'stock': 1};
      final result = mergeVariantEdit(null, edited);

      expect(result, edited);
      expect(result.containsKey('image'), false);
      expect(result.containsKey('sourceSkuId'), false);
    });
  });
}
