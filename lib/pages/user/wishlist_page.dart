import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../widgets/product_card.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();

  static Future<void> toggleWishlist(Map<String, dynamic> product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;

    final productId = (
        product['id'] ??
            product['productId'] ??
            product['name']
    ).toString();

    final ref = db
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .doc(productId);

    final snap = await ref.get();

    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({
        ...product,
        'productId': productId,
        'vendorId': product['vendorId'] ?? 'super_admin',
        'vendorName': product['vendorName'] ?? 'ChalakChar Mart',
        'isMarketplace':
        (product['vendorId'] ?? 'super_admin') != 'super_admin',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}

class _WishlistPageState extends State<WishlistPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String sortBy = 'newest';
  bool onlyMarketplace = false;
  bool onlyPharmacy = false;
  bool onlyInStock = false;

  double _priceOf(Map<String, dynamic> data) {
    final variants = data['variants'];

    if (variants is List && variants.isNotEmpty) {
      final first = variants.first;

      if (first is Map) {
        return double.tryParse(
          (first['price'] ?? 0).toString(),
        ) ??
            0;
      }
    }

    return double.tryParse(
      (data['price'] ?? data['piecePrice'] ?? 0).toString(),
    ) ??
        0;
  }

  int _stockOf(Map<String, dynamic> data) {
    final variants = data['variants'];

    if (variants is List && variants.isNotEmpty) {
      int total = 0;

      for (final v in variants) {
        if (v is Map) {
          total +=
              int.tryParse(
                (v['stock'] ?? 0).toString(),
              ) ??
                  0;
        }
      }

      return total;
    }

    return int.tryParse(
      (data['stock'] ?? 0).toString(),
    ) ??
        0;
  }

  bool _isMarketplace(Map<String, dynamic> data) {
    final vendorId = (data['vendorId'] ?? '').toString().trim();

    return vendorId.isNotEmpty &&
        vendorId != 'super_admin';
  }

  List<QueryDocumentSnapshot> _filterSort(
      List<QueryDocumentSnapshot> docs,
      ) {
    final list = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data['isActive'] == false) return false;

      if (onlyMarketplace && !_isMarketplace(data)) {
        return false;
      }

      if (onlyPharmacy && _isMarketplace(data)) {
        return false;
      }

      if (onlyInStock && _stockOf(data) <= 0) {
        return false;
      }

      return true;
    }).toList();

    list.sort((a, b) {
      final ad = a.data() as Map<String, dynamic>;
      final bd = b.data() as Map<String, dynamic>;

      switch (sortBy) {
        case 'price_low':
          return _priceOf(ad).compareTo(_priceOf(bd));

        case 'price_high':
          return _priceOf(bd).compareTo(_priceOf(ad));

        case 'stock':
          return _stockOf(bd).compareTo(_stockOf(ad));

        case 'newest':
        default:
          final at = ad['createdAt'];
          final bt = bd['createdAt'];

          final aDate =
          at is Timestamp ? at.toDate() : DateTime(2000);

          final bDate =
          bt is Timestamp ? bt.toDate() : DateTime(2000);

          return bDate.compareTo(aDate);
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final isDesktop =
        kIsWeb &&
            MediaQuery.of(context).size.width >= 1024;

    if (user == null) {
      return Scaffold(
        appBar: (isDesktop
            ? const GlobalWebHeader()
            : AppBar(
          title: const Text('Wishlist'),
        )) as PreferredSizeWidget,
        body: const Center(
          child: Text('Please login to view wishlist'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: (isDesktop
          ? const GlobalWebHeader()
          : AppBar(
        title: const Text('Wishlist'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      )) as PreferredSizeWidget,

      body: Column(
        children: [
          _header(),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('users')
                  .doc(user.uid)
                  .collection('wishlist')
                  .orderBy(
                'createdAt',
                descending: true,
              )
                  .snapshots(),

              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Wishlist failed: ${snap.error}',
                    ),
                  );
                }

                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final allDocs = snap.data!.docs;

                final docs = _filterSort(allDocs);

                if (docs.isEmpty) {
                  return _emptyState();
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ProductCard.gridHorizontalPadding,
                    vertical: 14,
                  ),

                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                      const BoxConstraints(maxWidth: 1300),

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          _summary(
                            allDocs.length,
                            docs.length,
                          ),

                          const SizedBox(height: 14),

                          _filters(),

                          const SizedBox(height: 16),

                          LayoutBuilder(
                            builder: (
                                context,
                                constraints,
                                ) {
                              int crossAxisCount =
                              (constraints.maxWidth /
                                  185)
                                  .floor();

                              if (crossAxisCount < 2) {
                                crossAxisCount = 2;
                              }

                              if (crossAxisCount > 7) {
                                crossAxisCount = 7;
                              }

                              return GridView.builder(
                                shrinkWrap: true,

                                physics:
                                const NeverScrollableScrollPhysics(),

                                itemCount: docs.length,

                                clipBehavior: Clip.none,
                                padding: EdgeInsets.zero,

                                gridDelegate: ProductCard.gridDelegate(
                                  context,
                                  crossAxisCount: crossAxisCount,
                                ),

                                itemBuilder: (_, i) {
                                  final data =
                                  docs[i].data()
                                  as Map<
                                      String,
                                      dynamic
                                  >;

                                  data['id'] ??=
                                      data['productId'] ??
                                          docs[i].id;

                                  final isMarketplace =
                                  _isMarketplace(
                                    data,
                                  );

                                  return Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ProductCard(
                                          data: data,
                                          gridMode: true,
                                        ),
                                      ),

                                      Positioned(
                                        top: 6,
                                        right: 6,

                                        child: Column(
                                          children: [
                                            if (isMarketplace)
                                              _marketplaceBadge(),

                                            const SizedBox(
                                              height: 6,
                                            ),

                                            Material(
                                              color:
                                              Colors
                                                  .white,

                                              borderRadius:
                                              BorderRadius.circular(
                                                20,
                                              ),

                                              child:
                                              IconButton(
                                                icon: const Icon(
                                                  Icons
                                                      .delete_outline,
                                                  color:
                                                  Colors
                                                      .red,
                                                ),

                                                onPressed:
                                                    () => docs[i]
                                                    .reference
                                                    .delete(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (isDesktop)
            const GlobalWebFooter(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,

      padding: const EdgeInsets.all(16),

      child: Row(
        children: [
          CircleAvatar(
            radius: 24,

            backgroundColor:
            Colors.red.withValues(alpha: 0.12),

            child: const Icon(
              Icons.favorite,
              color: Colors.red,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  'My Wishlist',

                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                SizedBox(height: 2),

                Text(
                  'Saved products for future purchase',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(int total, int showing) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
      ),

      child: Row(
        children: [
          const Icon(
            Icons.favorite_border,
            color: Colors.red,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              'Showing $showing of $total wishlist items',

              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
      ),

      child: Wrap(
        spacing: 8,
        runSpacing: 8,

        children: [
          DropdownButton<String>(
            value: sortBy,

            items: const [
              DropdownMenuItem(
                value: 'newest',
                child: Text('Newest'),
              ),

              DropdownMenuItem(
                value: 'price_low',
                child: Text('Price low'),
              ),

              DropdownMenuItem(
                value: 'price_high',
                child: Text('Price high'),
              ),

              DropdownMenuItem(
                value: 'stock',
                child: Text('Stock'),
              ),
            ],

            onChanged:
                (v) => setState(
                  () => sortBy = v ?? 'newest',
            ),
          ),

          FilterChip(
            label: const Text('In stock'),

            selected: onlyInStock,

            onSelected:
                (v) => setState(
                  () => onlyInStock = v,
            ),
          ),

          FilterChip(
            label: const Text('Marketplace'),

            selected: onlyMarketplace,

            onSelected: (v) {
              setState(() {
                onlyMarketplace = v;

                if (v) {
                  onlyPharmacy = false;
                }
              });
            },
          ),

          FilterChip(
            label: const Text('Best Selling'),

            selected: onlyPharmacy,

            onSelected: (v) {
              setState(() {
                onlyPharmacy = v;

                if (v) {
                  onlyMarketplace = false;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _marketplaceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),

      decoration: BoxDecoration(
        color: Colors.deepPurple,

        borderRadius: BorderRadius.circular(20),
      ),

      child: const Text(
        'Marketplace',

        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(
            Icons.favorite_border,
            size: 90,
            color: Colors.grey.shade300,
          ),

          const SizedBox(height: 12),

          const Text(
            'Your wishlist is empty',

            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Save products you love for later.',

            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}


