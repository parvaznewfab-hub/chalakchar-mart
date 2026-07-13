import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/guest_cart_service.dart';
import '../services/product_service.dart';
import '../services/web_url_service.dart';

class ProductCard extends StatelessWidget {
  final dynamic data;
  final Function(GlobalKey)? onAddToCart;
  /// Kept for backward compatibility with older pages.
  /// ProductCard now uses one universal size everywhere.
  final bool gridMode;

  static const double cardWidth = 150;
  static const double imageHeight = 112;

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
    const primaryColor = Color(0xFF32A8C7);

    final name = _text(product['name'], 'Product Name');
    final strength = _text(product['strength']);
    final manufacturer = _text(product['manufacturer'] ?? product['brand']);
    final image = _text(product['image'] ?? product['imageUrl']);

    final price = ProductService.getDisplayPrice(product);
    final oldPrice = ProductService.getDisplayMrp(product);
    final stock = ProductService.getStock(product);
    final isOutOfStock = stock <= 0;

    return GestureDetector(
      onTap: () {
        final productId = ProductService.productIdFrom(product).trim();
        if (productId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid product link')),
          );
          return;
        }

        final path = '/product/$productId';
        WebUrlService.push(path);

        Navigator.of(context, rootNavigator: true).pushNamed(path);
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(
          right: 12,
          bottom: 8,
          top: 4,
          left: 4,
        ),
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
          mainAxisSize: MainAxisSize.min,
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
                          image,
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
                    const SizedBox(height: 2),
                    Text(
                      manufacturer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '৳${price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (oldPrice > price)
                        Expanded(
                          child: Text(
                            '৳${oldPrice.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              fontSize: 9,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      GestureDetector(
                        onTap: isOutOfStock
                            ? null
                            : () => _addToCart(context, product, imageKey),
                        child: Container(
                          height: 26,
                          width: 26,
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
            ),
          ],
        ),
      ),
    );
  }
}
