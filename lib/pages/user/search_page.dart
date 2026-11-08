import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../services/category_service.dart';
import '../../widgets/product_card.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';

class SearchPage extends StatefulWidget {
  final String initialQuery;
  final String detectedLabel;

  const SearchPage({super.key, this.initialQuery = '', this.detectedLabel = ''});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  String _sort = 'relevance';
  String _selectedCategory = 'All';

  // Tracks which query text has already triggered a search-miss AliExpress
  // import this session, so a rebuild (e.g. from an unrelated Firestore
  // snapshot) never fires a second request for the same query.
  String? _autoImportTriggeredFor;

  bool _onlyInStock = false;
  bool _onlyMarketplace = false;
  bool _onlyPharmacy = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _searchController.text = _query;
    _saveRecentSearch(_query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Future<void> _saveRecentSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;

    try {
      await db.collection('search_logs').add({
        'query': query.toLowerCase(),
        'displayQuery': query,
        'source': 'user_search_page',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Search should never fail just because recent-search logging failed.
    }
  }

  static const String _searchImportUrl =
      'https://asia-south1-chalakchar-mart.cloudfunctions.net/aliexpressSearchImport';

  Future<void> _triggerSearchImport(String query) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      // Fire-and-forget — the search UI must never wait on or depend on
      // this. AliExpress fetch + import can take well over the time a
      // shopper will stay on this screen; the result surfaces later via
      // the normal Firestore query (or a push notification once imported).
      http.post(
        Uri.parse(_searchImportUrl),
        headers: {
          'content-type': 'application/json',
          if (idToken != null) 'authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'query': query, 'userId': user?.uid}),
      );
    } catch (_) {
      // Silent — best-effort, search UI must not depend on it.
    }
  }

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
    final vendorId = _text(data['vendorId']);
    return vendorId.isNotEmpty && vendorId != 'super_admin';
  }

  int _searchScore(Map<String, dynamic> data, String q) {
    if (q.trim().isEmpty) return 0;

    final query = q.toLowerCase().trim();
    final name = _text(data['name']).toLowerCase();
    final generic = _text(data['generic']).toLowerCase();
    final manufacturer = _text(data['manufacturer']).toLowerCase();
    final brand = _text(data['brand']).toLowerCase();
    final category = _text(data['category']).toLowerCase();
    final type = _text(data['type']).toLowerCase();
    final strength = _text(data['strength']).toLowerCase();
    final vendorName = _text(data['vendorName'] ?? data['shopName']).toLowerCase();

    int score = 0;

    if (name == query) score += 100;
    if (name.startsWith(query)) score += 60;
    if (name.contains(query)) score += 40;
    if (generic.contains(query)) score += 30;
    if (manufacturer.contains(query)) score += 20;
    if (brand.contains(query)) score += 20;
    if (category.contains(query)) score += 15;
    if (type.contains(query)) score += 10;
    if (strength.contains(query)) score += 10;
    if (vendorName.contains(query)) score += 8;

    final terms = query.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final haystack = [
      name,
      generic,
      manufacturer,
      brand,
      category,
      type,
      strength,
      vendorName,
    ].join(' ');

    for (final term in terms) {
      if (haystack.contains(term)) score += 5;
    }

    return score;
  }

  bool _matches(Map<String, dynamic> data, String q) {
    if (q.trim().isEmpty) return true;

    final query = q.toLowerCase().trim();
    final terms = query.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);

    final haystack = [
      data['name'],
      data['generic'],
      data['manufacturer'],
      data['brand'],
      data['category'],
      data['type'],
      data['strength'],
      data['vendorName'],
      data['shopName'],
      data['overview'],
    ].where((e) => e != null).join(' ').toLowerCase();

    return terms.every(haystack.contains);
  }

  List<QueryDocumentSnapshot> _filterSort(List<QueryDocumentSnapshot> docs) {
    final list = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data['isActive'] == false) return false;
      if (_selectedCategory != 'All' && _text(data['category']) != _selectedCategory) return false;
      if (_onlyInStock && _stockOf(data) <= 0) return false;
      if (_onlyMarketplace && !_isMarketplace(data)) return false;
      if (_onlyPharmacy && _isMarketplace(data)) return false;

      return _matches(data, _query);
    }).toList();

    list.sort((a, b) {
      final ad = a.data() as Map<String, dynamic>;
      final bd = b.data() as Map<String, dynamic>;

      switch (_sort) {
        case 'price_low':
          return _priceOf(ad).compareTo(_priceOf(bd));
        case 'price_high':
          return _priceOf(bd).compareTo(_priceOf(ad));
        case 'stock':
          return _stockOf(bd).compareTo(_stockOf(ad));
        case 'newest':
          return _dateOf(bd).compareTo(_dateOf(ad));
        case 'relevance':
        default:
          final bScore = _searchScore(bd, _query);
          final aScore = _searchScore(ad, _query);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return _dateOf(bd).compareTo(_dateOf(ad));
      }
    });

    return list;
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _searchController.clear();
      _sort = 'relevance';
      _selectedCategory = 'All';
      _onlyInStock = false;
      _onlyMarketplace = false;
      _onlyPharmacy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = kIsWeb && MediaQuery.of(context).size.width >= 1024;

    final PreferredSizeWidget pageAppBar = isDesktop
        ? const PreferredSize(
      preferredSize: Size.fromHeight(136),
      child: GlobalWebHeader(),
    )
        : AppBar(
      title: const Text('Search'),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: pageAppBar,
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('products')
            .where('isActive', isEqualTo: true)
            .where('approvalStatus', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Search failed: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = _filterSort(snapshot.data!.docs);

          if (products.isEmpty &&
              _query.trim().isNotEmpty &&
              _autoImportTriggeredFor != _query) {
            // Set the flag before calling, not after — a rebuild that lands
            // mid-request (e.g. an unrelated Firestore snapshot) must not
            // double-fire the same query.
            _autoImportTriggeredFor = _query;
            _triggerSearchImport(_query);
          }

          return LayoutBuilder(
            builder: (context, viewport) {
              final horizontalPadding = isDesktop ? 18.0 : 12.0;
              return CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _searchHeader(isDesktop)),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      isDesktop ? 18 : 12,
                      horizontalPadding,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1350),
                          child: products.isEmpty ? _emptyState() : _resultSummary(products.length),
                        ),
                      ),
                    ),
                  ),
                  if (products.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        14,
                        horizontalPadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1350),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.start,
                              children: products.map((doc) {
                                final data = Map<String, dynamic>.from(
                                  doc.data() as Map<String, dynamic>,
                                );
                                data['id'] = doc.id;

                                // Same card size as Home page and Product Details
                                // alternative product list: ProductCard default width = 150.
                                return ProductCard(data: data);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        SizedBox(height: products.isEmpty ? 28 : (isDesktop ? 70 : 28)),
                        const Spacer(),
                        if (isDesktop) const GlobalWebFooter(),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _searchHeader(bool isDesktop) {
    return Material(
      color: Colors.white,
      elevation: isDesktop ? 0 : 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isDesktop ? 14 : 12, 14, isDesktop ? 14 : 12, 14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1350),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: !isDesktop,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search products, vendors, brand, generic...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearFilters,
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: const BorderSide(color: Color(0xFFFF9900), width: 1.5),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onSubmitted: (v) {
                    final next = v.trim();
                    setState(() => _query = next);
                    _saveRecentSearch(next);
                  },
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                if (widget.detectedLabel.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _detectedBanner(),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _filterBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detectedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9900).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.image_search_rounded, color: Color(0xFFFF9900), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ছবি থেকে সনাক্ত হয়েছে: ${widget.detectedLabel}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return StreamBuilder<List<CategoryModel>>(
      stream: CategoryService.watchActiveCategories(),
      builder: (context, snap) {
        final categories = <String>['All'];

        if (snap.hasData) {
          for (final c in snap.data!) {
            final name = c.name.trim();

            if (name.isNotEmpty && !categories.contains(name)) {
              categories.add(name);
            }
          }
        }

        if (!categories.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _dropdownBox(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    items: categories
                        .map(
                          (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ),
                    )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v ?? 'All'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _dropdownBox(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'relevance', child: Text('Best match')),
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'price_low', child: Text('Price low')),
                      DropdownMenuItem(value: 'price_high', child: Text('Price high')),
                      DropdownMenuItem(value: 'stock', child: Text('Stock')),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? 'relevance'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('In stock'),
                selected: _onlyInStock,
                onSelected: (v) => setState(() => _onlyInStock = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Marketplace'),
                selected: _onlyMarketplace,
                onSelected: (v) {
                  setState(() {
                    _onlyMarketplace = v;
                    if (v) _onlyPharmacy = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Official Store'),
                selected: _onlyPharmacy,
                onSelected: (v) {
                  setState(() {
                    _onlyPharmacy = v;
                    if (v) _onlyMarketplace = false;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dropdownBox({required Widget child}) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: child,
    );
  }

  Widget _resultSummary(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Color(0xFF32A8C7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _query.isEmpty ? '$count products found' : '$count results for "$_query"',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _query.isEmpty ? 'No products found' : 'No result found for "$_query"',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _query.isEmpty
                ? 'Try another keyword or clear filters.'
                : 'প্রোডাক্টটি এখন নেই। আমরা AliExpress থেকে কিছুক্ষণের মধ্যে আপলোড করছি — একটু পরে আবার চেষ্টা করুন, অথবা পণ্যটি রেডি হলে নোটিফিকেশন পাবেন।',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.refresh),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}
