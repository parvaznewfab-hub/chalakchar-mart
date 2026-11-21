import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../services/category_service.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';
import '../../utils/search_import_guard.dart';
import '../../utils/settled_search_gate.dart';
import '../../utils/shop_visibility.dart';
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

  /// Normalized queries the server refused to import -> its reason
  /// ("health": medicine / health queries; "no_english_terms": Bangla words
  /// with no product word it can look up; ...). The empty state then stops
  /// promising the product soon.
  final Map<String, String> _rejectedImportQueries = {};

  /// Queries just sent to the server, for up to 3 s: a refused query
  /// (medicine, ...) is answered within that time, so the empty state
  /// doesn't flash "we'll bring it" + "জানিয়ে দিন" before the refusal.
  final Set<String> _importChecking = {};

  /// Queries actually sent for import; only these may promise the product.
  final Set<String> _importSent = {};
  String _sort = 'relevance';
  String _selectedCategory = 'All';

  // A query only counts as a real search once it "settles": the shopper
  // pressed Enter, opened this page with a query, or stopped typing for
  // [_settleDelay]. Only a settled query is logged to search_logs and may
  // trigger a search-miss import. Typing alone never does; that used to fire
  // an import for every prefix ("htm", "html", "html_a", ...).
  static const Duration _settleDelay = Duration(milliseconds: 1000);
  Timer? _settleTimer;

  // A settled query waiting for the next build, which has the product list
  // needed to know whether it found anything.
  final SettledSearchGate _settled = SettledSearchGate();

  // Normalized queries already logged / sent for import in this app session.
  // Static so it outlives this page: leaving and reopening search with the
  // same query does not send it again.
  static final Set<String> _handledQueryKeys = <String>{};

  bool _onlyInStock = false;
  bool _onlyMarketplace = false;
  bool _onlyPharmacy = false;

  // One listener for the page's life (not a new one per rebuild). Metadata
  // changes are included so the server's confirmation of a cached list
  // arrives even when no product changed.
  late final Stream<QuerySnapshot> _products = db
      .collection('products')
      .where('isActive', isEqualTo: true)
      .where('approvalStatus', isEqualTo: 'approved')
      .snapshots(includeMetadataChanges: true);

  // Switched-on categories (lower-cased), from CategoryService's session
  // cache: results only list what the shop shows (isShopVisibleProduct).
  Set<String>? _activeCategoriesLower;
  Object? _activeCategoriesError;

  @override
  void initState() {
    super.initState();
    CategoryService.activeCategoryNamesLower().then(
      (names) {
        if (mounted) setState(() => _activeCategoriesLower = names);
      },
      onError: (Object e) {
        if (mounted) setState(() => _activeCategoriesError = e);
      },
    );
    _query = widget.initialQuery.trim();
    _searchController.text = _query;
    // Opening the page with a query (from the header or home search box) is
    // a submit.
    _settled.settle(_query);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
    _settleTimer?.cancel();
    if (_query.isEmpty) return;
    _settleTimer = Timer(_settleDelay, () {
      if (!mounted) return;
      setState(() => _settled.settle(_query));
    });
  }

  void _onQuerySubmitted(String value) {
    _settleTimer?.cancel();
    final next = value.trim();
    setState(() {
      _query = next;
      _settled.settle(next);
    });
  }

  // Called from build() once a settled query has a loaded product list.
  // [matchCount] ignores the stock/vendor/category filters, so a filter that
  // hides results is never mistaken for a search miss.
  void _handleSettledQuery(String query, int matchCount) {
    final key = searchQueryKey(query);
    if (key.isEmpty || !_handledQueryKeys.add(key)) return;

    _logSearch(query, matchCount);
    if (shouldImportSearch(query, matchCount)) {
      _triggerSearchImport(normalizeSearchQuery(query));
    }
  }

  // Field set must match the search_logs create rule in firestore.rules.
  Future<void> _logSearch(String q, int resultCount) async {
    final display = normalizeSearchQuery(q);
    if (display.isEmpty) return;
    final clipped = display.length > searchLogMaxQueryLength
        ? display.substring(0, searchLogMaxQueryLength)
        : display;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      await db.collection('search_logs').add({
        'query': clipped.toLowerCase(),
        'displayQuery': clipped,
        'source': 'user_search_page',
        'resultCount': resultCount,
        'createdAt': FieldValue.serverTimestamp(),
        if (uid != null) 'userId': uid,
      });
    } catch (error) {
      // Search must not fail because logging failed, but a rejected write
      // (e.g. a rules mismatch) should be visible during development.
      if (kDebugMode) debugPrint('search_logs write failed: $error');
    }
  }

  static const String _searchImportUrl =
      'https://asia-south1-chalakchar-mart.cloudfunctions.net/aliexpressSearchImport';

  Future<void> _triggerSearchImport(String query) async {
    // Runs from a post-frame callback: rebuild so the empty state switches
    // to "খোঁজা হচ্ছে…" right away.
    setState(() {
      _importChecking.add(query);
      _importSent.add(query);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _importChecking.remove(query)) setState(() {});
    });
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
      ).then((response) {
        if (!mounted) return;
        if (_importChecking.remove(query)) setState(() {});
        if (response.statusCode != 400) return;
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] == 'QUERY_REJECTED') {
          setState(() => _rejectedImportQueries[query] = '${body['reason'] ?? ''}');
        }
      }).catchError((_) {});
    } catch (_) {
      // Silent — best-effort, search UI must not depend on it.
    }
  }

  List<QueryDocumentSnapshot> _filterSort(
    List<QueryDocumentSnapshot> docs,
    Set<String> activeCategoriesLower,
  ) {
    return searchResults(
      docs,
      (doc) => doc.data() as Map<String, dynamic>,
      activeCategoriesLower: activeCategoriesLower,
      query: _query,
      category: _selectedCategory,
      onlyInStock: _onlyInStock,
      onlyMarketplace: _onlyMarketplace,
      onlyPharmacy: _onlyPharmacy,
      sort: _sort,
    );
  }

  void _clearFilters() {
    _settleTimer?.cancel();
    setState(() {
      _settled.clear();
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
      preferredSize: Size.fromHeight(GlobalWebHeader.height),
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
        stream: _products,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // No server list: a settled query is dropped, never imported.
            _settled.clear();
          }
          final error = snapshot.error ?? _activeCategoriesError;
          if (error != null) {
            return Center(child: Text('Search failed: $error'));
          }

          final activeCategories = _activeCategoriesLower;
          if (!snapshot.hasData || activeCategories == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = _filterSort(snapshot.data!.docs, activeCategories);

          // Decided only on a list the server confirmed (see
          // SettledSearchGate); the work runs after this frame.
          final settled = _settled.take(
            currentQuery: _query,
            fromCache: snapshot.data!.metadata.isFromCache,
            failed: false,
          );
          if (settled != null) {
            // Counted over every active, approved product, hidden ones
            // too (as before): a query that only finds hidden items (old
            // grocery) is not a "search miss" and must not start an
            // AliExpress import.
            final matchCount = searchMatchCount(
              snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>),
              settled,
            );
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _handleSettledQuery(settled, matchCount),
            );
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
                            child: isDesktop
                                ? Wrap(
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
                                  )
                                : GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    clipBehavior: Clip.none,
                                    padding: EdgeInsets.zero,
                                    itemCount: products.length,
                                    gridDelegate: ProductCard.gridDelegate(context),
                                    itemBuilder: (context, index) {
                                      final doc = products[index];
                                      final data = Map<String, dynamic>.from(
                                        doc.data() as Map<String, dynamic>,
                                      );
                                      data['id'] = doc.id;
                                      return ProductCard(data: data, gridMode: true);
                                    },
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
                  onSubmitted: _onQuerySubmitted,
                  onChanged: _onQueryChanged,
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
          const Icon(Icons.manage_search_rounded, color: Color(0xFF1E7A3A)),
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
    final rejectReason = _query.isEmpty
        ? null
        : _rejectedImportQueries[normalizeSearchQuery(_query)];
    final rejected = rejectReason != null;
    final checking = _query.isNotEmpty &&
        !rejected &&
        _importChecking.contains(normalizeSearchQuery(_query));
    // Not sent at all (too short, digits only, ...): nothing is coming.
    final notSent = _query.isNotEmpty &&
        !rejected &&
        !checking &&
        !_importSent.contains(normalizeSearchQuery(_query));
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
                : rejectReason == 'health'
                    ? 'দুঃখিত, এই পণ্যটি আমরা বিক্রি করি না। অন্য কোনো পণ্য খুঁজে দেখুন।'
                    : rejected || notSent
                        ? 'এই নামে কিছু পাওয়া যায়নি। পণ্যের নাম বা মডেল ইংরেজিতে লিখে খুঁজে দেখুন (যেমন: Samsung A23 display)।'
                        : checking
                            ? 'খোঁজা হচ্ছে…'
                            : 'প্রোডাক্টটি এখন নেই। আমরা বিদেশ থেকে আনার চেষ্টা করছি, পাওয়া গেলে নোটিফিকেশন পাবেন।',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (_query.isNotEmpty && !rejected && !checking && !notSent)
                FilledButton.icon(
                  onPressed: _onNotifyMePressed,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('জানিয়ে দিন'),
                ),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.refresh),
                label: const Text('Clear filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // The only place on the search page that asks for notification permission,
  // and only because the shopper tapped it. Awaiting here is fine: it is a
  // button handler, so a pending prompt blocks nothing.
  Future<void> _onNotifyMePressed() async {
    final user = FirebaseAuth.instance.currentUser;
    final result = await NotificationService.requestAndSaveToken(user?.uid);
    if (!mounted) return;

    final String message;
    switch (result) {
      case NotificationPermissionResult.unsupported:
        message = 'এই ব্রাউজারে নোটিফিকেশন সাপোর্ট করে না।';
      case NotificationPermissionResult.denied:
        message = 'নোটিফিকেশন বন্ধ আছে। ব্রাউজারের সাইট সেটিংস থেকে চালু করুন।';
      case NotificationPermissionResult.granted:
        message = user == null
            ? 'নোটিফিকেশন চালু হয়েছে। পণ্য রেডি হলে জানাতে লগইন করুন।'
            : 'পণ্যটি রেডি হলে আপনাকে জানিয়ে দেব।';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}


// -----------------------------------------------------------------------------
// Search results (pure, so the rules can be tested)
// -----------------------------------------------------------------------------

String _searchText(dynamic value, [String fallback = '']) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

// Same "from" price as the cards (cheapest in-stock variant).
double _searchPriceOf(Map<String, dynamic> data) =>
    ProductService.getDisplayPrice(data);

int _searchStockOf(Map<String, dynamic> data) {
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

DateTime _searchDateOf(Map<String, dynamic> data) {
  final value = data['createdAt'];
  if (value is Timestamp) return value.toDate();
  return DateTime(2000);
}

bool _searchIsMarketplace(Map<String, dynamic> data) {
  final vendorId = _searchText(data['vendorId']);
  return vendorId.isNotEmpty && vendorId != 'super_admin';
}

int _searchScore(Map<String, dynamic> data, String q) {
  if (q.trim().isEmpty) return 0;

  final query = q.toLowerCase().trim();
  final name = _searchText(data['name']).toLowerCase();
  final generic = _searchText(data['generic']).toLowerCase();
  final manufacturer = _searchText(data['manufacturer']).toLowerCase();
  final brand = _searchText(data['brand']).toLowerCase();
  final category = _searchText(data['category']).toLowerCase();
  final type = _searchText(data['type']).toLowerCase();
  final strength = _searchText(data['strength']).toLowerCase();
  final vendorName = _searchText(data['vendorName'] ?? data['shopName']).toLowerCase();

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

bool searchMatches(Map<String, dynamic> data, String q) {
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

/// Products matching a settled query, for the search-miss decision: every
/// active, approved product, hidden ones too.
int searchMatchCount(Iterable<Map<String, dynamic>> products, String query) =>
    products.where((p) => p['isActive'] != false && searchMatches(p, query)).length;

/// The search page's list: only products the shop shows
/// ([isShopVisibleProduct]), then the shopper's category / stock / vendor
/// filters and the query, sorted by [sort].
List<T> searchResults<T>(
  Iterable<T> items,
  Map<String, dynamic> Function(T item) dataOf, {
  required Set<String> activeCategoriesLower,
  String query = '',
  String category = 'All',
  bool onlyInStock = false,
  bool onlyMarketplace = false,
  bool onlyPharmacy = false,
  String sort = 'relevance',
}) {
  final list = shopVisibleOnly(items, activeCategoriesLower, dataOf).where((item) {
    final data = dataOf(item);
    if (category != 'All' && _searchText(data['category']) != category) return false;
    if (onlyInStock && _searchStockOf(data) <= 0) return false;
    if (onlyMarketplace && !_searchIsMarketplace(data)) return false;
    if (onlyPharmacy && _searchIsMarketplace(data)) return false;
    return searchMatches(data, query);
  }).toList();

  list.sort((a, b) {
    final ad = dataOf(a);
    final bd = dataOf(b);
    switch (sort) {
      case 'price_low':
        return _searchPriceOf(ad).compareTo(_searchPriceOf(bd));
      case 'price_high':
        return _searchPriceOf(bd).compareTo(_searchPriceOf(ad));
      case 'stock':
        return _searchStockOf(bd).compareTo(_searchStockOf(ad));
      case 'newest':
        return _searchDateOf(bd).compareTo(_searchDateOf(ad));
      case 'relevance':
      default:
        final bScore = _searchScore(bd, query);
        final aScore = _searchScore(ad, query);
        if (aScore != bScore) return bScore.compareTo(aScore);
        return _searchDateOf(bd).compareTo(_searchDateOf(ad));
    }
  });
  return list;
}
