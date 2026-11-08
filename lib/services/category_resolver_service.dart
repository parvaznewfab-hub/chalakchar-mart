import 'package:cloud_functions/cloud_functions.dart';

/// Resolves a product's category (and optional subcategory) through the
/// shared backend resolver (functions/category/resolveProductTaxonomy.js) —
/// the only path through which Admin/Vendor Flutter clients ever cause a
/// `categories`/`subcategories` document to be created. This client never
/// writes to those collections directly; the backend derives visibility
/// defaults (active/hidden) from the signed-in caller's own role, not from
/// anything this client sends, so a vendor session cannot request
/// admin-tier visibility for a category it creates.
///
/// Shared by both the Admin and Vendor product forms so category resolution
/// never has two different implementations.
class CategoryResolverService {
  CategoryResolverService._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Resolves [categoryName] (and [subCategoryName], if given) to their
  /// canonical taxonomy IDs, creating either document if it doesn't already
  /// exist yet. Returns `null` when [categoryName] is blank — mirrors the
  /// backend's own validation, so a product with no category never triggers
  /// a network call at all.
  static Future<
      ({
        String categoryId,
        String categoryName,
        String? subcategoryId,
        bool createdCategory,
        bool createdSubcategory,
      })?> resolve(
    String categoryName, {
    String? subCategoryName,
  }) async {
    final trimmedCategory = categoryName.trim();
    if (trimmedCategory.isEmpty) return null;

    final trimmedSubCategory = (subCategoryName ?? '').trim();

    final result = await _functions.httpsCallable('resolveProductCategory').call<dynamic>(
      <String, dynamic>{
        'categoryName': trimmedCategory,
        if (trimmedSubCategory.isNotEmpty) 'subCategoryName': trimmedSubCategory,
      },
    );

    final data = result.data;
    final map = data is Map ? data : const {};
    final categoryId = (map['categoryId'] as String?) ?? '';
    if (categoryId.isEmpty) return null;

    return (
      categoryId: categoryId,
      categoryName: (map['categoryName'] as String?) ?? trimmedCategory,
      subcategoryId: map['subcategoryId'] as String?,
      createdCategory: map['createdCategory'] == true,
      createdSubcategory: map['createdSubcategory'] == true,
    );
  }
}
