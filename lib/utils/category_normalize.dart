import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Dart port of functions/category/categoryNormalize.js.
///
/// The backend resolvers (ensureCategoryExists / ensureSubcategoryExists)
/// dedupe on `normalizedName`. Anything the admin app writes to
/// `categories` or `subcategories` must produce the exact same key, or an
/// AliExpress/vendor import would create a duplicate next to an
/// admin-created entry. Parity is pinned by
/// test/category_normalize_parity_test.dart against outputs generated from
/// the JS implementation.

/// NFKC-normalize, collapse internal whitespace, trim, lowercase.
/// Used only as a lookup key, never displayed.
String normalizeCategoryKey(String? rawName) {
  final text = (rawName ?? '').trim();
  if (text.isEmpty) return '';
  return unorm
      .nfkc(text)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

/// URL-safe kebab-case slug base. Not unique on its own; callers append
/// "-2", "-3", ... on collision, same as generateUniqueSlug in JS.
String slugifyCategoryName(String? rawName) {
  final text = (rawName ?? '').trim();
  if (text.isEmpty) return '';
  return unorm
      .nfkc(text)
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .replaceAll(RegExp(r'-{2,}'), '-');
}
