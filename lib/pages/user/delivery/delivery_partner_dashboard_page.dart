import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';


class DeliveryPartnerDashboardPage extends StatefulWidget {
  const DeliveryPartnerDashboardPage({super.key});

  @override
  State<DeliveryPartnerDashboardPage> createState() =>
      _DeliveryPartnerDashboardPageState();
}

class _DeliveryPartnerDashboardPageState
    extends State<DeliveryPartnerDashboardPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String statusFilter = 'active';

  String get riderId => FirebaseAuth.instance.currentUser?.uid ?? '';

  static const Color primary = Color(0xFF32A8C7);
  static const Color darkText = Color(0xFF0F172A);
  static const Color pageBg = Color(0xFFF5F7FA);

  String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _deliveryStepRank(String status) {
    switch (status) {
      case 'assigned':
        return 1;
      case 'picked_up':
        return 2;
      case 'on_the_way':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _call(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) {
      _snack('Phone not found', error: true);
      return;
    }

    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Cannot open phone dialer', error: true);
    }
  }

  Future<void> _updateDeliveryStatus(String orderId, String status) async {
    try {
      final orderRef = db.collection('orders').doc(orderId);
      final orderSnap = await orderRef.get();
      final orderData = orderSnap.data() ?? <String, dynamic>{};

      if (_text(orderData['deliveryPartnerId']) != riderId) {
        throw Exception('This order is not assigned to you');
      }

      final current = _text(orderData['deliveryStatus'], 'assigned');

      if (current == 'delivered') {
        throw Exception('This order is already delivered');
      }

      final allowed = <String, List<String>>{
        'assigned': ['picked_up'],
        'picked_up': ['on_the_way'],
        'on_the_way': ['delivered'],
      };

      if (!(allowed[current]?.contains(status) ?? false)) {
        throw Exception('Invalid delivery step: $current → $status');
      }

      if (_deliveryStepRank(status) <= _deliveryStepRank(current)) {
        throw Exception('You cannot move delivery status backward');
      }

      final updateData = <String, dynamic>{
        'deliveryStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'deliveryTimeline.$status': FieldValue.serverTimestamp(),
      };

      if (status == 'picked_up') {
        updateData['status'] = 'picked_up';
        updateData['pickedUpAt'] = FieldValue.serverTimestamp();
      }

      if (status == 'on_the_way') {
        updateData['status'] = 'on_the_way';
        updateData['onTheWayAt'] = FieldValue.serverTimestamp();
      }

      if (status == 'delivered') {
        updateData['status'] = 'delivered';
        updateData['paymentStatus'] = 'paid';
        updateData['deliveredAt'] = FieldValue.serverTimestamp();
      }

      await orderRef.update(updateData);

      if (status == 'delivered') {
        await _createEarning(orderId);
      }

      _snack('Status updated: ${status.replaceAll('_', ' ')}');
    } catch (e) {
      _snack('Update failed: $e', error: true);
    }
  }

  Future<void> _createEarning(String orderId) async {
    final earningId = '${riderId}_$orderId';
    final earningRef = db.collection('deliveryEarnings').doc(earningId);
    final partnerRef = db.collection('deliveryPartners').doc(riderId);
    final orderRef = db.collection('orders').doc(orderId);

    debugPrint('SYNC STEP 1: read order $orderId');
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw Exception('Order not found');

    final orderData = orderSnap.data() ?? <String, dynamic>{};

    if (_text(orderData['deliveryPartnerId']) != riderId) {
      throw Exception('This order is not assigned to you');
    }

    final deliveryCharge = _toDouble(orderData['deliveryCharge']);
    final grandTotal = _toDouble(
      orderData['grandTotal'] ?? orderData['finalTotal'] ?? orderData['total'],
    );

    final paymentMethod = _text(orderData['paymentMethod']).toLowerCase().trim();
    final isCod = paymentMethod == 'cod' ||
        paymentMethod == 'cash_on_delivery' ||
        paymentMethod == 'cash on delivery';

    debugPrint('SYNC STEP 2: read earning $earningId');
    final old = await earningRef.get();

    if (old.exists && old.data()?['partnerSynced'] == true) {
      _snack('Earning already synced');
      return;
    }

    debugPrint('SYNC STEP 3: create/merge earning');
    await earningRef.set({
      'deliveryPartnerId': riderId,
      'orderId': orderId,
      'amount': deliveryCharge,
      'paymentMethod': paymentMethod,
      'status': 'pending',
      'grandTotal': grandTotal,
      'deliveryCharge': deliveryCharge,
      'partnerSynced': false,
      'createdAt': old.exists
          ? (old.data()?['createdAt'] ?? FieldValue.serverTimestamp())
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final partnerUpdate = <String, dynamic>{
      'totalDeliveries': FieldValue.increment(1),
      'totalEarning': FieldValue.increment(deliveryCharge),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastEarningSyncedAt': FieldValue.serverTimestamp(),
      'lastSyncedOrderId': orderId,
    };

    if (isCod) {
      partnerUpdate['codDue'] = FieldValue.increment(grandTotal);
    }

    // set(merge:true) is safer than update() if an old partner document is missing fields.
    debugPrint('SYNC STEP 4: update delivery partner balance');
    await partnerRef.set(partnerUpdate, SetOptions(merge: true));

    debugPrint('SYNC STEP 5: mark earning synced');
    await earningRef.set({
      'partnerSynced': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncEarning(String orderId) async {
    try {
      await _createEarning(orderId);
      if (mounted) setState(() {});
      _snack('Earning synced');
    } catch (e, s) {
      debugPrint('SYNC ERROR: $e');
      debugPrint('STACK: $s');

      _snack(
        'Earning sync failed:\n${e.toString()}',
        error: true,
      );
    }
  }

  Future<void> _requestWithdraw() async {
    try {
      final partnerRef = db.collection('deliveryPartners').doc(riderId);
      final partnerSnap = await partnerRef.get();
      final data = partnerSnap.data() ?? {};

      final total = _toDouble(data['totalEarning']);
      final withdrawn = _toDouble(data['withdrawnAmount']);
      final pending = _toDouble(data['pendingAmount']);
      final codDue = _toDouble(data['codDue']);

      final available = total - withdrawn - pending - codDue;

      if (available < 100) {
        _snack('Minimum withdraw amount is ৳100', error: true);
        return;
      }

      final pendingWithdraw = await db
          .collection('deliveryWithdraws')
          .where('deliveryPartnerId', isEqualTo: riderId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pendingWithdraw.docs.isNotEmpty) {
        _snack('You already have a pending withdraw request', error: true);
        return;
      }

      final batch = db.batch();
      final withdrawRef = db.collection('deliveryWithdraws').doc();

      batch.set(withdrawRef, {
        'deliveryPartnerId': riderId,
        'amount': available,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(partnerRef, {
        'pendingAmount': FieldValue.increment(available),
        'lastWithdrawRequestId': withdrawRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      _snack('Withdraw request submitted');
    } catch (e) {
      _snack('Withdraw failed: $e', error: true);
    }
  }

  Future<void> _confirmDelivered(String orderId) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Delivery'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Enter customer OTP',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final order = await db.collection('orders').doc(orderId).get();

              final data = order.data() ?? {};
              final otp = _text(data['deliveryOtp']);

              if (otp.isNotEmpty && controller.text.trim() != otp) {
                _snack('Invalid OTP', error: true);
                return;
              }

              if (!mounted) return;

              Navigator.of(context).pop();

              await _updateDeliveryStatus(orderId, 'delivered');
            },
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream() {
    Query<Map<String, dynamic>> q =
    db.collection('orders').where('deliveryPartnerId', isEqualTo: riderId);

    if (statusFilter == 'active') {
      q = q.where(
        'deliveryStatus',
        whereIn: ['assigned', 'picked_up', 'on_the_way'],
      );
    } else if (statusFilter != 'all') {
      q = q.where('deliveryStatus', isEqualTo: statusFilter);
    }

    return q.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    if (riderId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Login required')));
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text('Delivery Dashboard'),
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();

              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('deliveryPartners').doc(riderId).snapshots(),
        builder: (context, partnerSnap) {
          final partner = partnerSnap.data?.data();

          if (partnerSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (partner == null) {
            return _stateBox(
              icon: Icons.delivery_dining_rounded,
              title: 'Delivery partner profile not found',
              message: 'Please apply first or contact admin.',
            );
          }

          if (_text(partner['status']) != 'approved' ||
              partner['isActive'] == false) {
            return _stateBox(
              icon: Icons.pending_actions_rounded,
              title: 'Account not approved yet',
              message:
              'Status: ${_text(partner['status'], 'pending').toUpperCase()}\nAdmin will review your delivery partner account.',
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: RefreshIndicator(
                    onRefresh: () async => setState(() {}),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 22 : 14,
                            16,
                            isDesktop ? 22 : 14,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _heroCard(partner, isDesktop),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 22 : 14,
                            14,
                            isDesktop ? 22 : 14,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _kpiSection(partner, isDesktop),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 22 : 14,
                            14,
                            isDesktop ? 22 : 14,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(child: _filters()),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            isDesktop ? 22 : 14,
                            14,
                            isDesktop ? 22 : 14,
                            24,
                          ),
                          sliver: _ordersSliver(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _heroCard(Map<String, dynamic> partner, bool isDesktop) {
    final total = _toDouble(partner['totalEarning']);
    final withdrawn = _toDouble(partner['withdrawnAmount']);
    final pending = _toDouble(partner['pendingAmount']);
    final codDue = _toDouble(partner['codDue']);
    final available = (total - withdrawn - pending - codDue).clamp(0, double.infinity);

    return Container(
      padding: EdgeInsets.all(isDesktop ? 22 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF32A8C7), Color(0xFF1592B3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: isDesktop
          ? Row(
        children: [
          _profileBlock(partner),
          const Spacer(),
          _heroMini('Available', available.toDouble(), Icons.account_balance_wallet_rounded),
          const SizedBox(width: 12),
          _heroMini('Deliveries', _toDouble(partner['totalDeliveries']), Icons.check_circle_rounded, money: false),
          const SizedBox(width: 16),
          _withdrawButton(),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: _profileBlock(partner)), _withdrawButton(compact: true)]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _heroMini('Available', available.toDouble(), Icons.account_balance_wallet_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _heroMini('Deliveries', _toDouble(partner['totalDeliveries']), Icons.check_circle_rounded, money: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileBlock(Map<String, dynamic> partner) {
    return Row(
      children: [
        Container(
          height: 58,
          width: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(partner['name'], 'Delivery Partner'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${partner['totalDeliveries'] ?? 0} deliveries completed',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroMini(String title, double value, IconData icon, {bool money = true}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12)),
              Text(
                money ? '৳${value.toStringAsFixed(0)}' : value.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _withdrawButton({bool compact = false}) {
    return ElevatedButton.icon(
      onPressed: _requestWithdraw,
      icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
      label: Text(compact ? 'Withdraw' : 'Request Withdraw'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _kpiSection(Map<String, dynamic> partner, bool isDesktop) {
    final total = _toDouble(partner['totalEarning']);
    final withdrawn = _toDouble(partner['withdrawnAmount']);
    final pending = _toDouble(partner['pendingAmount']);
    final codDue = _toDouble(partner['codDue']);
    final available = (total - withdrawn - pending - codDue).clamp(0, double.infinity).toDouble();

    final cards = [
      _kpiCard('Total Earned', total, Icons.trending_up_rounded, Colors.green),
      _kpiCard('Available', available, Icons.account_balance_wallet_rounded, Colors.blue),
      _kpiCard('Pending', pending, Icons.hourglass_top_rounded, Colors.orange),
      _kpiCard('COD Due', codDue, Icons.payments_rounded, Colors.red),
    ];

    if (isDesktop) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.75,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: cards,
    );
  }

  Widget _kpiCard(String title, double amount, IconData icon, Color color) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '৳${amount.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final filters = <String, String>{
      'Active': 'active',
      'Assigned': 'assigned',
      'Picked Up': 'picked_up',
      'On The Way': 'on_the_way',
      'Delivered': 'delivered',
      'All': 'all',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10, right: 10),
            child: Icon(Icons.filter_list_rounded, color: primary),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filters.entries.map((entry) {
                final selected = statusFilter == entry.value;
                return ChoiceChip(
                  selected: selected,
                  label: Text(entry.key),
                  onSelected: (_) => setState(() => statusFilter = entry.value),
                  selectedColor: primary.withValues(alpha: 0.16),
                  labelStyle: TextStyle(
                    color: selected ? primary : Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: BorderSide(color: selected ? primary : const Color(0xFFE5E7EB)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersSliver() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ordersStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: _stateBox(
              icon: Icons.error_outline_rounded,
              title: 'Orders load failed',
              message: '${snap.error}',
            ),
          );
        }

        if (!snap.hasData) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snap.data!.docs.toList();
        docs.sort((a, b) {
          final ad = a.data()['createdAt'];
          final bd = b.data()['createdAt'];
          final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
          final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);
          return bt.compareTo(at);
        });

        if (docs.isEmpty) {
          return SliverToBoxAdapter(
            child: _stateBox(
              icon: Icons.inbox_rounded,
              title: 'No delivery orders found',
              message: 'Assigned orders will appear here automatically.',
            ),
          );
        }

        return SliverList.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _orderCard(docs[i].id, docs[i].data()),
        );
      },
    );
  }

  Widget _orderCard(String orderId, Map<String, dynamic> data) {
    final address =
    data['address'] is Map ? Map<String, dynamic>.from(data['address']) : <String, dynamic>{};

    final phone = _text(address['phone'] ?? data['phone'] ?? data['userPhone']);
    final deliveryStatus = _text(data['deliveryStatus'], 'assigned');
    final total = _toDouble(data['grandTotal'] ?? data['finalTotal'] ?? data['total']);
    final customer = _text(data['userName'], 'Customer');
    final deliveryOtp = _text(data['deliveryOtp']);
    final payment = _text(data['paymentMethod'], 'N/A').toUpperCase();
    final addressText = _text(address['address'] ?? data['addressText'], 'N/A');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${orderId.length >= 8 ? orderId.substring(0, 8) : orderId}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: darkText),
                      ),
                      const SizedBox(height: 2),
                      Text(customer, style: TextStyle(color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                _statusChip(deliveryStatus),
              ],
            ),
            const SizedBox(height: 14),
            _infoGrid(phone, addressText, total, payment, deliveryOtp),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _call(phone),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Call Customer'),
                ),
                if (deliveryStatus == 'assigned')
                  ElevatedButton.icon(
                    onPressed: () => _updateDeliveryStatus(orderId, 'picked_up'),
                    icon: const Icon(Icons.inventory_2_rounded, size: 18),
                    label: const Text('Picked Up'),
                  ),
                if (deliveryStatus == 'picked_up')
                  ElevatedButton.icon(
                    onPressed: () => _updateDeliveryStatus(orderId, 'on_the_way'),
                    icon: const Icon(Icons.delivery_dining_rounded, size: 18),
                    label: const Text('On The Way'),
                  ),
                if (deliveryStatus == 'on_the_way')
                  ElevatedButton.icon(
                    onPressed: () => _confirmDelivered(orderId),
                    icon: const Icon(Icons.verified_rounded, size: 18),
                    label: const Text('Delivered'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (deliveryStatus == 'delivered') ...[
                  Chip(
                    avatar: const Icon(Icons.lock_rounded, size: 16, color: Colors.green),
                    label: const Text('Completed - read only'),
                    backgroundColor: Colors.green.withValues(alpha: 0.10),
                    labelStyle: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _syncEarning(orderId),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Sync Earning'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoGrid(String phone, String address, double total, String payment, String otp) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final items = [
          _infoTile(Icons.call_rounded, 'Phone', phone.isEmpty ? 'N/A' : phone),
          _infoTile(Icons.location_on_rounded, 'Address', address),
          _infoTile(
            Icons.payments_rounded,
            'Customer Payable',
            '৳${total.toStringAsFixed(0)}',
          ),
          _infoTile(Icons.credit_card_rounded, 'Payment', payment),
          if (otp.isNotEmpty) _infoTile(Icons.pin_rounded, 'Delivery OTP', otp),
        ];

        if (wide) {
          return Wrap(spacing: 10, runSpacing: 10, children: items.map((e) => SizedBox(width: 230, child: e)).toList());
        }
        return Column(children: items.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: e)).toList());
      },
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color = Colors.orange;
    if (status == 'picked_up') color = Colors.blue;
    if (status == 'on_the_way') color = Colors.deepPurple;
    if (status == 'delivered') color = Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11),
      ),
    );
  }

  Widget _stateBox({required IconData icon, required String title, required String message}) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 66,
              width: 66,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: primary, size: 34),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, height: 1.45)),
          ],
        ),
      ),
    );
  }
}
