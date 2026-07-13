import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'product_service.dart';

class GuestCartService {
  GuestCartService._();

  static const String _key = 'guest_cart_items_v2';

  /// CartBadge listens to this notifier so guest count updates immediately.
  static final ValueNotifier<int> cartCount = ValueNotifier<int>(0);

  static Future<List<Map<String, dynamic>>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];

      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> refreshCount() async {
    final items = await getItems();
    cartCount.value = items.fold<int>(
      0,
          (total, item) => total + ProductService.toInt(item['qty'], 1),
    );
  }

  static Future<void> addItem(Map<String, dynamic> cartPayload) async {
    final items = await getItems();
    final cleanPayload = _jsonSafeCartPayload(cartPayload);

    final id = ProductService.cartDocId(
      productId: ProductService.text(cleanPayload['productId']),
      vendorId: ProductService.text(cleanPayload['vendorId'], 'super_admin'),
      unit: ProductService.text(cleanPayload['unit'], 'Default'),
    );

    final index = items.indexWhere((item) => item['id'] == id);

    if (index >= 0) {
      final oldQty = ProductService.toInt(items[index]['qty'], 1);
      final stock = ProductService.toInt(items[index]['stock'], 999999);
      final nextQty = oldQty + ProductService.toInt(cleanPayload['qty'], 1);

      items[index] = {
        ...items[index],
        ...cleanPayload,
        'id': id,
        'qty': nextQty > stock ? stock : nextQty,
        'updatedAtLocal': DateTime.now().toIso8601String(),
      };
    } else {
      items.add({
        ...cleanPayload,
        'id': id,
        'qty': ProductService.toInt(cleanPayload['qty'], 1),
        'createdAtLocal': DateTime.now().toIso8601String(),
        'updatedAtLocal': DateTime.now().toIso8601String(),
      });
    }

    await _save(items);
  }

  static Future<void> updateQty(String itemId, int qty) async {
    final items = await getItems();
    final index = items.indexWhere((item) => item['id'] == itemId);
    if (index < 0) return;

    if (qty <= 0) {
      items.removeAt(index);
    } else {
      final stock = ProductService.toInt(items[index]['stock'], 999999);
      items[index]['qty'] = qty > stock ? stock : qty;
      items[index]['updatedAtLocal'] = DateTime.now().toIso8601String();
    }

    await _save(items);
  }

  static Future<void> removeItem(String itemId) async {
    final items = await getItems();
    items.removeWhere((item) => item['id'] == itemId);
    await _save(items);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await refreshCount();
  }

  /// Merge guest cart into the signed-in user's Firestore cart.
  /// Call this after login or when CartPage opens with a logged-in user.
  static Future<void> mergeToUserCart(String userId) async {
    if (userId.trim().isEmpty) return;

    final items = await getItems();
    if (items.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    for (final item in items) {
      final productId = ProductService.text(item['productId']);
      final vendorId = ProductService.text(item['vendorId'], 'super_admin');
      final unit = ProductService.text(item['unit'], 'Default');

      if (productId.isEmpty) continue;

      final docId = ProductService.cartDocId(
        productId: productId,
        vendorId: vendorId,
        unit: unit,
      );

      final ref = db
          .collection('cart')
          .doc(userId)
          .collection('items')
          .doc(docId);

      final payload = Map<String, dynamic>.from(item)
        ..remove('id')
        ..remove('createdAtLocal')
        ..remove('updatedAtLocal');

      batch.set(
        ref,
        {
          ...payload,
          'qty': FieldValue.increment(ProductService.toInt(item['qty'], 1)),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    await clear();
  }

  static Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
    await refreshCount();
  }

  static Map<String, dynamic> _jsonSafeCartPayload(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};

    payload.forEach((key, value) {
      if (value == null) return;

      // FieldValue.serverTimestamp() cannot be JSON encoded.
      if (value is FieldValue) return;

      if (value is String || value is num || value is bool) {
        result[key] = value;
      } else if (value is List) {
        result[key] = value
            .where((e) => e == null || e is String || e is num || e is bool)
            .toList();
      } else if (value is Map) {
        result[key] = Map<String, dynamic>.from(value);
      } else {
        result[key] = value.toString();
      }
    });

    return result;
  }
}
