import 'package:chalakchar_mart/services/category_service.dart';
import 'package:chalakchar_mart/utils/ai_taxonomy_match.dart';
import 'package:flutter_test/flutter_test.dart';

CategoryModel _cat(String id, String name) => CategoryModel(
      id: id,
      name: name,
      description: '',
      imageUrl: '',
      priority: 0,
      isActive: true,
      isFeatured: false,
      showOnHome: true,
    );

SubcategoryModel _sub(String id, String categoryId, String name) => SubcategoryModel(
      id: id,
      categoryId: categoryId,
      name: name,
      slug: '',
      imageUrl: '',
      priority: 0,
      isActive: true,
    );

void main() {
  final taxonomy = AiTaxonomy(
    [_cat('mp', 'Mobile Parts'), _cat('ca', 'Computer Accessories')],
    {
      'mp': [
        _sub('disp', 'mp', 'Display & Digitizer'),
        _sub('usb', 'mp', 'USB Charging port board'),
      ],
    },
  );

  test('category and subcategory match, case and & insensitive', () {
    final m = taxonomy.match(' mobile parts', 'display and digitizer');
    expect(m.matched, isTrue);
    expect(m.categoryId, 'mp');
    expect(m.categoryName, 'Mobile Parts');
    expect(m.subcategoryId, 'disp');
    expect(m.subcategoryName, 'Display & Digitizer');
  });

  test('unknown category is no match, even with a known subcategory name', () {
    final m = taxonomy.match('Electronics', 'Display & Digitizer');
    expect(m.matched, isFalse);
    expect(m.subcategoryId, isEmpty);
  });

  test('unknown subcategory keeps the category only', () {
    final m = taxonomy.match('Computer Accessories', 'Storage Devices');
    expect(m.matched, isTrue);
    expect(m.categoryId, 'ca');
    expect(m.subcategoryId, isEmpty);
  });

  test("another category's subcategory is not accepted", () {
    final m = taxonomy.match('Computer Accessories', 'USB Charging port board');
    expect(m.categoryId, 'ca');
    expect(m.subcategoryId, isEmpty);
  });

  test('empty answer is no match', () {
    expect(taxonomy.match('', '').matched, isFalse);
  });

  test('name lookups for the current category/subcategory', () {
    expect(taxonomy.categoryName('mp'), 'Mobile Parts');
    expect(taxonomy.subcategoryName('mp', 'usb'), 'USB Charging port board');
    expect(taxonomy.subcategoryName('mp', 'missing'), '');
  });
}
