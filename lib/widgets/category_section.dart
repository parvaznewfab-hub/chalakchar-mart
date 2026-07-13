import 'package:flutter/material.dart';
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
          height: 205,
          child: StreamBuilder(
            stream: FirebaseService.getProducts(title, limit: limit),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }

              var products = snapshot.data!.docs;

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



