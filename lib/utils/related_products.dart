// Picks the product page's two related rows from already-fetched candidates.
// The Firestore queries live in widgets/related_products_section.dart; this
// file is pure so the rules can be tested.
//
//   1) "এই মডেলের আরও পার্টস": a shared model key (iphone 12 pro max only
//      matches iphone 12 pro max). Fewer than 2 -> the same series instead,
//      titled "{series} সিরিজের আরও পার্টস". Fewer than 2 again -> hidden.
//   2) "একই ধরনের আরও পণ্য": same subcategory (else category), nearest
//      price first, at most 12, nothing already in row 1.
//
// Both: never the product itself, only what the shop shows (active,
// approved, visible, published, no hiddenReason, category switched on —
// needsReview is a marketing gate, not a shop filter), in stock first.

import '../services/product_service.dart';
import 'device_model.dart';

const int relatedRowMax = 12;
const int relatedModelRowMin = 2;

String _text(dynamic v) => (v ?? '').toString().trim();

/// Same rule as the home "all products" grid and the sitemap.
bool isShopVisibleProduct(Map<String, dynamic> p, Set<String> activeCategoriesLower) {
  if (p['isActive'] != true) return false;
  if (p['approvalStatus'] != 'approved') return false;
  if (p['isVisible'] == false || p['isPublished'] == false) return false;
  if (_text(p['hiddenReason']).isNotEmpty) return false;
  return activeCategoriesLower.contains(_text(p['category']).toLowerCase());
}

/// "iphone 12" -> "iPhone 12", "samsung a52" -> "Samsung A52",
/// "huawei nova 4" -> "Huawei Nova 4", "iphone x" -> "iPhone X".
String displayModelName(String key) {
  return key.split(' ').map((w) {
    if (w == 'iphone') return 'iPhone';
    if (RegExp(r'^[a-z]{1,2}$').hasMatch(w) || RegExp(r'^[a-z]\d').hasMatch(w)) return w.toUpperCase();
    if (w.isEmpty || RegExp(r'^\d').hasMatch(w)) return w;
    return w[0].toUpperCase() + w.substring(1);
  }).join(' ');
}

// One odd product doc (bad variants/price shape) must not break the rows:
// it counts as out of stock / price 0 instead.
int _stock(Map<String, dynamic> p) {
  try {
    return ProductService.getStock(ProductService.normalizeProductData(p));
  } catch (_) {
    return 0;
  }
}

double _price(Map<String, dynamic> p) {
  try {
    return ProductService.getDisplayPrice(ProductService.normalizeProductData(p));
  } catch (_) {
    return 0;
  }
}

/// Keys stored on the doc, else derived from its name (not backfilled yet).
List<String> productModelKeys(Map<String, dynamic> p) {
  final stored = p['modelKeys'];
  if (stored is List && stored.isNotEmpty) return stored.map((e) => e.toString()).toList();
  return modelFieldsForName(_text(p['name'])).modelKeys;
}

List<String> productModelSeries(Map<String, dynamic> p) {
  final stored = p['modelSeries'];
  if (stored is List && stored.isNotEmpty) return stored.map((e) => e.toString()).toList();
  return modelFieldsForName(_text(p['name'])).modelSeries;
}

/// Runs what ProductCard runs on a product; a doc that would make the card
/// throw (odd variants/units/price shape) is left out of the rows, so it
/// cannot break the page. [onBadProduct] gets the error for the log.
bool cardSafe(Map<String, dynamic> p, [void Function(String id, Object error)? onBadProduct]) {
  try {
    final n = ProductService.normalizeProductData(p);
    ProductService.getDisplayPrice(n);
    ProductService.getDisplayMrp(n);
    ProductService.hasPriceRange(n);
    ProductService.getStock(n);
    ProductService.getUnits(n);
    return ProductService.productIdFrom(n).trim().isNotEmpty;
  } catch (e) {
    onBadProduct?.call(_text(p['id']), e);
    return false;
  }
}

void Function(String id, Object error)? relatedBadProductLogger;

List<Map<String, dynamic>> _clean(
  String currentId,
  Iterable<Map<String, dynamic>> candidates,
  Set<String> activeCategoriesLower,
  Set<String> excludeIds,
) {
  final seen = <String>{currentId, ...excludeIds};
  return [
    for (final p in candidates)
      if (seen.add(_text(p['id'])) &&
          isShopVisibleProduct(p, activeCategoriesLower) &&
          cardSafe(p, relatedBadProductLogger))
        p,
  ];
}

/// In-stock first; otherwise the given order (a stable sort).
List<Map<String, dynamic>> _inStockFirst(List<Map<String, dynamic>> list) {
  final inStock = [for (final p in list) if (_stock(p) > 0) p];
  final out = [for (final p in list) if (_stock(p) <= 0) p];
  return [...inStock, ...out];
}

typedef ModelRow = ({String title, List<Map<String, dynamic>> products});

/// Row 1, or null when it should be hidden. [exactCandidates] came from a
/// modelKeys query, [seriesCandidates] from a modelSeries query; both are
/// re-checked here (a doc may carry stale or name-derived keys).
ModelRow? pickModelRow({
  required Map<String, dynamic> current,
  required Iterable<Map<String, dynamic>> exactCandidates,
  required Iterable<Map<String, dynamic>> seriesCandidates,
  required Set<String> activeCategoriesLower,
}) {
  final id = _text(current['id']);
  final keys = productModelKeys(current).toSet();
  if (keys.isEmpty) return null;

  final exact = _clean(id, exactCandidates, activeCategoriesLower, const {})
      .where((p) => productModelKeys(p).any(keys.contains))
      .toList();
  if (exact.length >= relatedModelRowMin) {
    return (title: 'এই মডেলের আরও পার্টস', products: _inStockFirst(exact).take(relatedRowMax).toList());
  }

  final series = productModelSeries(current);
  final seriesSet = series.toSet();
  final inSeries = _clean(id, seriesCandidates, activeCategoriesLower, const {})
      .where((p) => productModelSeries(p).any(seriesSet.contains))
      .toList();
  if (inSeries.length < relatedModelRowMin) return null;

  // Name only the series the shown products share with this one.
  final shared = [
    for (final s in series)
      if (inSeries.any((p) => productModelSeries(p).contains(s))) s,
  ];
  final label = shared.take(2).map(displayModelName).join(' / ');
  return (title: '$label সিরিজের আরও পার্টস', products: _inStockFirst(inSeries).take(relatedRowMax).toList());
}

/// Row 2: same subcategory/category, nearest price first, in stock first.
List<Map<String, dynamic>> pickSimilarRow({
  required Map<String, dynamic> current,
  required Iterable<Map<String, dynamic>> candidates,
  required Set<String> activeCategoriesLower,
  Set<String> excludeIds = const {},
}) {
  final id = _text(current['id']);
  final subcategoryId = _text(current['subcategoryId']);
  final category = _text(current['category']).toLowerCase();
  final price = _price(current);
  final list = _clean(id, candidates, activeCategoriesLower, excludeIds)
      .where((p) => subcategoryId.isNotEmpty
          ? _text(p['subcategoryId']) == subcategoryId
          : _text(p['category']).toLowerCase() == category)
      .toList();
  // Same brand first (iPhone page: iPhone displays before Samsung), then
  // nearest price; in stock before out of stock above both.
  final brands = productBrands(current);
  int sameBrand(Map<String, dynamic> p) => brands.isNotEmpty && productBrands(p).any(brands.contains) ? 0 : 1;
  list.sort((a, b) {
    final byBrand = sameBrand(a).compareTo(sameBrand(b));
    if (byBrand != 0) return byBrand;
    return (_price(a) - price).abs().compareTo((_price(b) - price).abs());
  });
  return _inStockFirst(list).take(relatedRowMax).toList();
}

/// Brands named by a product's model keys: "iphone 12" -> iphone,
/// "samsung a52s" -> samsung, "redmi note 9" -> redmi. Empty when the
/// name has no device model (e.g. an SSD).
Set<String> productBrands(Map<String, dynamic> p) =>
    {for (final k in productModelKeys(p)) k.split(' ').first};
