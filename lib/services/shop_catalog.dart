import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../utils/shop_visibility.dart';
import 'category_service.dart';

/// Every product the shop shows, from one Firestore listener shared by the
/// whole app session (the header search suggestions search all of it).
///
/// The query is the home "সব প্রোডাক্ট" grid's own (isActive, approved,
/// category in the switched-on list, limit 300), so while the home page is
/// open both share one listener. After the first full read only changed
/// products are read again. The category list comes from
/// CategoryService.activeCategoryNames (10-minute cache); when it changes the
/// listener is replaced on the next subscription.
class ShopCatalog {
  ShopCatalog._();

  static final StreamController<ShopCatalogData> _updates =
      StreamController<ShopCatalogData>.broadcast();
  static ShopCatalogData? _latest;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static List<String>? _names;
  static Future<void>? _starting;

  /// The current catalog first (when there is one), then every change.
  static Stream<ShopCatalogData> watch() {
    StreamSubscription<ShopCatalogData>? relay;
    late final StreamController<ShopCatalogData> out;
    out = StreamController<ShopCatalogData>(
      onListen: () {
        // Subscribe before starting, so the first snapshot is never missed.
        relay = _updates.stream.listen(out.add, onError: out.addError);
        final latest = _latest;
        if (latest != null) out.add(latest);
        _ensureListening().catchError((Object e) => out.addError(e));
      },
      onCancel: () => relay?.cancel(),
    );
    return out.stream;
  }

  static Future<void> _ensureListening() {
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  static Future<void> _start() async {
    final names = await CategoryService.activeCategoryNames();
    if (_sub != null && listEquals(names, _names)) return;

    await _sub?.cancel();
    _sub = null;
    _names = names;
    final active = {for (final n in names) n.toLowerCase()};
    if (names.isEmpty) {
      _emit(ShopCatalogData(const [], active));
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('products')
        .where('isActive', isEqualTo: true)
        .where('approvalStatus', isEqualTo: 'approved')
        .where('category', whereIn: names.take(30).toList())
        .limit(300)
        .snapshots()
        .listen(
      (snap) => _emit(ShopCatalogData(
        shopVisibleOnly(
          [for (final d in snap.docs) {...d.data(), 'id': d.id}],
          active,
          (p) => p,
        ),
        active,
      )),
      onError: (Object e) {
        // Dropped, so the next subscriber starts a fresh listener.
        _sub = null;
        _names = null;
        _updates.addError(e);
      },
    );
  }

  static void _emit(ShopCatalogData data) {
    _latest = data;
    _updates.add(data);
  }
}

/// Shop-visible products (each map carries its `id`) and the lower-cased
/// switched-on category names they were checked against.
class ShopCatalogData {
  const ShopCatalogData(this.products, this.activeCategoriesLower);

  final List<Map<String, dynamic>> products;
  final Set<String> activeCategoriesLower;
}
