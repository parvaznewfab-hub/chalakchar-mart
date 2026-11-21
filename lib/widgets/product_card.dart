import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/guest_cart_service.dart';
import '../services/product_service.dart';
import '../utils/price_format.dart';
import '../utils/image_url.dart';

class ProductCard extends StatelessWidget {
  final dynamic data;
  final Function(GlobalKey)? onAddToCart;
  /// false (default): fixed 150px-wide card with outer margin, for
  /// horizontal lists / Wrap.
  /// true: card fills its grid cell exactly (no margin, no fixed width) —
  /// use together with [gridDelegate] so the cell height matches the content.
  final bool gridMode;

  static const double cardWidth = 150;
  static const double imageHeight = 112;
  static const double gridSpacing = 10;
  static const double gridHorizontalPadding = 12;

  // Text metrics the card height is computed from. Each style sets an
  // explicit line height, so a line is exactly fontSize * height.
  static const double _titleFontSize = 13;
  static const double _titleLineHeight = 1.25;
  static const int _titleMaxLines = 2;
  static const double _metaFontSize = 10;
  static const double _metaLineHeight = 1.3;
  // Price block (audit: 5-digit price + MRP + "+" overflowed one row):
  // line 1 = price + "থেকে", line 2 = struck-out MRP (space kept even
  // without an MRP so every card in a row is the same height).
  static const double _priceFontSize = 13;
  static const double _priceLineHeight = 1.25;
  static const double _mrpFontSize = 10;
  static const double _mrpLineHeight = 1.3;
  static const double _addButtonSize = 26;
  static const double _contentTopPadding = 5;
  static const double _contentBottomPadding = 8;
  static const double _lineGap = 2;

  // Outer margin of the fixed-width (row / Wrap) card.
  static const EdgeInsets _rowMargin = EdgeInsets.only(right: 12, bottom: 8, top: 4, left: 4);

  /// Exact card height: image + 2-line title + manufacturer line + price row
  /// + paddings, following the system text scale. Used for grid cells and
  /// for the fixed-width card itself, so neither leaves empty space.
  static double cardHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scaler.scale(_titleFontSize) * _titleLineHeight * _titleMaxLines;
    final meta = scaler.scale(_metaFontSize) * _metaLineHeight;
    final priceBlock = _PriceBlock.lineHeights(scaler).reduce((a, b) => a + b);
    final priceRow = priceBlock > _addButtonSize ? priceBlock : _addButtonSize;
    return (imageHeight +
            _contentTopPadding +
            title +
            _lineGap +
            meta +
            _lineGap +
            priceRow +
            _contentBottomPadding)
        .ceilToDouble();
  }

  /// Height of a horizontal list of fixed-width cards (card + its margin).
  static double rowHeight(BuildContext context) =>
      cardHeight(context) + _rowMargin.vertical;

  static double gridMainAxisExtent(BuildContext context) => cardHeight(context);

  static SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
    BuildContext context, {
    int crossAxisCount = 2,
  }) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisExtent: gridMainAxisExtent(context),
      mainAxisSpacing: gridSpacing,
      crossAxisSpacing: gridSpacing,
    );
  }

  const ProductCard({
    super.key,
    required this.data,
    this.onAddToCart,
    this.gridMode = false,
  });

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Future<void> _addToCart(
      BuildContext context,
      Map<String, dynamic> product,
      GlobalKey imageKey,
      ) async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null;

    final normalized = ProductService.normalizeProductData(product);

    if (normalized['isActive'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is currently inactive')),
      );
      return;
    }

    final variant = ProductService.firstVariant(normalized);
    final unit = ProductService.text(
      variant['name'],
      ProductService.text(normalized['unit'], 'Default'),
    );
    final stock = ProductService.getStock(normalized, unit: unit);

    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Out of stock')),
      );
      return;
    }

    final cartPayload = ProductService.buildCartItem(
      normalized,
      variant,
      qty: 1,
    );

    final cartDocId = ProductService.cartDocId(
      productId: ProductService.text(cartPayload['productId']),
      vendorId: ProductService.text(cartPayload['vendorId'], 'super_admin'),
      unit: ProductService.text(cartPayload['unit'], 'Default'),
    );

    try {
      onAddToCart?.call(imageKey);

      if (isGuest) {
        await GuestCartService.addItem(cartPayload);
      } else {
        await FirebaseFirestore.instance
            .collection('cart')
            .doc(user.uid)
            .collection('items')
            .doc(cartDocId)
            .set({
          ...cartPayload,
          'qty': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ProductService.text(normalized['name'], 'Product')} added to cart!',
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add to cart failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = ProductService.normalizeProductData(data);

    final imageKey = GlobalKey();
    const primaryColor = Color(0xFF1E7A3A);

    final name = _text(product['name'], 'Product Name');
    final strength = _text(product['strength']);
    final manufacturer = _text(product['manufacturer'] ?? product['brand']);
    final image = _text(product['image'] ?? product['imageUrl']);

    // "From" price: the cheapest in-stock variant, never simply the first.
    final price = ProductService.getDisplayPrice(product);
    final oldPrice = ProductService.getDisplayMrp(product);
    final hasPriceRange = ProductService.hasPriceRange(product);
    final stock = ProductService.getStock(product);
    final isOutOfStock = stock <= 0;
    final discount = discountPercent(price, oldPrice);

    void openProduct() {
      final productId = ProductService.productIdFrom(product).trim();
      if (productId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid product link')),
        );
        return;
      }
      Navigator.of(context, rootNavigator: true)
          .pushNamed('/product/$productId');
    }

    // With several variants the shopper must choose one, so "+" opens the
    // product page instead of silently adding some variant to the cart.
    final hasVariantChoice = ProductService.getUnits(product).length > 1;

    return GestureDetector(
      onTap: openProduct,
      child: Container(
        width: gridMode ? double.infinity : cardWidth,
        // Grid cells size the card; the fixed-width card sizes itself to the
        // same computed content height, so rows have no empty space.
        height: gridMode ? null : cardHeight(context),
        margin: gridMode ? EdgeInsets.zero : _rowMargin,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                        child: image.isNotEmpty
                            ? Image.network(
                          sizedImageUrl(image, 350),
                          key: imageKey,
                          fit: BoxFit.contain,
                          cacheWidth: 220,
                          cacheHeight: 180,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        )
                            : Container(
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    if (isOutOfStock)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    if (discount > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-$discount%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                _contentTopPadding,
                8,
                _contentBottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    maxLines: _titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    TextSpan(
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: _titleFontSize,
                        height: _titleLineHeight,
                      ),
                      children: [
                        TextSpan(text: '$name '),
                        if (strength.isNotEmpty)
                          TextSpan(
                            text: strength,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (manufacturer.isNotEmpty) ...[
                    const SizedBox(height: _lineGap),
                    Text(
                      manufacturer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: _metaFontSize,
                        height: _metaLineHeight,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                  // Pins the price row to the card bottom; any slack is the
                  // room reserved for a 1-line title or missing manufacturer.
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _PriceBlock(
                          price: price,
                          mrp: oldPrice,
                          isFromPrice: hasPriceRange,
                        ),
                      ),
                      // "+" in its own column, centred on both lines: never
                      // squeezed into the text.
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: isOutOfStock
                            ? null
                            : hasVariantChoice
                                ? openProduct
                                : () => _addToCart(context, product, imageKey),
                        child: Container(
                          height: _addButtonSize,
                          width: _addButtonSize,
                          decoration: BoxDecoration(
                            color: isOutOfStock ? Colors.grey : primaryColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

}

/// Two lines: price (+ "থেকে" for a from-price), then the struck-out MRP.
/// Each line has a fixed height (from the text scale) and scales its text
/// down instead of overflowing, so even "৳62,477 থেকে" / "৳99,999" fit a
/// 320px phone at text scale 1.3. Line 2 keeps its space without an MRP.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({
    required this.price,
    required this.mrp,
    this.isFromPrice = false,
  });

  final double price;
  final double mrp;

  /// Variants cost different amounts: shown as "৳X থেকে".
  final bool isFromPrice;

  static const TextStyle _priceStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: Color(0xFF1E7A3A),
    fontSize: ProductCard._priceFontSize,
    height: ProductCard._priceLineHeight,
  );

  // Readable next to the price (audit item 5).
  static const TextStyle _fromStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF4B5563),
    height: ProductCard._priceLineHeight,
  );

  static const TextStyle _mrpStyle = TextStyle(
    decoration: TextDecoration.lineThrough,
    fontSize: ProductCard._mrpFontSize,
    height: ProductCard._mrpLineHeight,
    color: Color(0xFF6B7280),
  );

  /// [price line, MRP line] heights at [scaler].
  static List<double> lineHeights(TextScaler scaler) => [
        scaler.scale(ProductCard._priceFontSize) * ProductCard._priceLineHeight,
        scaler.scale(ProductCard._mrpFontSize) * ProductCard._mrpLineHeight,
      ];

  @override
  Widget build(BuildContext context) {
    final heights = lineHeights(MediaQuery.textScalerOf(context));
    final showMrp = mrp > price;

    Widget line(double height, Widget child) => SizedBox(
          height: height,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: child,
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(
          heights[0],
          Text.rich(
            TextSpan(
              text: formatTaka(price),
              style: _priceStyle,
              children: [
                if (isFromPrice) const TextSpan(text: ' থেকে', style: _fromStyle),
              ],
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
        line(
          heights[1],
          showMrp
              ? Text(formatTaka(mrp), maxLines: 1, softWrap: false, style: _mrpStyle)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
