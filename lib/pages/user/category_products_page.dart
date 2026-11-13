import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../services/category_service.dart';
import '../../widgets/product_card.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import '../../widgets/category_sidebar.dart';
import '../../services/web_url_service.dart';

class CategoryProductsPage extends StatefulWidget {
  final String category;

  /// Subcategory slug from `?sub=`; null shows all products.
  final String? initialSub;

  const CategoryProductsPage({
    super.key,
    required this.category,
    this.initialSub,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  String sortBy = 'newest';
  bool onlyInStock = false;
  bool onlyMarketplace = false;
  bool onlyPharmacy = false;

  /// Selected subcategory slug (the `?sub=` value), null = All.
  String? _sub;
  final Future<Map<String, List<SubcategoryModel>>> _subcategories =
      CategoryService.activeSubcategoriesByCategory();
  void Function()? _cancelPopState;

  // Streams are created once, not in build(): a new stream per setState
  // (chip, filter or sort tap) re-subscribed both queries, flashed the
  // spinner and rebuilt the whole page.
  late final Stream<List<CategoryModel>> _categoriesStream =
      CategoryService.watchActiveCategories();
  Stream<QuerySnapshot>? _productsStream;
  String? _productsStreamCategory;

  Stream<QuerySnapshot> _productsFor(String categoryName) {
    if (_productsStream == null || _productsStreamCategory != categoryName) {
      _productsStreamCategory = categoryName;
      _productsStream = FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: categoryName)
          .where('isActive', isEqualTo: true)
          .where('approvalStatus', isEqualTo: 'approved')
          .snapshots();
    }
    return _productsStream!;
  }

  @override
  void initState() {
    super.initState();
    final fromUrl = kIsWeb ? WebUrlService.currentQuery()['sub'] : null;
    _sub = _cleanSub(widget.initialSub ?? fromUrl);
    // Back/forward between ?sub= entries of this page.
    _cancelPopState = WebUrlService.onPopState((query) {
      if (!mounted) return;
      setState(() => _sub = _cleanSub(query['sub']));
    });
  }

  @override
  void dispose() {
    _cancelPopState?.call();
    super.dispose();
  }

  String? _cleanSub(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? null : v;
  }

  void _selectSub(String? slug) {
    if (slug == _sub) return;
    setState(() => _sub = slug);
    if (kIsWeb) {
      final path = Uri.base.path;
      WebUrlService.pushInPage(
        slug == null ? path : '$path?sub=${Uri.encodeQueryComponent(slug)}',
      );
    }
  }

  String _normalizeSlug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _syncCategoryUrl(String categoryName) {
    // URL is handled by named route /category/{slug}.
    // Do not use history.replaceState here; it can overwrite /product/{id}
    // when this page rebuilds behind the product page.
  }

  double _priceOf(Map<String, dynamic> data) {
    final variants = data['variants'];
    if (variants is List && variants.isNotEmpty) {
      final first = variants.first;
      if (first is Map) {
        return double.tryParse((first['price'] ?? 0).toString()) ?? 0;
      }
    }
    return double.tryParse(
            (data['price'] ?? data['piecePrice'] ?? 0).toString()) ??
        0;
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

  /// isActive plus the In stock / Marketplace / Official Store filters —
  /// everything except the subcategory and the sort.
  List<QueryDocumentSnapshot> _applyFilters(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data['isActive'] == false) return false;
      if (onlyInStock && _stockOf(data) <= 0) return false;
      if (onlyMarketplace && !_isMarketplace(data)) return false;
      if (onlyPharmacy && _isMarketplace(data)) return false;

      return true;
    }).toList();
  }

  List<QueryDocumentSnapshot> _sort(List<QueryDocumentSnapshot> filtered) {
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
        stream: _categoriesStream,
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

          final activeCategories = categorySnap.data ?? const <CategoryModel>[];

          final requestedSlug = _normalizeSlug(widget.category);

          final matchedList = activeCategories.where((c) {
            final categorySlug = _normalizeSlug(c.name);
            return categorySlug == requestedSlug;
          }).toList();

          final CategoryModel? matchedCategory =
              matchedList.isNotEmpty ? matchedList.first : null;

          final exists = matchedCategory != null;

          if (exists) {
            _syncCategoryUrl(matchedCategory.name);
          }

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

          final content = FutureBuilder<Map<String, List<SubcategoryModel>>>(
            future: _subcategories,
            builder: (context, subSnap) {
              // Cached after the first read; on failure the page just has
              // no chip row.
              final subcategories = subSnap.data?[matchedCategory.id] ??
                  const <SubcategoryModel>[];
              return _productsView(matchedCategory, subcategories, isDesktop);
            },
          );

          if (!isDesktop) return content;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 260,
                height: MediaQuery.of(context).size.height,
                padding: const EdgeInsets.fromLTRB(40, 16, 0, 30),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - 140,
                  child: CategorySidebar(
                    activeCategoryId: matchedCategory.id,
                    activeSubSlug: _sub,
                    onSelectActiveSub: _selectSub,
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _productsView(
    CategoryModel matchedCategory,
    List<SubcategoryModel> subcategories,
    bool isDesktop,
  ) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _productsFor(matchedCategory.name),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Products load failed: ${snapshot.error}',
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final allProducts = snapshot.data?.docs ?? [];

              // Chip visibility uses unfiltered counts (so In stock
              // can't make a chip vanish); chip numbers use the
              // filtered set, so they match what a click shows.
              final liveProducts = allProducts
                  .where((d) =>
                      (d.data() as Map<String, dynamic>)['isActive'] != false)
                  .toList();
              final filtered = _applyFilters(allProducts);
              int countIn(List<QueryDocumentSnapshot> docs, String subId) =>
                  docs
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['subcategoryId'] ==
                          subId)
                      .length;
              final chipSubs = subcategories
                  .where((sub) => countIn(liveProducts, sub.id) > 0)
                  .toList();
              final selected =
                  chipSubs.where((sub) => sub.slug == _sub).firstOrNull;

              final products = _sort(selected == null
                  ? filtered
                  : filtered
                      .where((d) =>
                          (d.data() as Map<String, dynamic>)['subcategoryId'] ==
                          selected.id)
                      .toList());

              return SingleChildScrollView(
                padding: isDesktop
                    ? const EdgeInsets.all(16)
                    : const EdgeInsets.symmetric(
                        horizontal: ProductCard.gridHorizontalPadding,
                        vertical: 16,
                      ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 1400,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(
                          matchedCategory.name,
                          allProducts.length,
                          products.length,
                        ),
                        if (chipSubs.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _subcategoryChips(
                            chipSubs,
                            selected,
                            allCount: filtered.length,
                            countFor: (sub) => countIn(filtered, sub.id),
                          ),
                        ],
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

                              return ProductCard(data: data);
                            }).toList(),
                          )
                        else
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            clipBehavior: Clip.none, // keep card shadows
                            padding: EdgeInsets.zero,
                            itemCount: products.length,
                            gridDelegate: ProductCard.gridDelegate(context),
                            itemBuilder: (context, index) {
                              final doc = products[index];
                              final data = doc.data() as Map<String, dynamic>;
                              data['id'] = doc.id;

                              return ProductCard(data: data, gridMode: true);
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
  }

  Widget _subcategoryChips(
    List<SubcategoryModel> subs,
    SubcategoryModel? selected, {
    required int allCount,
    required int Function(SubcategoryModel) countFor,
  }) {
    const accent = Color(0xFF32A8C7);

    Widget avatar(SubcategoryModel? sub) {
      final url = sub?.imageUrl ?? '';
      final letter = sub == null
          ? null
          : (sub.name.isEmpty ? '?' : sub.name.characters.first.toUpperCase());
      return CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.12),
        backgroundImage: url.isEmpty ? null : NetworkImage(url),
        child: url.isNotEmpty
            ? null
            : letter == null
                ? const Icon(Icons.apps_rounded, size: 14, color: accent)
                : Text(
                    letter,
                    style: const TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
      );
    }

    Widget chip(SubcategoryModel? sub, String label, int count) {
      final isSelected = sub?.id == selected?.id;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ChoiceChip(
          avatar: avatar(sub),
          label: Text('$label ($count)'),
          selected: isSelected,
          showCheckmark: false,
          selectedColor: accent.withValues(alpha: 0.16),
          labelStyle: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF1592B3) : Colors.black87,
          ),
          onSelected: (_) => _selectSub(sub?.slug),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      // One line that scrolls sideways on narrow screens; never wraps.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 12, right: 2),
        child: Row(
          children: [
            chip(null, 'All', allCount),
            for (final sub in subs) chip(sub, sub.name, countFor(sub)),
          ],
        ),
      ),
    );
  }

  Widget _header(String categoryName, int total, int showing) {
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
                  categoryName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
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
            Icon(Icons.inventory_2_outlined,
                size: 80, color: Colors.grey.shade300),
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
