import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/health_gate.dart';
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

        // Health products were removed from the shop (hidden, not deleted);
        // an old shared link must not show their details.
        if (data['hiddenReason'] == 'health_removed' && !HealthFeatures.enabled) {
          return const _ProductUnavailablePage();
        }

        return ProductDetailsPage(
          data: data,
        );
      },
    );
  }
}

class _ProductUnavailablePage extends StatelessWidget {
  const _ProductUnavailablePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ChalakChar Mart')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              const Text(
                'এই পণ্যটি এখন পাওয়া যাচ্ছে না।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .pushNamedAndRemoveUntil('/', (route) => false),
                child: const Text('হোমে যান'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
