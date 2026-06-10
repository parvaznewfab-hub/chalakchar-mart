import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VendorShopPage extends StatelessWidget {
  final String vendorId;

  const VendorShopPage({
    super.key,
    required this.vendorId,
  });

  FirebaseFirestore get db => FirebaseFirestore.instance;

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _text(dynamic v, [String fallback = '']) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('vendors').doc(vendorId).snapshots(),
        builder: (context, vendorSnap) {
          if (vendorSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!vendorSnap.hasData || !vendorSnap.data!.exists) {
            return const Center(child: Text('Vendor shop not found'));
          }

          final vendor = vendorSnap.data!.data() ?? {};
          final shopName = _text(vendor['shopName'] ?? vendor['name'], 'Vendor Shop');
          final banner = _text(vendor['bannerUrl'] ?? vendor['coverImage']);
          final logo = _text(vendor['logoUrl'] ?? vendor['image']);
          final phone = _text(vendor['phone']);
          final address = _text(vendor['address']);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 230,
                pinned: true,
                backgroundColor: const Color(0xFF32A8C7),
                foregroundColor: Colors.white,
                title: Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (banner.isNotEmpty)
                        Image.network(
                          banner,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _bannerFallback(),
                        )
                      else
                        _bannerFallback(),
                      Container(color: Colors.black.withValues(alpha: 0.30)),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.white,
                              backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
                              child: logo.isEmpty
                                  ? const Icon(Icons.store, size: 34, color: Color(0xFF32A8C7))
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    shopName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (address.isNotEmpty)
                                    Text(
                                      address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  if (phone.isNotEmpty)
                                    Text(
                                      phone,
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _shopStats(vendor)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                sliver: _productsGrid(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bannerFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF32A8C7), Color(0xFF197B96)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.storefront, color: Colors.white24, size: 100),
    );
  }

  Widget _shopStats(Map<String, dynamic> vendor) {
    final totalOrders = _toDouble(vendor['totalOrders']);
    final rating = _toDouble(vendor['rating']);
    final status = _text(vendor['status'], 'active');

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Expanded(child: _statItem('Orders', totalOrders.toStringAsFixed(0))),
          Expanded(child: _statItem('Rating', rating > 0 ? rating.toStringAsFixed(1) : 'New')),
          Expanded(child: _statItem('Status', status.toUpperCase())),
        ],
      ),
    );
  }

  Widget _statItem(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _productsGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('products')
          .where('vendorId', isEqualTo: vendorId)
          .where('isActive', isEqualTo: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('No products found')),
            ),
          );
        }

        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final doc = docs[index];
              return _productCard(context, doc.id, doc.data());
            },
            childCount: docs.length,
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 190,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
        );
      },
    );
  }

  Widget _productCard(BuildContext context, String productId, Map<String, dynamic> data) {
    final name = _text(data['name'], 'Product');
    final image = _text(data['image'] ?? data['imageUrl']);
    final price = _toDouble(data['price']);
    final oldPrice = _toDouble(data['oldPrice'] ?? data['old_price']);
    final strength = _text(data['strength']);
    final manufacturer = _text(data['manufacturer']);

    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/product-details',
          arguments: productId,
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Image.network(
                  image,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.medication, size: 42, color: Colors.grey),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text(
                '$name $strength',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            if (manufacturer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  manufacturer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Text(
                    '৳${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF32A8C7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 5),
                  if (oldPrice > price)
                    Expanded(
                      child: Text(
                        '৳${oldPrice.toStringAsFixed(0)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
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


