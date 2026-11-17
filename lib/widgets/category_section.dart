import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/category_service.dart';
import '../utils/shop_visibility.dart';
import '../widgets/product_card.dart';
import '../services/firebase_service.dart';


class CategorySection extends StatelessWidget {
  final String title;
  final Function(GlobalKey)? onAddToCart;

  final int limit;

  const CategorySection({
    super.key,
    required this.title,
    this.onAddToCart,
    this.limit = 10,
  });

  /// This category's products, only what the shop shows
  /// (isShopVisibleProduct, switched-on categories from CategoryService).
  Stream<List<QueryDocumentSnapshot>> _shopProducts() {
    return Stream.fromFuture(CategoryService.activeCategoryNamesLower()).asyncExpand(
      (active) => FirebaseService.getProducts(title, limit: limit).map(
        (snap) => shopVisibleOnly(snap.docs, active, (d) => d.data() as Map<String, dynamic>),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/category/${title.toLowerCase().replaceAll(" ", "-")}',
                  );
                },
                child: const Text(
                  "View all",
                  style: TextStyle(
                    color: Color(0xFF32A8C7),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          // Exactly one card (computed from its content and text scale) plus
          // its margin, so there is no empty space under the price row.
          height: ProductCard.rowHeight(context),
          child: StreamBuilder<List<QueryDocumentSnapshot>>(
            stream: _shopProducts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final products = snapshot.data ?? const [];
              if (products.isEmpty) return const SizedBox.shrink();

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  return ProductCard(
                    data: products[index],
                    onAddToCart: onAddToCart,
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}



