import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/product_service.dart';
import '../../services/web_url_service.dart';
import '../../widgets/health_gate.dart';
import 'product_details_page.dart';

/// /product/{key}: [productId] is the path key, a urlSlug or (older links)
/// a doc id or a previous slug. Same order as productSeo on the server.
class ProductSeoLoaderPage extends StatelessWidget {
  final String productId;

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _resolve(String key) async {
    final products = FirebaseFirestore.instance.collection('products');
    final bySlug = await products.where('urlSlug', isEqualTo: key).limit(1).get();
    if (bySlug.docs.isNotEmpty) return bySlug.docs.first;
    final byOldSlug = await products.where('previousSlugs', arrayContains: key).limit(1).get();
    if (byOldSlug.docs.isNotEmpty) return byOldSlug.docs.first;
    final byId = await products.doc(key).get();
    return byId.exists ? byId : null;
  }

  const ProductSeoLoaderPage({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _resolve(productId),
      builder: (context, snapshot) {

        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.data == null || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Text('Product not found'),
            ),
          );
        }

        final data = Map<String, dynamic>.from(snapshot.data!.data() ?? {});

        data['id'] = snapshot.data!.id;

        // Opened by an old key (doc id, previous slug): show the slug URL.
        final path = ProductService.productPath(data, snapshot.data!.id);
        if (path != '/product/${Uri.encodeComponent(productId)}') {
          WidgetsBinding.instance.addPostFrameCallback((_) => WebUrlService.replaceInPage(path));
        }

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
