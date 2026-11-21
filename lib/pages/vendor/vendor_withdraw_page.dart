import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/private_profile_service.dart';
import '../../utils/user_error_message.dart';
import '../../utils/vendor_balance.dart';

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
        // No phone/email copies (14b step B): staff see them in vendor_private.
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
    } catch (e, st) {
      // Plain message for the vendor; the real error goes to the log.
      _show(friendlySubmitError(e, where: 'vendor withdraw', stack: st), error: true);
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
      body: StreamBuilder<Map<String, dynamic>?>(
        // Public doc + vendor_private (payout account, balances; 14b step B).
        stream: PrivateProfileService.vendorMergedStream(vendorId),
        builder: (context, vendorSnap) {
          if (vendorSnap.hasError) {
            return _errorCard('Vendor Withdraw load failed', vendorSnap.error.toString());
          }
          if (vendorSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final vendor = vendorSnap.data ?? <String, dynamic>{};

          // ledger-1: all money from vendor_private; no sums from orders here.
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

                  final money = VendorBalance.from(
                    vendor,
                    requested: pendingRequestTotal(requests.map((d) => d.data())),
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _balanceCard(money),
                      const SizedBox(height: 16),
                      _requestCard(vendor, money),
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

  Widget _balanceCard(VendorBalance money) {
    final debt = money.inDebt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(debt ? 'Balance (you owe)' : 'Available Balance',
              style: TextStyle(color: debt ? Colors.red.shade700 : Colors.grey)),
          const SizedBox(height: 4),
          Text(
            debt ? '-৳${(-money.withdrawable).toStringAsFixed(0)}' : '৳${money.available.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: debt ? Colors.red.shade700 : primary),
          ),
          if (debt)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'An order was returned after its money was paid out. New withdrawals open again once this is cleared by new delivered orders.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(child: _miniStat('Orders not delivered', money.pendingOrders)),
              Expanded(child: _miniStat('Requested', money.requested)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _miniStat('Total Sales', money.totalSales)),
              Expanded(child: _miniStat('Commission', money.totalCommission)),
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

  Widget _requestCard(Map<String, dynamic> vendor, VendorBalance money) {
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
              onPressed: submitting || !money.canWithdraw
                  ? null
                  : () => _submitWithdraw(vendor: vendor, available: money.available),
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
