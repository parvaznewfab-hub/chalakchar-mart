import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../services/product_service.dart';
import '../../utils/product_delivery_resolver.dart';
import '../../utils/variant_image_selector.dart';
import '../../utils/variant_display_name.dart';
import '../../services/guest_cart_service.dart';
import '../../services/web_seo_service.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'wishlist_page.dart';
import 'cart_page.dart';

class ProductDetailsPage extends StatefulWidget {
  final Map<String, dynamic> data;

  const ProductDetailsPage({super.key, required this.data});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  late final TabController _tabController;

  late String _selectedUnit;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  // Set when the selected variant's image isn't part of the product's
  // general image gallery — shown instead of images[_selectedImageIndex].
  String? _variantImageOverride;
  bool _showMobileTopBar = false;
  bool _addingCart = false;
  bool _buyingNow = false;
  bool _wishlistWorking = false;
  bool _titleExpanded = false;
  static const double _reviewRewardAmount = 2;
  bool _submittingReview = false;
  // Caches the review-eligibility Future so the FutureBuilder in
  // _buildReviewSection doesn't restart into a perpetual loading spinner on
  // every unrelated rebuild of this page (a fresh Future.wait([...]) built
  // inline in `future:` resets FutureBuilder's state each time it's a new
  // instance). Bumping the version forces a one-off recompute, e.g. right
  // after a review is submitted.
  String? _reviewEligibilityKey;
  Future<List<bool>>? _reviewEligibilityFuture;
  int _reviewEligibilityVersion = 0;

  static const Color _primaryColor = Color(0xFF32A8C7);
  static const Color _darkText = Color(0xFF111827);
  static const Color _softBg = Color(0xFFF6F8FB);
  static const Color _borderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();

    final normalized = ProductService.normalizeProductData(widget.data);
    final units = ProductService.getUnits(normalized);
    _selectedUnit = units.isNotEmpty ? units.first : 'piece';
    if (kIsWeb) {
      _updateProductSeo(normalized);
    }

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _scrollController.addListener(() {
      final shouldShow = _scrollController.offset > 35;
      if (shouldShow != _showMobileTopBar && mounted) {
        setState(() => _showMobileTopBar = shouldShow);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _updateProductSeo(Map<String, dynamic> rawData) {
    if (!kIsWeb) return;

    final product = ProductService.normalizeProductData(rawData);
    final productId = ProductService.productIdFrom(product).trim();
    if (productId.isEmpty) return;

    WebSeoService.setProductSeo(
      product: product,
      productId: productId,
      price: ProductService.getDisplayPrice(product, unit: _selectedUnit),
      stock: ProductService.getStock(product, unit: _selectedUnit),
    );
  }

  @override
  void didUpdateWidget(covariant ProductDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data != widget.data && kIsWeb) {
      final normalized = ProductService.normalizeProductData(widget.data);
      final units = ProductService.getUnits(normalized);

      if (units.isNotEmpty && !units.contains(_selectedUnit)) {
        _selectedUnit = units.first;
        _quantity = 1;
      }

      _updateProductSeo(normalized);
    }
  }

  String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  List<String> _units(Map<String, dynamic> data) {
    return ProductService.getUnits(ProductService.normalizeProductData(data));
  }

  String _productId(Map<String, dynamic> data) {
    return ProductService.productIdFrom(
        ProductService.normalizeProductData(data));
  }

  String _vendorId(Map<String, dynamic> data) {
    final product = ProductService.normalizeProductData(data);
    return ProductService.text(product['vendorId'], 'super_admin');
  }

  String _vendorName(Map<String, dynamic> data) {
    final product = ProductService.normalizeProductData(data);
    return ProductService.text(product['vendorName'], 'ChalakChar Mart');
  }

  List<String> _getProductImages(Map<String, dynamic> data) {
    final product = ProductService.normalizeProductData(data);
    return List<String>.from(product['images'] ?? []);
  }

  /// Single shared handler for both the unit dropdown and the variant
  /// swatch grid: updates the selected unit and — when the variant carries
  /// its own image — the main image/gallery selection, in one rebuild.
  /// Price/MRP/stock update automatically since they're derived from
  /// _selectedUnit at build time. Reads raw `data['variants']` (not the
  /// ProductService-normalized list, which doesn't carry image/imageUrl)
  /// to find the tapped variant's image.
  void _selectVariantUnit(String name, Map<String, dynamic> data) {
    final variantsRaw = data['variants'];
    final variants =
        variantsRaw is List ? variantsRaw.whereType<Map>().toList() : <Map>[];
    Map? match;
    for (final v in variants) {
      if (_text(v['name']) == name) {
        match = v;
        break;
      }
    }
    final variantImage = _text(match?['imageUrl'] ?? match?['image']);
    final selection = resolveVariantImageSelection(
      images: _getProductImages(data),
      variantImage: variantImage,
    );

    setState(() {
      _selectedUnit = name;
      _quantity = 1;
      _selectedImageIndex = selection.imageIndex ?? _selectedImageIndex;
      _variantImageOverride = selection.imageOverride;
    });

    if (kIsWeb) _updateProductSeo(data);
  }

  String _productVideoUrl(Map<String, dynamic> data) {
    final product = ProductService.normalizeProductData(data);
    return _text(
      product['videoUrl'] ??
          product['youtubeUrl'] ??
          product['youtubeLink'] ??
          product['videoLink'] ??
          product['video'],
    );
  }

  String? _youtubeVideoId(String url) {
    final input = url.trim();
    if (input.isEmpty) return null;

    // Allow admins to paste only the YouTube video id.
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) return input;

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final segments =
        uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();

    if (host.contains('youtu.be')) {
      return segments.isNotEmpty ? segments.first : null;
    }

    if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      final watchId = uri.queryParameters['v'];
      if (watchId != null && watchId.trim().isNotEmpty) return watchId.trim();

      for (final marker in ['embed', 'shorts', 'live']) {
        final index = segments.indexOf(marker);
        if (index != -1 && segments.length > index + 1) {
          return segments[index + 1];
        }
      }
    }

    return null;
  }

  String _youtubeThumbnail(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  /// Labels a day-range estimate clearly as an estimate; other tiers (exact
  /// date, plain deliveryDays fallback) keep their existing wording.
  String _deliveryLabel(ProductDeliveryEstimate delivery, String prefix) {
    return delivery.isEstimateRange
        ? 'Estimated delivery: ${delivery.displayText}'
        : '$prefix ${delivery.displayText}';
  }

  Future<void> _contactVendorViaWhatsApp(Map<String, dynamic> data) async {
    const whatsappNumber = '8801975838764';
    final name = _text(data['name'], 'this product');
    final uri = Uri.parse(
      'https://wa.me/$whatsappNumber?text=${Uri.encodeComponent('Assalamu Alaikum, I have a question about: $name')}',
    );

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _snack('Could not open WhatsApp');
      }
    } catch (e) {
      debugPrint('WHATSAPP CONTACT ERROR: $e');
      _snack('Could not open WhatsApp');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF32A8C7),
      ),
    );
  }

  Future<bool> _canReviewProduct(Map<String, dynamic> productData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final productId = _productId(productData);
    final productName = _text(productData['name']).toLowerCase();

    try {
      final orders = await db
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .get();

      for (final order in orders.docs) {
        final orderData = order.data();
        final status = _text(orderData['status']).toLowerCase();

        if (!['delivered', 'received', 'completed'].contains(status)) {
          continue;
        }

        final items = orderData['items'];

        if (items is List) {
          for (final item in items) {
            if (item is Map) {
              final itemProductId = _text(
                item['productId'] ??
                    item['id'] ??
                    item['product_id'] ??
                    item['productDocId'] ??
                    item['pid'],
              );

              final itemName = _text(
                item['name'] ?? item['productName'] ?? item['title'],
              ).toLowerCase();

              if (itemProductId == productId ||
                  (productName.isNotEmpty && itemName == productName)) {
                return true;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CAN REVIEW ERROR: $e');
    }

    return false;
  }

  /// Returns a stable Future instance for the given product (recomputed
  /// only when the product changes or [_reviewEligibilityVersion] is
  /// bumped), so passing it to a FutureBuilder's `future:` never resets an
  /// in-flight/completed check back to a loading state on unrelated
  /// rebuilds.
  Future<List<bool>> _getReviewEligibilityFuture(
    Map<String, dynamic> data,
    String productId,
  ) {
    final key = '$productId#$_reviewEligibilityVersion';
    if (_reviewEligibilityKey != key) {
      _reviewEligibilityKey = key;
      _reviewEligibilityFuture = Future.wait([
        _canReviewProduct(data),
        _alreadyReviewed(productId),
      ]);
    }
    return _reviewEligibilityFuture!;
  }

  Future<bool> _alreadyReviewed(String productId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;

    final doc = await db
        .collection('products')
        .doc(productId)
        .collection('reviews')
        .doc(user.uid)
        .get();

    return doc.exists;
  }

  void _showReviewDialog(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please login first');
      return;
    }

    final commentController = TextEditingController();
    int rating = 5;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Write Product Review'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final star = index + 1;
                    return IconButton(
                      onPressed: () => setDialogState(() => rating = star),
                      icon: Icon(
                        star <= rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 30,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commentController,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Write your experience...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Submit review and get ৳${_reviewRewardAmount.toStringAsFixed(0)} ChalakChar Cash',
                  style: const TextStyle(
                    color: Color(0xFF32A8C7),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _submittingReview
                    ? null
                    : () async {
                        await _submitReview(
                          productData: data,
                          rating: rating,
                          comment: commentController.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF32A8C7),
                  foregroundColor: Colors.white,
                ),
                child: _submittingReview
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitReview({
    required Map<String, dynamic> productData,
    required int rating,
    required String comment,
  }) async {
    if (_submittingReview) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please login first');
      return;
    }

    if (comment.length < 3) {
      _snack('Please write a short review');
      return;
    }

    final productId = _productId(productData);

    setState(() => _submittingReview = true);

    try {
      final canReview = await _canReviewProduct(productData);
      if (!canReview) {
        _snack('Review allowed after product received');
        return;
      }

      final already = await _alreadyReviewed(productId);
      if (already) {
        _snack('You already reviewed this product');
        return;
      }

      final userRef = db.collection('users').doc(user.uid);
      final userDoc = await userRef.get();
      final userData = userDoc.data() ?? {};

      await db.runTransaction((transaction) async {
        final reviewRef = db
            .collection('products')
            .doc(productId)
            .collection('reviews')
            .doc(user.uid);

        final productRef = db.collection('products').doc(productId);
        final freshReview = await transaction.get(reviewRef);

        if (freshReview.exists) {
          throw Exception('already_reviewed');
        }

        transaction.set(reviewRef, {
          'productId': productId,
          'productName': _text(productData['name'], 'Product'),
          'userId': user.uid,
          'userName': _text(userData['name'], user.email ?? 'Customer'),
          'userEmail': user.email ?? '',
          'rating': rating,
          'comment': comment,
          'rewardAmount': _reviewRewardAmount,
          'rewardGiven': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          userRef,
          {
            'points': FieldValue.increment(_reviewRewardAmount),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          productRef,
          {
            'reviewCount': FieldValue.increment(1),
            'ratingCount': FieldValue.increment(1),
            'ratingTotal': FieldValue.increment(rating),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      _snack(
          'Review submitted! ৳${_reviewRewardAmount.toStringAsFixed(0)} ChalakChar Cash added.');
      if (mounted) setState(() => _reviewEligibilityVersion++);
    } catch (e) {
      if (e.toString().contains('already_reviewed')) {
        _snack('You already reviewed this product');
      } else {
        _snack('Review failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submittingReview = false);
    }
  }

  void _openVideo(String url) {
    final videoId = _youtubeVideoId(url);
    if (videoId == null || videoId.isEmpty) {
      _snack('Invalid YouTube video link');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProductVideoDialog(videoId: videoId),
    );
  }

  void _openImagePreview(List<String> images, int startIndex) {
    if (images.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _FullscreenImageViewer(
          images: images,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  Future<void> _toggleWishlistForProduct(Map<String, dynamic> data) async {
    if (_wishlistWorking) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please login first');
      return;
    }

    final product = ProductService.normalizeProductData(data);
    final productId = _productId(product);

    if (productId.trim().isEmpty) {
      _snack('Invalid product data');
      return;
    }

    setState(() => _wishlistWorking = true);

    try {
      final ref = db
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .doc(productId);

      final before = await ref.get();

      await WishlistPage.toggleWishlist({
        ...product,
        'id': productId,
        'productId': productId,
      });

      _snack(before.exists ? 'Removed from Wishlist' : 'Added to Wishlist');
    } catch (e, s) {
      debugPrint('WISHLIST TOGGLE ERROR: $e');
      debugPrintStack(stackTrace: s);
      final msg = e.toString().replaceFirst('Exception:', '').trim();
      _snack(msg.isEmpty ? 'Wishlist update failed' : msg);
    } finally {
      if (mounted) setState(() => _wishlistWorking = false);
    }
  }

  Widget _wishlistButton(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;
    final product = ProductService.normalizeProductData(data);
    final productId = _productId(product);

    if (user == null || productId.trim().isEmpty) {
      return _roundActionButton(
        icon: Icons.favorite_border,
        color: Colors.grey.shade700,
        tooltip: 'Add to Wishlist',
        onPressed: () => _toggleWishlistForProduct(product),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .doc(productId)
          .snapshots(),
      builder: (context, snap) {
        final saved = snap.data?.exists == true;

        return _roundActionButton(
          icon: saved ? Icons.favorite : Icons.favorite_border,
          color: saved ? Colors.red : Colors.grey.shade700,
          tooltip: saved ? 'Remove from Wishlist' : 'Add to Wishlist',
          onPressed: _wishlistWorking
              ? null
              : () => _toggleWishlistForProduct(product),
        );
      },
    );
  }

  Widget _roundActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final disabled = onPressed == null;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _borderColor),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Center(
                child: Icon(
                  icon,
                  color: disabled ? color.withValues(alpha: 0.45) : color,
                  size: 24,
                  fill: icon == Icons.favorite ? 1 : 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareProduct(Map<String, dynamic> data, double price) async {
    final product = ProductService.normalizeProductData(data);
    final productId = _productId(product);
    final name = _text(product['name'], 'Product');
    final category = _text(product['category']);
    final productUrl =
        'https://chalakcharmart.com/product/${Uri.encodeComponent(productId)}';

    final shareText = [
      '🛒 ChalakChar Mart',
      '',
      name,
      if (category.isNotEmpty) 'Category: $category',
      if (price > 0) 'Price: ৳${price.toStringAsFixed(0)}',
      '',
      productUrl,
    ].join('\n');

    try {
      await Share.share(
        shareText,
        subject: name,
      );
      _snack('Product shared');
    } catch (e) {
      debugPrint('PRODUCT SHARE ERROR: $e');
      _snack('Share failed');
    }
  }

  Future<bool> _addToCart({
    required Map<String, dynamic> data,
    required double unitPrice,
    required double unitOldPrice,
    required int selectedStock,
  }) async {
    if (_addingCart) return false;

    if (data['isActive'] == false) {
      _snack('This product is currently inactive');
      return false;
    }

    final variants = data['variants'];
    if (variants is List && variants.isEmpty && data.containsKey('variants')) {
      _snack('Variant unavailable');
      return false;
    }

    if (selectedStock <= 0) {
      _snack('Out of stock');
      return false;
    }

    if (_quantity > selectedStock) {
      _snack('Only $selectedStock item available');
      return false;
    }

    setState(() => _addingCart = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final isGuest = user == null;

      final product = ProductService.normalizeProductData(data);
      final selectedVariant = ProductService.selectedVariant(
        product,
        _selectedUnit,
      );

      final cartPayload = ProductService.buildCartItem(
        product,
        selectedVariant,
        qty: _quantity,
      );

      final productId = ProductService.text(cartPayload['productId']);
      final vendorId = ProductService.text(
        cartPayload['vendorId'],
        'super_admin',
      );
      final unit = ProductService.text(
        cartPayload['unit'],
        'Default',
      );

      if (productId.isEmpty) {
        _snack('Invalid product data. Please refresh and try again.');
        return false;
      }

      final cartDocId = ProductService.cartDocId(
        productId: productId,
        vendorId: vendorId,
        unit: unit,
      );

      if (isGuest) {
        await GuestCartService.addItem(cartPayload);
      } else {
        final cartRef = db
            .collection('cart')
            .doc(user.uid)
            .collection('items')
            .doc(cartDocId);

        final existingDoc = await cartRef.get();

        int existingQty = 0;
        dynamic existingCreatedAt;

        if (existingDoc.exists) {
          final existingData = existingDoc.data() ?? <String, dynamic>{};
          existingCreatedAt = existingData['createdAt'];

          final rawQty = existingData['qty'];
          if (rawQty is int) {
            existingQty = rawQty;
          } else if (rawQty is num) {
            existingQty = rawQty.toInt();
          } else {
            existingQty = int.tryParse(rawQty?.toString() ?? '0') ?? 0;
          }
        }

        final newQty = existingQty + _quantity;

        if (newQty > selectedStock) {
          _snack('Only $selectedStock item available');
          return false;
        }

        await cartRef.set(
          {
            ...cartPayload,
            'qty': newQty,
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': existingDoc.exists && existingCreatedAt != null
                ? existingCreatedAt
                : FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      _snack('${_text(data['name'], 'Product')} added to cart');
      return true;
    } catch (e) {
      debugPrint('ADD TO CART ERROR: $e');
      _snack('Add to cart failed');
      return false;
    } finally {
      if (mounted) {
        setState(() => _addingCart = false);
      }
    }
  }

  Future<void> _buyNow({
    required Map<String, dynamic> data,
    required double unitPrice,
    required double unitOldPrice,
    required int selectedStock,
  }) async {
    if (_buyingNow) return;
    setState(() => _buyingNow = true);
    try {
      final added = await _addToCart(
        data: data,
        unitPrice: unitPrice,
        unitOldPrice: unitOldPrice,
        selectedStock: selectedStock,
      );
      if (!added || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartPage()),
      );
    } finally {
      if (mounted) {
        setState(() => _buyingNow = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ProductService.normalizeProductData(widget.data);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    final units = _units(data);
    final unitPrice = ProductService.getDisplayPrice(data, unit: _selectedUnit);
    final unitOldPrice =
        ProductService.getDisplayMrp(data, unit: _selectedUnit);
    final selectedStock = ProductService.getStock(data, unit: _selectedUnit);
    final totalPrice = unitPrice * _quantity;
    final totalOldPrice = unitOldPrice * _quantity;

    final tabsBar = Material(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: _primaryColor,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: _primaryColor,
        isScrollable: isMobile,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Reviews'),
          Tab(text: 'Description'),
        ],
      ),
    );

    Widget tabContent;
    switch (_tabController.index) {
      case 1:
        tabContent = _buildReviewSection(data);
        break;
      case 2:
        tabContent = _buildDescriptionTabContent(data);
        break;
      case 0:
      default:
        tabContent = _buildOverviewTabContent(data);
    }

    return Scaffold(
      backgroundColor: _softBg,
      appBar: isMobile ? null : const GlobalWebHeader(),
      bottomNavigationBar: isMobile
          ? _buildBottomActionBar(data, unitPrice, unitOldPrice, selectedStock)
          : null,
      body: Stack(
        children: [
          SafeArea(
            bottom: !isMobile,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 0 : 24,
                      vertical: isMobile ? 0 : 24,
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 52),
                              _buildImageSection(data, 340),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 16),
                                    _buildTitleAndRating(data),
                                    const SizedBox(height: 16),
                                    _buildPriceBox(
                                      data,
                                      units,
                                      totalPrice,
                                      totalOldPrice,
                                      selectedStock,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              tabsBar,
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: tabContent,
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: _borderColor),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.035),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 35,
                                      child: _buildImageSection(data, 430),
                                    ),
                                    const SizedBox(width: 28),
                                    Expanded(
                                      flex: 35,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildTitleAndRating(data),
                                          const SizedBox(height: 20),
                                          _buildPriceBox(
                                            data,
                                            units,
                                            totalPrice,
                                            totalOldPrice,
                                            selectedStock,
                                            showQuantitySelector: false,
                                          ),
                                          const SizedBox(height: 20),
                                          _buildVariantSwatchGrid(data),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 28),
                                    Expanded(
                                      flex: 30,
                                      child: _buildDesktopSidebar(
                                        data,
                                        unitPrice,
                                        unitOldPrice,
                                        selectedStock,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              tabsBar,
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: tabContent,
                              ),
                              const SizedBox(height: 40),
                              const GlobalWebFooter(),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (isMobile) _buildTopBarOverlay(data),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
    );
  }

  /// Client-side safety net mirroring functions/index.js's
  /// sanitizeAliExpressHtml, applied at render time so it also covers
  /// products imported before that backend fix existed (their stored
  /// overviewHtml was never re-sanitized).
  ///
  /// - Protocol-relative image URLs (src="//host/...") never load in
  ///   flutter_html, since it only recognizes an explicit http/https scheme.
  /// - When an <img> fails to load for any reason, flutter_html's built-in
  ///   fallback renders that element's raw `alt` attribute as visible text
  ///   — the source of the stray broken-icon-plus-text seen at the end of
  ///   some imported descriptions. Blanking alt keeps a failed image a
  ///   silent, empty gap instead.
  String _sanitizeOverviewHtmlForRender(String html) {
    return html
        .replaceAllMapped(
          RegExp(r'''(href|src)\s*=\s*(["'])//([^"']+)\2''',
              caseSensitive: false),
          (m) => '${m[1]}=${m[2]}https://${m[3]}${m[2]}',
        )
        .replaceAll(RegExp(r'''\salt\s*=\s*"[^"]*"''', caseSensitive: false),
            ' alt=""')
        .replaceAll(RegExp(r"""\salt\s*=\s*'[^']*'""", caseSensitive: false),
            " alt=''");
  }

  Widget _buildDescriptionHtml(Map<String, dynamic> data) {
    final html = _text(data['overviewHtml']);
    if (html.isEmpty) {
      final overviewText = _text(data['overview']);
      final hasContent = overviewText.isNotEmpty;
      return Text(
        hasContent
            ? overviewText
            : 'No description has been added for this product yet.',
        style: TextStyle(
          color: hasContent ? Colors.grey.shade700 : Colors.grey.shade500,
          height: 1.65,
          fontSize: 14,
          fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
        ),
      );
    }
    return Html(
      data: _sanitizeOverviewHtmlForRender(html),
      extensions: const [TableHtmlExtension()],
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(14),
          color: Colors.grey.shade700,
          lineHeight: const LineHeight(1.65),
        ),
        'img': Style(
          width: Width(100, Unit.percent),
          margin: Margins.symmetric(vertical: 8),
        ),
        'table': Style(
          width: Width(100, Unit.percent),
        ),
      },
    );
  }

  Widget _buildSpecificationsSection(Map<String, dynamic> data) {
    final specs = data['specifications'];
    if (specs is! List || specs.isEmpty) return const SizedBox.shrink();

    final entries = <MapEntry<String, String>>[];
    for (final spec in specs) {
      if (spec is! Map) continue;
      final name = _text(spec['name']);
      final value = _text(spec['value']);
      if (name.isEmpty || value.isEmpty) continue;
      entries.add(MapEntry(name, value));
    }

    final rows = <TableRow>[];
    for (var i = 0; i < entries.length; i++) {
      final name = entries[i].key;
      final value = entries[i].value;
      final isLast = i == entries.length - 1;
      rows.add(
        TableRow(
          decoration: isLast
              ? null
              : BoxDecoration(
                  border: Border(bottom: BorderSide(color: _borderColor)),
                ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(
                value,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Specifications'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _borderColor),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(3),
              },
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBarOverlay(Map<String, dynamic> data) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: _showMobileTopBar ? Colors.white : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _topBarIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 18, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Search ChalakChar Mart',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _topBarIconButton(
                icon: Icons.share_rounded,
                onTap: () => _shareProduct(data,
                    ProductService.getDisplayPrice(data, unit: _selectedUnit)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBarIconButton(
      {required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: _showMobileTopBar ? 0 : 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 19, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildOverviewTabContent(Map<String, dynamic> data) {
    final aiOverview = _text(data['overview']);
    final hasOverview = aiOverview.isNotEmpty;

    // Always rendered — regardless of product source (AliExpress-imported
    // or manually-added) — so the tab is never blank; a muted fallback
    // shows instead of real content when nothing has been written yet.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: _primaryColor),
              const SizedBox(width: 8),
              const Text(
                'AI Overview',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasOverview
                ? aiOverview
                : 'No additional overview has been added for this product yet.',
            style: TextStyle(
              color: hasOverview ? Colors.grey.shade800 : Colors.grey.shade500,
              fontSize: 13,
              height: 1.5,
              fontStyle: hasOverview ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionTabContent(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpecificationsSection(data),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor),
          ),
          child: _buildDescriptionHtml(data),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar(
    Map<String, dynamic> data,
    double unitPrice,
    double unitOldPrice,
    int selectedStock,
  ) {
    final delivery = ProductDeliveryResolver.resolve(data);
    final subtext = selectedStock > 0 && selectedStock <= 5
        ? 'Only $selectedStock left'
        : delivery.hasEstimate
            ? _deliveryLabel(delivery, 'Arrives')
            : '';

    return Material(
      color: Colors.white,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _bottomBarIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Message seller',
                onTap: () => _contactVendorViaWhatsApp(data),
              ),
              const SizedBox(width: 6),
              _bottomBarIconButton(
                icon: Icons.shopping_cart_outlined,
                tooltip: 'View cart',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CartPage())),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: selectedStock <= 0 || _addingCart || _buyingNow
                      ? null
                      : () => _addToCart(
                            data: data,
                            unitPrice: unitPrice,
                            unitOldPrice: unitOldPrice,
                            selectedStock: selectedStock,
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: const BorderSide(color: _primaryColor),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _addingCart
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add To Cart',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: selectedStock <= 0 || _addingCart || _buyingNow
                      ? null
                      : () => _buyNow(
                            data: data,
                            unitPrice: unitPrice,
                            unitOldPrice: unitOldPrice,
                            selectedStock: selectedStock,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _buyingNow
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Buy Now',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14)),
                            if (subtext.isNotEmpty)
                              Text(subtext,
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(
              shape: BoxShape.circle, border: Border.all(color: _borderColor)),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: onTap,
                child: Icon(icon, size: 22, color: Colors.grey.shade700)),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(Map<String, dynamic> data, double height) {
    final images = _getProductImages(data);
    final videoUrl = _productVideoUrl(data);
    final videoId = _youtubeVideoId(videoUrl);
    final hasVideo = videoId != null && videoId.isNotEmpty;
    final videoThumbnail = hasVideo ? _youtubeThumbnail(videoId) : '';

    if (_selectedImageIndex >= images.length) _selectedImageIndex = 0;
    final selectedImage = (_variantImageOverride ?? '').isNotEmpty
        ? _variantImageOverride!
        : (images.isNotEmpty ? images[_selectedImageIndex] : '');

    Widget mainMedia() {
      if (selectedImage.isNotEmpty) {
        return _HoverMagnifierImage(imageUrl: selectedImage);
      }

      if (hasVideo) {
        return Image.network(
          videoThumbnail,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.play_circle_fill_rounded,
            size: 100,
            color: Color(0xFF32A8C7),
          ),
        );
      }

      return const Icon(Icons.image, size: 100, color: Colors.grey);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap: hasVideo && selectedImage.isEmpty
                ? () => _openVideo(videoUrl)
                : selectedImage.isEmpty
                    ? null
                    // Fullscreen must show the same active image as the
                    // main preview. Usually that's already in `images` (use
                    // it as-is, same swipeable gallery as before); if it's
                    // a variant-only override not present in the gallery,
                    // prepend it just for this preview call — never mutates
                    // the persistent gallery list, never duplicates it.
                    : () => _openImagePreview(
                          images.contains(selectedImage)
                              ? images
                              : [selectedImage, ...images],
                          images.contains(selectedImage) ? _selectedImageIndex : 0,
                        ),
            child: Container(
              height: height,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: mainMedia()),
                  if (images.isNotEmpty)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _heroBadge(
                          'Item ${_selectedImageIndex + 1}/${images.length}'),
                    ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _wishlistButton(data),
                  ),
                  if (hasVideo)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(40),
                        onTap: () => _openVideo(videoUrl),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Watch Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (images.length > 1 || hasVideo) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 86,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length + (hasVideo ? 1 : 0),
              itemBuilder: (context, index) {
                if (hasVideo && index == images.length) {
                  return GestureDetector(
                    onTap: () => _openVideo(videoUrl),
                    child: Container(
                      width: 110,
                      height: 86,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF32A8C7).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF32A8C7),
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            videoThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF32A8C7)
                                  .withValues(alpha: 0.10),
                            ),
                          ),
                          Container(
                              color: Colors.black.withValues(alpha: 0.25)),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                          const Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Text(
                              'VIDEO',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final url = images[index];
                final selected = index == _selectedImageIndex;

                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedImageIndex = index;
                    _variantImageOverride = null;
                  }),
                  child: Container(
                    width: 86,
                    height: 86,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF32A8C7)
                            : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasVideo
                ? 'Tap image for zoom preview • Tap video to watch'
                : 'Tap image for zoom preview',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _heroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildTitleAndRating(Map<String, dynamic> data) {
    final ratingCount = _toInt(data['reviewCount'] ?? data['ratingCount'], 0);
    final ratingAvg = ratingCount > 0
        ? (double.tryParse('${data['ratingAvg'] ?? 0}') ?? 0)
        : 0.0;
    final soldCount = _toInt(data['orderCount'], 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _text(data['name'], 'Product'),
                maxLines: _titleExpanded ? null : 2,
                overflow: _titleExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _darkText,
                    height: 1.25),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _titleExpanded = !_titleExpanded),
              icon: Icon(_titleExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded),
              tooltip: _titleExpanded ? 'Show less' : 'Show more',
            ),
          ],
        ),
        if (_text(data['strength']).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_text(data['strength']),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 5),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (_text(data['type']).isNotEmpty)
              _miniChip(_text(data['type']), Colors.blueGrey),
            if (_text(data['generic']).isNotEmpty)
              _miniChip('Generic: ${_text(data['generic'])}',
                  const Color(0xFF32A8C7)),
            if (_text(data['manufacturer']).isNotEmpty)
              _miniChip(_text(data['manufacturer']), Colors.deepPurple),
          ],
        ),
        if (ratingCount > 0 || soldCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (ratingCount > 0) ...[
                ...List.generate(5, (i) {
                  return Icon(
                    i < ratingAvg.round()
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 16,
                    color: const Color(0xFFFFA41C),
                  );
                }),
                const SizedBox(width: 6),
                Text(
                  '${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ],
              if (ratingCount > 0 && soldCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child:
                      Text('·', style: TextStyle(color: Colors.grey.shade400)),
                ),
              if (soldCount > 0)
                Text(
                  '$soldCount+ sold',
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPriceBox(
    Map<String, dynamic> data,
    List<String> units,
    double totalPrice,
    double totalOldPrice,
    int selectedStock, {
    bool showQuantitySelector = true,
  }) {
    final discount = totalOldPrice > totalPrice && totalOldPrice > 0
        ? (((totalOldPrice - totalPrice) / totalOldPrice) * 100).round()
        : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '৳${totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  color: Color(0xFF32A8C7),
                ),
              ),
              if (discount > 0) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      '-$discount%',
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'MRP ৳${totalOldPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                  decoration: TextDecoration.lineThrough, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Price excludes applicable taxes',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                selectedStock > 0 ? 'In Stock: $selectedStock' : 'Out of Stock',
                style: TextStyle(
                  color: selectedStock > 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (selectedStock <= 5 && selectedStock > 0)
                const Text(
                  'Low Stock',
                  style: TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          if (showQuantitySelector) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: units.contains(_selectedUnit)
                          ? _selectedUnit
                          : units.first,
                      items: units
                          .map((u) => DropdownMenuItem(
                                value: u,
                                child: Text(cleanVariantDisplayName(u),
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        _selectVariantUnit(v, data);
                      },
                    ),
                  ),
                ),
                _buildQuantityStepper(selectedStock),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuantityStepper(int selectedStock) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () =>
                setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1),
            icon: const Icon(Icons.remove, size: 18),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
          Text('$_quantity',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            onPressed: selectedStock <= 0 || _quantity >= selectedStock
                ? null
                : () => setState(() => _quantity++),
            icon: const Icon(Icons.add, size: 18),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantSwatchGrid(Map<String, dynamic> data) {
    final variantsRaw = data['variants'];
    final variants =
        variantsRaw is List ? variantsRaw.whereType<Map>().toList() : <Map>[];
    if (variants.length <= 1) return const SizedBox.shrink();

    final fallbackImage = _text(data['imageUrl'] ?? data['image']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color: ${cleanVariantDisplayName(_selectedUnit)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: variants.map((v) {
            final name = _text(v['name'], 'Option');
            final image = _text(v['imageUrl'] ?? v['image'], fallbackImage);
            final selected = name == _selectedUnit;

            return Tooltip(
              message: cleanVariantDisplayName(name),
              child: GestureDetector(
                onTap: () => _selectVariantUnit(name, data),
                child: Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _primaryColor : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: image.isNotEmpty
                        ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _swatchFallback(name),
                          )
                        : _swatchFallback(name),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _swatchFallback(String name) {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style:
            TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade600),
      ),
    );
  }

  Widget _sidebarValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sidebarLinkRow(String label, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarSoldByRow(Map<String, dynamic> data) {
    final vendorId = _vendorId(data);
    final nameFuture = vendorId == 'super_admin'
        ? Future.value(_vendorName(data))
        : db.collection('vendors').doc(vendorId).get().then(
              (s) => _text(s.data()?['shopName'], _vendorName(data)),
            );

    return FutureBuilder<String>(
      future: nameFuture,
      builder: (context, snap) {
        final name = snap.data ?? _vendorName(data);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Sold By  ',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                      TextSpan(
                          text: name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => _contactVendorViaWhatsApp(data),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                tooltip: 'Message',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarWishlistButton(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;
    final productId = _productId(data);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user != null && productId.isNotEmpty)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('users')
                .doc(user.uid)
                .collection('wishlist')
                .doc(productId)
                .snapshots(),
            builder: (context, snap) {
              final saved = snap.data?.exists == true;
              return IconButton(
                onPressed: _wishlistWorking
                    ? null
                    : () => _toggleWishlistForProduct(data),
                icon: Icon(
                  saved ? Icons.favorite : Icons.favorite_border,
                  color: saved ? Colors.red : Colors.grey.shade700,
                  size: 20,
                ),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              );
            },
          )
        else
          IconButton(
            onPressed: () => _toggleWishlistForProduct(data),
            icon: Icon(Icons.favorite_border,
                color: Colors.grey.shade700, size: 20),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        if (productId.isNotEmpty) ...[
          const SizedBox(width: 6),
          FutureBuilder<AggregateQuerySnapshot>(
            future: db
                .collectionGroup('wishlist')
                .where('productId', isEqualTo: productId)
                .count()
                .get(),
            builder: (context, snap) {
              final count = snap.data?.count ?? 0;
              if (count <= 0) return const SizedBox.shrink();
              return Text(
                '$count',
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopSidebar(
    Map<String, dynamic> data,
    double unitPrice,
    double unitOldPrice,
    int selectedStock,
  ) {
    final delivery = ProductDeliveryResolver.resolve(data);
    final shippingRaw = data['shippingCost'] ?? data['shippingFee'];
    final shippingCost =
        shippingRaw != null ? double.tryParse('$shippingRaw') : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebarSoldByRow(data),
          const Divider(height: 20),
          if (shippingCost != null)
            _sidebarValueRow('Shipping', '৳${shippingCost.toStringAsFixed(2)}'),
          if (delivery.hasEstimate)
            _sidebarValueRow(
              delivery.isEstimateRange ? 'Estimated delivery' : 'Delivery',
              delivery.displayText!,
            ),
          _sidebarLinkRow(
            'Return & refund policy',
            onTap: () => Navigator.of(context, rootNavigator: true)
                .pushNamed('/return-policy'),
          ),
          _sidebarLinkRow(
            'Security & Privacy',
            onTap: () => Navigator.of(context, rootNavigator: true)
                .pushNamed('/privacy-policy'),
          ),
          const Divider(height: 20),
          Row(
            children: [
              Text('Quantity',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              const Spacer(),
              _buildQuantityStepper(selectedStock),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: selectedStock <= 0 || _addingCart || _buyingNow
                  ? null
                  : () => _buyNow(
                        data: data,
                        unitPrice: unitPrice,
                        unitOldPrice: unitOldPrice,
                        selectedStock: selectedStock,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _buyingNow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Buy Now',
                      style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: selectedStock <= 0 || _addingCart || _buyingNow
                  ? null
                  : () => _addToCart(
                        data: data,
                        unitPrice: unitPrice,
                        unitOldPrice: unitOldPrice,
                        selectedStock: selectedStock,
                      ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: const BorderSide(color: _primaryColor),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _addingCart
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add To Cart',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _shareProduct(data, unitPrice),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
              ),
              const SizedBox(width: 16),
              _buildSidebarWishlistButton(data),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildReviewSection(Map<String, dynamic> data) {
    final productId = _productId(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Customer Reviews'),
        const SizedBox(height: 12),
        FutureBuilder<List<bool>>(
          future: _getReviewEligibilityFuture(data, productId),
          builder: (context, snap) {
            final loading = snap.connectionState == ConnectionState.waiting;
            final canReview = snap.data?[0] ?? false;
            final alreadyReviewed = snap.data?[1] ?? true;

            if (loading) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Checking review eligibility...'),
                  ],
                ),
              );
            }

            if (!canReview) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Review option will be available after product received.',
                        style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (alreadyReviewed) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.20)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You already reviewed this product. ChalakChar Mart Cash reward added.',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF32A8C7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF32A8C7).withValues(alpha: 0.20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product received? Share your experience.',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Write a review and get ৳${_reviewRewardAmount.toStringAsFixed(0)} ChalakChar Cash.',
                    style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _submittingReview
                        ? null
                        : () => _showReviewDialog(data),
                    icon: _submittingReview
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.rate_review_rounded),
                    label: Text(
                        _submittingReview ? 'Submitting...' : 'Write Review'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF32A8C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('products')
              .doc(productId)
              .collection('reviews')
              .orderBy('createdAt', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 44,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }

            final reviews = snapshot.data?.docs ?? [];
            if (reviews.isEmpty) {
              return Text(
                'No reviews yet.',
                style: TextStyle(
                    color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              );
            }

            return Column(
              children: reviews.map((doc) {
                final review = doc.data();
                final rating = _toInt(review['rating'], 5).clamp(1, 5);

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(review['userName'], 'Customer'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < rating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 18,
                            color: Colors.amber,
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(review['comment']),
                        style:
                            TextStyle(color: Colors.grey.shade800, height: 1.4),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

}

class _HoverMagnifierImage extends StatefulWidget {
  final String imageUrl;

  const _HoverMagnifierImage({required this.imageUrl});

  @override
  State<_HoverMagnifierImage> createState() => _HoverMagnifierImageState();
}

class _HoverMagnifierImageState extends State<_HoverMagnifierImage> {
  Offset _mousePosition = Offset.zero;
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return MouseRegion(
          cursor:
              isDesktop ? SystemMouseCursors.zoomIn : SystemMouseCursors.basic,
          onEnter: (_) {
            if (isDesktop) setState(() => _isHovering = true);
          },
          onExit: (_) {
            if (isDesktop) setState(() => _isHovering = false);
          },
          onHover: (event) {
            if (!isDesktop) return;
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(event.position);
            setState(() {
              _mousePosition = Offset(
                local.dx.clamp(0.0, width),
                local.dy.clamp(0.0, height),
              );
            });
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    size: 100,
                    color: Colors.grey,
                  ),
                ),
              ),
              if (_isHovering && width > 0 && height > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Transform.scale(
                        scale: 1.8,
                        alignment: Alignment(
                          (_mousePosition.dx / width) * 2 - 1,
                          (_mousePosition.dy / height) * 2 - 1,
                        ),
                        child: Image.network(
                          widget.imageUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductVideoDialog extends StatefulWidget {
  final String videoId;

  const _ProductVideoDialog({required this.videoId});

  @override
  State<_ProductVideoDialog> createState() => _ProductVideoDialogState();
}

class _ProductVideoDialogState extends State<_ProductVideoDialog> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableCaption: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 900 ? 820.0 : screenWidth * 0.94;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: Color(0xFF32A8C7)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Product Video',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              child:
                  YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullscreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late PageController _controller;
  late int _index;
  bool _mirror = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.images.length}'),
        actions: [
          IconButton(
            tooltip: 'Mirror',
            onPressed: () => setState(() => _mirror = !_mirror),
            icon: const Icon(Icons.flip),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scaleByVector3(Vector3(_mirror ? -1.0 : 1.0, 1.0, 1.0)),
                child: Image.network(
                  widget.images[index],
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                      color: Colors.white70, size: 100),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
