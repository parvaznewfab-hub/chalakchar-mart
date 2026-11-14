// Pure presentation decisions for the product-details variant selector and
// gallery. Kept free of Flutter imports so it is unit-testable.

/// True when variant images carry no information to tell options apart —
/// every variant's image is missing, or all present ones are the same URL
/// (common for AliExpress storage/size SKUs that reuse the product photo).
/// In that case the selector must render text chips, not identical swatches.
bool variantsShareOneImage(Iterable<String> variantImages) {
  final distinct = variantImages
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  return distinct.length <= 1;
}

/// The label shown before the selected value, e.g. "Capacity" in
/// "Capacity: 4TB". Order:
///   1. product `variantAttributeName` (manual, admin-set),
///   2. subcategory `variantLabel` (admin default, e.g. "Model"),
///   3. category `variantLabel`,
///   4. "Color"    — only if MOST values are real colours ("Rose Gold",
///                   "Light Blue"; not "TFT Black Frame"),
///   5. "Capacity" — MOST values start with a storage size ("4TB Black"),
///   6. "Size"     — every value is a clothing size (S, M, XL, 3XL),
///   7. "Option".
/// AliExpress's own name (variants[].sourceAttributeName) and per-variant
/// attributeName are deliberately not used: sellers misuse "Color" for
/// models/storage/frames (70 of 71 products, 2026-11-14).
///
/// Mirrored in functions/catalog/variantLabel.js; both are checked against
/// test/fixtures/variant_label_cases.json — change them together.
String resolveVariantAttributeLabel({
  String? productAttributeName,
  String? subcategoryLabel,
  String? categoryLabel,
  Iterable<String> variantValues = const [],
}) {
  for (final explicit in [productAttributeName, subcategoryLabel, categoryLabel]) {
    final label = (explicit ?? '').trim();
    if (label.isNotEmpty) return label;
  }

  final values = variantValues
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  if (values.isEmpty) return 'Option';
  if (values.where(isColourValue).length * 2 > values.length) return 'Color';
  if (values.where(_storagePrefix.hasMatch).length * 2 > values.length) {
    return 'Capacity';
  }
  if (values.every(_size.hasMatch)) return 'Size';
  return 'Option';
}

/// Starts with a storage size: "512GB", "1 TB", "4TB Black" (not "256g").
final _storagePrefix =
    RegExp(r'^\d+(\.\d+)?\s?(GB|TB|MB)(?![A-Za-z])', caseSensitive: false);
final _size =
    RegExp(r'^(XXS|XS|S|M|L|XL|XXL|XXXL|[2-6]XL)$', caseSensitive: false);

const _colours = {
  'black', 'white', 'red', 'blue', 'green', 'yellow', 'pink', 'purple',
  'violet', 'orange', 'brown', 'grey', 'gray', 'silver', 'gold', 'golden',
  'beige', 'ivory', 'cream', 'khaki', 'navy', 'teal', 'cyan', 'turquoise',
  'aqua', 'magenta', 'maroon', 'burgundy', 'wine', 'coffee', 'chocolate',
  'tan', 'camel', 'champagne', 'bronze', 'copper', 'rose', 'lavender',
  'lilac', 'mint', 'olive', 'coral', 'peach', 'apricot', 'lemon',
  'transparent', 'clear', 'multicolor', 'multicolour', 'colorful',
  'colourful', 'rainbow', 'graphite', 'titanium',
};
const _colourModifiers = {
  'light', 'dark', 'deep', 'pale', 'bright', 'matte', 'matt', 'glossy',
  'metallic', 'sky', 'royal', 'army', 'hot', 'baby', 'neon', 'pastel',
  'space', 'midnight', 'starlight', 'jet', 'pure', 'off', 'and',
};

/// True when every word is a colour or colour modifier, with at least one
/// colour ("Rose Gold", "Sky Blue", "Black-Red"; not "Black Frame").
bool isColourValue(String value) {
  final tokens = value
      .toLowerCase()
      .split(RegExp(r'[\s\-&+,/]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return false;
  var colours = 0;
  for (final t in tokens) {
    if (_colours.contains(t)) {
      colours++;
    } else if (!_colourModifiers.contains(t)) {
      return false;
    }
  }
  return colours > 0;
}

/// Number of thumbnails the gallery strip renders: every gallery image plus
/// one for the video. The strip is only shown when there is more than one
/// item to choose from, so 0 means "no strip".
int galleryThumbnailCount({required int imageCount, required bool hasVideo}) {
  final total = imageCount + (hasVideo ? 1 : 0);
  return (imageCount > 1 || hasVideo) ? total : 0;
}

/// "Item X/Y" badge text, or null when it should be hidden: no thumbnail
/// strip to count against, or the main image is a variant-only override
/// that has no thumbnail (a position claim would point at nothing).
String? galleryCounterLabel({
  required int selectedIndex,
  required int imageCount,
  required bool hasVideo,
  required bool showingOverride,
}) {
  final total =
      galleryThumbnailCount(imageCount: imageCount, hasVideo: hasVideo);
  if (total == 0 || showingOverride) return null;
  if (selectedIndex < 0 || selectedIndex >= imageCount) return null;
  return 'Item ${selectedIndex + 1}/$total';
}

/// Columns that fit in [availableWidth] for items of [itemWidth] separated
/// by [spacing]. Always at least 1.
int gridColumns({
  required double availableWidth,
  required double itemWidth,
  double spacing = 10,
}) {
  final n = ((availableWidth + spacing) / (itemWidth + spacing)).floor();
  return n < 1 ? 1 : n;
}

/// Mobile variant collapse: with more than [threshold] options that don't
/// fit in [rows] rows of [perRow], show the first `rows * perRow - 1`
/// options and use the last slot for "+N more". Returns how many options to
/// show, or null to show them all — including when the selected option
/// would otherwise be hidden (never hide the current selection).
int? collapsedOptionCount({
  required int total,
  required int perRow,
  required int selectedIndex,
  int threshold = 8,
  int rows = 2,
}) {
  final slots = rows * perRow;
  if (total <= threshold || total <= slots) return null;
  final visible = slots - 1;
  if (visible < 1 || selectedIndex >= visible) return null;
  return visible;
}

final _storageSizeParts =
    RegExp(r'^(\d+(?:\.\d+)?)\s?(GB|TB|MB)(?![A-Za-z])', caseSensitive: false);

/// Size in MB when [value] starts with a storage size ("4TB Black" -> 4194304),
/// else null.
double? storageSizeInMb(String value) {
  final m = _storageSizeParts.firstMatch(value.trim());
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  switch (m.group(2)!.toUpperCase()) {
    case 'TB':
      return n * 1024 * 1024;
    case 'GB':
      return n * 1024;
    default:
      return n;
  }
}

/// Display order (indices into [values]) for variant chips: when most
/// values start with a storage size, those are sorted ascending
/// (128GB → 4TB; ties keep their original order) and any others follow in
/// their original order. Otherwise the original order is kept.
List<int> variantDisplayOrder(List<String> values) {
  final sizes = values.map(storageSizeInMb).toList();
  final indices = List<int>.generate(values.length, (i) => i);
  if (sizes.where((s) => s != null).length * 2 <= values.length) return indices;
  final sized = indices.where((i) => sizes[i] != null).toList()
    ..sort((a, b) {
      final c = sizes[a]!.compareTo(sizes[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [...sized, ...indices.where((i) => sizes[i] == null)];
}

/// Thumbnail strip sizing. When the strip scrolls ([visible] < [count]),
/// [thumb] is chosen so a whole number of thumbnails fills [width] exactly —
/// never a half-cut item at the edge — staying near [maxThumb] (it may
/// exceed it slightly to fill exactly) and never below [minThumb]. When
/// everything fits, thumbnails are at most [maxThumb].
({double thumb, int visible}) galleryStripLayout({
  required double width,
  required int count,
  double spacing = 10,
  double minThumb = 64,
  double maxThumb = 86,
}) {
  if (count <= 0 || width <= 0) return (thumb: maxThumb, visible: 0);
  var n = ((width + spacing) / (maxThumb + spacing)).ceil();
  if (n > count) n = count;
  double size(int k) => (width - spacing * (k - 1)) / k;
  while (n > 1 && size(n) < minThumb) {
    n--;
  }
  final exact = size(n);
  final thumb = n >= count ? (exact < maxThumb ? exact : maxThumb) : exact;
  return (thumb: thumb, visible: n);
}

/// Variant to select when the page opens: the first in-stock one in display
/// order ([variantDisplayOrder]; e.g. Netac → 128GB, not the stored first
/// 4TB), else the first in display order. -1 when [displayValues] is empty.
int defaultVariantIndex(List<String> displayValues, List<int> stocks) {
  final order = variantDisplayOrder(displayValues);
  if (order.isEmpty) return -1;
  for (final i in order) {
    if (i < stocks.length && stocks[i] > 0) return i;
  }
  return order.first;
}
