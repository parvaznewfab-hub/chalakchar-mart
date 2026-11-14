import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/category_service.dart';

/// Bundled flat icon for a category, used whenever the admin-uploaded
/// image is missing or fails to load. Picked by keywords in the name so
/// new categories get a sensible icon without code changes.
class CategoryFallbackIcon {
  CategoryFallbackIcon._();

  static const computerAccessories =
      'assets/icons/category_computer_accessories.svg';
  static const mobileParts = 'assets/icons/category_mobile_parts.svg';
  static const motherboard = 'assets/icons/category_motherboard.svg';
  static const generic = 'assets/icons/category_generic.svg';

  static final _motherboard = RegExp(r'\b(mother|main)board\b');
  static final _mobile = RegExp(r'\b(mobile|phones?|smartphones?)\b');
  static final _computer =
      RegExp(r'\b(computers?|pc|laptops?|keyboards?|mouse)\b');

  static String assetFor(String categoryName) {
    final name = categoryName.toLowerCase();
    if (_motherboard.hasMatch(name)) return motherboard;
    if (_mobile.hasMatch(name)) return mobileParts;
    if (_computer.hasMatch(name)) return computerAccessories;
    return generic;
  }
}

/// "Product Categories" grid on the desktop home page.
///
/// Up to 4 categories sit in one left-aligned row of cards no wider than
/// [maxCardWidth]; more fall into an auto-fill grid with cards at least
/// [minCardWidth] wide. Below 600px it is a fixed 3-per-row grid.
class HomeCategoryGrid extends StatelessWidget {
  const HomeCategoryGrid({
    super.key,
    required this.categories,
    required this.onTap,
    this.imageProviderFor = _networkImage,
  });

  final List<CategoryModel> categories;
  final ValueChanged<CategoryModel> onTap;

  /// Resolves an uploaded image URL. Tests swap this to feed mock images
  /// without touching the network.
  final ImageProvider Function(String url) imageProviderFor;

  static const double minCardWidth = 140;
  static const double maxCardWidth = 200;
  static const double maxTileSize = 140;
  static const double _narrowBreakpoint = 600;

  static ImageProvider _networkImage(String url) => NetworkImage(url);

  /// Column count for [count] cards in [width] logical pixels.
  static int columnsFor(int count, double width) {
    if (width < _narrowBreakpoint) return 3;
    final gap = gapFor(width);
    final fit = ((width + gap) / (minCardWidth + gap)).floor().clamp(1, 1 << 20);
    if (count <= 4) return count <= fit ? count : fit;
    return fit;
  }

  static double gapFor(double width) => width < _narrowBreakpoint ? 12 : 20;

  /// Card width for [count] cards in [width]: an even share of the row,
  /// capped so a few cards on a wide screen don't balloon.
  static double cardWidthFor(int count, double width) {
    final gap = gapFor(width);
    final columns = columnsFor(count, width);
    final share = (width - gap * (columns - 1)) / columns;
    return share < maxCardWidth ? share : maxCardWidth;
  }

  @override
  Widget build(BuildContext context) {
    final visible = categories.where((c) => c.name.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gap = gapFor(width);
        final columns = columnsFor(visible.length, width);
        final cardWidth = cardWidthFor(visible.length, width);
        // Narrow (3-up) cards are ~100px wide: tighter padding and a smaller
        // font keep single words like "Motherboard" from breaking mid-word.
        final compact = width < _narrowBreakpoint;
        final padding = compact ? 8.0 : 12.0;
        // Inner width = card minus padding and 1px border on each side.
        final tileSize = (cardWidth - 2 * padding - 2)
            .clamp(0.0, maxTileSize)
            .toDouble();

        final rows = <Widget>[];
        for (var start = 0; start < visible.length; start += columns) {
          final rowItems = visible.skip(start).take(columns).toList();
          if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rowItems.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: cardWidth,
                      child: _HomeCategoryCard(
                        category: rowItems[i],
                        onTap: () => onTap(rowItems[i]),
                        tileSize: tileSize,
                        padding: padding,
                        fontSize: compact ? 12.5 : 14,
                        imageProviderFor: imageProviderFor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

class _HomeCategoryCard extends StatefulWidget {
  const _HomeCategoryCard({
    required this.category,
    required this.onTap,
    required this.tileSize,
    required this.padding,
    required this.fontSize,
    required this.imageProviderFor,
  });

  final CategoryModel category;
  final VoidCallback onTap;
  final double tileSize;
  final double padding;
  final double fontSize;
  final ImageProvider Function(String url) imageProviderFor;

  @override
  State<_HomeCategoryCard> createState() => _HomeCategoryCardState();
}

class _HomeCategoryCardState extends State<_HomeCategoryCard> {
  static const _tileColor = Color(0xFFEFF7FA);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.category.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
            padding: EdgeInsets.all(widget.padding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.10 : 0.03),
                  blurRadius: _hovered ? 18 : 10,
                  offset: Offset(0, _hovered ? 8 : 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: widget.tileSize,
                  height: widget.tileSize,
                  padding: EdgeInsets.all(widget.tileSize * 0.14),
                  decoration: BoxDecoration(
                    color: _tileColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _CategoryImage(
                    category: widget.category,
                    imageProviderFor: widget.imageProviderFor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: widget.fontSize,
                    height: 1.3,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uploaded image when there is one, the bundled SVG otherwise — including
/// when the upload fails to load, so a broken-image glyph never shows.
class _CategoryImage extends StatelessWidget {
  const _CategoryImage({
    required this.category,
    required this.imageProviderFor,
  });

  final CategoryModel category;
  final ImageProvider Function(String url) imageProviderFor;

  @override
  Widget build(BuildContext context) {
    final fallback = SvgPicture.asset(
      CategoryFallbackIcon.assetFor(category.name),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    if (category.imageUrl.isEmpty) return fallback;

    return Image(
      image: imageProviderFor(category.imageUrl),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      // Empty tile while loading, then a short fade-in.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: child,
        );
      },
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
