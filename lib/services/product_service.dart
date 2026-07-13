import 'package:cloud_firestore/cloud_firestore.dart';


/// Central product schema/service for ChalakChar Mart.
///
/// Goal:
/// - Admin product add/edit
/// - Vendor product add/edit
/// - CSV/JSON upload
/// - Product card/details
/// - Cart/checkout/order stock
///
/// সব জায়গায় same product schema + variant logic use করার জন্য।
class ProductService {
  ProductService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Basic converters
  // ---------------------------------------------------------------------------

  static String text(dynamic value, [String fallback = '']) {
    final result = (value ?? '').toString().trim();
    return result.isEmpty ? fallback : result;
  }

  static double toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static int toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static bool toBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final v = value.toString().trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return fallback;
  }

  static String safeId(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  // ---------------------------------------------------------------------------
  // Product normalize
  // ---------------------------------------------------------------------------

  /// New preferred name.
  static Map<String, dynamic> normalizeProductData(dynamic source) {
    return normalizeProduct(source);
  }

  /// Backward compatible name.
  static Map<String, dynamic> normalizeProduct(dynamic source) {
    final Map<String, dynamic> product = source is DocumentSnapshot
        ? Map<String, dynamic>.from(source.data() as Map<String, dynamic>? ?? {})
        : Map<String, dynamic>.from(source as Map<String, dynamic>? ?? {});

    if (source is DocumentSnapshot && text(product['id']).isEmpty) {
      product['id'] = source.id;
    }

    final variants = normalizeVariants(
      product['variants'],
      fallbackUnit: product['unit'] ?? product['variantName'],
      fallbackPrice: product['price'] ?? product['piecePrice'],
      fallbackMrp: product['oldPrice'] ?? product['mrp'],
      fallbackStock: product['stock'],
    );

    final first = variants.isNotEmpty
        ? variants.first
        : {
      'id': 'default',
      'name': text(product['unit'] ?? product['variantName'], 'Default'),
      'price': toDouble(product['price'] ?? product['piecePrice']),
      'mrp': toDouble(product['oldPrice'] ?? product['mrp'] ?? product['price']),
      'stock': toInt(product['stock']),
    };

    final totalStock = variants.fold<int>(0, (total, v) => total + toInt(v['stock']));
    final units = variants
        .map((v) => text(v['name'], 'Default'))
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();

    final vendorId = text(product['vendorId'] ?? product['sellerId'], 'super_admin');
    final vendorName = text(
      product['vendorName'] ?? product['shopName'],
      vendorId == 'super_admin' ? 'ChalakChar Mart' : 'Vendor',
    );

    return {
      ...product,
      'id': text(product['id'] ?? product['productId']),
      'productId': text(product['productId'] ?? product['id']),
      'name': text(product['name'], 'Product'),
      'category': text(product['category'], 'Other'),
      'generic': text(product['generic']),
      'manufacturer': text(product['manufacturer'] ?? product['brand']),
      'brand': text(product['brand'] ?? product['manufacturer']),
      'type': text(product['type']),
      'strength': text(product['strength']),
      'overview': text(product['overview'] ?? product['description']),
      'description': text(product['description'] ?? product['overview']),
      'image': text(product['image'] ?? product['imageUrl']),
      'imageUrl': text(product['imageUrl'] ?? product['image']),
      'images': normalizeImages(product['images'], product['image'] ?? product['imageUrl']),
      'videoUrl': text(product['videoUrl'] ?? product['youtubeUrl'] ?? product['youtubeLink'] ?? product['videoLink']),
      'youtubeUrl': text(product['youtubeUrl'] ?? product['videoUrl'] ?? product['youtubeLink'] ?? product['videoLink']),
      'youtubeVideoId': text(product['youtubeVideoId']),
      'videoThumbnailUrl': text(product['videoThumbnailUrl']),
      'videoDuration': text(product['videoDuration']),
      'hasVideo': text(product['videoUrl'] ?? product['youtubeUrl'] ?? product['youtubeLink'] ?? product['videoLink']).isNotEmpty || text(product['youtubeVideoId']).isNotEmpty,
      'isActive': product['isActive'] != false,
      'isMarketplace': product['isMarketplace'] == true || vendorId != 'super_admin',
      'vendorId': vendorId,
      'sellerId': vendorId,
      'vendorName': vendorName,
      'shopName': text(product['shopName'] ?? vendorName, vendorName),
      'approvalStatus': text(product['approvalStatus'], 'approved'),
      'price': toDouble(first['price']),
      'piecePrice': toDouble(first['price']),
      'oldPrice': toDouble(first['mrp']),
      'mrp': toDouble(first['mrp']),
      'unit': text(first['name'], 'Default'),
      'units': units.isEmpty ? [text(first['name'], 'Default')] : units,
      'stock': variants.isEmpty ? toInt(first['stock']) : totalStock,
      'variants': variants.isEmpty ? [first] : variants,
      'piecesPerStrip': toInt(product['piecesPerStrip'], 10),
      'metaTitle': text(product['metaTitle']),
      'metaDescription': text(product['metaDescription']),
      'searchKeywords': product['searchKeywords'] ?? [],
      'seoTags': product['seoTags'] ?? [],
      'facebookCaption': text(product['facebookCaption']),
      'whatsappCaption': text(product['whatsappCaption']),
      'banglaTitle': text(product['banglaTitle']),
      'banglaDescription': text(product['banglaDescription']),
      'suggestedCategory': text(product['suggestedCategory']),
      'suggestedSubCategory': text(product['suggestedSubCategory']),
      'productType': text(product['productType']),
    };
  }




  static List<String> normalizeImages(dynamic rawImages, dynamic mainImage) {
    final images = <String>[];

    if (rawImages is List) {
      for (final item in rawImages) {
        final url = text(item);
        if (url.isNotEmpty && !images.contains(url)) images.add(url);
      }
    }

    final main = text(mainImage);
    if (main.isNotEmpty && !images.contains(main)) {
      images.insert(0, main);
    }

    return images;
  }

  static List<Map<String, dynamic>> normalizeVariants(
      dynamic raw, {
        dynamic fallbackUnit,
        dynamic fallbackPrice,
        dynamic fallbackMrp,
        dynamic fallbackStock,
      }) {
    final result = <Map<String, dynamic>>[];

    if (raw is List && raw.isNotEmpty) {
      final seen = <String>{};

      for (int i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;

        final id = text(item['id'] ?? item['variantId'], 'v_$i');
        final name = text(item['name'] ?? item['unit'] ?? item['variantName'], 'Default');
        final key = name.toLowerCase();

        if (seen.contains(key)) continue;
        seen.add(key);

        final price = toDouble(item['price'] ?? item['piecePrice'] ?? fallbackPrice);
        final mrp = toDouble(item['mrp'] ?? item['oldPrice'] ?? fallbackMrp ?? price);

        result.add({
          'id': id,
          'variantId': id,
          'name': name,
          'unit': name,
          'variantName': name,
          'price': price,
          'piecePrice': price,
          'mrp': mrp,
          'oldPrice': mrp,
          'stock': toInt(item['stock'] ?? fallbackStock),
        });
      }
    }

    if (result.isEmpty) {
      final price = toDouble(fallbackPrice);
      final mrp = toDouble(fallbackMrp ?? fallbackPrice);
      final name = text(fallbackUnit, 'Default');

      result.add({
        'id': 'default',
        'variantId': 'default',
        'name': name,
        'unit': name,
        'variantName': name,
        'price': price,
        'piecePrice': price,
        'mrp': mrp,
        'oldPrice': mrp,
        'stock': toInt(fallbackStock),
      });
    }

    return result;
  }

  static String productIdFrom(dynamic source) {
    final product = normalizeProductData(source);

    final productId = text(product['productId']);
    if (productId.isNotEmpty) return productId;

    final id = text(product['id']);
    if (id.isNotEmpty) return id;

    return safeId(text(product['name'], 'product'));
  }

  // ---------------------------------------------------------------------------
  // Display helpers
  // ---------------------------------------------------------------------------

  /// New preferred method.
  static double getDisplayPrice(Map<String, dynamic> product, {String? unit}) {
    final normalized = normalizeProductData(product);
    final variant = unit == null || unit.trim().isEmpty
        ? firstVariant(normalized)
        : selectedVariant(normalized, unit);
    return toDouble(variant['price'] ?? normalized['price']);
  }

  static double getDisplayMrp(Map<String, dynamic> product, {String? unit}) {
    final normalized = normalizeProductData(product);
    final variant = unit == null || unit.trim().isEmpty
        ? firstVariant(normalized)
        : selectedVariant(normalized, unit);
    return toDouble(variant['mrp'] ?? variant['oldPrice'] ?? normalized['oldPrice'] ?? getDisplayPrice(product, unit: unit));
  }

  /// New preferred method.
  static int getStock(Map<String, dynamic> product, {String? unit, String? variantId}) {
    final normalized = normalizeProductData(product);

    if (variantId != null && variantId.trim().isNotEmpty) {
      final variant = selectedVariantById(normalized, variantId);
      if (variant != null) return toInt(variant['stock']);
    }

    if (unit != null && unit.trim().isNotEmpty) {
      return getVariantStock(normalized, unit);
    }

    return toInt(normalized['stock']);
  }

  static bool isOutOfStock(Map<String, dynamic> product, {String? unit, String? variantId}) {
    return getStock(product, unit: unit, variantId: variantId) <= 0;
  }

  static List<String> getUnits(Map<String, dynamic> product) {
    final normalized = normalizeProductData(product);
    final rawUnits = normalized['units'];

    if (rawUnits is List && rawUnits.isNotEmpty) {
      return rawUnits.map((e) => text(e)).where((e) => e.isNotEmpty).toList();
    }

    final variants = normalized['variants'];
    if (variants is List && variants.isNotEmpty) {
      return variants
          .whereType<Map>()
          .map((e) => text(e['name']))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [text(normalized['unit'], 'Default')];
  }

  static Map<String, dynamic> firstVariant(Map<String, dynamic> product) {
    final normalized = normalizeProductData(product);
    final variants = normalized['variants'];

    if (variants is List && variants.isNotEmpty && variants.first is Map) {
      return Map<String, dynamic>.from(variants.first as Map);
    }

    return {
      'id': 'default',
      'variantId': 'default',
      'name': text(normalized['unit'], 'Default'),
      'unit': text(normalized['unit'], 'Default'),
      'price': normalized['price'] ?? 0,
      'mrp': normalized['oldPrice'] ?? normalized['mrp'] ?? normalized['price'] ?? 0,
      'oldPrice': normalized['oldPrice'] ?? normalized['mrp'] ?? normalized['price'] ?? 0,
      'stock': normalized['stock'] ?? 0,
    };
  }

  static Map<String, dynamic> selectedVariant(
      Map<String, dynamic> product,
      String unit,
      ) {
    final normalized = normalizeProductData(product);
    final variants = normalized['variants'];

    if (variants is List) {
      for (final v in variants) {
        if (v is Map && text(v['name']).toLowerCase() == unit.toLowerCase()) {
          return Map<String, dynamic>.from(v);
        }
      }

      for (final v in variants) {
        if (v is Map && text(v['unit']).toLowerCase() == unit.toLowerCase()) {
          return Map<String, dynamic>.from(v);
        }
      }

      for (final v in variants) {
        if (v is Map && text(v['variantName']).toLowerCase() == unit.toLowerCase()) {
          return Map<String, dynamic>.from(v);
        }
      }
    }

    return firstVariant(normalized);
  }

  static Map<String, dynamic>? selectedVariantById(
      Map<String, dynamic> product,
      String variantId,
      ) {
    final normalized = normalizeProductData(product);
    final variants = normalized['variants'];

    if (variants is List) {
      for (final v in variants) {
        if (v is Map &&
            (text(v['id']) == variantId || text(v['variantId']) == variantId)) {
          return Map<String, dynamic>.from(v);
        }
      }
    }

    return null;
  }

  static int getVariantStock(Map<String, dynamic> product, String unit) {
    final variant = selectedVariant(product, unit);
    return toInt(variant['stock'] ?? product['stock']);
  }

  // ---------------------------------------------------------------------------
  // Product payload for admin/vendor/CSV/JSON
  // ---------------------------------------------------------------------------

  static String? validateVariants(List<Map<String, dynamic>> variants) {
    if (variants.isEmpty) return 'At least one variant required';

    final seen = <String>{};

    for (final v in variants) {
      final name = text(v['name'] ?? v['unit'] ?? v['variantName']);
      final key = name.toLowerCase();

      if (name.isEmpty) return 'Variant name required';
      if (seen.contains(key)) return 'Duplicate variant: $name';

      final price = toDouble(v['price'] ?? v['piecePrice']);
      final mrp = toDouble(v['mrp'] ?? v['oldPrice'] ?? price);
      final stock = toInt(v['stock']);

      if (price <= 0) return 'Price must be greater than 0 for $name';
      if (mrp < 0) return 'MRP cannot be negative for $name';
      if (stock < 0) return 'Stock cannot be negative for $name';

      seen.add(key);
    }

    return null;
  }

  static Map<String, dynamic> buildProductPayload({
    required String name,
    required String category,
    String generic = '',
    String manufacturer = '',
    String type = '',
    String strength = '',
    String overview = '',
    String image = '',
    List<String> images = const [],
    String videoUrl = '',
    String youtubeVideoId = '',
    String videoThumbnailUrl = '',
    String videoDuration = '',
    bool isActive = true,
    bool isMarketplace = false,
    String vendorId = 'super_admin',
    String vendorName = 'ChalakChar Mart',
    String approvalStatus = 'approved',
    required List<Map<String, dynamic>> variants,
    bool includeCreatedAt = false,
  }) {
    final cleanVariants = normalizeVariants(variants);
    final error = validateVariants(cleanVariants);
    if (error != null) throw Exception(error);

    final first = cleanVariants.first;
    final totalStock = cleanVariants.fold<int>(0, (total, v) => total + toInt(v['stock']));
    final cleanImages = normalizeImages(images, image);

    final cleanVendorId = text(vendorId, 'super_admin');
    final cleanVendorName = text(
      vendorName,
      cleanVendorId == 'super_admin' ? 'ChalakChar Mart' : 'Vendor',
    );

    final payload = <String, dynamic>{
      'name': text(name),
      'slug': safeId(name),
      'generic': text(generic),
      'manufacturer': text(manufacturer),
      'brand': text(manufacturer),
      'type': text(type),
      'strength': text(strength),
      'overview': text(overview),
      'description': text(overview),
      'category': text(category, 'Other'),
      'image': cleanImages.isNotEmpty ? cleanImages.first : text(image),
      'imageUrl': cleanImages.isNotEmpty ? cleanImages.first : text(image),
      'images': cleanImages,
      'videoUrl': text(videoUrl),
      'youtubeUrl': text(videoUrl),
      'youtubeVideoId': text(youtubeVideoId),
      'videoThumbnailUrl': text(videoThumbnailUrl),
      'videoDuration': text(videoDuration),
      'hasVideo': text(videoUrl).isNotEmpty || text(youtubeVideoId).isNotEmpty,
      'isActive': isActive,
      'isVisible': isActive,
      'isPublished': isActive,
      'showOnHome': isActive,
      'isMarketplace': isMarketplace || cleanVendorId != 'super_admin',
      'vendorId': cleanVendorId,
      'sellerId': cleanVendorId,
      'vendorName': cleanVendorName,
      'shopName': cleanVendorName,
      'approvalStatus': text(approvalStatus, 'approved'),
      'price': toDouble(first['price']),
      'piecePrice': toDouble(first['price']),
      'oldPrice': toDouble(first['mrp']),
      'mrp': toDouble(first['mrp']),
      'unit': text(first['name'], 'Default'),
      'units': cleanVariants.map((v) => text(v['name'], 'Default')).toList(),
      'stock': totalStock,
      'variants': cleanVariants,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (includeCreatedAt) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    return payload;
  }

  static Future<String> saveProduct({
    String? productId,
    required Map<String, dynamic> payload,
  }) async {
    if (productId == null || productId.trim().isEmpty) {
      final doc = await _db.collection('products').add({
        ...payload,
        'createdAt': payload['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    }

    await _db.collection('products').doc(productId).set({
      ...payload,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return productId;
  }

  // ---------------------------------------------------------------------------
  // Cart item payload
  // ---------------------------------------------------------------------------

  /// New preferred method.
  static Map<String, dynamic> buildCartItem(
      Map<String, dynamic> product,
      Map<String, dynamic> variantData, {
        int qty = 1,
      }) {
    final normalized = normalizeProductData(product);
    final variant = Map<String, dynamic>.from(variantData);
    final selectedUnit = text(
      variant['name'] ?? variant['unit'] ?? variant['variantName'],
      text(normalized['unit'], 'Default'),
    );

    final resolvedVariant = selectedVariant(normalized, selectedUnit);

    return _buildCartPayloadFromVariant(
      normalized: normalized,
      variant: resolvedVariant,
      qty: qty,
    );
  }

  /// Backward compatible method.
  static Map<String, dynamic> buildCartItemPayload({
    required Map<String, dynamic> product,
    required String unit,
    int qty = 1,
  }) {
    final normalized = normalizeProductData(product);
    final variant = selectedVariant(normalized, unit);

    return _buildCartPayloadFromVariant(
      normalized: normalized,
      variant: variant,
      qty: qty,
    );
  }

  static Map<String, dynamic> _buildCartPayloadFromVariant({
    required Map<String, dynamic> normalized,
    required Map<String, dynamic> variant,
    required int qty,
  }) {
    final productId = productIdFrom(normalized);
    final vendorId = text(normalized['vendorId'], 'super_admin');
    final vendorName = text(
      normalized['vendorName'],
      vendorId == 'super_admin' ? 'ChalakChar Mart' : 'Vendor',
    );

    final selectedUnit = text(variant['name'] ?? variant['unit'] ?? variant['variantName'], 'Default');
    final price = toDouble(variant['price'] ?? normalized['price']);
    final oldPrice = toDouble(variant['mrp'] ?? variant['oldPrice'] ?? normalized['oldPrice'] ?? price);
    final stock = toInt(variant['stock'] ?? normalized['stock']);

    return {
      'productId': productId,
      'vendorId': vendorId,
      'vendorName': vendorName,
      'isMarketplace': vendorId != 'super_admin',
      'name': text(normalized['name'], 'Product'),
      'price': price,
      'oldPrice': oldPrice < price ? price : oldPrice,
      'qty': qty,
      'unit': selectedUnit,
      'variantId': text(variant['id'] ?? variant['variantId'], 'default'),
      'units': getUnits(normalized),
      'image': text(normalized['image']),
      'images': normalized['images'] ?? [],
      'strength': text(normalized['strength']),
      'manufacturer': text(normalized['manufacturer']),
      'category': text(normalized['category']),
      'generic': text(normalized['generic']),
      'stockAtAddTime': stock,
      'stock': stock,
      'piecesPerStrip': toInt(normalized['piecesPerStrip'], 10),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String cartDocId({
    required String productId,
    required String vendorId,
    required String unit,
  }) {
    return safeId('${productId}_${vendorId}_$unit');
  }

  // ---------------------------------------------------------------------------
  // Stock helpers
  // ---------------------------------------------------------------------------

  static String stockKey(String productId, String unit) {
    return '${productId.trim()}__${unit.trim().toLowerCase()}';
  }

  /// New preferred stock reduction method.
  ///
  /// variantId can be:
  /// - variant id / variantId
  /// - unit name
  /// - empty/default
  ///
  /// qty positive means reduce stock.
  static Future<void> reduceStock(
      String productId,
      String variantId,
      int qty,
      ) async {
    if (productId.trim().isEmpty || qty <= 0) return;

    await _db.runTransaction((transaction) async {
      final productRef = _db.collection('products').doc(productId);
      final snap = await transaction.get(productRef);

      if (!snap.exists) {
        throw Exception('Product not found');
      }

      final data = snap.data() ?? {};
      final variants = normalizeVariants(
        data['variants'],
        fallbackUnit: data['unit'],
        fallbackPrice: data['price'],
        fallbackMrp: data['oldPrice'] ?? data['mrp'],
        fallbackStock: data['stock'],
      );

      bool found = false;

      for (int i = 0; i < variants.length; i++) {
        final v = variants[i];
        final idMatch = variantId.trim().isNotEmpty &&
            (text(v['id']) == variantId || text(v['variantId']) == variantId);
        final unitMatch = variantId.trim().isNotEmpty &&
            text(v['name']).toLowerCase() == variantId.toLowerCase();

        if (variantId.trim().isEmpty || idMatch || unitMatch) {
          final currentStock = toInt(v['stock']);
          if (currentStock < qty) {
            throw Exception('Insufficient stock for ${text(v['name'], 'variant')}');
          }
          v['stock'] = currentStock - qty;
          found = true;
          break;
        }
      }

      if (!found && variants.isNotEmpty) {
        final currentStock = toInt(variants.first['stock']);
        if (currentStock < qty) {
          throw Exception('Insufficient stock');
        }
        variants.first['stock'] = currentStock - qty;
      }

      final totalStock = variants.fold<int>(0, (total, v) => total + toInt(v['stock']));
      final first = variants.first;

      transaction.set(productRef, {
        'variants': variants,
        'units': variants.map((v) => text(v['name'], 'Default')).toList(),
        'stock': totalStock,
        'price': toDouble(first['price']),
        'piecePrice': toDouble(first['price']),
        'oldPrice': toDouble(first['mrp']),
        'mrp': toDouble(first['mrp']),
        'unit': text(first['name'], 'Default'),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// delta positive = restore stock, delta negative = reduce stock.
  static Future<void> applyStockDelta({
    required WriteBatch batch,
    required String productId,
    required String unit,
    required int delta,
  }) async {
    if (productId.trim().isEmpty || delta == 0) return;

    final productRef = _db.collection('products').doc(productId);
    final snap = await productRef.get();

    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final variants = normalizeVariants(
      data['variants'],
      fallbackUnit: data['unit'],
      fallbackPrice: data['price'],
      fallbackMrp: data['oldPrice'] ?? data['mrp'],
      fallbackStock: data['stock'],
    );

    bool found = false;

    for (int i = 0; i < variants.length; i++) {
      final v = variants[i];
      if (unit.trim().isEmpty || text(v['name']).toLowerCase() == unit.toLowerCase()) {
        final newStock = toInt(v['stock']) + delta;
        v['stock'] = newStock < 0 ? 0 : newStock;
        found = true;
        break;
      }
    }

    if (!found && variants.isNotEmpty) {
      final newStock = toInt(variants.first['stock']) + delta;
      variants.first['stock'] = newStock < 0 ? 0 : newStock;
    }

    final totalStock = variants.fold<int>(0, (total, v) => total + toInt(v['stock']));
    final first = variants.first;

    batch.set(productRef, {
      'variants': variants,
      'units': variants.map((v) => text(v['name'], 'Default')).toList(),
      'stock': totalStock,
      'price': toDouble(first['price']),
      'piecePrice': toDouble(first['price']),
      'oldPrice': toDouble(first['mrp']),
      'mrp': toDouble(first['mrp']),
      'unit': text(first['name'], 'Default'),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, Map<String, dynamic>> buildStockMapFromItems(
      List<Map<String, dynamic>> items,
      ) {
    final result = <String, Map<String, dynamic>>{};

    for (final item in items) {
      final productId = text(item['productId']);
      if (productId.isEmpty) continue;

      final unit = text(item['unit'] ?? item['variantName']);
      final qty = toInt(item['qty']);
      if (qty <= 0) continue;

      final key = stockKey(productId, unit);

      result.putIfAbsent(key, () {
        return {
          'productId': productId,
          'unit': unit,
          'qty': 0,
        };
      });

      result[key]!['qty'] = toInt(result[key]!['qty']) + qty;
    }

    return result;
  }

  static Map<String, Map<String, dynamic>> buildStockMapFromReducedItems(
      dynamic raw,
      ) {
    if (raw is! List) return {};

    return buildStockMapFromItems(
      raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  static List<Map<String, dynamic>> stockMapToList(
      Map<String, Map<String, dynamic>> map,
      ) {
    return map.values
        .map((e) => {
      'productId': e['productId'],
      'unit': e['unit'],
      'qty': toInt(e['qty']),
    })
        .toList();
  }

  /// Order edit stock sync:
  /// - old qty > new qty => stock restore
  /// - new qty > old qty => stock reduce
  static Future<void> syncStockForOrderEdit({
    required dynamic previousReducedItems,
    required List<Map<String, dynamic>> currentItems,
  }) async {
    final oldMap = buildStockMapFromReducedItems(previousReducedItems);
    final newMap = buildStockMapFromItems(currentItems);

    final keys = <String>{...oldMap.keys, ...newMap.keys};
    final batch = _db.batch();

    for (final key in keys) {
      final oldQty = toInt(oldMap[key]?['qty']);
      final newQty = toInt(newMap[key]?['qty']);

      final delta = oldQty - newQty;
      if (delta == 0) continue;

      final productId = text(newMap[key]?['productId'] ?? oldMap[key]?['productId']);
      final unit = text(newMap[key]?['unit'] ?? oldMap[key]?['unit']);

      await applyStockDelta(
        batch: batch,
        productId: productId,
        unit: unit,
        delta: delta,
      );
    }

    await batch.commit();
  }

  static Future<bool> hasEnoughStock({
    required String productId,
    required String unit,
    required int qty,
  }) async {
    final doc = await _db.collection('products').doc(productId).get();
    if (!doc.exists) return false;

    final product = normalizeProductData(doc);
    if (product['isActive'] == false) return false;

    final stock = getVariantStock(product, unit);
    return qty <= stock;
  }

  /// Atomic stock validation + reduce helper for checkout.
  ///
  /// Pass cart/order items containing productId, unit/variantId, qty.
  static Future<void> reduceStockForItems(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final productId = text(item['productId']);
      final variantId = text(item['variantId'] ?? item['unit'] ?? item['variantName']);
      final qty = toInt(item['qty'], 1);
      if (productId.isEmpty || qty <= 0) continue;
      await reduceStock(productId, variantId, qty);
    }
  }
}
