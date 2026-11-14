import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/image_upload_service.dart';
import '../../services/product_service.dart';
import '../../services/ai_product_optimizer_service.dart';
import '../../widgets/ai_product_preview_dialog.dart';
import '../../services/marketing_settings_service.dart';
import '../../services/marketing_queue_service.dart';
import '../../utils/variant_merge.dart';
import '../../services/category_resolver_service.dart';
import '../../utils/category_lookup.dart';
import '../../utils/category_normalize.dart';

class ManageProductsPage extends StatefulWidget {
  const ManageProductsPage({super.key});

  @override
  State<ManageProductsPage> createState() => _ManageProductsPageState();
}

class _ManageProductsPageState extends State<ManageProductsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();


  static const String _kFilterAll = 'all';
  static const String _kUncategorized = '__uncategorized__';
  // Non-selectable "Hidden" section header in the category filter.
  static const String _kHiddenHeader = '__hidden_header__';
  // Product-dialog category value for a name with no category doc yet.
  static const String _kNameOnlyCategory = '__name_only__';
  // All products are loaded client-side (1 read each per page open); past
  // this size, switch to per-category queries + count() aggregations.
  static const int _kLargeCatalogNotice = 2000;

  final TextEditingController _searchController = TextEditingController();
  String searchText = '';
  String stockFilter = _kFilterAll;
  String statusFilter = _kFilterAll;
  // A category doc id, _kFilterAll or _kUncategorized.
  String categoryFilter = _kFilterAll;
  // A subcategory doc id or _kFilterAll; only used with a specific category.
  String subcategoryFilter = _kFilterAll;
  // Bumped by "Clear filters" so the initialValue-based dropdowns rebuild.
  int _filterResetEpoch = 0;

  // One listener each, shared by the filter bar (option counts) and the list.
  StreamSubscription<QuerySnapshot>? _productsSub;
  StreamSubscription<QuerySnapshot>? _categoriesSub;
  StreamSubscription<QuerySnapshot>? _subcategoriesSub;
  List<QueryDocumentSnapshot>? _productDocs;
  Object? _productsError;
  List<QueryDocumentSnapshot> _categoryDocs = const [];
  bool _categoriesLoaded = false;
  List<QueryDocumentSnapshot> _subcategoryDocs = const [];
  String? _subcategoriesFor;

  bool bulkWorking = false;
  bool permissionLoading = true;
  bool canViewProducts = false;
  bool canEditProducts = false;
  bool canDeleteProducts = false;
  bool canBulkProducts = false;
  bool canChangeProductStatus = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _categoriesSub?.cancel();
    _subcategoriesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startListListeners() {
    if (_productsSub != null) return;
    // Every product, unordered and unlimited: the category filter exists to
    // find old miscategorized products, and orderBy('createdAt') would
    // silently drop any doc missing that field. Sorted newest-first below.
    _productsSub = db.collection('products').snapshots().listen(
      (snap) {
        if (!mounted) return;
        final docs = snap.docs.toList()..sort(_compareNewestFirst);
        setState(() {
          _productDocs = docs;
          _productsError = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _productsError = e);
      },
    );
    // All categories, including inactive / hidden-from-home ones.
    _categoriesSub = FirebaseService.getCategories().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _categoryDocs = snap.docs;
          _categoriesLoaded = true;
        });
      },
      onError: (Object e) {
        debugPrint('PRODUCT FILTER CATEGORIES ERROR: $e');
        if (!mounted) return;
        setState(() => _categoriesLoaded = true);
      },
    );
  }

  /// createdAt descending; products without a usable createdAt go last.
  static int _compareNewestFirst(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    DateTime? created(QueryDocumentSnapshot d) {
      final v = (d.data() as Map<String, dynamic>)['createdAt'];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final ca = created(a);
    final cb = created(b);
    if (ca == null && cb == null) return 0;
    if (ca == null) return 1;
    if (cb == null) return -1;
    return cb.compareTo(ca);
  }

  void _listenSubcategories(String categoryId) {
    _subcategoriesSub?.cancel();
    _subcategoriesSub = null;
    _subcategoryDocs = const [];
    _subcategoriesFor = null;
    if (categoryId == _kFilterAll || categoryId == _kUncategorized) return;

    _subcategoriesFor = categoryId;
    _subcategoriesSub = db
        .collection('subcategories')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted || _subcategoriesFor != categoryId) return;
        setState(() => _subcategoryDocs = snap.docs);
      },
      onError: (Object e) => debugPrint('PRODUCT FILTER SUBCATEGORIES ERROR: $e'),
    );
  }

  void _selectCategoryFilter(String value) {
    if (value == categoryFilter) return;
    setState(() {
      categoryFilter = value;
      subcategoryFilter = _kFilterAll;
      _listenSubcategories(value);
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      searchText = '';
      statusFilter = _kFilterAll;
      stockFilter = _kFilterAll;
      categoryFilter = _kFilterAll;
      subcategoryFilter = _kFilterAll;
      _listenSubcategories(_kFilterAll);
      _filterResetEpoch++;
    });
  }

  Future<void> _loadPermissions() async {
    try {
      final results = await Future.wait<bool>([
        authService.hasPermission('products.view'),
        authService.hasPermission('products.edit'),
        authService.hasPermission('products.delete'),
        authService.hasPermission('products.bulk'),
        authService.hasPermission('products.status'),
      ]);

      if (!mounted) return;

      setState(() {
        canViewProducts = results[0] || results[1];
        canEditProducts = results[1];
        canDeleteProducts = results[2] || results[1];
        canBulkProducts = results[3] || results[1];
        canChangeProductStatus = results[4] || results[1];
        permissionLoading = false;
      });
      if (canViewProducts) _startListListeners();
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e', isError: true);
    }
  }

  bool _denyIf(bool denied, String message) {
    if (!denied) return false;
    _snack(message, isError: true);
    return true;
  }


  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _text(dynamic value, [String fallback = '']) {
    final t = (value ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Future<String> _uploadPickedImage(XFile file) async {
    try {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('Selected image is empty');
        }
        return ImageUploadService.upload(null, webImage: bytes, folder: 'products');
      }

      if (file.path.isEmpty) {
        throw Exception('Image file path is empty');
      }

      return ImageUploadService.upload(File(file.path), folder: 'products');
    } catch (e, s) {
      debugPrint('PRODUCT IMAGE UPLOAD ERROR: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }

  String? _youtubeVideoId(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;

    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) return input;

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();

    if (host.contains('youtu.be')) {
      return segments.isNotEmpty ? segments.first : null;
    }

    if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      final watchId = uri.queryParameters['v'];
      if (watchId != null && watchId.trim().isNotEmpty) return watchId.trim();

      for (final marker in ['embed', 'shorts', 'live']) {
        final index = segments.indexOf(marker);
        if (index != -1 && segments.length > index + 1) return segments[index + 1];
      }
    }

    return null;
  }

  String _youtubeThumbnail(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  /// Resolves a raw category (and optional subcategory) name through the
  /// shared backend resolver before a product is saved — used by every
  /// admin product-writing path (manual save, CSV import, JSON import) so
  /// category resolution is never duplicated or done inconsistently.
  /// Falls back to the raw (or 'Other') text on any resolver error, so a
  /// transient failure never blocks a product save.
  Future<({String category, String? categoryId, String? subcategoryId})>
      _resolveCategoryForImport(String rawCategory, {String? subCategory}) async {
    final trimmed = rawCategory.trim().isEmpty ? 'Other' : rawCategory.trim();
    try {
      final resolution =
          await CategoryResolverService.resolve(trimmed, subCategoryName: subCategory);
      if (resolution != null) {
        return (
          category: resolution.categoryName,
          categoryId: resolution.categoryId,
          subcategoryId: resolution.subcategoryId,
        );
      }
    } catch (_) {
      // ignore — fall back to the raw value below
    }
    return (category: trimmed, categoryId: null, subcategoryId: null);
  }


  Future<void> _pickCSVFile() async {
    if (_denyIf(!canBulkProducts, 'You do not have products.bulk permission.')) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      setState(() => bulkWorking = true);

      String csvContent;

      if (kIsWeb) {
        csvContent = utf8.decode(result.files.first.bytes ?? []);
      } else {
        csvContent = await File(result.files.first.path!).readAsString();
      }

      final rows = const CsvToListConverter().convert(csvContent);

      if (rows.length <= 1) {
        _snack('CSV file is empty', isError: true);
        return;
      }

      int added = 0;
      int updated = 0;
      int skipped = 0;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.isEmpty || _text(row[0]).isEmpty) {
          skipped++;
          continue;
        }

        final name = _text(row[0]);
        final strength = row.length > 1 ? _text(row[1]) : '';
        final type = row.length > 2 ? _text(row[2]) : 'Tablet';
        final price = row.length > 3 ? _toDouble(row[3]) : 0;
        final oldPrice = row.length > 4 ? _toDouble(row[4]) : price;
        final generic = row.length > 5 ? _text(row[5]) : '';
        final manufacturer = row.length > 6 ? _text(row[6]) : '';
        final variantName = row.length > 7 && _text(row[7]).isNotEmpty ? _text(row[7]) : 'Default';
        final stock = row.length > 8 ? _toInt(row[8]) : 0;
        final category = row.length > 9 && _text(row[9]).isNotEmpty ? _text(row[9]) : 'Other';
        final overview = row.length > 10 ? _text(row[10]) : '';

        final existing = await db
            .collection('products')
            .where('name', isEqualTo: name)
            .where('strength', isEqualTo: strength)
            .limit(1)
            .get();

        final newVariant = {
          'name': variantName,
          'price': price,
          'mrp': oldPrice,
          'stock': stock,
        };

        if (existing.docs.isNotEmpty) {
          final doc = existing.docs.first;
          final data = doc.data();
          final variants = List<Map<String, dynamic>>.from(
            (data['variants'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
          );

          final exists = variants.any(
                (v) => _text(v['name']).toLowerCase() == variantName.toLowerCase(),
          );

          if (exists) {
            skipped++;
            continue;
          }

          variants.add(newVariant);

          final rawCategory = _text(data['category']).isEmpty ? category : _text(data['category']);
          final categoryResolution = await _resolveCategoryForImport(rawCategory);

          final payload = ProductService.buildProductPayload(
            name: _text(data['name']),
            category: categoryResolution.category,
            generic: _text(data['generic']),
            manufacturer: _text(data['manufacturer']),
            type: _text(data['type']).isEmpty ? type : _text(data['type']),
            strength: _text(data['strength']).isEmpty ? strength : _text(data['strength']),
            overview: _text(data['overview']).isEmpty ? overview : _text(data['overview']),
            image: _text(data['image']),
            images: List<String>.from(data['images'] ?? []),
            videoUrl: _text(data['videoUrl']),
            isActive: data['isActive'] != false,
            isMarketplace: data['isMarketplace'] == true,
            vendorId: _text(data['vendorId']).isEmpty ? 'super_admin' : _text(data['vendorId']),
            vendorName: _text(data['vendorName']).isEmpty ? 'ChalakChar Mart' : _text(data['vendorName']),
            approvalStatus: _text(data['approvalStatus']).isEmpty ? 'approved' : _text(data['approvalStatus']),
            variants: variants,
          );
          if (categoryResolution.categoryId != null) {
            payload['categoryId'] = categoryResolution.categoryId;
          }
          if (categoryResolution.subcategoryId != null) {
            payload['subcategoryId'] = categoryResolution.subcategoryId;
          }

          await ProductService.saveProduct(
            productId: doc.id,
            payload: payload,
          );

          updated++;
        } else {
          final categoryResolution = await _resolveCategoryForImport(category);

          final payload = ProductService.buildProductPayload(
            name: name,
            category: categoryResolution.category,
            generic: generic,
            manufacturer: manufacturer,
            type: type,
            strength: strength,
            overview: overview,

            isActive: true,
            isMarketplace: false,
            vendorId: 'super_admin',
            vendorName: 'ChalakChar Mart',
            approvalStatus: 'approved',

            variants: [newVariant],
            includeCreatedAt: true,
          );
          if (categoryResolution.categoryId != null) {
            payload['categoryId'] = categoryResolution.categoryId;
          }
          if (categoryResolution.subcategoryId != null) {
            payload['subcategoryId'] = categoryResolution.subcategoryId;
          }

          await ProductService.saveProduct(payload: payload);

          added++;
        }
      }

      _snack('CSV done: $added added, $updated updated, $skipped skipped');
    } catch (e) {
      _snack('CSV error: $e', isError: true);
    } finally {
      if (mounted) setState(() => bulkWorking = false);
    }
  }

  Future<void> _showJsonBulkDialog() async {
    if (_denyIf(!canBulkProducts, 'You do not have products.bulk permission.')) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Paste JSON Products'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[{"name":"Ace","price":2,"stock":100,"category":"Product"}]',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(context);
              try {
                final raw = jsonDecode(controller.text);
                if (raw is! List) throw Exception('JSON must be a list');

                int count = 0;

                for (final item in raw) {
                  if (item is! Map) continue;

                  final price = _toDouble(item['price']);
                  final oldPrice = _toDouble(item['oldPrice'] ?? item['mrp'] ?? price);
                  final stock = _toInt(item['stock']);
                  final variantName = _text(item['variantName']).isEmpty ? 'Default' : _text(item['variantName']);
                  final categoryResolution = await _resolveCategoryForImport(_text(item['category']));

                  final payload = ProductService.buildProductPayload(
                    name: _text(item['name']),
                    category: categoryResolution.category,
                    generic: _text(item['generic']),
                    manufacturer: _text(item['manufacturer']),
                    type: _text(item['type']).isEmpty ? 'Tablet' : _text(item['type']),
                    strength: _text(item['strength']),
                    overview: _text(item['overview']),
                    image: _text(item['image']),
                    images: List<String>.from(item['images'] ?? []),
                    videoUrl: _text(item['videoUrl']),

                    isActive: true,
                    isMarketplace: false,
                    vendorId: 'super_admin',
                    vendorName: 'ChalakChar Mart',
                    approvalStatus: 'approved',

                    variants: [
                      {
                        'name': variantName,
                        'price': price,
                        'mrp': oldPrice,
                        'stock': stock,
                      }
                    ],
                    includeCreatedAt: true,
                  );
                  if (categoryResolution.categoryId != null) {
                    payload['categoryId'] = categoryResolution.categoryId;
                  }
                  if (categoryResolution.subcategoryId != null) {
                    payload['subcategoryId'] = categoryResolution.subcategoryId;
                  }

                  await ProductService.saveProduct(payload: payload);

                  count++;
                }

                if (dialogNavigator.mounted) dialogNavigator.pop();
                _snack('$count products uploaded from JSON');
              } catch (e) {
                _snack('JSON error: $e', isError: true);
              }
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDialog({
    String? id,
    Map<String, dynamic>? data,
  }) async {
    if (_denyIf(!canEditProducts, 'You do not have products.edit permission.')) return;

    final name = TextEditingController(text: _text(data?['name']));
    final generic = TextEditingController(text: _text(data?['generic']));
    final manufacturer = TextEditingController(text: _text(data?['manufacturer']));
    final type = TextEditingController(text: _text(data?['type']));
    final strength = TextEditingController(text: _text(data?['strength']));
    // Label before the variant value on the product page ("Model: 12 Pro").
    // Empty = automatic (subcategory/category default, then the values).
    final variantLabel = TextEditingController(text: _text(data?['variantAttributeName']));
    final overview = TextEditingController(text: _text(data?['overview']));
    final videoUrl = TextEditingController(
      text: _text(
        data?['videoUrl'] ??
            data?['youtubeUrl'] ??
            data?['youtubeLink'] ??
            data?['videoLink'],
      ),
    );
    String youtubeVideoId = _text(data?['youtubeVideoId']);
    String videoThumbnailUrl = _text(data?['videoThumbnailUrl']);
    String videoDuration = _text(data?['videoDuration']);

    final String productSource = _text(data?['source']);
    final String sourceProductId = _text(data?['sourceProductId']);
    final bool isAliExpressSourced = ProductService.isAliExpressSourced({'source': productSource});
    final String aliExpressLink = isAliExpressSourced && sourceProductId.isNotEmpty
        ? ProductService.buildAliExpressLink(sourceProductId)
        : '';

    String? category = _text(data?['category']).isEmpty ? null : _text(data?['category']);
    // Picked from the dropdown only; the AI suggestedSubCategory is shown as
    // a hint and never creates a subcategory on its own.
    String subcategoryId = _text(data?['subcategoryId']);
    // Set when an AI category suggestion moved the product to another
    // category and so dropped the selected subcategory; saving without
    // picking a new one asks for confirmation first.
    bool aiDroppedSubcategory = false;
    // The selected category doc. Empty for old name-only products until the
    // category list loads and their name is matched (see categoryDropdown);
    // [category] always carries the selected doc's display name.
    String categoryId = _text(data?['categoryId']);
    // Memoized so dialog rebuilds don't resubscribe and flicker.
    final Stream<QuerySnapshot> allCategoriesStream = FirebaseService.getCategories();
    String? subcategoryStreamParentId;
    Stream<QuerySnapshot>? subcategoryStream;
    String imageUrl = _text(data?['image']);
    List<String> images = List<String>.from(data?['images'] ?? []);
    bool isActive = data?['isActive'] != false;
    bool saving = false;
    bool uploading = false;
    bool aiLoading = false;
    bool aiImageLoading = false;
    bool aiStudioLoading = false;

    String banglaTitle = _text(data?['banglaTitle']);
    String banglaDescription = _text(data?['banglaDescription']);
    List<String> seoTags = List<String>.from(data?['seoTags'] ?? []);

    String facebookCaption = _text(data?['facebookCaption']);
    String whatsappCaption = _text(data?['whatsappCaption']);
    final marketingCaptionController = TextEditingController(
      text: _text(
        data?['marketingCaption'] ??
            data?['facebookCaption'] ??
            data?['whatsappCaption'],
      ),
    );

    final existingMarketingChannels = data != null && data['marketingChannels'] is Map
        ? Map<String, dynamic>.from(data['marketingChannels'] as Map)
        : <String, dynamic>{};

    bool marketingEnabled = data == null
        ? true
        : data['autoMarketingDisabled'] != true;
    bool marketingQueue = true;
    bool marketingPush = existingMarketingChannels.isEmpty
        ? true
        : (existingMarketingChannels['fcm'] == true ||
        existingMarketingChannels['push'] == true);
    bool marketingInApp = existingMarketingChannels.isEmpty
        ? true
        : existingMarketingChannels['inApp'] == true;
    bool marketingFacebook = existingMarketingChannels['facebook'] == true;
    bool marketingInstagram = existingMarketingChannels['instagram'] == true;
    bool marketingWhatsapp = existingMarketingChannels['whatsapp'] == true;
    bool marketingMessenger = existingMarketingChannels['messenger'] == true;
    bool marketingTiktok = existingMarketingChannels['tiktok'] == true;
    String marketingAudience = _text(data?['marketingAudience'], 'everyone');
    String marketingPublishMode = _text(data?['marketingPublishMode'], 'now');
    DateTime? marketingScheduledAt;

    String metaTitle = _text(data?['metaTitle']);
    String metaDescription = _text(data?['metaDescription']);
    List<String> searchKeywords = List<String>.from(data?['searchKeywords'] ?? []);
    String suggestedCategory = _text(data?['suggestedCategory']);
    String suggestedSubCategory = _text(data?['suggestedSubCategory']);
    String productType = _text(data?['productType']);

    List<Map<String, TextEditingController>> variantControllers = [];
    // Parallel to variantControllers (same length, same index): the exact
    // original variant map each row was seeded from, or null for a row
    // added fresh during this edit session (nothing to preserve for those).
    // Kept in sync on add/delete so a row can never inherit another
    // variant's metadata.
    List<Map<String, dynamic>?> variantOriginals = [];

    final oldVariants = data?['variants'] is List ? data!['variants'] as List : [];

    if (oldVariants.isNotEmpty) {
      for (final v in oldVariants) {
        if (v is! Map) continue;
        variantControllers.add({
          'name': TextEditingController(text: _text(v['name'])),
          'price': TextEditingController(text: _toDouble(v['price']).toStringAsFixed(0)),
          'mrp': TextEditingController(text: _toDouble(v['mrp'] ?? v['oldPrice']).toStringAsFixed(0)),
          'stock': TextEditingController(text: _toInt(v['stock']).toString()),
        });
        variantOriginals.add(Map<String, dynamic>.from(v));
      }
    } else {
      variantControllers.add({
        'name': TextEditingController(text: _text(data?['unit']).isEmpty ? 'Default' : _text(data?['unit'])),
        'price': TextEditingController(text: _toDouble(data?['price']).toStringAsFixed(0)),
        'mrp': TextEditingController(text: _toDouble(data?['oldPrice']).toStringAsFixed(0)),
        'stock': TextEditingController(text: _toInt(data?['stock']).toString()),
      });
      // Synthesized from top-level product fields, not a real variant doc.
      variantOriginals.add(null);
    }

    final pageContext = context;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickImage({bool main = false}) async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );

            if (picked == null) return;

            setDialogState(() => uploading = true);

            try {
              final url = await _uploadPickedImage(picked);

              setDialogState(() {
                if (main) imageUrl = url;
                if (!images.contains(url)) images.add(url);
                if (imageUrl.isEmpty) imageUrl = url;
              });
            } catch (e) {
              _snack('Image upload failed: $e', isError: true);
            } finally {
              setDialogState(() => uploading = false);
            }
          }

          void addVariant() {
            setDialogState(() {
              variantControllers.add({
                'name': TextEditingController(text: 'Default'),
                'price': TextEditingController(text: '0'),
                'mrp': TextEditingController(text: '0'),
                'stock': TextEditingController(text: '0'),
              });
              variantOriginals.add(null);
            });
          }
          Future<void> applySuggestedCategory(String value) async {
            final suggested = value.trim();
            if (suggested.isEmpty) return;

            // Category Manager is now the single source of truth: the shared
            // resolver reuses an existing (normalized-match) category or
            // auto-creates one — no separate confirmation step, matching the
            // approved "automatic" behavior. Falls back to just using the
            // typed name if resolution fails, so an admin is never blocked
            // from picking an AI-suggested category by a transient error.
            String resolvedCategory = suggested;
            String resolvedCategoryId = '';
            try {
              final resolution = await CategoryResolverService.resolve(suggested);
              if (resolution != null) {
                resolvedCategory = resolution.categoryName;
                resolvedCategoryId = resolution.categoryId;
              }
            } catch (_) {
              // ignore — fall back to the raw suggested name below (matched
              // by name in the dropdown, or resolved on save)
            }

            if (!pageContext.mounted) return;

            // Same category (by id, or by name when the resolver gave no
            // id): keep categoryId and the subcategory as they are.
            final sameCategory = resolvedCategoryId.isNotEmpty
                ? resolvedCategoryId == categoryId
                : resolvedCategory == category;
            if (sameCategory) {
              setDialogState(() => category = resolvedCategory);
              return;
            }

            // A subcategory belongs to one category, so it can't follow the
            // product to another one — drop it, but say so.
            final dropped = subcategoryId.isNotEmpty;
            setDialogState(() {
              subcategoryId = '';
              if (dropped) aiDroppedSubcategory = true;
              category = resolvedCategory;
              categoryId = resolvedCategoryId;
            });
            if (dropped) {
              _snack(
                'AI changed the category to "$resolvedCategory" — the subcategory was cleared. Pick a new one or it will be removed on save.',
                isError: true,
              );
            }
          }

          Future<void> createProductFromImage() async {
            if (aiImageLoading || saving || uploading) return;

            setDialogState(() => aiImageLoading = true);

            try {
              String targetImageUrl = imageUrl;

              if (targetImageUrl.trim().isEmpty) {
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );

                if (picked == null) return;

                targetImageUrl = await _uploadPickedImage(picked);

                setDialogState(() {
                  imageUrl = targetImageUrl;
                  if (!images.contains(targetImageUrl)) images.add(targetImageUrl);
                });
              }

              final result = await AIProductOptimizerService.optimizeFromImage(
                imageUrl: targetImageUrl,
                hintTitle: name.text.trim(),
                hintCategory: category ?? '',
              );

              if (!pageContext.mounted) return;

              if (result == null) {
                _snack('AI image analysis failed. Please try again.', isError: true);
                return;
              }

              await showDialog(
                context: pageContext,
                builder: (_) => AIProductPreviewDialog(
                  title: result.title,
                  banglaTitle: result.banglaTitle,
                  description: result.description,
                  banglaDescription: result.banglaDescription,
                  seoTags: result.seoTags,
                  facebookCaption: result.facebookCaption,
                  whatsappCaption: result.whatsappCaption,
                  metaTitle: result.metaTitle,
                  metaDescription: result.metaDescription,
                  suggestedCategory: result.suggestedCategory,
                  suggestedSubCategory: result.suggestedSubCategory,
                  productType: result.productType,
                  searchKeywords: result.searchKeywords,
                  onApply: () {
                    if (!mounted) return;

                    if (result.title.trim().isNotEmpty) name.text = result.title.trim();
                    overview.text = result.banglaDescription.isNotEmpty
                        ? result.banglaDescription
                        : result.description;

                    setDialogState(() {
                      banglaTitle = result.banglaTitle;
                      banglaDescription = result.banglaDescription;
                      seoTags = result.seoTags;
                      facebookCaption = result.facebookCaption;
                      whatsappCaption = result.whatsappCaption;
                      metaTitle = result.metaTitle;
                      metaDescription = result.metaDescription;
                      searchKeywords = result.searchKeywords;
                      suggestedCategory = result.suggestedCategory;
                      suggestedSubCategory = result.suggestedSubCategory;
                      productType = result.productType;

                      if (type.text.trim().isEmpty &&
                          result.productType.trim().isNotEmpty) {
                        type.text = result.productType.trim();
                      }
                    });

                    if ((category == null || category!.trim().isEmpty) &&
                        result.suggestedCategory.trim().isNotEmpty) {
                      applySuggestedCategory(result.suggestedCategory);
                    }
                  },
                ),
              );
            } catch (e, s) {
              debugPrint('AI image product error: $e');
              debugPrintStack(stackTrace: s);
              if (mounted) {
                final message = e.toString().replaceFirst('Exception:', '').trim();
                _snack(message.isEmpty ? 'AI image analysis failed' : message, isError: true);
              }
            } finally {
              if (mounted) setDialogState(() => aiImageLoading = false);
            }
          }

          Future<void> openAIImageStudio() async {
            if (aiStudioLoading || saving || uploading) return;

            if (imageUrl.trim().isEmpty) {
              _snack('Please upload or select a main image first.', isError: true);
              return;
            }

            final selectedStyle = await showDialog<String>(
              context: pageContext,
              builder: (_) => SimpleDialog(
                title: const Text('AI Product Image Studio'),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'white_background'),
                    child: const ListTile(
                      leading: Icon(Icons.photo_size_select_actual_rounded),
                      title: Text('White Background'),
                      subtitle: Text('Clean ecommerce product image'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'studio'),
                    child: const ListTile(
                      leading: Icon(Icons.light_mode_rounded),
                      title: Text('Studio Product Photo'),
                      subtitle: Text('Premium lighting and clean shadow'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'lifestyle'),
                    child: const ListTile(
                      leading: Icon(Icons.local_florist_rounded),
                      title: Text('Lifestyle Image'),
                      subtitle: Text('Natural product usage scene'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'human_model'),
                    child: const ListTile(
                      leading: Icon(Icons.accessibility_new_rounded),
                      title: Text('Human Model Wearing / Using'),
                      subtitle: Text('For shoes, clothes, accessories etc.'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, 'social_banner'),
                    child: const ListTile(
                      leading: Icon(Icons.campaign_rounded),
                      title: Text('Social Media Banner'),
                      subtitle: Text('Ad-ready image composition'),
                    ),
                  ),
                ],
              ),
            );

            if (selectedStyle == null || selectedStyle.trim().isEmpty) return;

            setDialogState(() => aiStudioLoading = true);

            try {
              final generatedUrl = await AIProductOptimizerService.generateProductImage(
                imageUrl: imageUrl,
                productName: name.text.trim(),
                style: selectedStyle,
              );

              if (!pageContext.mounted) return;

              if (generatedUrl == null || generatedUrl.trim().isEmpty) {
                _snack('AI image generation failed. Please try again.', isError: true);
                return;
              }

              final action = await showDialog<String>(
                context: pageContext,
                builder: (_) => AlertDialog(
                  title: const Text('AI Generated Image'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            generatedUrl,
                            height: 320,
                            width: 320,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 64),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Use this image as main image or add to gallery?',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'cancel'),
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 'gallery'),
                      icon: const Icon(Icons.collections_rounded),
                      label: const Text('Add Gallery'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, 'main'),
                      icon: const Icon(Icons.check),
                      label: const Text('Use as Main'),
                    ),
                  ],
                ),
              );

              if (action == 'main') {
                setDialogState(() {
                  imageUrl = generatedUrl;
                  if (!images.contains(generatedUrl)) {
                    images.insert(0, generatedUrl);
                  }
                });
                _snack('AI image set as main image');
              } else if (action == 'gallery') {
                setDialogState(() {
                  if (!images.contains(generatedUrl)) {
                    images.add(generatedUrl);
                  }
                });
                _snack('AI image added to gallery');
              }
            } catch (e, s) {
              debugPrint('openAIImageStudio, error: $e');
              debugPrintStack(stackTrace: s);

              if (mounted) {
                final message = e.toString()
                    .replaceFirst('Exception:', '')
                    .trim();

                _snack(
                  message.isEmpty ? 'AI image generation failed' : message,
                  isError: true,
                );
              }
            } finally {
              if (mounted) {
                setDialogState(() => aiStudioLoading = false);
              }
            }
          }

          Future<void> optimizeWithAI() async {
            final productName = name.text.trim();

            if (productName.isEmpty) {
              _snack('Product name required before AI optimize', isError: true);
              return;
            }

            if (aiLoading || saving) return;

            setDialogState(() => aiLoading = true);

            try {
              final result = await AIProductOptimizerService.optimize(
                title: productName,
                description: overview.text.trim(),
                category: category ?? '',
              );

              if (!pageContext.mounted) return;

              if (result == null) {
                _snack('AI optimize failed. Please try again.', isError: true);
                return;
              }

              await showDialog(
                context: pageContext,
                builder: (_) => AIProductPreviewDialog(
                  title: result.title,
                  banglaTitle: result.banglaTitle,
                  description: result.description,
                  banglaDescription: result.banglaDescription,
                  seoTags: result.seoTags,
                  facebookCaption: result.facebookCaption,
                  whatsappCaption: result.whatsappCaption,
                  metaTitle: result.metaTitle,
                  metaDescription: result.metaDescription,
                  suggestedCategory: result.suggestedCategory,
                  suggestedSubCategory: result.suggestedSubCategory,
                  productType: result.productType,
                  searchKeywords: result.searchKeywords,
                  onApply: () {
                    if (!mounted) return;

                    name.text = result.title;
                    overview.text = result.banglaDescription.isNotEmpty
                        ? result.banglaDescription
                        : result.description;

                    setDialogState(() {
                      banglaTitle = result.banglaTitle;
                      banglaDescription = result.banglaDescription;
                      seoTags = result.seoTags;

                      facebookCaption = result.facebookCaption;
                      whatsappCaption = result.whatsappCaption;
                      metaTitle = result.metaTitle;
                      metaDescription = result.metaDescription;
                      searchKeywords = result.searchKeywords;
                      suggestedCategory = result.suggestedCategory;
                      suggestedSubCategory = result.suggestedSubCategory;
                      productType = result.productType;

                      if (type.text.trim().isEmpty &&
                          result.productType.trim().isNotEmpty) {
                        type.text = result.productType.trim();
                      }
                    });

                    if ((category == null || category!.trim().isEmpty) &&
                        result.suggestedCategory.trim().isNotEmpty) {
                      applySuggestedCategory(result.suggestedCategory);
                    }
                  },
                ),
              );
            } catch (e, s) {
              debugPrint('AI dialog error: $e');
              debugPrintStack(stackTrace: s);

              if (mounted) {
                final message = e.toString()
                    .replaceFirst('Exception:', '')
                    .trim();

                _snack(
                  message.isEmpty ? 'AI optimization failed' : message,
                  isError: true,
                );
              }
            } finally {
              if (mounted) {
                setDialogState(() {
                  aiLoading = false;
                });

              }
            }
          }



          Future<void> saveProduct() async {
            final dialogNavigator = Navigator.of(context);
            final user = FirebaseAuth.instance.currentUser;

            debugPrint('========== PRODUCT SAVE DEBUG ==========');
            debugPrint('UID: ${user?.uid}');
            debugPrint('EMAIL: ${user?.email}');

            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user!.uid)
                .get();

            debugPrint('USER DOC: ${userDoc.data()}');
            final productName = name.text.trim();

            if (productName.isEmpty) {
              _snack('Product name required', isError: true);
              return;
            }

            if (category == null || category!.isEmpty) {
              _snack('Category required', isError: true);
              return;
            }

            if (aiDroppedSubcategory && subcategoryId.isEmpty && id != null) {
              if (!context.mounted) return;
              final proceed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Subcategory will be removed'),
                  content: Text(
                    'AI changed the category to "$category", so the product\'s '
                    'previous subcategory no longer applies. Saving now removes '
                    'the subcategory. Pick one under "$category" first to keep '
                    'the product in a subcategory.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Go back'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Save without subcategory'),
                    ),
                  ],
                ),
              );
              if (proceed != true) return;
            }

            final variants = <Map<String, dynamic>>[
              for (var i = 0; i < variantControllers.length; i++)
                mergeVariantEdit(
                  variantOriginals[i],
                  {
                    'name': variantControllers[i]['name']!.text.trim().isEmpty
                        ? 'Default'
                        : variantControllers[i]['name']!.text.trim(),
                    'price': _toDouble(variantControllers[i]['price']!.text),
                    'mrp': _toDouble(variantControllers[i]['mrp']!.text),
                    'stock': _toInt(variantControllers[i]['stock']!.text),
                  },
                ),
            ];

            setDialogState(() => saving = true);

            try {
              final preparedYoutubeVideoId =
                  _youtubeVideoId(videoUrl.text) ?? youtubeVideoId;
              final preparedVideoThumbnailUrl = preparedYoutubeVideoId.isNotEmpty
                  ? _youtubeThumbnail(preparedYoutubeVideoId)
                  : videoThumbnailUrl;

              // Category only: the subcategory comes from the dropdown, so the
              // AI suggestedSubCategory text no longer auto-creates one. A
              // category picked from the dropdown is saved by its doc id; only
              // a name with no matching doc goes through the resolver.
              final ({String category, String? categoryId, String? subcategoryId}) categoryResolution =
                  categoryId.isNotEmpty
                      ? (category: category!, categoryId: categoryId, subcategoryId: null)
                      : await _resolveCategoryForImport(category!);

              // Never store a subcategoryId that isn't a child of the
              // resolved categoryId (resolveProductTaxonomy invariant).
              Object? subcategoryField; // null = leave the field untouched
              if (categoryResolution.categoryId != null) {
                if (subcategoryId.isEmpty) {
                  if (id != null) subcategoryField = FieldValue.delete();
                } else {
                  final subDoc = await FirebaseFirestore.instance
                      .collection('subcategories')
                      .doc(subcategoryId)
                      .get();
                  if (!subDoc.exists ||
                      _text(subDoc.data()?['categoryId']) != categoryResolution.categoryId) {
                    setDialogState(() => saving = false);
                    _snack('Selected subcategory does not belong to "${categoryResolution.category}". Pick it again.',
                        isError: true);
                    return;
                  }
                  subcategoryField = subcategoryId;
                }
              }

              final payload = ProductService.buildProductPayload(
                name: productName,
                category: categoryResolution.category,
                generic: generic.text.trim(),
                manufacturer: manufacturer.text.trim(),
                type: type.text.trim(),
                strength: strength.text.trim(),
                overview: overview.text.trim(),
                image: imageUrl,
                images: images,
                videoUrl: videoUrl.text.trim(),
                youtubeVideoId: preparedYoutubeVideoId,
                videoThumbnailUrl: preparedVideoThumbnailUrl,
                videoDuration: videoDuration,
                isActive: isActive,
                isMarketplace: false,
                vendorId: 'super_admin',
                vendorName: 'ChalakChar Mart',
                approvalStatus: 'approved',
                variants: variants,
                includeCreatedAt: id == null,
              );

              payload.addAll({
                'banglaTitle': banglaTitle,
                'banglaDescription': banglaDescription,
                'seoTags': seoTags,
                'facebookCaption': facebookCaption,
                'whatsappCaption': whatsappCaption,
                'metaTitle': metaTitle,
                'metaDescription': metaDescription,
                'searchKeywords': searchKeywords,
                'suggestedCategory': suggestedCategory,
                'suggestedSubCategory': suggestedSubCategory,
                if (categoryResolution.categoryId != null)
                  'categoryId': categoryResolution.categoryId,
                if (subcategoryField != null) 'subcategoryId': subcategoryField,
                if (variantLabel.text.trim().isNotEmpty)
                  'variantAttributeName': variantLabel.text.trim()
                else if (id != null)
                  'variantAttributeName': FieldValue.delete(),
                'productType': productType,
                'youtubeUrl': videoUrl.text.trim(),
                'youtubeVideoId': preparedYoutubeVideoId,
                'videoThumbnailUrl': preparedVideoThumbnailUrl,
                'videoDuration': videoDuration,
                'hasVideo': videoUrl.text.trim().isNotEmpty || preparedYoutubeVideoId.isNotEmpty,
                'aiOptimized': banglaTitle.isNotEmpty ||
                    banglaDescription.isNotEmpty ||
                    seoTags.isNotEmpty ||
                    facebookCaption.isNotEmpty ||
                    whatsappCaption.isNotEmpty ||
                    metaTitle.isNotEmpty ||
                    metaDescription.isNotEmpty ||
                    searchKeywords.isNotEmpty ||
                    suggestedCategory.isNotEmpty ||
                    suggestedSubCategory.isNotEmpty ||
                    productType.isNotEmpty,
                'aiOptimizedAt': banglaTitle.isNotEmpty ||
                    banglaDescription.isNotEmpty ||
                    seoTags.isNotEmpty ||
                    facebookCaption.isNotEmpty ||
                    whatsappCaption.isNotEmpty ||
                    metaTitle.isNotEmpty ||
                    metaDescription.isNotEmpty ||
                    searchKeywords.isNotEmpty ||
                    suggestedCategory.isNotEmpty ||
                    suggestedSubCategory.isNotEmpty ||
                    productType.isNotEmpty
                    ? FieldValue.serverTimestamp()
                    : null,
                'autoMarketingDisabled': !marketingEnabled,
                'marketingQueue': marketingQueue,
                'marketingAudience': marketingAudience,
                'marketingPublishMode': marketingPublishMode,
                'marketingChannels': {
                  'fcm': marketingPush,
                  'push': marketingPush,
                  'inApp': marketingInApp,
                  'facebook': marketingFacebook,
                  'instagram': marketingInstagram,
                  'whatsapp': marketingWhatsapp,
                  'messenger': marketingMessenger,
                  'tiktok': marketingTiktok,
                },
                'marketingCaption': marketingCaptionController.text.trim(),
              });

              final savedProductId = await ProductService.saveProduct(
                productId: id,
                payload: payload,
              );

              if (marketingEnabled && marketingQueue) {
                try {
                  final marketingSettings =
                  await MarketingSettingsService.load(forceRefresh: true);

                  final caption = marketingCaptionController.text.trim().isNotEmpty
                      ? marketingCaptionController.text.trim()
                      : (facebookCaption.trim().isNotEmpty
                      ? facebookCaption.trim()
                      : whatsappCaption.trim());

                  await MarketingQueueService.enqueueProduct(
                    productId: savedProductId,
                    productData: payload,
                    settings: marketingSettings,
                    channels: {
                      'fcm': marketingPush,
                      'push': marketingPush,
                      'inApp': marketingInApp,
                      'facebook': marketingFacebook,
                      'instagram': marketingInstagram,
                      'whatsapp': marketingWhatsapp,
                      'messenger': marketingMessenger,
                      'tiktok': marketingTiktok,
                    },
                    audience: marketingAudience,
                    publishMode: marketingPublishMode,
                    scheduledAt: marketingPublishMode == 'schedule'
                        ? marketingScheduledAt
                        : null,
                    reason: id == null ? 'new_product' : 'product_update',
                    source: 'admin_product_manager',
                    caption: caption,
                  );
                } catch (e) {
                  debugPrint('MARKETING QUEUE CREATE ERROR: $e');
                  _snack('Product saved, but marketing queue failed: $e', isError: true);
                }
              }

              _snack(marketingEnabled && marketingQueue
                  ? (id == null ? 'Product added + marketing queued' : 'Product updated + marketing queued')
                  : (id == null ? 'Product added' : 'Product updated'));

              if (dialogNavigator.mounted) dialogNavigator.pop();
            } catch (e) {
              _snack('Save failed: $e', isError: true);
            } finally {
              setDialogState(() => saving = false);
            }
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final screen = MediaQuery.of(context).size;
              final isMobile = screen.width < 700;
              final dialogWidth = isMobile ? screen.width * 0.94 : 760.0;
              final dialogMaxHeight = screen.height * 0.92;

              InputDecoration deco(String label, {String? hint}) {
                return InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF0E8094), width: 1.4),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                );
              }

              Widget formField(
                  TextEditingController controller,
                  String label, {
                    int maxLines = 1,
                    TextInputType? keyboardType,
                  }) {
                return TextField(
                  controller: controller,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  decoration: deco(label),
                );
              }

              Widget fieldPair(Widget left, Widget right) {
                if (isMobile) {
                  return Column(
                    children: [
                      left,
                      const SizedBox(height: 12),
                      right,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 10),
                    Expanded(child: right),
                  ],
                );
              }

              Widget actionButton({
                required VoidCallback? onPressed,
                required IconData icon,
                required String label,
                bool primary = false,
                bool loading = false,
              }) {
                final child = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    loading
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(icon, size: 18),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );

                final style = primary
                    ? ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  backgroundColor: const Color(0xFF2FB3CF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                )
                    : OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: const Color(0xFF0E8094),
                  side: const BorderSide(color: Color(0xFF0E8094)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                );

                return primary
                    ? ElevatedButton(onPressed: onPressed, style: style, child: child)
                    : OutlinedButton(onPressed: onPressed, style: style, child: child);
              }

              Future<void> openProductVideoStudio() async {
                final id = _youtubeVideoId(videoUrl.text);
                if (id == null || id.isEmpty) {
                  _snack(
                    'Valid YouTube URL required. Supports watch, youtu.be, shorts, live and embed links.',
                    isError: true,
                  );
                  return;
                }

                setDialogState(() {
                  youtubeVideoId = id;
                  videoThumbnailUrl = _youtubeThumbnail(id);
                });

                _snack('Product video ready');
              }

              Widget socialMarketingBox() {
                Widget channelTile({
                  required String title,
                  required String subtitle,
                  required IconData icon,
                  required bool value,
                  required ValueChanged<bool?> onChanged,
                }) {
                  return SizedBox(
                    width: isMobile ? double.infinity : 330,
                    child: CheckboxListTile(
                      value: value,
                      onChanged: marketingEnabled ? onChanged : null,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(icon, color: const Color(0xFF0E8094)),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  );
                }

                Future<void> pickSchedule() async {
                  final pickedDate = await showDatePicker(
                    context: pageContext,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                    initialDate: marketingScheduledAt ?? DateTime.now().add(const Duration(hours: 1)),
                  );
                  if (pickedDate == null) return;

                  if (!pageContext.mounted) return;
                  final pickedTime = await showTimePicker(
                    context: pageContext,
                    initialTime: TimeOfDay.fromDateTime(
                      marketingScheduledAt ?? DateTime.now().add(const Duration(hours: 1)),
                    ),
                  );
                  if (pickedTime == null) return;

                  setDialogState(() {
                    marketingScheduledAt = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedTime.hour,
                      pickedTime.minute,
                    );
                    marketingPublishMode = 'schedule';
                  });
                }

                final hasSocial = marketingFacebook ||
                    marketingInstagram ||
                    marketingWhatsapp ||
                    marketingMessenger ||
                    marketingTiktok;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: marketingEnabled
                        ? const Color(0xFF0E8094).withValues(alpha: 0.055)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: marketingEnabled
                          ? const Color(0xFF0E8094).withValues(alpha: 0.25)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFEAF8FB),
                            child: Icon(Icons.campaign_rounded, color: Color(0xFF0E8094)),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Social Marketing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                SizedBox(height: 2),
                                Text('Queue push, in-app and social campaigns when product is saved.'),
                              ],
                            ),
                          ),
                          Switch(
                            value: marketingEnabled,
                            onChanged: (v) => setDialogState(() => marketingEnabled = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          channelTile(
                            title: 'Push Notification',
                            subtitle: 'Send to app/web FCM users',
                            icon: Icons.notifications_active_rounded,
                            value: marketingPush,
                            onChanged: (v) => setDialogState(() => marketingPush = v ?? false),
                          ),
                          channelTile(
                            title: 'In-App Notification',
                            subtitle: 'Create notification documents',
                            icon: Icons.mark_unread_chat_alt_rounded,
                            value: marketingInApp,
                            onChanged: (v) => setDialogState(() => marketingInApp = v ?? false),
                          ),
                          channelTile(
                            title: 'Facebook Queue',
                            subtitle: 'Ready for Page API posting',
                            icon: Icons.facebook_rounded,
                            value: marketingFacebook,
                            onChanged: (v) => setDialogState(() => marketingFacebook = v ?? false),
                          ),
                          channelTile(
                            title: 'Instagram Queue',
                            subtitle: 'Ready for Business API posting',
                            icon: Icons.camera_alt_rounded,
                            value: marketingInstagram,
                            onChanged: (v) => setDialogState(() => marketingInstagram = v ?? false),
                          ),
                          channelTile(
                            title: 'WhatsApp Broadcast',
                            subtitle: 'Ready for WhatsApp Business API',
                            icon: Icons.chat_rounded,
                            value: marketingWhatsapp,
                            onChanged: (v) => setDialogState(() => marketingWhatsapp = v ?? false),
                          ),
                          channelTile(
                            title: 'Messenger Campaign',
                            subtitle: 'Queue Messenger customer campaign',
                            icon: Icons.messenger_outline_rounded,
                            value: marketingMessenger,
                            onChanged: (v) => setDialogState(() => marketingMessenger = v ?? false),
                          ),
                          channelTile(
                            title: 'TikTok Queue',
                            subtitle: 'Caption/video campaign queue',
                            icon: Icons.music_note_rounded,
                            value: marketingTiktok,
                            onChanged: (v) => setDialogState(() => marketingTiktok = v ?? false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      fieldPair(
                        DropdownButtonFormField<String>(
                          initialValue: marketingAudience,
                          decoration: deco('Audience'),
                          items: const [
                            DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                            DropdownMenuItem(value: 'wishlist_users', child: Text('Wishlist Users')),
                            DropdownMenuItem(value: 'category_interested', child: Text('Category Interested')),
                            DropdownMenuItem(value: 'previous_buyers', child: Text('Previous Buyers')),
                            DropdownMenuItem(value: 'followers', child: Text('Followers')),
                          ],
                          onChanged: marketingEnabled
                              ? (v) => setDialogState(() => marketingAudience = v ?? 'everyone')
                              : null,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: marketingPublishMode,
                          decoration: deco('Publish Time'),
                          items: const [
                            DropdownMenuItem(value: 'now', child: Text('Immediately')),
                            DropdownMenuItem(value: 'schedule', child: Text('Schedule')),
                          ],
                          onChanged: marketingEnabled
                              ? (v) => setDialogState(() => marketingPublishMode = v ?? 'now')
                              : null,
                        ),
                      ),
                      if (marketingPublishMode == 'schedule') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: marketingEnabled ? pickSchedule : null,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(
                            marketingScheduledAt == null
                                ? 'Select schedule date & time'
                                : 'Scheduled: ${marketingScheduledAt!.day.toString().padLeft(2, '0')}-${marketingScheduledAt!.month.toString().padLeft(2, '0')}-${marketingScheduledAt!.year} ${marketingScheduledAt!.hour.toString().padLeft(2, '0')}:${marketingScheduledAt!.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: marketingCaptionController,
                        enabled: marketingEnabled,
                        maxLines: 3,
                        decoration: deco(
                          'Marketing Caption',
                          hint: 'Leave blank to use AI Facebook/WhatsApp caption',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.queue_rounded, size: 16),
                            label: Text(marketingEnabled ? 'Queue will be created' : 'Marketing disabled'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.public_rounded, size: 16),
                            label: Text(hasSocial ? 'Social API pending' : 'Push/In-App only'),
                          ),
                          const Chip(
                            avatar: Icon(Icons.analytics_rounded, size: 16),
                            label: Text('Visible in Marketing Center'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              Widget productVideoStudioBox() {
                final id = _youtubeVideoId(videoUrl.text) ?? youtubeVideoId;
                final thumb = id.isNotEmpty ? _youtubeThumbnail(id) : videoThumbnailUrl;
                final hasVideo = id.isNotEmpty;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasVideo
                        ? const Color(0xFF32A8C7).withValues(alpha: 0.07)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasVideo
                          ? const Color(0xFF32A8C7).withValues(alpha: 0.25)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final compact = c.maxWidth < 520;

                      final preview = ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: compact ? double.infinity : 160,
                          height: 92,
                          color: Colors.black12,
                          child: hasVideo
                              ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                thumb,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.video_library_rounded,
                                ),
                              ),
                              Container(color: Colors.black.withValues(alpha: 0.25)),
                              const Center(
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                            ],
                          )
                              : const Center(
                            child: Icon(
                              Icons.video_library_rounded,
                              size: 42,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );

                      final info = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Product Video Studio',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasVideo
                                ? 'YouTube video ID: $id'
                                : 'Paste a YouTube link, then prepare video preview.',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                          if (videoDuration.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Duration: $videoDuration',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: openProductVideoStudio,
                                icon: const Icon(Icons.smart_display_rounded, size: 18),
                                label: const Text('Prepare Video'),
                              ),
                              if (hasVideo)
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      videoUrl.clear();
                                      youtubeVideoId = '';
                                      videoThumbnailUrl = '';
                                      videoDuration = '';
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  label: const Text('Remove'),
                                ),
                            ],
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            preview,
                            const SizedBox(height: 10),
                            info,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          preview,
                          const SizedBox(width: 12),
                          Expanded(child: info),
                        ],
                      );
                    },
                  ),
                );
              }

              Widget imageToolbar() {
                final buttons = [
                  actionButton(
                    onPressed: uploading ? null : () => pickImage(main: true),
                    icon: Icons.image_rounded,
                    label: isMobile ? 'Main' : 'Main Image',
                    primary: true,
                  ),
                  actionButton(
                    onPressed: uploading ? null : () => pickImage(main: false),
                    icon: Icons.collections_rounded,
                    label: isMobile ? 'Gallery' : 'Add Gallery',
                  ),
                  actionButton(
                    onPressed: aiImageLoading || saving || uploading ? null : createProductFromImage,
                    icon: Icons.camera_alt_rounded,
                    label: aiImageLoading ? 'Analyzing...' : (isMobile ? 'AI Image' : 'AI From Image'),
                    loading: aiImageLoading,
                  ),
                  actionButton(
                    onPressed: aiStudioLoading || saving || uploading ? null : openAIImageStudio,
                    icon: Icons.auto_fix_high_rounded,
                    label: aiStudioLoading ? 'Creating...' : (isMobile ? 'Studio' : 'AI Image Studio'),
                    loading: aiStudioLoading,
                  ),
                ];

                if (isMobile) {
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 3.2,
                    children: buttons,
                  );
                }

                return Wrap(spacing: 8, runSpacing: 8, children: buttons);
              }

              Widget mainImageBox() {
                final size = isMobile ? 96.0 : 110.0;
                return GestureDetector(
                  onTap: uploading ? null : () => pickImage(main: true),
                  child: Container(
                    height: size,
                    width: size,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: uploading
                        ? const Center(child: CircularProgressIndicator())
                        : imageUrl.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    )
                        : const Icon(Icons.add_a_photo_rounded, size: 34),
                  ),
                );
              }

              Widget activeProductSwitch() {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Active Product',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (!canChangeProductStatus)
                              const Text(
                                'products.status permission required',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isActive,
                        onChanged: canChangeProductStatus ? (v) => setDialogState(() => isActive = v) : null,
                      ),
                    ],
                  ),
                );
              }

              Widget galleryStrip() {
                if (images.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final url = images[i];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  url,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 72,
                                    height: 72,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () => setDialogState(() => images.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              }

              Widget variantCard(int index) {
                final v = variantControllers[index];

                if (isMobile) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: [
                        formField(v['name']!, 'Unit'),
                        const SizedBox(height: 10),
                        fieldPair(
                          formField(v['price']!, 'Price', keyboardType: TextInputType.number),
                          formField(v['mrp']!, 'MRP', keyboardType: TextInputType.number),
                        ),
                        const SizedBox(height: 10),
                        formField(v['stock']!, 'Stock', keyboardType: TextInputType.number),
                        if (variantControllers.length > 1) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setDialogState(() {
                                variantControllers.removeAt(index);
                                variantOriginals.removeAt(index);
                              }),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              label: const Text('Remove', style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: formField(v['name']!, 'Unit')),
                      const SizedBox(width: 8),
                      Expanded(child: formField(v['price']!, 'Price', keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: formField(v['mrp']!, 'MRP', keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: formField(v['stock']!, 'Stock', keyboardType: TextInputType.number)),
                      IconButton(
                        onPressed: variantControllers.length == 1
                            ? null
                            : () => setDialogState(() {
                                variantControllers.removeAt(index);
                                variantOriginals.removeAt(index);
                              }),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                );
              }

              /// Active categories by doc id. The product's current category is
              /// kept (labelled "(hidden)") when inactive, so it never blanks.
              Widget categoryDropdown() {
                return StreamBuilder<QuerySnapshot>(
                  stream: allCategoriesStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      debugPrint('PRODUCT DIALOG CATEGORIES ERROR: ${snap.error}');
                      return _dialogLoadError('Category', 'Couldn\'t load categories: ${snap.error}');
                    }
                    final docs = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
                    final byId = {for (final d in docs) d.id: d.data() as Map<String, dynamic>};

                    if (snap.hasData) {
                      final before = categoryId;
                      final selection = _resolveCategorySelection(byId, categoryId, category);
                      categoryId = selection.id;
                      if (selection.name != null) category = selection.name;
                      // The subcategory dropdown reads categoryId; rebuild it
                      // once when the selection was resolved here.
                      if (before != categoryId) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (pageContext.mounted) setDialogState(() {});
                        });
                      }
                    }

                    final active = byId.entries
                        .where((e) => e.value['isActive'] == true && _text(e.value['mergedInto']).isEmpty)
                        .toList()
                      ..sort((a, b) => _text(a.value['name']).toLowerCase().compareTo(_text(b.value['name']).toLowerCase()));
                    final nameUses = <String, int>{};
                    for (final e in active) {
                      final k = normalizeCategoryKey(_text(e.value['name']));
                      nameUses[k] = (nameUses[k] ?? 0) + 1;
                    }
                    String label(MapEntry<String, Map<String, dynamic>> e) {
                      final name = _text(e.value['name'], 'Unnamed');
                      final clash = (nameUses[normalizeCategoryKey(name)] ?? 0) > 1;
                      return clash ? '$name · ${e.key.substring(0, e.key.length < 4 ? e.key.length : 4)}' : name;
                    }

                    final items = <DropdownMenuItem<String>>[
                      for (final e in active) DropdownMenuItem(value: e.key, child: Text(label(e))),
                    ];
                    if (categoryId.isNotEmpty && !active.any((e) => e.key == categoryId)) {
                      items.insert(
                        0,
                        DropdownMenuItem(
                          value: categoryId,
                          child: Text('${category ?? 'Unnamed'} (hidden)'),
                        ),
                      );
                    }
                    // A name with no category doc yet (e.g. "Other", or an
                    // AI suggestion the resolver couldn't reach): resolved on save.
                    final nameOnly = categoryId.isEmpty && (category ?? '').isNotEmpty;
                    if (nameOnly) {
                      items.insert(
                        0,
                        DropdownMenuItem(
                          value: _kNameOnlyCategory,
                          child: Text(snap.hasData ? '$category (no category doc)' : category!),
                        ),
                      );
                    }

                    return DropdownButtonFormField<String>(
                      key: ValueKey('cat-$categoryId-$nameOnly'),
                      initialValue: nameOnly ? _kNameOnlyCategory : (categoryId.isEmpty ? null : categoryId),
                      isExpanded: true,
                      decoration: deco('Category'),
                      items: items,
                      onChanged: (v) {
                        if (v == null || v == _kNameOnlyCategory) return;
                        setDialogState(() {
                          if (v != categoryId) subcategoryId = '';
                          categoryId = v;
                          category = _text(byId[v]?['name'], category ?? '');
                        });
                      },
                    );
                  },
                );
              }

              /// Subcategories of the currently selected category only.
              Widget subcategoryDropdown() {
                final aiHint = suggestedSubCategory.isEmpty
                    ? null
                    : 'AI suggestion: $suggestedSubCategory (hint only — pick from the list)';

                Widget disabled(String label) => DropdownButtonFormField<String>(
                      key: ValueKey('sub-disabled-$label'),
                      initialValue: null,
                      isExpanded: true,
                      decoration: deco('Subcategory').copyWith(helperText: aiHint ?? label),
                      hint: Text(label),
                      items: const [],
                      onChanged: null,
                    );

                if (category == null || category!.isEmpty) {
                  return disabled('Select a category first');
                }

                // Loaded by the selected category's doc id only.
                final parentId = categoryId;
                if (parentId.isEmpty) {
                  return disabled('No category doc yet — save the product first');
                }

                // Live query, re-created only when the parent changes, so a
                // subcategory added in the Category Manager shows up at once.
                if (subcategoryStreamParentId != parentId) {
                  subcategoryStreamParentId = parentId;
                  subcategoryStream = FirebaseFirestore.instance
                      .collection('subcategories')
                      .where('categoryId', isEqualTo: parentId)
                      .snapshots();
                }

                return StreamBuilder<QuerySnapshot>(
                      stream: subcategoryStream,
                      builder: (context, subSnap) {
                        if (subSnap.hasError) {
                          debugPrint('PRODUCT DIALOG SUBCATEGORIES ERROR ($parentId): ${subSnap.error}');
                          return _dialogLoadError('Subcategory', 'Couldn\'t load subcategories: ${subSnap.error}');
                        }
                        if (!subSnap.hasData) return disabled('Loading…');

                        final subs = subSnap.data!.docs.toList()
                          ..sort((a, b) {
                            final da = a.data() as Map<String, dynamic>;
                            final dbb = b.data() as Map<String, dynamic>;
                            final p = _toInt(da['priority']).compareTo(_toInt(dbb['priority']));
                            if (p != 0) return p;
                            return _text(da['name']).toLowerCase().compareTo(_text(dbb['name']).toLowerCase());
                          });

                        final items = <DropdownMenuItem<String>>[
                          const DropdownMenuItem(value: '', child: Text('— None —')),
                          for (final s in subs)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                '${_text((s.data() as Map<String, dynamic>)['name'], 'Unnamed')}'
                                '${(s.data() as Map<String, dynamic>)['isActive'] == false ? '  (inactive)' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ];

                        // A saved id that no longer belongs to this
                        // category (deleted, or moved) must still be a
                        // valid item, or the dropdown asserts.
                        if (subcategoryId.isNotEmpty && !subs.any((s) => s.id == subcategoryId)) {
                          items.add(DropdownMenuItem(
                            value: subcategoryId,
                            child: const Text('⚠ Not in this category — pick again',
                                style: TextStyle(color: Colors.red)),
                          ));
                        }

                        return DropdownButtonFormField<String>(
                          key: ValueKey('sub-$parentId'),
                          initialValue: subcategoryId,
                          isExpanded: true,
                          decoration: deco('Subcategory').copyWith(
                            helperText: aiHint ??
                                (subs.isEmpty ? 'This category has no subcategories yet' : null),
                            helperMaxLines: 2,
                          ),
                          items: items,
                          onChanged: (v) => setDialogState(() => subcategoryId = v ?? ''),
                        );
                      },
                    );
              }

              Widget aiResultBox() {
                if (!(banglaTitle.isNotEmpty ||
                    banglaDescription.isNotEmpty ||
                    seoTags.isNotEmpty ||
                    facebookCaption.isNotEmpty ||
                    whatsappCaption.isNotEmpty ||
                    metaTitle.isNotEmpty ||
                    metaDescription.isNotEmpty ||
                    searchKeywords.isNotEmpty ||
                    suggestedCategory.isNotEmpty ||
                    suggestedSubCategory.isNotEmpty ||
                    productType.isNotEmpty)) {
                  return const SizedBox.shrink();
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (banglaTitle.isNotEmpty) ...[
                        const Text('Bangla Title', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(banglaTitle),
                      ],
                      if (banglaDescription.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Bangla Description', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(banglaDescription),
                      ],
                      if (seoTags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('SEO Tags', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: seoTags.map((tag) => Chip(label: Text(tag), visualDensity: VisualDensity.compact)).toList(),
                        ),
                      ],
                      if (metaTitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Meta Title', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(metaTitle),
                      ],
                      if (metaDescription.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Meta Description', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(metaDescription),
                      ],
                      if (facebookCaption.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Facebook Caption', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(facebookCaption),
                      ],
                      if (whatsappCaption.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('WhatsApp Caption', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(whatsappCaption),
                      ],
                      if (searchKeywords.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Search Keywords', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: searchKeywords.map((tag) => Chip(label: Text(tag), visualDensity: VisualDensity.compact)).toList(),
                        ),
                      ],
                      if (suggestedCategory.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Suggested Category', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(suggestedCategory),
                      ],
                      if (suggestedSubCategory.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Suggested Sub Category', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(suggestedSubCategory),
                      ],
                      if (productType.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Product Type', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(productType),
                      ],
                    ],
                  ),
                );
              }

              Widget aliExpressSourceBox() {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, color: Colors.deepOrange, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'AliExpress Source',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.deepOrange),
                          ),
                          const SizedBox(width: 8),
                          const Chip(
                            label: Text('Read-only', style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Source Product ID: ${sourceProductId.isEmpty ? 'N/A' : sourceProductId}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (aliExpressLink.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(aliExpressLink),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(
                            aliExpressLink,
                            style: const TextStyle(
                              color: Colors.deepOrange,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              final formContent = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isMobile) ...[
                    Center(child: mainImageBox()),
                    const SizedBox(height: 12),
                    imageToolbar(),
                    const SizedBox(height: 12),
                    activeProductSwitch(),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        mainImageBox(),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              imageToolbar(),
                              const SizedBox(height: 12),
                              activeProductSwitch(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  galleryStrip(),
                  const SizedBox(height: 16),
                  if (isAliExpressSourced) ...[
                    aliExpressSourceBox(),
                    const SizedBox(height: 16),
                  ],
                  formField(name, 'Product Name'),
                  const SizedBox(height: 10),
                  Align(
                    alignment: isMobile ? Alignment.center : Alignment.centerRight,
                    child: SizedBox(
                      width: isMobile ? double.infinity : null,
                      child: ElevatedButton.icon(
                        onPressed: aiLoading || saving ? null : optimizeWithAI,
                        icon: aiLoading
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome),
                        label: Text(aiLoading ? 'Optimizing...' : 'AI Optimize'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: const Color(0xFF2FB3CF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  aiResultBox(),
                  if (banglaTitle.isNotEmpty || banglaDescription.isNotEmpty || seoTags.isNotEmpty) const SizedBox(height: 12),
                  fieldPair(
                    formField(generic, 'Generic'),
                    formField(manufacturer, 'Manufacturer'),
                  ),
                  const SizedBox(height: 12),
                  fieldPair(
                    formField(type, 'Type'),
                    formField(strength, 'Strength'),
                  ),
                  const SizedBox(height: 12),
                  categoryDropdown(),
                  const SizedBox(height: 12),
                  subcategoryDropdown(),
                  const SizedBox(height: 12),
                  formField(overview, 'Overview', maxLines: isMobile ? 4 : 3),
                  const SizedBox(height: 12),
                  formField(videoUrl, 'YouTube / Product Video URL'),
                  const SizedBox(height: 8),
                  productVideoStudioBox(),
                  const SizedBox(height: 12),
                  socialMarketingBox(),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('product-variant-label'),
                    controller: variantLabel,
                    decoration: deco('Variant label', hint: 'e.g. Model, Type, Capacity').copyWith(
                      helperText: 'Shown before the selected variant, e.g. "Model: 12 Pro". Empty = automatic.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Variants',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: addVariant,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(isMobile ? 'Add' : 'Add Variant'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(variantControllers.length, variantCard),
                ],
              );

              return Dialog(
                insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 24, vertical: isMobile ? 10 : 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 24 : 20)),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: dialogWidth,
                    maxHeight: dialogMaxHeight,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.fromLTRB(isMobile ? 18 : 24, 18, isMobile ? 10 : 20, 12),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                id == null ? 'Add Product' : 'Edit Product',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: isMobile ? 20 : 22, fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              onPressed: saving ? null : () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: const Color(0xFFF8FAFC),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(isMobile ? 18 : 24, 4, isMobile ? 18 : 24, 18),
                            child: formContent,
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 12, isMobile ? 14 : 24, 12),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: saving ? null : () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: isMobile ? 2 : 1,
                                child: ElevatedButton.icon(
                                  onPressed: saving ? null : saveProduct,
                                  icon: saving
                                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.save_rounded, size: 18),
                                  label: Text(id == null ? 'Add Product' : 'Update Product'),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 46),
                                    backgroundColor: const Color(0xFF2FB3CF),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteProduct(String id) async {
    if (_denyIf(!canDeleteProducts, 'You do not have products.delete permission.')) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product?'),
        content: const Text('This product will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('products').doc(id).delete();
      _snack('Product deleted');
    }
  }

  Future<void> _toggleStatus(String id, bool active) async {
    if (_denyIf(!canChangeProductStatus, 'You do not have products.status permission.')) return;

    await db.collection('products').doc(id).set({
      'isActive': active,
      'isVisible': active,
      'isPublished': active,
      'showOnHome': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _normName(String value) => value.trim().toLowerCase();

  /// Lookup tables for the Category / Subcategory filters, rebuilt per build
  /// from the in-memory category, subcategory and product docs.
  _ProductCategoryIndex _buildCategoryIndex() {
    final options = <_FilterOption>[];
    final nameById = <String, String>{};
    final idByName = <String, String>{};
    // Docs merged into another (scripts/categoryMerge.js) are not listed;
    // anything still pointing at one counts under the doc it was merged into.
    final mergedInto = <String, String>{};
    // Active first, then by id, so a legacy (name-only) product falls into the
    // active doc of a name, and the choice is stable across reloads.
    final categoryDocs = _categoryDocs.where((doc) {
      final target = _text((doc.data() as Map<String, dynamic>)['mergedInto']);
      if (target.isNotEmpty) mergedInto[doc.id] = target;
      return target.isEmpty;
    }).toList()
      ..sort((a, b) {
        final aActive = (a.data() as Map<String, dynamic>)['isActive'] == true;
        final bActive = (b.data() as Map<String, dynamic>)['isActive'] == true;
        if (aActive != bActive) return aActive ? -1 : 1;
        return a.id.compareTo(b.id);
      });
    final nameUses = <String, int>{};
    for (final doc in categoryDocs) {
      final key = _normName(_text((doc.data() as Map<String, dynamic>)['name'], 'Unnamed'));
      nameUses[key] = (nameUses[key] ?? 0) + 1;
    }
    for (final doc in categoryDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = _text(data['name'], 'Unnamed');
      // A real category literally named "Uncategorized" is merged into the
      // synthetic "Uncategorized" option instead of being listed twice.
      if (_normName(name) == 'uncategorized') continue;
      nameById[doc.id] = name;
      idByName.putIfAbsent(_normName(name), () => doc.id);
      final isDuplicate = (nameUses[_normName(name)] ?? 0) > 1;
      options.add(_FilterOption(
        id: doc.id,
        // Only a real name clash left after merging gets a short id suffix.
        name: isDuplicate ? '$name · ${doc.id.substring(0, doc.id.length < 4 ? doc.id.length : 4)}' : name,
        hidden: data['isActive'] != true,
      ));
    }
    // Active categories first, hidden ones after (shown under a "Hidden" header).
    options.sort((a, b) {
      if (a.hidden != b.hidden) return a.hidden ? 1 : -1;
      return _normName(a.name).compareTo(_normName(b.name));
    });

    // Until categories load, keep the chosen id so a refresh doesn't reset it;
    // afterwards a deleted category falls back to "All".
    final effectiveCategory = categoryFilter == _kFilterAll ||
            categoryFilter == _kUncategorized ||
            !_categoriesLoaded ||
            nameById.containsKey(categoryFilter)
        ? categoryFilter
        : _kFilterAll;

    final subOptions = <_FilterOption>[];
    final subIdByName = <String, String>{};
    if (effectiveCategory != _kFilterAll &&
        effectiveCategory != _kUncategorized &&
        _subcategoriesFor == effectiveCategory) {
      for (final doc in _subcategoryDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final name = _text(data['name'], 'Unnamed');
        subIdByName.putIfAbsent(_normName(name), () => doc.id);
        subOptions.add(_FilterOption(id: doc.id, name: name, hidden: data['isActive'] == false));
      }
      subOptions.sort((a, b) => _normName(a.name).compareTo(_normName(b.name)));
    }
    final effectiveSubcategory =
        subOptions.any((o) => o.id == subcategoryFilter) ? subcategoryFilter : _kFilterAll;

    final index = _ProductCategoryIndex(
      options: options,
      nameById: nameById,
      idByName: idByName,
      mergedInto: mergedInto,
      subOptions: subOptions,
      subIdByName: subIdByName,
      effectiveCategory: effectiveCategory,
      effectiveSubcategory: effectiveSubcategory,
    );

    for (final doc in _productDocs ?? const <QueryDocumentSnapshot>[]) {
      final data = doc.data() as Map<String, dynamic>;
      final bucket = _categoryBucket(data, index);
      index.categoryCounts[bucket] = (index.categoryCounts[bucket] ?? 0) + 1;
      if (bucket == effectiveCategory && subOptions.isNotEmpty) {
        final sub = _subcategoryBucket(data, index);
        if (sub.isNotEmpty) index.subCounts[sub] = (index.subCounts[sub] ?? 0) + 1;
      }
    }
    return index;
  }

  /// The category a product belongs to for filtering: its categoryId when that
  /// category exists; for old products with no id, the category whose name
  /// matches; otherwise [_kUncategorized] (no id, "Uncategorized", unknown
  /// name, or an id pointing at a deleted category).
  String _categoryBucket(Map<String, dynamic> data, _ProductCategoryIndex index) {
    final rawId = _text(data['categoryId']);
    if (rawId.isNotEmpty) {
      final id = index.mergedInto[rawId] ?? rawId;
      return index.nameById.containsKey(id) ? id : _kUncategorized;
    }
    return index.idByName[_normName(_text(data['category']))] ?? _kUncategorized;
  }

  /// Subcategory id within the selected category, by subcategoryId first and
  /// the stored subcategory name only when the product has no id. '' = none.
  String _subcategoryBucket(Map<String, dynamic> data, _ProductCategoryIndex index) {
    final id = _text(data['subcategoryId']);
    if (id.isNotEmpty) return id;
    final name = _normName(_text(data['subCategoryName'], _text(data['subcategoryName'])));
    if (name.isEmpty) return '';
    return index.subIdByName[name] ?? '';
  }

  List<QueryDocumentSnapshot> _filterProducts(
    List<QueryDocumentSnapshot> docs,
    _ProductCategoryIndex index,
  ) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = _text(data['name']).toLowerCase();
      final generic = _text(data['generic']).toLowerCase();
      final manufacturer = _text(data['manufacturer']).toLowerCase();
      final approvalStatus = _text(data['approvalStatus'], 'approved');
      final isVendorProduct = data['isMarketplace'] == true ||
          _text(data['vendorId'], 'super_admin') != 'super_admin';
      final active = data['isActive'] == true;
      final displayActive = isVendorProduct && approvalStatus != 'approved'
          ? false
          : active;
      final stock = _toInt(data['stock']);

      final search = searchText.toLowerCase().trim();

      if (search.isNotEmpty &&
          !name.contains(search) &&
          !generic.contains(search) &&
          !manufacturer.contains(search)) {
        return false;
      }

      if (index.effectiveCategory != _kFilterAll) {
        if (_categoryBucket(data, index) != index.effectiveCategory) return false;
        if (index.effectiveSubcategory != _kFilterAll &&
            _subcategoryBucket(data, index) != index.effectiveSubcategory) {
          return false;
        }
      }

      if (statusFilter == 'active' && !displayActive) return false;
      if (statusFilter == 'inactive' && displayActive) return false;

      if (stockFilter == 'low' && stock > 5) return false;
      if (stockFilter == 'out' && stock > 0) return false;
      if (stockFilter == 'available' && stock <= 0) return false;

      return true;
    }).toList();
  }

  /// "Name (count) (hidden)": the name ellipsizes, count and tag never do.
  /// Product dialog: the category doc to select for a product with
  /// [categoryId] / [categoryName]. Follows `mergedInto`; with no usable id,
  /// matches the name by normalized key (active docs first). `id` is '' and
  /// `name` null when nothing matches, leaving the selection as it was.
  ({String id, String? name}) _resolveCategorySelection(
    Map<String, Map<String, dynamic>> byId,
    String categoryId,
    String? categoryName,
  ) {
    final id = resolveCategoryId(byId, categoryId: categoryId, categoryName: categoryName);
    if (id == null) return (id: '', name: null);
    return (id: id, name: _text(byId[id]?['name'], categoryName ?? ''));
  }

  /// Disabled dialog field that shows a load failure instead of an endless
  /// "Loading…" or an empty list that looks like real data.
  Widget _dialogLoadError(String label, String message) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: message,
        errorMaxLines: 4,
      ),
      child: const Text('—'),
    );
  }

  Widget _filterOptionLabel(String name, int? count, {bool hidden = false, bool muted = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted ? TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic) : null,
          ),
        ),
        if (count != null) Text(' ($count)', style: TextStyle(color: Colors.grey.shade700)),
        if (hidden)
          Text(' (hidden)', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }

  Widget _buildFilterBar(_ProductCategoryIndex index) {
    final countsReady = _productDocs != null;
    int? countFor(Map<String, int> counts, String key) => countsReady ? (counts[key] ?? 0) : null;
    const fieldGap = SizedBox(width: 8);

    final showSubcategory = index.effectiveCategory != _kFilterAll &&
        index.effectiveCategory != _kUncategorized &&
        index.subOptions.isNotEmpty;
    final anyFilterActive = searchText.trim().isNotEmpty ||
        statusFilter != _kFilterAll ||
        stockFilter != _kFilterAll ||
        index.effectiveCategory != _kFilterAll;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        );

    final search = TextField(
      controller: _searchController,
      decoration: const InputDecoration(
        hintText: 'Search product, generic, manufacturer...',
        prefixIcon: Icon(Icons.search_rounded),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => setState(() => searchText = v),
    );

    final category = DropdownButtonFormField<String>(
      key: ValueKey('cat-$_filterResetEpoch-${index.effectiveCategory}'),
      initialValue: index.effectiveCategory,
      isExpanded: true,
      decoration: deco('Category'),
      items: [
        DropdownMenuItem(
          value: _kFilterAll,
          child: _filterOptionLabel('All', countsReady ? _productDocs!.length : null),
        ),
        for (final o in index.options.where((o) => !o.hidden))
          DropdownMenuItem(
            value: o.id,
            child: _filterOptionLabel(o.name, countFor(index.categoryCounts, o.id)),
          ),
        if (index.options.any((o) => o.hidden))
          DropdownMenuItem(
            value: _kHiddenHeader,
            enabled: false,
            child: Text('Hidden',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        for (final o in index.options.where((o) => o.hidden))
          DropdownMenuItem(
            value: o.id,
            child: _filterOptionLabel(o.name, countFor(index.categoryCounts, o.id), hidden: true),
          ),
        DropdownMenuItem(
          value: _kUncategorized,
          child: _filterOptionLabel(
            'Uncategorized',
            countFor(index.categoryCounts, _kUncategorized),
            muted: true,
          ),
        ),
      ],
      onChanged: (v) => _selectCategoryFilter(v ?? _kFilterAll),
    );

    final subcategory = DropdownButtonFormField<String>(
      key: ValueKey('sub-$_filterResetEpoch-${index.effectiveCategory}-${index.effectiveSubcategory}'),
      initialValue: index.effectiveSubcategory,
      isExpanded: true,
      decoration: deco('Subcategory'),
      items: [
        DropdownMenuItem(
          value: _kFilterAll,
          child: _filterOptionLabel('All', countFor(index.categoryCounts, index.effectiveCategory)),
        ),
        for (final o in index.subOptions)
          DropdownMenuItem(
            value: o.id,
            child: _filterOptionLabel(o.name, countFor(index.subCounts, o.id), hidden: o.hidden),
          ),
      ],
      onChanged: (v) => setState(() => subcategoryFilter = v ?? _kFilterAll),
    );

    final status = DropdownButtonFormField<String>(
      key: ValueKey('status-$_filterResetEpoch'),
      initialValue: statusFilter,
      isExpanded: true,
      decoration: deco('Status'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All')),
        DropdownMenuItem(value: 'active', child: Text('Active')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
      ],
      onChanged: (v) => setState(() => statusFilter = v ?? _kFilterAll),
    );

    final stock = DropdownButtonFormField<String>(
      key: ValueKey('stock-$_filterResetEpoch'),
      initialValue: stockFilter,
      isExpanded: true,
      decoration: deco('Stock'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All')),
        DropdownMenuItem(value: 'available', child: Text('Available')),
        DropdownMenuItem(value: 'low', child: Text('Low')),
        DropdownMenuItem(value: 'out', child: Text('Out')),
      ],
      onChanged: (v) => setState(() => stockFilter = v ?? _kFilterAll),
    );

    final clear = TextButton.icon(
      onPressed: anyFilterActive ? _clearFilters : null,
      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
      label: const Text('Clear filters'),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;

        // One row: Search | Category | Subcategory | Status | Stock | Clear.
        if (width >= 1100) {
          return Row(
            children: [
              Expanded(flex: 3, child: search),
              fieldGap,
              Expanded(flex: 3, child: category),
              fieldGap,
              if (showSubcategory) ...[
                Expanded(flex: 3, child: subcategory),
                fieldGap,
              ],
              Expanded(flex: 2, child: status),
              fieldGap,
              Expanded(flex: 2, child: stock),
              fieldGap,
              clear,
            ],
          );
        }

        // Search on its own row; dropdowns wrap underneath in fixed columns.
        final half = ((width - 8) / 2).floorToDouble();
        final categoryWidth = width < 560 ? width : half;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(width: categoryWidth, child: category),
                if (showSubcategory) SizedBox(width: categoryWidth, child: subcategory),
                SizedBox(width: half, child: status),
                SizedBox(width: half, child: stock),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: clear),
          ],
        );
      },
    );
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
      ),
    );
  }

  Widget _productImage(String url) {
    if (url.isEmpty) {
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 58,
          height: 58,
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  Widget _statusChip(bool active) {
    return Chip(
      label: Text(active ? 'Active' : 'Inactive'),
      backgroundColor: active ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: active ? Colors.green.shade800 : Colors.red.shade800,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _approvalChip(String status) {
    Color color = Colors.orange;
    final clean = status.trim().isEmpty ? 'pending' : status.trim().toLowerCase();

    if (clean == 'approved') {
      color = Colors.green;
    } else if (clean == 'rejected') {
      color = Colors.red;
    }

    return Chip(
      label: Text(clean.toUpperCase()),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _stockChip(int stock) {
    Color color = Colors.green;
    String label = 'Stock: $stock';

    if (stock <= 0) {
      color = Colors.red;
      label = 'Out';
    } else if (stock <= 5) {
      color = Colors.orange;
      label = 'Low: $stock';
    }

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewProducts) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  'Products access denied',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'You need products.view permission to open Product Manager.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final categoryIndex = _buildCategoryIndex();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            color: Colors.white,
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 700;

                    final csvButton = OutlinedButton.icon(
                      onPressed: bulkWorking ? null : _pickCSVFile,
                      icon: bulkWorking
                          ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text('CSV Upload'),
                    );

                    final jsonButton = OutlinedButton.icon(
                      onPressed: bulkWorking ? null : _showJsonBulkDialog,
                      icon: const Icon(Icons.data_object_rounded, size: 18),
                      label: const Text('JSON'),
                    );

                    final addButton = ElevatedButton.icon(
                      onPressed: () => _showProductDialog(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(isMobile ? 'Add' : 'Add Product'),
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Product Manager Pro',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (canBulkProducts) csvButton,
                                if (canBulkProducts) const SizedBox(width: 8),
                                if (canBulkProducts) jsonButton,
                                if (canBulkProducts) const SizedBox(width: 8),
                                if (canEditProducts) addButton,
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Product Manager Pro',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (canBulkProducts) ...[
                          csvButton,
                          const SizedBox(width: 8),
                          jsonButton,
                          const SizedBox(width: 8),
                        ],
                        if (canEditProducts) addButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _buildFilterBar(categoryIndex),
              ],
            ),
          ),

          Expanded(
            child: Builder(
              builder: (context) {
                final allDocs = _productDocs;
                if (allDocs == null) {
                  if (_productsError != null) {
                    return Center(child: Text('Could not load products: $_productsError'));
                  }
                  return const Center(child: CircularProgressIndicator());
                }

                if (allDocs.isEmpty) {
                  return const Center(child: Text('No products found'));
                }

                final products = _filterProducts(allDocs, categoryIndex);
                final largeCatalog = allDocs.length > _kLargeCatalogNotice;

                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No matching products'),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _clearFilters, child: const Text('Clear filters')),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: products.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, rawIndex) {
                    if (rawIndex == 0) {
                      return Text(
                        'Showing ${products.length} of ${allDocs.length} products'
                        '${largeCatalog ? ' · Over $_kLargeCatalogNotice products are loaded on every '
                            'open of this page; it should move to per-category queries.' : ''}',
                        style: TextStyle(
                          color: largeCatalog ? Colors.orange.shade900 : Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }
                    final doc = products[rawIndex - 1];
                    final data = doc.data() as Map<String, dynamic>;

                    final active = data['isActive'] == true;
                    final approvalStatus = _text(data['approvalStatus'], 'approved');
                    final isVendorProduct = data['isMarketplace'] == true ||
                        _text(data['vendorId'], 'super_admin') != 'super_admin';
                    final isPendingVendorProduct =
                        isVendorProduct && approvalStatus != 'approved';
                    final displayActive = isPendingVendorProduct ? false : active;
                    final stock = _toInt(data['stock']);
                    final variants = data['variants'] is List ? data['variants'] as List : [];

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final productInfo = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text(data['name']).isEmpty ? 'Unnamed Product' : _text(data['name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_text(data['category'])} • ${_text(data['strength'])} • ${_text(data['manufacturer'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _statusChip(displayActive),
                                    if (isPendingVendorProduct) _approvalChip(approvalStatus),
                                    _stockChip(stock),
                                    Chip(label: Text('৳${_toDouble(data['price']).toStringAsFixed(0)}')),
                                    Chip(label: Text('${variants.length} variants')),
                                  ],
                                ),
                              ],
                            );

                            final actions = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: displayActive,
                                  onChanged: canChangeProductStatus && !isPendingVendorProduct
                                      ? (v) => _toggleStatus(doc.id, v)
                                      : null,
                                ),
                                if (canEditProducts)
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => _showProductDialog(id: doc.id, data: data),
                                    icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                                  ),
                                if (canDeleteProducts)
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteProduct(doc.id),
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                  ),
                              ],
                            );

                            if (constraints.maxWidth < 620) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _productImage(_text(data['image'])),
                                      const SizedBox(width: 12),
                                      Expanded(child: productInfo),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: actions,
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                _productImage(_text(data['image'])),
                                const SizedBox(width: 14),
                                Expanded(child: productInfo),
                                actions,
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
/// One Category / Subcategory filter choice.
class _FilterOption {
  const _FilterOption({required this.id, required this.name, this.hidden = false});

  final String id;
  final String name;
  final bool hidden;
}

/// Category lookup tables and option counts for the product list filters.
class _ProductCategoryIndex {
  _ProductCategoryIndex({
    required this.options,
    required this.nameById,
    required this.idByName,
    required this.mergedInto,
    required this.subOptions,
    required this.subIdByName,
    required this.effectiveCategory,
    required this.effectiveSubcategory,
  });

  final List<_FilterOption> options;
  final Map<String, String> nameById;
  final Map<String, String> idByName;
  /// Merged-away category id -> the id it was merged into.
  final Map<String, String> mergedInto;
  final List<_FilterOption> subOptions;
  final Map<String, String> subIdByName;
  final String effectiveCategory;
  final String effectiveSubcategory;
  final Map<String, int> categoryCounts = {};
  final Map<String, int> subCounts = {};
}
