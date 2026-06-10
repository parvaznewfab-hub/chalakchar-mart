import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'product_service.dart';

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> autoSetup() async {}

  // ---------------------------------------------------------------------------
  // Coupons
  // ---------------------------------------------------------------------------

  static Future<void> disableExpiredCoupons() async {
    try {
      final snapshot = await _db
          .collection('coupons')
          .where('isActive', isEqualTo: true)
          .get();

      final batch = _db.batch();
      final now = DateTime.now();

      for (final doc in snapshot.docs) {
        final expiry = doc.data()['expiry'];
        if (expiry is Timestamp && now.isAfter(expiry.toDate())) {
          batch.update(doc.reference, {
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error disabling coupons: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  static Stream<QuerySnapshot> getCategories({bool onlyActive = false}) {
    Query query = _db.collection('categories');
    if (onlyActive) query = query.where('isActive', isEqualTo: true);
    return query.snapshots();
  }

  static Stream<List<Map<String, dynamic>>> getCategoryList({
    bool onlyActive = false,
  }) {
    return _db.collection('categories').snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((e) {
        if (!onlyActive) return true;
        return e['isActive'] == true;
      }).toList();

      list.sort((a, b) {
        final ap = ProductService.toInt(a['priority']);
        final bp = ProductService.toInt(b['priority']);
        return ap.compareTo(bp);
      });

      return list;
    });
  }

  static Future<void> addCategory(
      String name,
      int priority,
      String imageUrl,
      ) async {
    await _db.collection('categories').add({
      'name': name.trim(),
      'priority': priority,
      'image': imageUrl.trim(),
      'imageUrl': imageUrl.trim(),
      'isActive': true,
      'showOnHome': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateCategory(
      String id,
      String name,
      int priority,
      String imageUrl,
      bool isActive,
      ) async {
    await _db.collection('categories').doc(id).set({
      'name': name.trim(),
      'priority': priority,
      'image': imageUrl.trim(),
      'imageUrl': imageUrl.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteCategory(String id) async {
    await _db.collection('categories').doc(id).delete();
  }

  static Future<void> toggleCategoryStatus(String id, bool status) async {
    await _db.collection('categories').doc(id).set({
      'isActive': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Product query helpers - PRO centralized layer
  // ---------------------------------------------------------------------------

  static Query<Map<String, dynamic>> _productsBaseQuery({
    bool onlyActive = true,
    bool onlyApproved = true,
    String? category,
    String? vendorId,
    bool? marketplaceOnly,
    bool? pharmacyOnly,
    bool? flashSaleOnly,
    bool? sponsoredOnly,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('products');

    if (category != null && category.trim().isNotEmpty) {
      query = query.where('category', isEqualTo: category.trim());
    }

    if (vendorId != null && vendorId.trim().isNotEmpty) {
      query = query.where('vendorId', isEqualTo: vendorId.trim());
    }

    if (onlyActive) {
      query = query.where('isActive', isEqualTo: true);
    }

    if (onlyApproved) {
      query = query.where('approvalStatus', isEqualTo: 'approved');
    }

    if (marketplaceOnly == true) {
      query = query.where('isMarketplace', isEqualTo: true);
    }

    if (pharmacyOnly == true) {
      query = query.where('vendorId', isEqualTo: 'super_admin');
    }

    if (flashSaleOnly == true) {
      query = query.where('isFlashSale', isEqualTo: true);
    }

    if (sponsoredOnly == true) {
      query = query.where('isSponsored', isEqualTo: true);
    }

    return query;
  }

  static Map<String, dynamic> _normalizeProductDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = ProductService.normalizeProductData(doc);
    data['id'] = doc.id;
    data['productId'] = doc.id;
    return data;
  }

  static List<Map<String, dynamic>> _normalizeAndSortProductDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
        String sortBy = 'newest',
        bool onlyInStock = false,
        bool marketplaceOnly = false,
        bool pharmacyOnly = false,
      }) {
    final products = docs.map(_normalizeProductDoc).where((product) {
      if (product['isActive'] == false) return false;

      final approval = ProductService.text(product['approvalStatus'], 'approved');
      if (approval != 'approved') return false;

      if (onlyInStock && ProductService.getStock(product) <= 0) return false;

      final vendorId = ProductService.text(product['vendorId'], 'super_admin');
      final isMarketplace = vendorId != 'super_admin' || product['isMarketplace'] == true;

      if (marketplaceOnly && !isMarketplace) return false;
      if (pharmacyOnly && isMarketplace) return false;

      return true;
    }).toList();

    products.sort((a, b) {
      switch (sortBy) {
        case 'price_low':
          return ProductService.getDisplayPrice(a)
              .compareTo(ProductService.getDisplayPrice(b));

        case 'price_high':
          return ProductService.getDisplayPrice(b)
              .compareTo(ProductService.getDisplayPrice(a));

        case 'stock':
          return ProductService.getStock(b).compareTo(ProductService.getStock(a));

        case 'name':
          return ProductService.text(a['name'])
              .toLowerCase()
              .compareTo(ProductService.text(b['name']).toLowerCase());

        case 'priority':
          final ap = ProductService.toInt(a['priority']);
          final bp = ProductService.toInt(b['priority']);
          if (ap != bp) return ap.compareTo(bp);
          return _dateOf(b).compareTo(_dateOf(a));

        case 'newest':
        default:
          return _dateOf(b).compareTo(_dateOf(a));
      }
    });

    return products;
  }

  static DateTime _dateOf(Map<String, dynamic> data) {
    final value = data['createdAt'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    return DateTime(2000);
  }

  /// Backward compatible old API.
  static Stream<QuerySnapshot> getProducts(
      String category, {
        bool onlyActive = true,
        int limit = 10,
      }) {
    return _productsBaseQuery(
      category: category,
      onlyActive: true,
      onlyApproved: true,
    ).limit(limit).snapshots();
  }

  /// Preferred normalized category products.
  static Stream<List<Map<String, dynamic>>> watchCategoryProducts({
    required String category,
    bool onlyActive = true,
    bool onlyApproved = true,
    bool onlyInStock = false,
    bool marketplaceOnly = false,
    bool pharmacyOnly = false,
    String sortBy = 'newest',
    int limit = 100,
  }) {
    return _productsBaseQuery(
      category: category,
      onlyActive: onlyActive,
      onlyApproved: onlyApproved,
    ).limit(limit).snapshots().map((snapshot) {
      return _normalizeAndSortProductDocs(
        snapshot.docs,
        sortBy: sortBy,
        onlyInStock: onlyInStock,
        marketplaceOnly: marketplaceOnly,
        pharmacyOnly: pharmacyOnly,
      );
    });
  }

  /// Backward compatible old API.
  static Stream<QuerySnapshot> getMarketplaceProducts({
    String? category,
    String? vendorId,
    bool onlyActive = true,
    int limit = 30,
  }) {
    return _productsBaseQuery(
      category: category,
      vendorId: vendorId,
      onlyActive: onlyActive,
      onlyApproved: onlyActive,
      marketplaceOnly: true,
    ).limit(limit).snapshots();
  }

  static Stream<List<Map<String, dynamic>>> watchMarketplaceProducts({
    String? category,
    String? vendorId,
    bool onlyActive = true,
    bool onlyApproved = true,
    int limit = 60,
    String sortBy = 'newest',
  }) {
    return _productsBaseQuery(
      category: category,
      vendorId: vendorId,
      onlyActive: onlyActive,
      onlyApproved: onlyApproved,
      marketplaceOnly: true,
    ).limit(limit).snapshots().map((snapshot) {
      return _normalizeAndSortProductDocs(
        snapshot.docs,
        sortBy: sortBy,
        marketplaceOnly: true,
      );
    });
  }

  static Stream<List<Map<String, dynamic>>> watchVendorProducts({
    required String vendorId,
    bool onlyActive = true,
    bool onlyApproved = true,
    int limit = 100,
    String sortBy = 'newest',
  }) {
    return _productsBaseQuery(
      vendorId: vendorId,
      onlyActive: onlyActive,
      onlyApproved: onlyApproved,
    ).limit(limit).snapshots().map((snapshot) {
      return _normalizeAndSortProductDocs(snapshot.docs, sortBy: sortBy);
    });
  }

  static Stream<QuerySnapshot> getFlashSaleProducts({int limit = 20}) {
    return _productsBaseQuery(
      onlyActive: true,
      onlyApproved: true,
      flashSaleOnly: true,
    ).limit(limit).snapshots();
  }

  static Stream<List<Map<String, dynamic>>> watchFlashSaleProducts({
    int limit = 20,
  }) {
    return _productsBaseQuery(
      onlyActive: true,
      onlyApproved: true,
      flashSaleOnly: true,
    ).limit(limit).snapshots().map((snapshot) {
      return _normalizeAndSortProductDocs(snapshot.docs, sortBy: 'priority');
    });
  }

  static Stream<QuerySnapshot> getSponsoredProducts({int limit = 20}) {
    return _productsBaseQuery(
      onlyActive: true,
      onlyApproved: true,
      sponsoredOnly: true,
    ).limit(limit).snapshots();
  }

  static Stream<List<Map<String, dynamic>>> watchSponsoredProducts({
    int limit = 20,
  }) {
    return _productsBaseQuery(
      onlyActive: true,
      onlyApproved: true,
      sponsoredOnly: true,
    ).limit(limit).snapshots().map((snapshot) {
      return _normalizeAndSortProductDocs(snapshot.docs, sortBy: 'priority');
    });
  }

  static Future<List<Map<String, dynamic>>> searchProducts({
    required String query,
    String? category,
    bool onlyActive = true,
    bool onlyApproved = true,
    int limit = 100,
  }) async {
    final q = query.trim().toLowerCase();

    final snapshot = await _productsBaseQuery(
      category: category,
      onlyActive: onlyActive,
      onlyApproved: onlyApproved,
    ).limit(limit).get();

    final products = _normalizeAndSortProductDocs(snapshot.docs);

    if (q.isEmpty) return products;

    return products.where((product) {
      final name = ProductService.text(product['name']).toLowerCase();
      final generic = ProductService.text(product['generic']).toLowerCase();
      final manufacturer = ProductService.text(product['manufacturer']).toLowerCase();
      final category = ProductService.text(product['category']).toLowerCase();
      final type = ProductService.text(product['type']).toLowerCase();
      final strength = ProductService.text(product['strength']).toLowerCase();

      return name.contains(q) ||
          generic.contains(q) ||
          manufacturer.contains(q) ||
          category.contains(q) ||
          type.contains(q) ||
          strength.contains(q);
    }).toList();
  }

  static Future<Map<String, dynamic>?> getProductById(String productId) async {
    final id = productId.trim();
    if (id.isEmpty) return null;

    final doc = await _db.collection('products').doc(id).get();
    if (!doc.exists) return null;

    final product = ProductService.normalizeProductData(doc);
    product['id'] = doc.id;
    product['productId'] = doc.id;
    return product;
  }

  static Future<void> toggleProductStatus(String id, bool status) async {
    await _db.collection('products').doc(id).set({
      'isActive': status,
      'isVisible': status,
      'isPublished': status,
      'showOnHome': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Banners
  // ---------------------------------------------------------------------------

  static Stream<QuerySnapshot> getBanners({bool onlyActive = false}) {
    Query query = _db.collection('banners');
    if (onlyActive) query = query.where('isActive', isEqualTo: true);
    return query.snapshots();
  }

  static Future<void> toggleBannerStatus(String id, bool status) async {
    await _db.collection('banners').doc(id).set({
      'isActive': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Vendors
  // ---------------------------------------------------------------------------

  static Stream<QuerySnapshot> getTopVendors({int limit = 20}) {
    return _db
        .collection('vendors')
        .where('isActive', isEqualTo: true)
        .limit(limit)
        .snapshots();
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  static Stream<QuerySnapshot> getOrders(String userId) {
    return _db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot> getVendorOrders(String vendorId) {
    return _db
        .collection('orders')
        .where('vendorIds', arrayContains: vendorId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> addOrder({
    required String? userId,
    required String userName,
    required double total,
    required String? addressId,
  }) async {
    await _db.collection('orders').add({
      'userId': userId,
      'userName': userName,
      'status': 'pending',
      'total': total,
      'addressId': addressId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Users / roles / tokens
  // ---------------------------------------------------------------------------

  static Future<bool> isAdmin(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final roles = List<String>.from(data['roles'] ?? []);
    return data['role'] == 'admin' ||
        data['role'] == 'superAdmin' ||
        roles.contains('admin');
  }

  static Future<bool> isVendor(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final userData = userDoc.data() ?? {};
    final roles = List<String>.from(userData['roles'] ?? []);

    if (userData['role'] == 'vendor' ||
        roles.contains('vendor') ||
        userData['sellerStatus'] == 'approved') {
      return true;
    }

    final vendorDoc = await _db.collection('vendors').doc(uid).get();
    final vendor = vendorDoc.data() ?? {};

    return vendor['status'] == 'approved' && vendor['isActive'] != false;
  }

  static Future<void> autoCreateUser(String uid) async {
    await _db.collection('users').doc(uid).set({
      'role': 'user',
      'roles': FieldValue.arrayUnion(['user']),
      'points': 0,
      'totalEarnings': 0,
      'referralCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> autoAdmin(String uid) async {
    await _db.collection('users').doc(uid).set({
      'role': 'admin',
      'roles': FieldValue.arrayUnion(['admin']),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveUserToken(String userId, String token) async {
    final cleanToken = token.trim();
    if (userId.trim().isEmpty || cleanToken.isEmpty) return;

    await _db.collection('users').doc(userId).set({
      'fcmToken': cleanToken,
      'fcmTokens': FieldValue.arrayUnion([cleanToken]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
