import 'package:flutter/material.dart';
import '../../utils/order_status_bn.dart';
import '../../utils/customer_notification_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import 'package:flutter/foundation.dart';
import 'customer_order_tracking_page.dart';
import '../../utils/price_format.dart';
import '../../utils/image_url.dart';
import '../../utils/variant_display_name.dart';

class OrderPage extends StatelessWidget {
  const OrderPage({super.key});

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

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('dd MMM yyyy, hh:mm a').format(value.toDate());
    }
    return 'N/A';
  }

  String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDesktop = kIsWeb && MediaQuery.of(context).size.width >= 1024;

    final PreferredSizeWidget? mobileAppBar = isDesktop
        ? null
        : AppBar(
      title: const Text('আমার অর্ডার'),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    );

    Widget pageBody;

    if (user == null) {
      pageBody = CustomScrollView(
        slivers: [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('অর্ডার দেখতে লগইন করুন')),
          ),
          if (isDesktop)
            const SliverToBoxAdapter(child: GlobalWebFooter()),
        ],
      );
    } else {
      pageBody = StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Orders load failed: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                ),
                if (isDesktop)
                  const SliverToBoxAdapter(child: GlobalWebFooter()),
              ],
            );
          }

          final orders = snapshot.data!.docs;

          return RefreshIndicator(
            onRefresh: () async {},
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 28 : 14,
                    vertical: 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final doc = orders[index];
                        final data = doc.data() as Map<String, dynamic>;
                        return _orderCard(context, doc.id, data);
                      },
                      childCount: orders.length,
                    ),
                  ),
                ),

                // Extra gap keeps the footer lower when there are only 1-2 orders.
                if (isDesktop)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.38,
                    ),
                  ),

                if (isDesktop)
                  const SliverToBoxAdapter(child: GlobalWebFooter()),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: mobileAppBar,
      body: Column(
        children: [
          if (isDesktop) const GlobalWebHeader(),
          Expanded(child: pageBody),
        ],
      ),
    );
  }

  Widget _orderCard(BuildContext context, String orderId, Map<String, dynamic> data) {
    final status = _text(data['status'], 'pending');
    final items = data['items'] is List ? data['items'] as List : [];
    final address = data['address'] is Map ? Map<String, dynamic>.from(data['address']) : <String, dynamic>{};
    final vendorIds = data['vendorIds'] is List ? List.from(data['vendorIds']) : [];
    final hasVendorItems = data['hasVendorItems'] == true || vendorIds.isNotEmpty;
    final orderType = _text(data['orderType'], hasVendorItems ? 'marketplace' : 'best selling');

    final totals = _calculateTotals(data, items);
    final dateStr = _dateText(data['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Expanded(
              child: Text(
                'অর্ডার #${_shortId(orderId)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            Text(
              '৳${totals['grandTotal']!.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF32A8C7),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statusChip(status),
              // Marketplace orders only; the old "Best Selling" tag on every
              // other order meant nothing to shoppers.
              if (orderType == 'marketplace') _miniChip('বিক্রেতার পণ্য', Colors.deepPurple),
              _miniChip('${bnNumber(items.length)}টি পণ্য', Colors.blueGrey),
              Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 20),
                _sectionTitle('অর্ডার ট্র্যাকিং'),
                const SizedBox(height: 10),
                _statusTimeline(status, _text(data['deliveryStatus'])),
                const SizedBox(height: 18),

                _sectionTitle('অর্ডারের পণ্য'),
                const SizedBox(height: 8),
                ...items.map((item) => _itemRow(item)),

                const Divider(height: 24),
                _sectionTitle('পেমেন্টের হিসাব'),
                const SizedBox(height: 10),
                _paymentRow('পণ্যের দাম', formatTaka(totals['totalMrp']!)),
                if (totals['productDiscount']! > 0)
                  _paymentRow('পণ্যে ছাড়', '-${formatTaka(totals['productDiscount']!)}', valueColor: Colors.red),
                if (totals['couponDiscount']! > 0)
                  _paymentRow('কুপন ছাড়', '-${formatTaka(totals['couponDiscount']!)}', valueColor: Colors.red),
                if (totals['chalakCharCashUsed']! > 0)
                  _paymentRow('ChalakChar Cash ব্যবহার', '-${formatTaka(totals['chalakCharCashUsed']!)}', valueColor: Colors.red),
                _paymentRow('ছাড়ের পর', formatTaka(totals['subtotalAfterDiscount']!)),
                _paymentRow('ডেলিভারি চার্জ', '+${formatTaka(totals['deliveryCharge']!)}', valueColor: Colors.green),
                const Divider(height: 18),
                _paymentRow(
                  'সর্বমোট',
                  formatTaka(totals['grandTotal']!),
                  isBold: true,
                  valueColor: const Color(0xFF32A8C7),
                ),

                const Divider(height: 24),
                _sectionTitle('ডেলিভারির ঠিকানা'),
                const SizedBox(height: 8),
                _addressBox(address),

                const SizedBox(height: 18),
                _actionArea(context, orderId, status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, double> _calculateTotals(Map<String, dynamic> data, List items) {
    double totalMrp = _toDouble(data['totalMrp']);
    double subtotal = _toDouble(data['subtotal']);

    if (subtotal <= 0) {
      for (final item in items) {
        if (item is! Map) continue;
        final price = _toDouble(item['price']);
        final qty = _toInt(item['qty']);
        subtotal += price * qty;

        final oldPrice = _toDouble(item['oldPrice'] ?? item['old_price'] ?? price);
        totalMrp += (oldPrice < price ? price : oldPrice) * qty;
      }
    }

    if (totalMrp <= 0) totalMrp = subtotal;

    final couponDiscount = _toDouble(data['couponDiscount']);
    final chalakCharCashUsed =
    _toDouble(data['ChalakCharCashUsed'] ?? data['chalakcharCashUsed']);
    final deliveryCharge = _toDouble(data['deliveryCharge']);

    final paymentDiscounts = data['paymentDiscounts'] is Map
        ? Map<String, dynamic>.from(data['paymentDiscounts'])
        : <String, dynamic>{};

    double productDiscount = _toDouble(paymentDiscounts['productDiscount']);
    if (productDiscount <= 0 && totalMrp > subtotal) {
      productDiscount = totalMrp - subtotal;
    }

    double subtotalAfterDiscount = subtotal - couponDiscount - chalakCharCashUsed;
    if (paymentDiscounts.isNotEmpty) {
      subtotalAfterDiscount = totalMrp - productDiscount - couponDiscount - chalakCharCashUsed;
    }
    if (subtotalAfterDiscount < 0) subtotalAfterDiscount = 0;

    double grandTotal = _toDouble(data['grandTotal'] ?? data['finalTotal'] ?? data['total']);
    if (grandTotal <= 0) {
      grandTotal = subtotalAfterDiscount + deliveryCharge;
    }

    return {
      'totalMrp': totalMrp,
      'subtotal': subtotal,
      'productDiscount': productDiscount,
      'couponDiscount': couponDiscount,
      'chalakCharCashUsed': chalakCharCashUsed,
      'deliveryCharge': deliveryCharge,
      'subtotalAfterDiscount': subtotalAfterDiscount,
      'grandTotal': grandTotal,
    };
  }

  Widget _itemRow(dynamic item) {
    if (item is! Map) return const SizedBox.shrink();

    final itemPrice = _toDouble(item['price']);
    final qty = _toInt(item['qty']);
    final vendorId = _text(item['vendorId'], 'super_admin');
    final vendorName = _text(item['vendorName'], 'ChalakChar Mart');
    final isMarketplace = vendorId != 'super_admin';
    final unit = cleanVariantDisplayName(_text(item['unit']));

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
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _text(item['image']).isNotEmpty
                ? Image.network(
              sizedImageUrl(_text(item['image']), 120),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.medication, color: Colors.grey),
            )
                : const Icon(Icons.medication, color: Colors.grey),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_text(item['name'], 'পণ্য')} ${_text(item['strength'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _miniChip('পরিমাণ: $qty${unit.isNotEmpty ? ' • $unit' : ''}', Colors.blueGrey),
                    _miniChip(
                      isMarketplace ? vendorName : 'ChalakChar Mart',
                      isMarketplace ? Colors.deepPurple : Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '৳${(itemPrice * qty).toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _addressBox(Map<String, dynamic> address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('নাম: ${_text(address['name'], '-')}'),
          Text('ফোন: ${_text(address['phone'], '-')}'),
          Text('ঠিকানা: ${_text(address['address'], '-')}'),
          Text(
            'এলাকা: ${_text(address['division'])} → ${_text(address['district'])} → ${_text(address['upazila'])}',
          ),
        ],
      ),
    );
  }

  Widget _actionArea(BuildContext context, String orderId, String status) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomerOrderTrackingPage(
                    orderId: orderId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('অর্ডার ট্র্যাক করুন'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF32A8C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        if (status == 'pending') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCancelConfirmation(context, orderId),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('অর্ডার বাতিল করুন'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text(
            status == 'cancelled'
                ? 'এই অর্ডারটি বাতিল করা হয়েছে'
                : 'অর্ডারটি প্রক্রিয়াধীন আছে',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }



  Widget _statusTimeline(String status, String deliveryStatus) {
    // Same steps and words as the Track Order page (order_status_bn.dart).
    final steps = orderStepsBn;

    if (status == 'cancelled' || status == 'rejected') {
      return Row(
        children: [
          _timelineDot(true, Colors.red),
          const SizedBox(width: 8),
          const Text('বাতিল করা হয়েছে', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      );
    }

    final activeIndex = orderStepIndex(status, deliveryStatus);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(steps.length, (i) {
          final active = i <= activeIndex;
          return Row(
            children: [
              _timelineDot(active, active ? const Color(0xFF32A8C7) : Colors.grey),
              const SizedBox(width: 6),
              Text(
                steps[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? const Color(0xFF32A8C7) : Colors.grey,
                ),
              ),
              if (i != steps.length - 1)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  height: 2,
                  width: 24,
                  color: active ? const Color(0xFF32A8C7) : Colors.grey.shade300,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _timelineDot(bool active, Color color) {
    return CircleAvatar(
      radius: 7,
      backgroundColor: active ? color : Colors.grey.shade300,
      child: active ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 12,
        color: Colors.blueGrey,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _paymentRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor ?? Colors.black,
              fontSize: isBold ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color = Colors.orange;
    String label = CustomerNotificationView.orderStatusBn[status] ?? status;

    if (status == 'delivered') {
      color = Colors.green;
    } else if (status == 'cancelled' || status == 'rejected') {
      color = Colors.red;
    } else if (status == 'confirmed' || status == 'assigned_to_rider') {
      color = const Color(0xFF32A8C7);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'এখনো কোনো অর্ডার নেই',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'কেনাকাটা শুরু করুন, আপনার অর্ডারগুলো এখানে দেখাবে।',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation(BuildContext context, String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('অর্ডার বাতিল করবেন?'),
        content: const Text('আপনি কি এই অর্ডারটি বাতিল করতে চান? বাতিল করলে আর ফেরানো যাবে না।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('না, রাখুন'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _cancelOrder(context, orderId);
            },
            child: const Text('হ্যাঁ, বাতিল করুন', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelOrder(BuildContext context, String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ref = FirebaseFirestore.instance.collection('orders').doc(orderId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snap = await transaction.get(ref);
        final data = snap.data() ?? <String, dynamic>{};

        if (data['userId'] != user.uid) {
          throw Exception('You are not allowed to cancel this order.');
        }

        final status = _text(data['status'], 'pending').toLowerCase();
        if (status != 'pending') {
          throw Exception('Only pending orders can be cancelled.');
        }

        transaction.update(ref, {
          'status': 'cancelled',
          'cancelledBy': 'customer',
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('অর্ডারটি বাতিল করা হয়েছে')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('অর্ডারটি বাতিল করা যায়নি। পেজ রিফ্রেশ করে আবার চেষ্টা করুন।')),
        );
      }
    }
  }
}



