import '../services/category_service.dart';

/// The store's active categories with their active subcategories — the
/// only names an AI category suggestion may resolve to.
class AiTaxonomy {
  final List<CategoryModel> categories;
  final Map<String, List<SubcategoryModel>> subcategoriesByCategory;

  const AiTaxonomy(this.categories, this.subcategoriesByCategory);

  /// Fresh (uncached) read, so a category or subcategory added in the
  /// Category Manager a moment ago is already matchable.
  static Future<AiTaxonomy> load() async {
    final results = await Future.wait([
      CategoryService.getActiveCategoriesOnce(),
      CategoryService.fetchActiveSubcategoriesByCategory(),
    ]);
    return AiTaxonomy(
      results[0] as List<CategoryModel>,
      results[1] as Map<String, List<SubcategoryModel>>,
    );
  }

  String categoryName(String categoryId) =>
      categories.where((c) => c.id == categoryId).firstOrNull?.name ?? '';

  String subcategoryName(String categoryId, String subcategoryId) =>
      (subcategoriesByCategory[categoryId] ?? const [])
          .where((s) => s.id == subcategoryId)
          .firstOrNull
          ?.name ??
      '';

  /// Matches the AI's raw answer to this taxonomy (case/punctuation
  /// insensitive, "&" == "and"). An unknown category gives no match at all;
  /// an unknown subcategory under a known category matches the category
  /// only.
  AiTaxonomyMatch match(String rawCategory, String rawSubcategory) {
    final category = categories
        .where((c) => matchKey(c.name) == matchKey(rawCategory) && matchKey(rawCategory).isNotEmpty)
        .firstOrNull;
    if (category == null) return const AiTaxonomyMatch.none();

    final subKey = matchKey(rawSubcategory);
    final sub = subKey.isEmpty
        ? null
        : (subcategoriesByCategory[category.id] ?? const [])
            .where((s) => matchKey(s.name) == subKey)
            .firstOrNull;
    return AiTaxonomyMatch(
      categoryId: category.id,
      categoryName: category.name,
      subcategoryId: sub?.id ?? '',
      subcategoryName: sub?.name ?? '',
    );
  }

  static String matchKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

class AiTaxonomyMatch {
  final String categoryId;
  final String categoryName;
  final String subcategoryId;
  final String subcategoryName;

  const AiTaxonomyMatch({
    required this.categoryId,
    required this.categoryName,
    required this.subcategoryId,
    required this.subcategoryName,
  });

  const AiTaxonomyMatch.none()
      : categoryId = '',
        categoryName = '',
        subcategoryId = '',
        subcategoryName = '';

  bool get matched => categoryId.isNotEmpty;
}
