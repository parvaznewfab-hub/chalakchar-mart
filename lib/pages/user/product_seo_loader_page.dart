import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_details_page.dart';

class ProductSeoLoaderPage extends StatelessWidget {
  final String productId;

  const ProductSeoLoaderPage({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get(),
      builder: (context, snapshot) {

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Text('Product not found'),
            ),
          );
        }

        final data =
        snapshot.data!.data() as Map<String, dynamic>;

        data['id'] = snapshot.data!.id;

        return ProductDetailsPage(
          data: data,
        );
      },
    );
  }
}