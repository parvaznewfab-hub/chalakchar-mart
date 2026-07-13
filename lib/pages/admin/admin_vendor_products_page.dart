import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminVendorProductsPage extends StatefulWidget {
  const AdminVendorProductsPage({super.key});

  @override
  State<AdminVendorProductsPage> createState() =>
      _AdminVendorProductsPageState();
}

class _AdminVendorProductsPageState extends State<AdminVendorProductsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String statusFilter = 'pending';
  String searchText = '';

  String _text(dynamic v, [String fallback = '']) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<void> _updateProductStatus(
    String productId,
    String status, {
    String reason = '',
  }) async {
    final approved = status == 'approved';

    final data = {
      'approvalStatus': status,
      'isActive': approved,
      'isVisible': approved,
      'isPublished': approved,
      'showOnHome': approved,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'approved') {
      data['approvedAt'] = FieldValue.serverTimestamp();
      data['rejectedReason'] = '';
    }

    if (status == 'rejected') {
      data['rejectedAt'] = FieldValue.serverTimestamp();
      data['rejectedReason'] = reason;
    }

    await db.collection('products').doc(productId).set(
          data,
          SetOptions(merge: true),
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Product $status')),
    );
  }

  Future<void> _rejectDialog(String productId) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Product'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reject reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final reason = controller.text.trim();
              Navigator.pop(context);
              await _updateProductStatus(
                productId,
                'rejected',
                reason: reason,
              );
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    controller.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream() {
    Query<Map<String, dynamic>> q =
        db.collection('products').where('isMarketplace', isEqualTo: true);

    if (statusFilter != 'all') {
      q = q.where('approvalStatus', isEqualTo: statusFilter);
    }

    return q.limit(300).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Vendor Product Approval'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _productsStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Load failed: ${snap.error}'));
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final q = searchText.toLowerCase().trim();
                final docs = snap.data!.docs.where((doc) {
                  final d = doc.data();

                  if (q.isEmpty) return true;

                  return _text(d['name']).toLowerCase().contains(q) ||
                      _text(d['vendorName']).toLowerCase().contains(q) ||
                      _text(d['shopName']).toLowerCase().contains(q) ||
                      _text(d['category']).toLowerCase().contains(q) ||
                      doc.id.toLowerCase().contains(q);
                }).toList();

                docs.sort((a, b) {
                  final ad = a.data()['createdAt'];
                  final bd = b.data()['createdAt'];
                  final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
                  final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);
                  return bt.compareTo(at);
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No vendor products found'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    return _productCard(docs[i].id, docs[i].data());
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 720;

          final search = TextField(
            decoration: const InputDecoration(
              hintText: 'Search product/vendor/category...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => searchText = v),
          );

          final filter = DropdownButtonFormField<String>(
            initialValue: statusFilter,
            decoration: const InputDecoration(
              labelText: 'Approval Status',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'approved', child: Text('Approved')),
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

  Widget _productCard(String productId, Map<String, dynamic> data) {
    final name = _text(data['name'], 'Product');
    final image = _text(data['image']);
    final vendorName = _text(data['vendorName'] ?? data['shopName'], 'Vendor');
    final category = _text(data['category'], 'No category');
    final status = _text(data['approvalStatus'], 'pending');
    final price = _toDouble(data['price']);
    final stock = _toInt(data['stock']);
    final reason = _text(data['rejectedReason']);

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
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 760;

            final info = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_not_supported),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vendor: $vendorName',
                        style: const TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(status.toUpperCase(), _statusColor(status)),
                          _chip('৳${price.toStringAsFixed(0)}', Colors.green),
                          _chip('Stock: $stock',
                              stock <= 5 ? Colors.red : Colors.blue),
                        ],
                      ),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Rejected reason: $reason',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status != 'approved')
                  ElevatedButton.icon(
                    onPressed: () => _updateProductStatus(
                      productId,
                      'approved',
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (status != 'rejected')
                  OutlinedButton.icon(
                    onPressed: () => _rejectDialog(productId),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _updateProductStatus(
                    productId,
                    'pending',
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Pending'),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info,
                  const Divider(height: 22),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 12),
                SizedBox(width: 330, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    return Colors.orange;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
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
