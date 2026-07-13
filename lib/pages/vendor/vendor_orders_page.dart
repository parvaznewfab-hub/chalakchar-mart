import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VendorOrdersPage extends StatefulWidget {
  const VendorOrdersPage({super.key});

  @override
  State<VendorOrdersPage> createState() => _VendorOrdersPageState();
}

class _VendorOrdersPageState extends State<VendorOrdersPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String statusFilter = 'all';
  String _vendorId = '';
  bool _loadingVendor = true;

  String get vendorId => _vendorId;

  @override
  void initState() {
    super.initState();
    _resolveVendorId();
  }

  Future<void> _resolveVendorId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loadingVendor = false);
      return;
    }

    String resolved = '';

    try {
      final userDoc = await db.collection('users').doc(user.uid).get();
      final userVendorId = _text(userDoc.data()?['vendorId']);

      if (userVendorId.isNotEmpty) {
        final vendorDoc = await db.collection('vendors').doc(userVendorId).get();
        final vendor = vendorDoc.data() ?? <String, dynamic>{};
        final ownerId = _text(vendor['ownerId'] ?? vendor['userId']);
        if (vendorDoc.exists && ownerId == user.uid) {
          resolved = userVendorId;
        }
      }

      if (resolved.isEmpty) {
        final directDoc = await db.collection('vendors').doc(user.uid).get();
        if (directDoc.exists) {
          final vendor = directDoc.data() ?? <String, dynamic>{};
          final ownerId = _text(vendor['ownerId'] ?? vendor['userId'], user.uid);
          if (ownerId == user.uid) resolved = directDoc.id;
        }
      }

      if (resolved.isEmpty) {
        final q = await db.collection('vendors').where('ownerId', isEqualTo: user.uid).limit(1).get();
        if (q.docs.isNotEmpty) resolved = q.docs.first.id;
      }
    } catch (e) {
      debugPrint('Vendor resolve failed: $e');
    }

    debugPrint('==============================');
    debugPrint('Firebase UID: ${user.uid}');
    debugPrint('Resolved Vendor ID: $resolved');
    debugPrint('==============================');

    if (!mounted) return;

    setState(() {
      _vendorId = resolved;
      _loadingVendor = false;
    });
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, [int fallback = 1]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _vendorStatus(Map<String, dynamic> order) {
    final vendorStatus = _text(order['vendorStatus']);

    if (vendorStatus.isNotEmpty) {
      return vendorStatus;
    }

    final updates = order['vendorStatusUpdates'];

    if (updates is Map && updates[vendorId] is Map) {
      final vendorData = Map<String, dynamic>.from(updates[vendorId]);

      return _text(
        vendorData['status'],
        _text(order['status'], 'pending'),
      );
    }

    return _text(order['status'], 'pending');
  }

  List<Map<String, dynamic>> _vendorItems(Map<String, dynamic> order) {
    final items = order['items'];
    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => _text(e['vendorId']) == vendorId)
        .toList();
  }

  double _vendorTotal(List<Map<String, dynamic>> items) {
    double total = 0;
    for (final item in items) {
      total += _toDouble(item['price']) * _toInt(item['qty']);
    }
    return total;
  }

  Future<void> _updateStatus(String orderId, String status) async {
    if (vendorId.isEmpty) return;

    try {
      final ref = db.collection('orders').doc(orderId);
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};
      final vendorIds = data['vendorIds'] is List
          ? List<String>.from((data['vendorIds'] as List).map((e) => e.toString()))
          : <String>[];
      final vendorOwnerIds = data['vendorOwnerIds'] is List
          ? List<String>.from((data['vendorOwnerIds'] as List).map((e) => e.toString()))
          : <String>[];
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (!vendorIds.contains(vendorId) && !vendorOwnerIds.contains(uid)) {
        throw Exception('This order does not belong to your vendor account.');
      }

      final currentStatus = _vendorStatus(data);
      final allowed = <String, List<String>>{
        'pending': ['confirmed'],
        'confirmed': ['ready_for_pickup'],
      };

      if (!(allowed[currentStatus]?.contains(status) ?? false)) {
        throw Exception('Invalid status change: $currentStatus → $status');
      }

      await ref.update({
        'vendorStatusUpdates.$vendorId.status': status,
        'vendorStatusUpdates.$vendorId.updatedAt': FieldValue.serverTimestamp(),
        'vendorStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vendor order marked as $status')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status update failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingVendor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (vendorId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Vendor account not found or not approved')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Vendor Orders'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('orders')
            .where(
          'vendorIds',
          arrayContains: vendorId,
        )
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('Vendor orders query failed: ${snap.error}');
            return Column(
              children: [
                _filters(),
                Expanded(child: _empty()),
              ],
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snap.data!.docs.toList();

          docs.sort((a, b) {
            final ad = (a.data() as Map<String, dynamic>)['createdAt'];
            final bd = (b.data() as Map<String, dynamic>)['createdAt'];

            final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
            final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);

            return bt.compareTo(at);
          });

          if (statusFilter != 'all') {
            docs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _vendorStatus(data) == statusFilter;
            }).toList();
          }

          return Column(
            children: [
              _filters(),
              Expanded(
                child: docs.isEmpty
                    ? _empty()
                    : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _orderCard(doc.id, data);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip('All', 'all'),
          _filterChip('Pending', 'pending'),
          _filterChip('Confirmed', 'confirmed'),
          _filterChip('Ready', 'ready_for_pickup'),
          _filterChip('Assigned', 'assigned_to_rider'),
          _filterChip('Picked Up', 'picked_up'),
          _filterChip('On The Way', 'on_the_way'),
          _filterChip('Delivered', 'delivered'),
          _filterChip('Cancelled', 'cancelled'),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: statusFilter == value,
      onSelected: (_) => setState(() => statusFilter = value),
    );
  }

  Widget _orderCard(String orderId, Map<String, dynamic> data) {
    final status = _vendorStatus(data);
    final mainStatus = _text(data['status'], 'pending');
    final items = _vendorItems(data);
    final vendorTotal = _vendorTotal(items);
    final address = data['address'] is Map
        ? Map<String, dynamic>.from(data['address'])
        : <String, dynamic>{};

    String date = 'N/A';
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      final d = createdAt.toDate();
      date =
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Order #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '৳${vendorTotal.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFF32A8C7),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _chip(
              'Vendor: ${status.replaceAll('_', ' ').toUpperCase()}',
              _statusColor(status),
            ),
            _chip(
              'Order: ${mainStatus.replaceAll('_', ' ').toUpperCase()}',
              _statusColor(mainStatus),
            ),
            _chip('${items.length} items', Colors.blueGrey),
            _chip(date, Colors.grey),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const Text(
                  'VENDOR ITEMS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map(_itemTile),
                const Divider(height: 24),
                const Text(
                  'CUSTOMER / DELIVERY',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Customer: ${_text(data['userName'], 'Customer')}'),
                Text(
                    'Phone: ${_text(address['phone'] ?? data['phone'], 'N/A')}'),
                Text('Address: ${_text(address['address'], 'N/A')}'),
                Text(
                  'Area: ${_text(address['district'])} → ${_text(address['upazila'])}',
                ),
                const SizedBox(height: 12),
                _deliveryInfo(data),
                const SizedBox(height: 14),
                _actions(orderId, status, mainStatus),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> item) {
    final price = _toDouble(item['price']);
    final qty = _toInt(item['qty']);
    final unit = _text(item['unit']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Image.network(
              _text(item['image']),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.medication),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_text(item['name'], 'Product')} ${_text(item['strength'])}\nQty: $qty ${unit.isNotEmpty ? unit : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '৳${(price * qty).toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _deliveryInfo(Map<String, dynamic> data) {
    final partnerName = _text(data['deliveryPartnerName']);
    final partnerPhone = _text(data['deliveryPartnerPhone']);
    final deliveryStatus = _text(data['deliveryStatus'], 'not_assigned');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DELIVERY STATUS',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(
                deliveryStatus.replaceAll('_', ' ').toUpperCase(),
                _statusColor(deliveryStatus),
              ),
              if (partnerName.isNotEmpty)
                _chip('Rider: $partnerName', Colors.indigo),
              if (partnerPhone.isNotEmpty) _chip(partnerPhone, Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(String orderId, String vendorStatus, String mainStatus) {
    if (mainStatus == 'cancelled' || vendorStatus == 'cancelled') {
      return const Center(
        child: Text(
          'Order cancelled',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (mainStatus == 'delivered' || vendorStatus == 'delivered') {
      return const Center(
        child: Text(
          'Order delivered',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (vendorStatus == 'pending')
          ElevatedButton.icon(
            onPressed: () => _updateStatus(orderId, 'confirmed'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm'),
          ),
        if (vendorStatus == 'confirmed')
          ElevatedButton.icon(
            onPressed: () => _updateStatus(orderId, 'ready_for_pickup'),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Ready'),
          ),
        if (vendorStatus == 'ready_for_pickup')
          const Chip(
            avatar: Icon(Icons.delivery_dining, size: 18),
            label: Text('Waiting for admin/rider assignment'),
          ),
        if (mainStatus == 'assigned_to_rider' ||
            mainStatus == 'picked_up' ||
            mainStatus == 'on_the_way')
          const Chip(
            avatar: Icon(Icons.local_shipping_outlined, size: 18),
            label: Text('Delivery in progress'),
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    if (status == 'confirmed') return Colors.blue;
    if (status == 'ready_for_pickup') return Colors.deepPurple;
    if (status == 'assigned_to_rider') return Colors.indigo;
    if (status == 'picked_up') return Colors.deepPurple;
    if (status == 'on_the_way') return Colors.teal;
    if (status == 'delivered') return Colors.green;
    if (status == 'cancelled') return Colors.red;
    return Colors.orange;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 82,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          const Text(
            'No vendor orders found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
    );
  }
}
