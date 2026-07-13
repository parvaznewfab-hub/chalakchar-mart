
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/product_card.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../services/product_service.dart';
import '../../services/guest_cart_service.dart';
import '../../services/web_seo_service.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'wishlist_page.dart';

class ProductDetailsPage extends StatefulWidget {
  final Map<String, dynamic> data;

  const ProductDetailsPage({super.key, required this.data});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  late String _selectedUnit;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  bool _showMobileTopBar = false;
  bool _addingCart = false;
  bool _wishlistWorking = false;
  static const double _reviewRewardAmount = 2;
  bool _submittingReview = false;

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
    return ProductService.productIdFrom(ProductService.normalizeProductData(data));
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
    final segments = uri.pathSegments.where((e) => e.trim().isNotEmpty).toList();

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
                item['name'] ??
                    item['productName'] ??
                    item['title'],
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

      _snack('Review submitted! ৳${_reviewRewardAmount.toStringAsFixed(0)} ChalakChar Cash added.');
      if (mounted) setState(() {});
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
          onPressed: _wishlistWorking ? null : () => _toggleWishlistForProduct(product),
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
    final productUrl = 'https://chalakcharmart.com/product/${Uri.encodeComponent(productId)}';

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

  Future<void> _addToCart({
    required Map<String, dynamic> data,
    required double unitPrice,
    required double unitOldPrice,
    required int selectedStock,
  }) async {
    if (_addingCart) return;

    if (data['isActive'] == false) {
      _snack('This product is currently inactive');
      return;
    }

    final variants = data['variants'];
    if (variants is List && variants.isEmpty && data.containsKey('variants')) {
      _snack('Variant unavailable');
      return;
    }

    if (selectedStock <= 0) {
      _snack('Out of stock');
      return;
    }

    if (_quantity > selectedStock) {
      _snack('Only $selectedStock item available');
      return;
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
        return;
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
          return;
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
    } catch (e) {
      debugPrint('ADD TO CART ERROR: $e');
      _snack('Add to cart failed');
    } finally {
      if (mounted) {
        setState(() => _addingCart = false);
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
    final unitOldPrice = ProductService.getDisplayMrp(data, unit: _selectedUnit);
    final selectedStock = ProductService.getStock(data, unit: _selectedUnit);
    final totalPrice = unitPrice * _quantity;
    final totalOldPrice = unitOldPrice * _quantity;

    return Scaffold(
      backgroundColor: _softBg,
      appBar: isMobile ? null : const GlobalWebHeader(),
      bottomNavigationBar: null,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 24,
                      vertical: isMobile ? 0 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMobile)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _borderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.035),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildImageSection(data, 430)),
                                const SizedBox(width: 44),
                                Expanded(
                                  child: _buildMainContent(
                                    data,
                                    units,
                                    unitPrice,
                                    unitOldPrice,
                                    totalPrice,
                                    totalOldPrice,
                                    selectedStock,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          const SizedBox(height: 52),
                          _buildImageSection(data, 285),
                          const SizedBox(height: 20),
                          _buildMainContent(
                            data,
                            units,
                            unitPrice,
                            unitOldPrice,
                            totalPrice,
                            totalOldPrice,
                            selectedStock,
                          ),
                        ],
                        const SizedBox(height: 22),
                        _buildVendorCard(data),
                        const SizedBox(height: 16),
                        _buildTrustStrip(),
                        const SizedBox(height: 32),
                        _buildReviewSection(data),
                        const SizedBox(height: 32),
                        _sectionTitle('Product Overview'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Text(
                            _text(data['overview'], 'No description available.'),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.65,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _sectionTitle('Alternative Brands'),
                        const SizedBox(height: 16),
                        buildAlternativeProducts(context),
                        if (!isMobile) ...[
                          const SizedBox(height: 40),
                          const GlobalWebFooter(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isMobile) _buildMobileBackButton(),
        ],
      ),
    );
  }


  Widget _buildTrustStrip() {
    final items = [
      (Icons.verified_user_rounded, 'Authentic', 'Checked product'),
      (Icons.local_shipping_rounded, 'Fast Delivery', 'Local delivery support'),
      (Icons.payments_rounded, 'Safe Payment', 'Cash / digital payment'),
      (Icons.support_agent_rounded, 'Support', 'Order help available'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor),
          ),
          child: Wrap(
            spacing: isNarrow ? 10 : 18,
            runSpacing: 10,
            children: items.map((item) {
              return SizedBox(
                width: isNarrow ? (constraints.maxWidth - 40) / 2 : 260,
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(item.$1, color: _primaryColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(item.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }


  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
    );
  }
  Widget _buildMobileBackButton() {
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(22),
            elevation: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.maybePop(context),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: Colors.black87,
                ),
              ),
            ),
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
    final selectedImage = images.isNotEmpty ? images[_selectedImageIndex] : '';

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
                : images.isEmpty
                ? null
                : () => _openImagePreview(images, _selectedImageIndex),
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
                              color: const Color(0xFF32A8C7).withValues(alpha: 0.10),
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
                  onTap: () => setState(() => _selectedImageIndex = index),
                  child: Container(
                    width: 86,
                    height: 86,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? const Color(0xFF32A8C7) : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
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

  Widget _buildMainContent(
      Map<String, dynamic> data,
      List<String> units,
      double unitPrice,
      double unitOldPrice,
      double totalPrice,
      double totalOldPrice,
      int selectedStock,
      ) {
    final discount = totalOldPrice > totalPrice && totalOldPrice > 0
        ? (((totalOldPrice - totalPrice) / totalOldPrice) * 100).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _text(data['name'], 'Product'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: _darkText, height: 1.18),
              ),
            ),
            const SizedBox(width: 8),
            _wishlistButton(data),
            const SizedBox(width: 8),
            _roundActionButton(
              icon: Icons.share_rounded,
              color: _primaryColor,
              tooltip: 'Share Product',
              onPressed: () => _shareProduct(data, unitPrice),
            ),
          ],
        ),
        if (_text(data['strength']).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_text(data['strength']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 5),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (_text(data['type']).isNotEmpty) _miniChip(_text(data['type']), Colors.blueGrey),
            if (_text(data['generic']).isNotEmpty) _miniChip('Generic: ${_text(data['generic'])}', const Color(0xFF32A8C7)),
            if (_text(data['manufacturer']).isNotEmpty) _miniChip(_text(data['manufacturer']), Colors.deepPurple),
          ],
        ),
        const SizedBox(height: 20),
        Container(
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
              Text(
                '৳${totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  color: Color(0xFF32A8C7),
                ),
              ),
              const SizedBox(height: 6),
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
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  if (discount > 0) ...[
                    Text(
                      'MRP ৳${totalOldPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        '$discount% OFF',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    height: 42,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: units.contains(_selectedUnit) ? _selectedUnit : units.first,
                        items: units
                            .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u, style: const TextStyle(fontSize: 13)),
                        ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _selectedUnit = v;
                            _quantity = 1;
                          });

                          if (kIsWeb) {
                            _updateProductSeo(data);
                          }
                        },
                      ),
                    ),
                  ),
                  Container(
                    height: 42,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1),
                          icon: const Icon(Icons.remove, size: 18),
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                        Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          onPressed: selectedStock <= 0 || _quantity >= selectedStock
                              ? null
                              : () => setState(() => _quantity++),
                          icon: const Icon(Icons.add, size: 18),
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: selectedStock <= 0 || _addingCart
                        ? null
                        : () => _addToCart(
                      data: data,
                      unitPrice: unitPrice,
                      unitOldPrice: unitOldPrice,
                      selectedStock: selectedStock,
                    ),
                    icon: _addingCart
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.shopping_cart_checkout_rounded),
                    label: Text(_addingCart ? 'Adding...' : 'Add To Cart'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF32A8C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(145, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVendorCard(Map<String, dynamic> data) {
    final vendorId = _vendorId(data);

    if (vendorId == 'super_admin') {
      return _vendorInfoBox(
        title: 'Sold by ChalakChar Mart',
        subtitle: 'Official Store stock',
        verified: true,
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.collection('vendors').doc(vendorId).get(),
      builder: (context, snap) {
        final vendor = snap.data?.data() ?? {};
        final status = _text(vendor['status'], 'approved');
        final active = vendor['isActive'] != false;
        final verified = vendor['isVerified'] == true;

        return _vendorInfoBox(
          title: _text(vendor['shopName'], _vendorName(data)),
          subtitle: active ? 'Vendor status: $status' : 'Vendor currently inactive',
          verified: verified,
        );
      },
    );
  }

  Widget _vendorInfoBox({
    required String title,
    required String subtitle,
    required bool verified,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
            child: const Icon(Icons.storefront_rounded, color: Color(0xFF32A8C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
          if (verified) _miniChip('Verified', Colors.green),
        ],
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
          future: Future.wait([
            _canReviewProduct(data),
            _alreadyReviewed(productId),
          ]),
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
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
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
                  border: Border.all(color: Colors.green.withValues(alpha: 0.20)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You already reviewed this product. ChalakChar Mart Cash reward added.',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
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
                border: Border.all(color: const Color(0xFF32A8C7).withValues(alpha: 0.20)),
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
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _submittingReview ? null : () => _showReviewDialog(data),
                    icon: _submittingReview
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.rate_review_rounded),
                    label: Text(_submittingReview ? 'Submitting...' : 'Write Review'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF32A8C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
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
                            index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 18,
                            color: Colors.amber,
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(review['comment']),
                        style: TextStyle(color: Colors.grey.shade800, height: 1.4),
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

  Widget buildAlternativeProducts(BuildContext context) {
    final category = _text(widget.data['category']);
    if (category.isEmpty) return const SizedBox();

    final currentId = _productId(widget.data);
    final currentName = _text(widget.data['name']).toLowerCase();

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('products')
          .where('category', isEqualTo: category)
          .where('isActive', isEqualTo: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));

        final products = snapshot.data!.docs.where((doc) {
          final itemData = doc.data() as Map<String, dynamic>;
          return doc.id != currentId && _text(itemData['name']).toLowerCase() != currentName;
        }).toList();

        if (products.isEmpty) {
          return const Text('No alternative products found.', style: TextStyle(color: Colors.grey));
        }

        return SizedBox(
          height: 205,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            itemBuilder: (context, index) {
              final item = products[index];
              final itemData = item.data() as Map<String, dynamic>;
              itemData['id'] = item.id;

              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: ProductCard(data: itemData),
              );
            },
          ),
        );
      },
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
          cursor: isDesktop ? SystemMouseCursors.zoomIn : SystemMouseCursors.basic,
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
                    child: Text('Product Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
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
                transform: Matrix4.identity()..scaleByVector3(Vector3(_mirror ? -1.0 : 1.0, 1.0, 1.0)),
                child: Image.network(
                  widget.images[index],
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70, size: 100),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
