import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalakchar_mart/utils/vendor_product_rules.dart';

void main() {
  final approved = {
    'name': 'Case', 'category': 'Mobile Parts', 'overview': 'x', 'image': 'a', 'imageUrl': 'a',
    'images': ['a'], 'approvalStatus': 'approved', 'isActive': true,
  };

  test('price / stock / variants only: stays approved, show/hide choice kept', () {
    final out = vendorProductUpdate(before: approved, content: {
      'name': 'Case', 'category': 'Mobile Parts', 'overview': 'x', 'image': 'a', 'imageUrl': 'a', 'images': ['a'],
      'price': 120.0, 'stock': 3,
    }, wantActive: true);
    expect(out.containsKey('approvalStatus'), isFalse);
    expect(out['isActive'], isTrue);
    expect(out['isVisible'], isTrue);
  });

  test('name / images / category / overview change: back to pending and hidden', () {
    for (final change in [
      {'name': 'New'}, {'images': ['a', 'b']}, {'category': 'Other'}, {'overview': 'y'}, {'image': 'b'},
    ]) {
      final out = vendorProductUpdate(before: approved, content: {...approved, ...change}, wantActive: true);
      expect(out['approvalStatus'], 'pending', reason: '$change');
      expect(out['isActive'], isFalse);
      expect(out['isVisible'], isFalse);
    }
  });

  test('same category with a resolver-added categoryId: no category fields sent, stays approved', () {
    final out = vendorProductUpdate(before: approved, content: {
      'category': 'Mobile Parts', 'categoryId': 'catMobile', 'price': 1790.0,
    }, wantActive: true);
    expect(out.containsKey('category'), isFalse);
    expect(out.containsKey('categoryId'), isFalse);
    expect(out.containsKey('approvalStatus'), isFalse);
    expect(out['isActive'], isTrue);
  });

  test('a real category change sends the id along and goes back to pending', () {
    final out = vendorProductUpdate(before: approved, content: {'category': 'Computer Accessories', 'categoryId': 'catComputer'}, wantActive: true);
    expect(out['categoryId'], 'catComputer');
    expect(out['approvalStatus'], 'pending');
  });

  test('a pending product stays hidden whatever the switch says', () {
    final out = vendorProductUpdate(before: {...approved, 'approvalStatus': 'pending'}, content: {'price': 1.0}, wantActive: true);
    expect(out['isActive'], isFalse);
    expect(out.containsKey('approvalStatus'), isFalse);
  });

  test('variants carry only name / price / mrp / stock', () {
    expect(vendorVariant(name: '', price: 1, mrp: 2, stock: 3).keys.toSet(), {'name', 'price', 'mrp', 'stock'});
    expect(vendorVariant(name: '', price: 1, mrp: 2, stock: 3)['name'], 'Default');
  });

  test('payloads never carry owner, publish or pharmacy fields', () {
    final out = vendorProductUpdate(before: approved, content: {'price': 1.0}, wantActive: false);
    for (final k in ['vendorId', 'vendorOwnerId', 'isPublished', 'showOnHome', 'generic', 'manufacturer', 'type', 'strength']) {
      expect(out.containsKey(k), isFalse, reason: k);
    }
  });

  test('Bengali error for a rules refusal', () {
    expect(vendorProductErrorBn(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')), contains('অনুমতি নেই'));
    expect(vendorProductErrorBn(Exception('x')), contains('আবার চেষ্টা'));
  });
}
