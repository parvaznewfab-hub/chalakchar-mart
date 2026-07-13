import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VendorWithdrawPage extends StatefulWidget {
  const VendorWithdrawPage({super.key});

  @override
  State<VendorWithdrawPage> createState() => _VendorWithdrawPageState();
}

class _VendorWithdrawPageState extends State<VendorWithdrawPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();

  bool submitting = false;
  bool loadingVendor = true;
  String vendorId = '';
  String ownerUid = '';

  static const Color primary = Color(0xFF32A8C7);

  @override
  void initState() {
    super.initState();
    _resolveVendorId();
  }

  Future<void> _resolveVendorId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => loadingVendor = false);
      return;
    }

    ownerUid = user.uid;
    String resolved = '';

    try {
      final userDoc = await db.collection('users').doc(user.uid).get();
      final userVendorId = _text(userDoc.data()?['vendorId']);

      if (userVendorId.isNotEmpty) {
        final vendorDoc = await db.collection('vendors').doc(userVendorId).get();
        final data = vendorDoc.data() ?? <String, dynamic>{};
        final ownerId = _text(data['ownerId'] ?? data['userId'], user.uid);
        if (vendorDoc.exists && ownerId == user.uid) resolved = userVendorId;
      }

      if (resolved.isEmpty) {
        final directDoc = await db.collection('vendors').doc(user.uid).get();
        if (directDoc.exists) resolved = directDoc.id;
      }

      if (resolved.isEmpty) {
        final q = await db.collection('vendors').where('ownerId', isEqualTo: user.uid).limit(1).get();
        if (q.docs.isNotEmpty) resolved = q.docs.first.id;
      }
    } catch (e) {
      debugPrint('Vendor withdraw resolve failed: $e');
    }

    if (!mounted) return;
    setState(() {
      vendorId = resolved;
      loadingVendor = false;
    });
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _toInt(dynamic v, [int fallback = 1]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  String _text(dynamic v, [String fallback = '']) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  void _show(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : primary,
      ),
    );
  }

  double _vendorItemTotal(Map<String, dynamic> order) {
    final items = order['items'];
    if (items is! List) return 0;

    double total = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      if (_text(item['vendorId']) != vendorId) continue;
      final price = _toDouble(item['price'] ?? item['sellingPrice']);
      final qty = _toInt(item['qty'] ?? item['quantity']);
      total += price * qty;
    }
    return total;
  }

  Map<String, double> _calculateMoney({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> orders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
    required Map<String, dynamic> vendor,
  }) {
    double deliveredSales = 0;

    for (final doc in orders) {
      final data = doc.data();
      final status = _text(data['status']).toLowerCase();
      final deliveryStatus = _text(data['deliveryStatus']).toLowerCase();
      if (status == 'delivered' || deliveryStatus == 'delivered') {
        deliveredSales += _vendorItemTotal(data);
      }
    }

    final commissionPercent = _toDouble(vendor['commissionPercent'] ?? vendor['commissionRate']);
    final commission = commissionPercent > 0 ? deliveredSales * commissionPercent / 100 : _toDouble(vendor['totalCommission']);

    double pending = 0;
    double paid = 0;
    for (final doc in requests) {
      final data = doc.data();
      final amount = _toDouble(data['amount']);
      final status = _text(data['status']).toLowerCase();
      if (status == 'pending') pending += amount;
      if (status == 'approved' || status == 'paid' || status == 'completed') paid += amount;
    }

    final manualWithdrawable = _toDouble(vendor['withdrawableBalance']);
    final calculatedAvailable = deliveredSales - commission - pending - paid;
    final available = manualWithdrawable > 0 ? manualWithdrawable : calculatedAvailable;

    return {
      'totalSales': deliveredSales,
      'commission': commission,
      'pending': pending,
      'paid': paid,
      'available': available < 0 ? 0 : available,
    };
  }

  Future<void> _submitWithdraw({
    required Map<String, dynamic> vendor,
    required double available,
  }) async {
    if (submitting) return;

    final amount = _toDouble(amountController.text);
    final payoutAccount = _text(vendor['payoutAccount'] ?? vendor['payoutNumber']);

    if (payoutAccount.isEmpty) {
      _show('Please add payout account first', error: true);
      return;
    }

    const minimumWithdraw = 100;
    if (amount < minimumWithdraw) {
      _show('Minimum withdraw amount is ৳$minimumWithdraw', error: true);
      return;
    }

    if (amount > available) {
      _show('Amount is greater than available balance', error: true);
      return;
    }

    setState(() => submitting = true);

    try {
      final existingPending = await db
          .collection('vendorWithdrawRequests')
          .where('vendorId', isEqualTo: vendorId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingPending.docs.isNotEmpty) {
        _show('You already have a pending withdraw request', error: true);
        return;
      }

      await db.collection('vendorWithdrawRequests').add({
        'vendorId': vendorId,
        'vendorOwnerId': ownerUid,
        'vendorName': _text(vendor['shopName'] ?? vendor['name'], 'Vendor'),
        'vendorEmail': _text(vendor['email']),
        'vendorPhone': _text(vendor['phone']),
        'amount': amount,
        'status': 'pending',
        'note': noteController.text.trim(),
        'payoutAccount': payoutAccount,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      amountController.clear();
      noteController.clear();
      _show('Withdraw request submitted');
    } catch (e) {
      _show('Withdraw failed: $e', error: true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loadingVendor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (vendorId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Vendor profile not found')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Vendor Withdraw'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('vendors').doc(vendorId).snapshots(),
        builder: (context, vendorSnap) {
          if (vendorSnap.hasError) {
            return _errorCard('Vendor Withdraw load failed', vendorSnap.error.toString());
          }
          if (!vendorSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final vendor = vendorSnap.data!.data() ?? <String, dynamic>{};

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('orders').where('vendorIds', arrayContains: vendorId).snapshots(),
            builder: (context, orderSnap) {
              if (orderSnap.hasError) {
                return _errorCard('Orders load failed', orderSnap.error.toString());
              }
              if (!orderSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('vendorWithdrawRequests')
                // IMPORTANT: Query by vendorOwnerId, not vendorId.
                // Firestore rules can prove: resource.data.vendorOwnerId == request.auth.uid
                // This fixes permission-denied on Vendor Withdraw history.
                    .where('vendorOwnerId', isEqualTo: ownerUid)
                    .snapshots(),
                builder: (context, requestSnap) {
                  if (requestSnap.hasError) {
                    return _errorCard('Withdraw history load failed', requestSnap.error.toString());
                  }
                  if (!requestSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final requests = requestSnap.data!.docs.toList();
                  requests.sort((a, b) {
                    final ad = a.data()['createdAt'];
                    final bd = b.data()['createdAt'];
                    final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
                    final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);
                    return bt.compareTo(at);
                  });

                  final money = _calculateMoney(
                    orders: orderSnap.data!.docs,
                    requests: requests,
                    vendor: vendor,
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _balanceCard(
                        balance: money['available'] ?? 0,
                        pending: money['pending'] ?? 0,
                        totalSales: money['totalSales'] ?? 0,
                        totalCommission: money['commission'] ?? 0,
                      ),
                      const SizedBox(height: 16),
                      _requestCard(vendor, money['available'] ?? 0),
                      const SizedBox(height: 16),
                      const Text(
                        'Withdraw History',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _historyList(requests),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _errorCard(String title, String message) {
    return Center(
      child: Container(
        width: 520,
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 46),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _resolveVendorId,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard({
    required double balance,
    required double pending,
    required double totalSales,
    required double totalCommission,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available Balance', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            '৳${balance.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: primary),
          ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(child: _miniStat('Pending', pending)),
              Expanded(child: _miniStat('Total Sales', totalSales)),
              Expanded(child: _miniStat('Commission', totalCommission)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text('৳${value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _requestCard(Map<String, dynamic> vendor, double balance) {
    final payoutAccount = _text(vendor['payoutAccount'] ?? vendor['payoutNumber']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Request Withdraw', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (payoutAccount.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text('Payout Account: $payoutAccount'),
            ),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '৳ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note optional',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting || balance <= 0 ? null : () => _submitWithdraw(vendor: vendor, available: balance),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SUBMIT REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: const Center(child: Text('No withdraw request yet')),
      );
    }

    return Column(
      children: docs.map((doc) {
        final data = doc.data();
        final amount = _toDouble(data['amount']);
        final status = _text(data['status'], 'pending');
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                child: Icon(Icons.account_balance_wallet, color: _statusColor(status)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('৳${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'paid':
      case 'completed':
        return Colors.green;
      case 'rejected':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
      ],
    );
  }
}
