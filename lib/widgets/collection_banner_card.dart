import 'package:flutter/material.dart';

/// One cell of a collection ("amazon_grid") banner.
///
/// Firestore shape (`banners/{id}.items[]`):
/// `{imageUrl, title, clickActionType, clickValue, categoryName?}` where
/// clickActionType is product | subcategory | category | url | search | none.
/// For `subcategory`, clickValue is the subcategory slug and categoryName is
/// its parent category (falls back to the banner's categoryName).
class CollectionBannerItem {
  const CollectionBannerItem({
    required this.imageUrl,
    required this.label,
    this.actionType = '',
    this.actionValue = '',
    this.categoryName = '',
  });

  final String imageUrl;

  /// Real product / subcategory name; empty when the admin left the default.
  final String label;
  final String actionType;
  final String actionValue;
  final String categoryName;

  static final RegExp _placeholderLabel =
      RegExp(r'^(item\s*\d+|featured item)$', caseSensitive: false);

  /// True for the admin form's old default names ("Item 1".."Item 4").
  static bool isPlaceholderLabel(String text) =>
      _placeholderLabel.hasMatch(text.trim());

  static String _s(dynamic v) => v?.toString().trim() ?? '';

  static CollectionBannerItem? fromMap(Map<dynamic, dynamic> map) {
    final imageUrl = _s(map['imageUrl']);
    final rawLabel = _s(map['title']);
    final label = isPlaceholderLabel(rawLabel) ? '' : rawLabel;
    final actionType = _s(map['clickActionType']).toLowerCase();
    final actionValue = _s(map['clickValue']);
    // An item with nothing to show and nowhere to go is skipped.
    if (imageUrl.isEmpty && label.isEmpty) return null;
    return CollectionBannerItem(
      imageUrl: imageUrl,
      label: label,
      actionType: actionType,
      actionValue: actionValue,
      categoryName: _s(map['categoryName']),
    );
  }

  /// Parses `banners/{id}.items`, keeping at most [max] usable items.
  static List<CollectionBannerItem> listFrom(dynamic raw, {int max = 4}) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(fromMap)
        .whereType<CollectionBannerItem>()
        .take(max)
        .toList();
  }
}

/// Collection banner: title row + up to 4 item cells.
///
/// Height comes from the content: the title (max 2 lines), and square image
/// cells whose size follows [width]. Item count decides the grid:
/// 4 → 2x2 (1x4 when the card is wide), 3 → one row of 3,
/// 2 → one row of 2, 1 → a single wide image.
class CollectionBannerCard extends StatelessWidget {
  const CollectionBannerCard({
    super.key,
    required this.title,
    required this.items,
    required this.width,
    this.subtitle = '',
    this.isDesktop = false,
    this.onHeaderTap,
    this.onItemTap,
    this.imageBuilder,
  });

  final String title;
  final String subtitle;
  final List<CollectionBannerItem> items;

  /// Card width from the parent; the grid is laid out for it.
  final double width;
  final bool isDesktop;
  final VoidCallback? onHeaderTap;
  final ValueChanged<CollectionBannerItem>? onItemTap;

  /// Overrides how an image URL is drawn (used by tests); returning null
  /// uses the default [Image.network] with a placeholder on error.
  final Widget? Function(BuildContext context, String url)? imageBuilder;

  static const Color _accent = Color(0xFF32A8C7);

  /// Card width at which 4 items go in one row instead of 2x2.
  static const double _oneRowBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final double pad = isDesktop ? 16 : 12;
    final double gap = isDesktop ? 12 : 8;

    return Container(
      width: width,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 13),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty || subtitle.isNotEmpty) _header(),
          if (items.isNotEmpty) ...[
            SizedBox(height: isDesktop ? 12 : 10),
            _grid(context, gap),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return InkWell(
      onTap: onHeaderTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isDesktop ? 20 : 17,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 12,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: _accent),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, double gap) {
    final n = items.length;
    if (n == 1) {
      return _cell(context, items.first, aspectRatio: 2);
    }

    final int columns =
        n == 4 ? (width >= _oneRowBreakpoint ? 4 : 2) : n; // 2 or 3 → one row
    final rows = <Widget>[];
    for (int start = 0; start < n; start += columns) {
      final rowItems = items.sublist(start, (start + columns).clamp(0, n));
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rowItems.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: _cell(context, rowItems[i], aspectRatio: 1)),
          ],
        ],
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _cell(
    BuildContext context,
    CollectionBannerItem item, {
    required double aspectRatio,
  }) {
    final bool dense = !isDesktop;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onItemTap == null ? null : () => onItemTap!(item),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: _image(context, item.imageUrl),
              ),
            ),
            if (item.label.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(2, dense ? 5 : 7, 2, 0),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _image(BuildContext context, String url) {
    if (url.isEmpty) return const _ImagePlaceholder();
    final custom = imageBuilder?.call(context, url);
    if (custom != null) return custom;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}
