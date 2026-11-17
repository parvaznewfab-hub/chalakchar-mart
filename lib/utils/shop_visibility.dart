// The one rule for "does the shop show this product to customers".
// Every customer-facing list (home grid, related rows, search suggestions,
// search results, vendor shop, marketplace) filters through it. The server
// keeps the same rule for productSeo's related links (functions/index.js,
// `isVisible` next to pickRelatedRows).
//
// needsReview is a marketing gate, not a shop filter, so it is not checked.

String _text(dynamic v) => (v ?? '').toString().trim();

/// Active, approved, visible, published, no hiddenReason, and its category
/// is a switched-on category ([activeCategoriesLower]: lower-cased names).
/// A product whose category has no category doc (the old grocery items)
/// is not shown.
bool isShopVisibleProduct(Map<String, dynamic> p, Set<String> activeCategoriesLower) {
  if (p['isActive'] != true) return false;
  if (p['approvalStatus'] != 'approved') return false;
  if (p['isVisible'] == false || p['isPublished'] == false) return false;
  if (_text(p['hiddenReason']).isNotEmpty) return false;
  return activeCategoriesLower.contains(_text(p['category']).toLowerCase());
}

/// [items] the shop shows, in their original order. [dataOf] reads a
/// product map from an item (a Firestore doc's `data()`, or the map itself).
List<T> shopVisibleOnly<T>(
  Iterable<T> items,
  Set<String> activeCategoriesLower,
  Map<String, dynamic> Function(T item) dataOf,
) {
  return [
    for (final item in items)
      if (isShopVisibleProduct(dataOf(item), activeCategoriesLower)) item,
  ];
}
