import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../utils/variant_selector_model.dart';

/// Horizontal product-gallery thumbnail strip.
///
/// - Thumbnails are sized so a whole number of them fills the column
///   ([galleryStripLayout]) — never a half-cut item at the edge.
/// - When there are more than fit, arrow buttons sit in their own columns
///   at both ends (the visible cue that the strip scrolls; greyed out at
///   the ends) and thumbnails fit whole between them. Mouse drag also
///   scrolls (Flutter web doesn't drag-scroll with a mouse by default).
/// - The selected item is scrolled into view when it changes.
class GalleryThumbnailStrip extends StatefulWidget {
  final int itemCount;
  final int? selectedIndex;

  /// Horizontal inset (e.g. the mobile page gutter).
  final EdgeInsets padding;


  /// Builds item [index] at [size] x [size].
  final Widget Function(BuildContext context, int index, double size) itemBuilder;

  static const double spacing = 10;

  const GalleryThumbnailStrip({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.selectedIndex,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<GalleryThumbnailStrip> createState() => _GalleryThumbnailStripState();
}

class _GalleryThumbnailStripState extends State<GalleryThumbnailStrip> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;
  double _step = 0; // one thumbnail + spacing

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
  }

  @override
  void didUpdateWidget(covariant GalleryThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final back = p.pixels > 0.5;
    final forward = p.pixels < p.maxScrollExtent - 0.5;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _revealSelected() {
    final i = widget.selectedIndex;
    if (i == null || !_controller.hasClients || _step <= 0) return;
    final p = _controller.position;
    final start = i * _step;
    final end = start + _step - GalleryThumbnailStrip.spacing;
    double? target;
    if (start < p.pixels) target = start;
    if (end > p.pixels + p.viewportDimension) target = end - p.viewportDimension;
    if (target != null) {
      _controller.animateTo(target.clamp(0.0, p.maxScrollExtent),
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    // Move by the visible thumbnails minus one, landing on an item edge.
    final visible = math.max(1, (p.viewportDimension / _step).floor() - 1);
    final raw = p.pixels + direction * visible * _step;
    final snapped = (raw / _step).round() * _step;
    _controller.animateTo(snapped.clamp(0.0, p.maxScrollExtent),
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final inner = constraints.maxWidth - widget.padding.horizontal;
      // If everything fits, no arrows. Otherwise reserve a column for each
      // arrow and fit whole thumbnails into the space between them, so an
      // arrow never covers (and visually cuts) a thumbnail.
      final full = galleryStripLayout(
          width: inner, count: widget.itemCount, spacing: GalleryThumbnailStrip.spacing);
      final scrolls = full.visible < widget.itemCount;
      final listWidth = scrolls ? inner - 2 * (_arrowSize + _arrowGap) : inner;
      final layout = scrolls
          ? galleryStripLayout(
              width: listWidth, count: widget.itemCount, spacing: GalleryThumbnailStrip.spacing)
          : full;
      final thumb = layout.thumb;
      _step = thumb + GalleryThumbnailStrip.spacing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateArrows();
      });

      final list = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
          scrollbars: false,
        ),
        child: ListView.separated(
          key: const Key('gallery-strip'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) =>
              const SizedBox(width: GalleryThumbnailStrip.spacing),
          itemBuilder: (context, index) => SizedBox(
            width: thumb,
            height: thumb,
            child: widget.itemBuilder(context, index, thumb),
          ),
        ),
      );

      return Padding(
        padding: widget.padding,
        child: SizedBox(
          height: thumb,
          child: Row(
            children: [
              if (scrolls) ...[
                _arrow(left: true, enabled: _canBack),
                const SizedBox(width: _arrowGap),
              ],
              SizedBox(width: listWidth, child: list),
              if (scrolls) ...[
                const SizedBox(width: _arrowGap),
                _arrow(left: false, enabled: _canForward),
              ],
            ],
          ),
        ),
      );
    });
  }

  static const double _arrowSize = 28;
  static const double _arrowGap = 4;

  /// Edge arrow: always shown while the strip scrolls (greyed out at that
  /// end), so the layout never jumps and the cue is always visible.
  Widget _arrow({required bool left, required bool enabled}) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: left ? 'Previous images' : 'More images',
      excludeSemantics: true,
      child: SizedBox(
        key: Key(left ? 'gallery-strip-prev' : 'gallery-strip-next'),
        width: _arrowSize,
        height: _arrowSize,
        child: Material(
          color: Colors.white,
          shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
          elevation: enabled ? 1 : 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => _page(left ? -1 : 1) : null,
            child: Icon(
              left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              size: 20,
              color: enabled ? const Color(0xFF111827) : Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }
}
