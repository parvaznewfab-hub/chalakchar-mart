import 'package:flutter/material.dart';

import '../services/product_service.dart';
import '../utils/price_format.dart';
import '../utils/variant_display_name.dart';
import '../utils/variant_selector_model.dart';

/// Product-details variant picker.
///
/// - Every option shows its value as text. When the variants have their own
///   pictures, a small thumbnail sits to the left of the value (pictures
///   alone often look identical, e.g. motherboard SKUs); when they share one
///   picture (or have none) the option is a plain text chip.
/// - The price is shown under the value when variant prices differ.
/// - Label: product variantAttributeName, then the subcategory/category
///   default ([subcategoryLabel]/[categoryLabel]), else inferred from the
///   values ("Capacity: 4TB"); "Color" only when the values are colours.
/// - Out-of-stock options are greyed and struck through but stay tappable,
///   so shoppers can still view them.
/// - Options are ordered with storage sizes ascending (128GB → 4TB); other
///   values keep their stored order ([variantDisplayOrder]).
/// - Mobile (< 800px, the page's breakpoint) — and desktop picture options —
///   sit in an even grid of equal-height cells (picture options two per
///   row, value wraps to two lines). With more than 8 that don't fit in two
///   rows (mobile) / three rows (desktop), the last slot becomes "+N more"
///   (expands in place, "Show less" collapses again).
///
/// Works on raw or ProductService-normalized data (both keep name, price,
/// stock, image/imageUrl per variant).
class VariantSelector extends StatefulWidget {
  final Map<String, dynamic> data;
  final String selectedUnit;
  final ValueChanged<String> onSelect;

  /// Default labels from the product's subcategory / category docs
  /// (`variantLabel`); '' when unset or not loaded yet.
  final String subcategoryLabel;
  final String categoryLabel;

  const VariantSelector({
    super.key,
    required this.data,
    required this.selectedUnit,
    required this.onSelect,
    this.subcategoryLabel = '',
    this.categoryLabel = '',
  });

  static const double mobileBreakpoint = 800;

  static List<Map> rawVariants(Map<String, dynamic> data) {
    final raw = data['variants'];
    return raw is List ? raw.whereType<Map>().toList() : <Map>[];
  }

  /// Whether the selector renders at all (needs 2+ variants).
  static bool isShownFor(Map<String, dynamic> data) =>
      rawVariants(data).length > 1;

  @override
  State<VariantSelector> createState() => _VariantSelectorState();
}

class _VariantSelectorState extends State<VariantSelector> {
  static const Color _primary = Color(0xFF32A8C7);
  static const Color _darkText = Color(0xFF111827);
  static const Color _mutedText = Color(0xFF6B7280);
  static const double _spacing = 10;
  static const double _thumb = 36;
  static const double _thumbGap = 8;
  static const double _chipHPad = 14;
  static const double _chipHPadMobile = 10;
  static const double _chipVPad = 8;
  static const double _border = 2; // selected border width (per side)
  static const double _minPictureCell = 140;
  static const double _minTextCell = 96;
  static const TextStyle _chipNameStyle =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
  static const TextStyle _chipPriceStyle =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  bool _expanded = false;

  static String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final stored = VariantSelector.rawVariants(data);
    if (stored.length <= 1) return const SizedBox.shrink();
    // Storage sizes ascending (128GB → 4TB); other values keep their order.
    final variants = [
      for (final i in variantDisplayOrder([
        for (final v in stored)
          cleanVariantDisplayName(_text(v['name'], 'Option'))
      ]))
        stored[i]
    ];

    final names = [for (final v in variants) _text(v['name'], 'Option')];
    final displays = names.map(cleanVariantDisplayName).toList();
    final ownImages = [
      for (final v in variants) _text(v['imageUrl'] ?? v['image'])
    ];
    final withPictures = !variantsShareOneImage(ownImages);
    final fallbackImage = _text(data['imageUrl'] ?? data['image']);

    final prices = [
      for (final n in names) ProductService.getDisplayPrice(data, unit: n)
    ];
    // Per-variant prices are only worth the space when they actually differ.
    final showPrices = prices.where((p) => p > 0).toSet().length > 1;

    final label = resolveVariantAttributeLabel(
      productAttributeName: _text(data['variantAttributeName']),
      subcategoryLabel: widget.subcategoryLabel,
      categoryLabel: widget.categoryLabel,
      variantValues: displays,
    );
    final selectedUnit = widget.selectedUnit;
    final selectedOut = ProductService.getStock(data, unit: selectedUnit) <= 0;
    final isMobile =
        MediaQuery.sizeOf(context).width < VariantSelector.mobileBreakpoint;
    // Tighter padding for text chips (they sit in narrow grid cells).
    final hPad = isMobile || !withPictures ? _chipHPadMobile : _chipHPad;

    Widget option(int i, {double? width, double? height}) => _option(
          hPad: hPad,
          name: names[i],
          display: displays[i],
          selected: names[i] == selectedUnit,
          outOfStock: ProductService.getStock(data, unit: names[i]) <= 0,
          image: withPictures ? _text(ownImages[i], fallbackImage) : null,
          price: showPrices && prices[i] > 0 ? prices[i] : null,
          width: width,
          height: height,
        );

    final header = Text.rich(
      key: const Key('variant-label'),
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
                color: Colors.grey.shade700, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: cleanVariantDisplayName(selectedUnit)),
          if (selectedOut)
            const TextSpan(
              text: '  (Out of stock)',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
    );

    // Always an even grid of equal cells (collapsible): a free-flowing wrap
    // of different-width chips can't keep a steady 2 per row in the narrow
    // 800–1000px desktop column, and picture options would stack one per row.
    final maxRows = isMobile ? 2 : 3;

    final Widget options = LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth;
      final scaler = MediaQuery.textScalerOf(context);
      // Measure in the font the chips actually inherit.
      final base = DefaultTextStyle.of(context).style;
      final nameStyle = base.merge(_chipNameStyle);
      final priceStyle = base.merge(_chipPriceStyle);
      final leading = withPictures ? _thumb + _thumbGap : 0.0;
      final chrome = hPad * 2 + _border * 2;

      TextPainter paint(String text, TextStyle style,
              {double maxWidth = double.infinity, int maxLines = 1}) =>
          TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: maxWidth);

      // Columns: fit the widest one-line value; picture options keep two
      // per row whenever they can (their values may then wrap).
      var widest = 0.0;
      for (final d in displays) {
        final w = paint(d, nameStyle).width;
        if (w > widest) widest = w;
      }
      if (showPrices) {
        for (final p in prices) {
          final w = paint(formatTaka(p), priceStyle).width;
          if (w > widest) widest = w;
        }
      }
      final itemWidth = (widest + leading + chrome).clamp(64.0, available);
      var perRow = gridColumns(
          availableWidth: available, itemWidth: itemWidth, spacing: _spacing);
      if (withPictures) {
        // Two per row whenever the column allows it (values may wrap).
        if (!isMobile) perRow = 1;
        if (perRow < 2 && available >= 2 * _minPictureCell + _spacing) {
          perRow = 2;
        }
      } else if (perRow < 2 && available >= 2 * _minTextCell + _spacing) {
        // Short text values: at least two per row (may wrap to 2 lines).
        perRow = 2;
      }
      final cellWidth = (available - _spacing * (perRow - 1)) / perRow;

      // One height for every cell (tallest wrapped value + price), so the
      // grid rows line up and "+N more" matches.
      final textWidth = (cellWidth - leading - chrome).clamp(24.0, available);
      var textHeight = 0.0;
      for (final d in displays) {
        final h = paint(d, nameStyle, maxWidth: textWidth, maxLines: 2).height;
        if (h > textHeight) textHeight = h;
      }
      if (showPrices) {
        // Measure the real strings: "৳" comes from the fallback font,
        // whose line metrics are taller than the digits'.
        var priceHeight = 0.0;
        for (final p in prices) {
          final h = paint(formatTaka(p), priceStyle).height;
          if (h > priceHeight) priceHeight = h;
        }
        textHeight += 2 + priceHeight;
      }
      final contentHeight =
          withPictures && _thumb > textHeight ? _thumb : textHeight;
      final cellHeight = contentHeight + _chipVPad * 2 + _border * 2;

      final collapsed = _expanded
          ? null
          : collapsedOptionCount(
              total: names.length,
              perRow: perRow,
              selectedIndex: names.indexOf(selectedUnit),
              rows: maxRows,
            );
      final canCollapse = collapsedOptionCount(
            total: names.length,
            perRow: perRow,
            selectedIndex: 0,
            rows: maxRows,
          ) !=
          null;
      final shown = collapsed ?? names.length;

      return Wrap(
        spacing: _spacing,
        runSpacing: _spacing,
        children: [
          for (var i = 0; i < shown; i++)
            option(i, width: cellWidth, height: cellHeight),
          if (collapsed != null)
            _toggleTile(
              key: const Key('variant-more'),
              text: '+${names.length - shown} more',
              width: cellWidth,
              height: cellHeight,
              onTap: () => setState(() => _expanded = true),
            )
          else if (_expanded && canCollapse)
            _toggleTile(
              key: const Key('variant-less'),
              text: 'Show less',
              width: cellWidth,
              height: cellHeight,
              onTap: () => setState(() => _expanded = false),
            ),
        ],
      );
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, const SizedBox(height: 10), options],
    );
  }

  Widget _toggleTile({
    required Key key,
    required String text,
    required double width,
    required double height,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _primary.withValues(alpha: 0.5)),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: _primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option({
    required String name,
    required String display,
    required bool selected,
    required bool outOfStock,
    required double hPad,
    String? image,
    double? price,
    double? width,
    double? height,
  }) {
    final borderColor = selected
        ? _primary
        : (outOfStock ? Colors.grey.shade200 : Colors.grey.shade300);
    final textColor = outOfStock ? Colors.grey.shade500 : _darkText;
    final hasPicture = image != null;

    final value = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          hasPicture ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          display,
          textAlign: hasPicture ? TextAlign.start : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: textColor,
            decoration: outOfStock ? TextDecoration.lineThrough : null,
            decorationColor: textColor,
          ),
        ),
        if (price != null) ...[
          const SizedBox(height: 2),
          Text(
            formatTaka(price),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: outOfStock ? Colors.grey.shade500 : _mutedText,
              decoration: outOfStock ? TextDecoration.lineThrough : null,
              decorationColor: Colors.grey.shade500,
            ),
          ),
        ],
      ],
    );

    final body = Container(
      key: ValueKey('${hasPicture ? 'variant-swatch' : 'variant-chip'}-$name'),
      width: width,
      height: height,
      constraints: BoxConstraints(
        minWidth: 64,
        minHeight: 40,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: hPad + (selected ? 0 : _border - 1),
        vertical: _chipVPad + (selected ? 0 : _border - 1),
      ),
      // Only grid cells (fixed width) align their content; a Container with
      // an alignment expands to its max width, which made desktop text chips
      // full-width. Desktop text chips size to their content and wrap.
      alignment: width == null
          ? null
          : (hasPicture ? Alignment.centerLeft : Alignment.center),
      decoration: BoxDecoration(
        color: outOfStock
            ? Colors.grey.shade100
            : (selected ? _primary.withValues(alpha: 0.08) : Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: selected ? _border : 1),
      ),
      child: hasPicture
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Opacity(
                    opacity: outOfStock ? 0.4 : 1,
                    child: SizedBox(
                      width: _thumb,
                      height: _thumb,
                      child: image.isNotEmpty
                          ? Image.network(
                              image,
                              fit: BoxFit.cover,
                              // Neutral box while loading (no empty gap).
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(color: Colors.grey.shade100),
                              errorBuilder: (_, __, ___) => _fallback(name),
                            )
                          : _fallback(name),
                    ),
                  ),
                ),
                const SizedBox(width: _thumbGap),
                Flexible(child: value),
              ],
            )
          : value,
    );

    final tooltip = [
      display,
      if (price != null) formatTaka(price),
      if (outOfStock) 'Out of stock',
    ].join(' · ');

    // One accessible label per option (the tooltip and the visible texts
    // would otherwise each be announced).
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect(name),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _fallback(String name) {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style:
            TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade600),
      ),
    );
  }
}
