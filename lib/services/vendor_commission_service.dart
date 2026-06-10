import 'package:cloud_firestore/cloud_firestore.dart';

class VendorCommissionService {
  VendorCommissionService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static int _toInt(dynamic v, [int fallback = 1]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static bool _isRealVendor(String vendorId) {
    final id = vendorId.trim();
    return id.isNotEmpty && id != 'super_admin';
  }

  static Future<Map<String, dynamic>> getVendorCommission(String vendorId) async {
    if (!_isRealVendor(vendorId)) {
      return {'percent': 0.0, 'vendor': null};
    }

    final doc = await _db.collection('vendors').doc(vendorId).get();
    final data = doc.data();

    final percent = _toDouble(
      data?['commissionPercent'] ?? data?['commissionRate'],
      10,
    );

    return {
      'percent': percent,
      'vendor': data,
    };
  }

  static Future<void> createOrderCommissionLedger({
    required String orderId,
    required List items,
  }) async {
    if (orderId.trim().isEmpty) return;

    final Map<String, double> vendorSubtotal = {};
    final Map<String, int> vendorItemCount = {};

    for (final item in items) {
      if (item is! Map) continue;

      final vendorId = (item['vendorId'] ?? '').toString().trim();
      if (!_isRealVendor(vendorId)) continue;

      final price = _toDouble(item['price']);
      final qty = _toInt(item['qty'], 1);

      vendorSubtotal[vendorId] = (vendorSubtotal[vendorId] ?? 0) + (price * qty);
      vendorItemCount[vendorId] = (vendorItemCount[vendorId] ?? 0) + qty;
    }

    if (vendorSubtotal.isEmpty) return;

    final batch = _db.batch();

    for (final entry in vendorSubtotal.entries) {
      final vendorId = entry.key;
      final subtotal = entry.value;

      final ledgerRef = _db
          .collection('vendors')
          .doc(vendorId)
          .collection('commissionLedger')
          .doc(orderId);

      final oldLedger = await ledgerRef.get();
      if (oldLedger.exists) continue;

      final commissionInfo = await getVendorCommission(vendorId);
      final percent = _toDouble(commissionInfo['percent'], 10);

      final adminCommission = subtotal * percent / 100;
      final vendorPayable = subtotal - adminCommission;

      batch.set(ledgerRef, {
        'orderId': orderId,
        'vendorId': vendorId,
        'subtotal': subtotal,
        'itemCount': vendorItemCount[vendorId] ?? 0,
        'commissionPercent': percent,
        'adminCommission': adminCommission,
        'vendorPayable': vendorPayable,
        'status': 'pending',
        'withdrawStatus': 'not_requested',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final vendorRef = _db.collection('vendors').doc(vendorId);

      batch.set(vendorRef, {
        'totalSales': FieldValue.increment(subtotal),
        'totalCommission': FieldValue.increment(adminCommission),
        'pendingBalance': FieldValue.increment(vendorPayable),
        'totalOrders': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  static Future<void> markOrderDelivered({
    required String orderId,
  }) async {
    if (orderId.trim().isEmpty) return;

    final orderDoc = await _db.collection('orders').doc(orderId).get();
    final order = orderDoc.data() ?? {};
    final vendorIds = order['vendorIds'] is List
        ? List<String>.from(order['vendorIds'].map((e) => e.toString()))
        : <String>[];

    if (vendorIds.isEmpty) return;

    final batch = _db.batch();

    for (final vendorId in vendorIds) {
      if (!_isRealVendor(vendorId)) continue;

      final ledgerRef = _db
          .collection('vendors')
          .doc(vendorId)
          .collection('commissionLedger')
          .doc(orderId);

      final ledgerDoc = await ledgerRef.get();
      if (!ledgerDoc.exists) continue;

      final ledger = ledgerDoc.data() ?? {};
      final status = (ledger['status'] ?? '').toString();

      if (status == 'delivered' || status == 'cancelled') continue;

      final vendorPayable = _toDouble(ledger['vendorPayable']);

      batch.set(ledgerRef, {
        'status': 'delivered',
        'deliveredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(_db.collection('vendors').doc(vendorId), {
        'pendingBalance': FieldValue.increment(-vendorPayable),
        'withdrawableBalance': FieldValue.increment(vendorPayable),
        'deliveredOrders': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  static Future<void> markOrderCancelled({
    required String orderId,
  }) async {
    if (orderId.trim().isEmpty) return;

    final orderDoc = await _db.collection('orders').doc(orderId).get();
    final order = orderDoc.data() ?? {};
    final vendorIds = order['vendorIds'] is List
        ? List<String>.from(order['vendorIds'].map((e) => e.toString()))
        : <String>[];

    if (vendorIds.isEmpty) return;

    final batch = _db.batch();

    for (final vendorId in vendorIds) {
      if (!_isRealVendor(vendorId)) continue;

      final ledgerRef = _db
          .collection('vendors')
          .doc(vendorId)
          .collection('commissionLedger')
          .doc(orderId);

      final ledgerDoc = await ledgerRef.get();
      if (!ledgerDoc.exists) continue;

      final ledger = ledgerDoc.data() ?? {};
      final status = (ledger['status'] ?? '').toString();

      if (status == 'cancelled') continue;

      final vendorPayable = _toDouble(ledger['vendorPayable']);
      final subtotal = _toDouble(ledger['subtotal']);
      final adminCommission = _toDouble(ledger['adminCommission']);

      batch.set(ledgerRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (status == 'delivered') {
        batch.set(_db.collection('vendors').doc(vendorId), {
          'withdrawableBalance': FieldValue.increment(-vendorPayable),
          'totalSales': FieldValue.increment(-subtotal),
          'totalCommission': FieldValue.increment(-adminCommission),
          'cancelledOrders': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        batch.set(_db.collection('vendors').doc(vendorId), {
          'pendingBalance': FieldValue.increment(-vendorPayable),
          'totalSales': FieldValue.increment(-subtotal),
          'totalCommission': FieldValue.increment(-adminCommission),
          'cancelledOrders': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }
}