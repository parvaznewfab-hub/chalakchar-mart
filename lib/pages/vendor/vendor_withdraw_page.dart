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
        backgroundColor: error ? Colors.red : const Color(0xFF32A8C7),
      ),
    );
  }

  Future<void> _submitWithdraw({
    required String vendorId,
    required Map<String, dynamic> vendor,
  }) async {
    if (submitting) return;

    final amount = _toDouble(amountController.text);
    final balance = _toDouble(vendor['withdrawableBalance']);

    final payoutAccount = vendor['payoutAccount'];

    if (payoutAccount == null || payoutAccount.toString().trim().isEmpty) {
      _show(
        'Please add payout account first',
        error: true,
      );
      return;
    }

    const minimumWithdraw = 100;

    if (amount < minimumWithdraw) {
      _show(
        'Minimum withdraw amount is ৳$minimumWithdraw',
        error: true,
      );
      return;
    }

    if (amount <= 0) {
      _show('Enter valid withdraw amount', error: true);
      return;
    }

    if (amount > balance) {
      _show('Amount is greater than withdrawable balance', error: true);
      return;
    }

    final existingPending = await db
        .collection('vendorWithdrawRequests')
        .where('vendorId', isEqualTo: vendorId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existingPending.docs.isNotEmpty) {
      _show(
        'You already have a pending withdraw request',
        error: true,
      );
      return;
    }

    setState(() => submitting = true);

    try {
      final batch = db.batch();

      final requestRef = db.collection('vendorWithdrawRequests').doc();

      batch.set(requestRef, {
        'vendorId': vendorId,
        'vendorName': _text(vendor['shopName'] ?? vendor['name'], 'Vendor'),
        'vendorEmail': _text(vendor['email']),
        'vendorPhone': _text(vendor['phone']),
        'amount': amount,
        'status': 'pending',
        'note': noteController.text.trim(),
        'payoutAccount': vendor['payoutAccount'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(
        db.collection('vendors').doc(vendorId),
        {
          'withdrawableBalance': FieldValue.increment(-amount),
          'withdrawPendingBalance': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      amountController.clear();
      noteController.clear();

      _show('Withdraw request submitted');
    } catch (e) {
      _show('Withdraw failed: $e', error: true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _vendorStream(String uid) {
    return db.collection('vendors').doc(uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _withdrawHistory(String uid) {
    return db
        .collection('vendorWithdrawRequests')
        .where('vendorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login as vendor')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Vendor Withdraw'),
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _vendorStream(user.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Vendor profile not found'));
          }

          final vendor = snap.data!.data() ?? {};
          final balance = _toDouble(vendor['withdrawableBalance']);
          final pending = _toDouble(vendor['withdrawPendingBalance']);
          final totalSales = _toDouble(vendor['totalSales']);
          final totalCommission = _toDouble(vendor['totalCommission']);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _balanceCard(
                balance: balance,
                pending: pending,
                totalSales: totalSales,
                totalCommission: totalCommission,
              ),
              const SizedBox(height: 16),
              _requestCard(user.uid, vendor, balance),
              const SizedBox(height: 16),
              const Text(
                'Withdraw History',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _historyList(user.uid),
            ],
          );
        },
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
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Color(0xFF32A8C7),
            ),
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
        Text(
          '৳${value.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _requestCard(
      String vendorId, Map<String, dynamic> vendor, double balance) {
    final payoutAccount = vendor['payoutAccount'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request Withdraw',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (payoutAccount != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Payout Account: ${payoutAccount.toString()}'),
            ),
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '৳ ',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note optional',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting || balance <= 0
                  ? null
                  : () => _submitWithdraw(vendorId: vendorId, vendor: vendor),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF32A8C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'SUBMIT REQUEST',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList(String vendorId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _withdrawHistory(vendorId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];

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
                    backgroundColor:
                        _statusColor(status).withValues(alpha: 0.12),
                    child: Icon(Icons.account_balance_wallet,
                        color: _statusColor(status)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '৳${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
      case 'paid':
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
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
