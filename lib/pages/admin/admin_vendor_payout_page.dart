import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminVendorPayoutPage extends StatefulWidget {
  const AdminVendorPayoutPage({super.key});

  @override
  State<AdminVendorPayoutPage> createState() => _AdminVendorPayoutPageState();
}

class _AdminVendorPayoutPageState extends State<AdminVendorPayoutPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String statusFilter = 'pending';
  String searchText = '';

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _text(dynamic v, [String fallback = '']) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  String _dateText(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    }
    return 'N/A';
  }

  Color _statusColor(String status) {
    if (status == 'approved' || status == 'paid') return Colors.green;
    if (status == 'rejected' || status == 'cancelled') return Colors.red;
    return Colors.orange;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _requestsStream() {
    Query<Map<String, dynamic>> q = db.collection('vendorWithdrawRequests');

    if (statusFilter != 'all') {
      q = q.where('status', isEqualTo: statusFilter);
    }

    return q.orderBy('createdAt', descending: true).limit(200).snapshots();
  }

  Future<void> _approveRequest(
      String requestId, Map<String, dynamic> data) async {
    final vendorId = _text(data['vendorId']);
    final amount = _toDouble(data['amount']);

    if (vendorId.isEmpty || amount <= 0) {
      _snack('Invalid payout request');
      return;
    }

    final ok = await _confirm(
      title: 'Approve payout?',
      message:
          'This will mark the payout as paid and reduce vendor pending withdraw balance.',
      confirmText: 'Approve',
      danger: false,
    );

    if (ok != true) return;

    final batch = db.batch();

    final requestRef = db.collection('vendorWithdrawRequests').doc(requestId);
    final vendorRef = db.collection('vendors').doc(vendorId);
    final payoutRef = db.collection('vendorPayouts').doc();

    batch.set(
        requestRef,
        {
          'status': 'paid',
          'approvedAt': FieldValue.serverTimestamp(),
          'paidAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(
        vendorRef,
        {
          'withdrawPendingBalance': FieldValue.increment(-amount),
          'totalPaidOut': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(payoutRef, {
      'requestId': requestId,
      'vendorId': vendorId,
      'vendorName': _text(data['vendorName'], 'Vendor'),
      'vendorPhone': _text(data['vendorPhone']),
      'vendorEmail': _text(data['vendorEmail']),
      'amount': amount,
      'status': 'paid',
      'payoutAccount': data['payoutAccount'],
      'note': _text(data['note']),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    _snack('Payout approved and marked as paid');
  }

  Future<void> _rejectRequest(
      String requestId, Map<String, dynamic> data) async {
    final vendorId = _text(data['vendorId']);
    final amount = _toDouble(data['amount']);

    if (vendorId.isEmpty || amount <= 0) {
      _snack('Invalid payout request');
      return;
    }

    final ok = await _confirm(
      title: 'Reject payout?',
      message: 'This will return the amount to vendor withdrawable balance.',
      confirmText: 'Reject',
      danger: true,
    );

    if (ok != true) return;

    final batch = db.batch();

    batch.set(
        db.collection('vendorWithdrawRequests').doc(requestId),
        {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(
        db.collection('vendors').doc(vendorId),
        {
          'withdrawPendingBalance': FieldValue.increment(-amount),
          'withdrawableBalance': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    await batch.commit();
    _snack('Payout request rejected and balance returned');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    required bool danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _call(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) {
      _snack('Phone not found');
      return;
    }

    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsapp(String phone) async {
    String clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      _snack('Phone not found');
      return;
    }

    if (clean.startsWith('0')) clean = '88$clean';

    final uri = Uri.parse('https://wa.me/$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Vendor Payout Manager'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          _topFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _requestsStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text('Payout load failed: ${snap.error}'));
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final query = searchText.toLowerCase().trim();
                final docs = snap.data!.docs.where((doc) {
                  final d = doc.data();

                  if (query.isEmpty) return true;

                  return _text(d['vendorName']).toLowerCase().contains(query) ||
                      _text(d['vendorPhone']).toLowerCase().contains(query) ||
                      _text(d['vendorEmail']).toLowerCase().contains(query) ||
                      _text(d['vendorId']).toLowerCase().contains(query) ||
                      doc.id.toLowerCase().contains(query);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No payout requests found'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _payoutCard(doc.id, doc.data());
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _topFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 720;

          final search = TextField(
            decoration: const InputDecoration(
              hintText: 'Search vendor, phone, email, request id...',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => searchText = v),
          );

          final filter = DropdownButtonFormField<String>(
            value: statusFilter,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
            ],
            onChanged: (v) => setState(() => statusFilter = v ?? 'pending'),
          );

          if (compact) {
            return Column(
              children: [
                search,
                const SizedBox(height: 8),
                filter,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 10),
              Expanded(child: filter),
            ],
          );
        },
      ),
    );
  }

  Widget _payoutCard(String requestId, Map<String, dynamic> data) {
    final status = _text(data['status'], 'pending');
    final amount = _toDouble(data['amount']);
    final vendorName = _text(data['vendorName'], 'Vendor');
    final phone = _text(data['vendorPhone']);
    final email = _text(data['vendorEmail']);
    final payoutAccount = data['payoutAccount'];

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _statusColor(status).withOpacity(0.12),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: _statusColor(status),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vendorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '৳${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF32A8C7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(status.toUpperCase(), _statusColor(status)),
                _chip(
                    'Request #${requestId.length > 8 ? requestId.substring(0, 8) : requestId}',
                    Colors.blueGrey),
                _chip(_dateText(data['createdAt']), Colors.indigo),
                if (phone.isNotEmpty) _chip(phone, Colors.teal),
                if (email.isNotEmpty) _chip(email, Colors.deepPurple),
              ],
            ),
            const SizedBox(height: 12),
            if (payoutAccount != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text('Payout Account: ${payoutAccount.toString()}'),
              ),
            if (_text(data['note']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Note: ${_text(data['note'])}'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'pending')
                  ElevatedButton.icon(
                    onPressed: () => _approveRequest(requestId, data),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Mark Paid'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (status == 'pending')
                  OutlinedButton.icon(
                    onPressed: () => _rejectRequest(requestId, data),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                if (phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _call(phone),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                if (phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _whatsapp(phone),
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
