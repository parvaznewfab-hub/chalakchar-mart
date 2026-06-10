import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../services/category_service.dart';
import '../../widgets/product_card.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';

class CategoryProductsPage extends StatefulWidget {
  final String category;

  const CategoryProductsPage({
    super.key,
    required this.category,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  String sortBy = 'newest';
  bool onlyInStock = false;
  bool onlyMarketplace = false;
  bool onlyPharmacy = false;

  double _priceOf(Map<String, dynamic> data) {
    final variants = data['variants'];
    if (variants is List && variants.isNotEmpty) {
      final first = variants.first;
      if (first is Map) {
        return double.tryParse((first['price'] ?? 0).toString()) ?? 0;
      }
    }
    return double.tryParse((data['price'] ?? data['piecePrice'] ?? 0).toString()) ?? 0;
  }

  int _stockOf(Map<String, dynamic> data) {
    final variants = data['variants'];
    if (variants is List && variants.isNotEmpty) {
      int total = 0;
      for (final v in variants) {
        if (v is Map) {
          total += int.tryParse((v['stock'] ?? 0).toString()) ?? 0;
        }
      }
      return total;
    }
    return int.tryParse((data['stock'] ?? 0).toString()) ?? 0;
  }

  DateTime _dateOf(Map<String, dynamic> data) {
    final value = data['createdAt'];
    if (value is Timestamp) return value.toDate();
    return DateTime(2000);
  }

  bool _isMarketplace(Map<String, dynamic> data) {
    final vendorId = (data['vendorId'] ?? '').toString().trim();
    return vendorId.isNotEmpty && vendorId != 'super_admin';
  }

  List<QueryDocumentSnapshot> _filterAndSort(List<QueryDocumentSnapshot> docs) {
    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data['isActive'] == false) return false;
      if (onlyInStock && _stockOf(data) <= 0) return false;
      if (onlyMarketplace && !_isMarketplace(data)) return false;
      if (onlyPharmacy && _isMarketplace(data)) return false;

      return true;
    }).toList();

    filtered.sort((a, b) {
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
          return _dateOf(bd).compareTo(_dateOf(ad));
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = kIsWeb && MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: (isDesktop
          ? const GlobalWebHeader()
          : AppBar(
              title: Text(widget.category),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            )) as PreferredSizeWidget?,
      body: StreamBuilder<List<CategoryModel>>(
        stream: CategoryService.watchActiveCategories(),
        builder: (context, categorySnap) {
          if (categorySnap.hasError) {
            return Center(
              child: Text(
                'Category load failed: ${categorySnap.error}',
              ),
            );
          }

          if (categorySnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final activeCategories =
              categorySnap.data ?? const <CategoryModel>[];

          final exists = activeCategories.any(
                (c) =>
            c.name.trim().toLowerCase() ==
                widget.category.trim().toLowerCase(),
          );

          if (!exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 72,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${widget.category} category not found',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This category is inactive or removed.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('products')
                      .where('category', isEqualTo: widget.category)
                      .where('isActive', isEqualTo: true)
                      .where('approvalStatus', isEqualTo: 'approved')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Products load failed: ${snapshot.error}',
                        ),
                      );
                    }

                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final allProducts =
                        snapshot.data?.docs ?? [];

                    final products =
                    _filterAndSort(allProducts);

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                          const BoxConstraints(
                            maxWidth: 1400,
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              _header(
                                allProducts.length,
                                products.length,
                              ),
                              const SizedBox(height: 14),
                              _filters(),
                              const SizedBox(height: 16),
                              if (products.isEmpty)
                                _emptyState()
                              else if (isDesktop)
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: products.map((doc) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    data['id'] = doc.id;

                                    return SizedBox(
                                      width: 190,
                                      height: 230,
                                      child: ProductCard(data: data),
                                    );
                                  }).toList(),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    int crossAxisCount = (constraints.maxWidth / 190).floor();

                                    if (crossAxisCount < 2) crossAxisCount = 2;
                                    if (crossAxisCount > 6) crossAxisCount = 6;

                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: products.length,
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        childAspectRatio: 0.88,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                      ),
                                      itemBuilder: (context, index) {
                                        final doc = products[index];
                                        final data = doc.data() as Map<String, dynamic>;
                                        data['id'] = doc.id;

                                        return ProductCard(data: data);
                                      },
                                    );
                                  },
                                ),

                              if (isDesktop) ...[
                                const SizedBox(height: 40),
                                const GlobalWebFooter(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(int total, int showing) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
            child: const Icon(Icons.category_rounded, color: Color(0xFF32A8C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.category,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  'Showing $showing of $total products',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: sortBy,
            items: const [
              DropdownMenuItem(value: 'newest', child: Text('Newest')),
              DropdownMenuItem(value: 'price_low', child: Text('Price low')),
              DropdownMenuItem(value: 'price_high', child: Text('Price high')),
              DropdownMenuItem(value: 'stock', child: Text('Stock')),
            ],
            onChanged: (v) => setState(() => sortBy = v ?? 'newest'),
          ),
          FilterChip(
            label: const Text('In stock'),
            selected: onlyInStock,
            onSelected: (v) => setState(() => onlyInStock = v),
          ),
          FilterChip(
            label: const Text('Marketplace'),
            selected: onlyMarketplace,
            onSelected: (v) {
              setState(() {
                onlyMarketplace = v;
                if (v) onlyPharmacy = false;
              });
            },
          ),
          FilterChip(
            label: const Text('Official Store'),
            selected: onlyPharmacy,
            onSelected: (v) {
              setState(() {
                onlyPharmacy = v;
                if (v) onlyMarketplace = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SizedBox(
      height: 360,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'No products found in ${widget.category}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Try changing filters.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}



