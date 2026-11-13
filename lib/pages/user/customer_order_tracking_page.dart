import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/price_format.dart';

class CustomerOrderTrackingPage extends StatefulWidget {
  final String orderId;

  const CustomerOrderTrackingPage({super.key, required this.orderId});

  @override
  State<CustomerOrderTrackingPage> createState() => _CustomerOrderTrackingPageState();
}

class _CustomerOrderTrackingPageState extends State<CustomerOrderTrackingPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
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

  Future<void> _callPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  int _statusIndex(String status, String deliveryStatus) {
    if (status == 'cancelled') return -1;
    if (status == 'delivered' || deliveryStatus == 'delivered') return 5;
    if (deliveryStatus == 'on_the_way' || status == 'on_the_way') return 4;
    if (deliveryStatus == 'picked_up' || status == 'picked_up') return 3;
    if (deliveryStatus == 'assigned' || status == 'assigned_to_rider') return 2;
    if (status == 'ready_for_pickup') return 1;
    if (status == 'confirmed') return 1;
    return 0;
  }

  Color _statusColor(String status) {
    if (status == 'cancelled') return Colors.red;
    if (status == 'delivered') return Colors.green;
    if (status == 'on_the_way') return Colors.teal;
    if (status == 'picked_up') return Colors.deepPurple;
    if (status == 'assigned' || status == 'assigned_to_rider') return Colors.indigo;
    if (status == 'ready_for_pickup') return Colors.purple;
    if (status == 'confirmed') return Colors.blue;
    return Colors.orange;
  }

  String _displayStatus(String status, String deliveryStatus) {
    if (status == 'cancelled') return 'Cancelled';
    if (deliveryStatus.isNotEmpty && deliveryStatus != 'not_assigned') {
      return deliveryStatus.replaceAll('_', ' ').toUpperCase();
    }
    return status.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Order not found'));
          }

          final data = snap.data!.data() ?? {};
          final status = _text(data['status'], 'pending');
          final deliveryStatus = _text(data['deliveryStatus'], 'not_assigned');
          final items = data['items'] is List ? data['items'] as List : [];
          final address = data['address'] is Map ? Map<String, dynamic>.from(data['address']) : <String, dynamic>{};
          final progressIndex = _statusIndex(status, deliveryStatus);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _orderHeader(data, status, deliveryStatus),
                const SizedBox(height: 14),
                _progressCard(progressIndex, status),
                const SizedBox(height: 14),
                _deliveryPartnerCard(data),
                const SizedBox(height: 14),
                _otpCard(data),
                const SizedBox(height: 14),
                _addressCard(address, data),
                const SizedBox(height: 14),
                _itemsCard(items),
                const SizedBox(height: 14),
                _paymentCard(data),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _orderHeader(Map<String, dynamic> data, String status, String deliveryStatus) {
    final display = _displayStatus(status, deliveryStatus);
    final color = _statusColor(deliveryStatus != 'not_assigned' ? deliveryStatus : status);

    String date = 'N/A';
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      final d = createdAt.toDate();
      date = '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #${widget.orderId.substring(0, 8)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  display,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Placed: $date', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(
            'Total: ৳${_toDouble(data['grandTotal'] ?? data['finalTotal'] ?? data['total']).toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(int currentIndex, String status) {
    final steps = [
      {'title': 'Order Placed', 'icon': Icons.receipt_long},
      {'title': 'Ready', 'icon': Icons.inventory_2_outlined},
      {'title': 'Rider Assigned', 'icon': Icons.delivery_dining},
      {'title': 'Picked Up', 'icon': Icons.shopping_bag_outlined},
      {'title': 'On The Way', 'icon': Icons.directions_bike},
      {'title': 'Delivered', 'icon': Icons.verified},
    ];

    if (status == 'cancelled') {
      return _simpleCard(
        title: 'Order Cancelled',
        icon: Icons.cancel,
        iconColor: Colors.red,
        child: const Text('This order has been cancelled.'),
      );
    }

    return _simpleCard(
      title: 'Delivery Progress',
      icon: Icons.timeline,
      iconColor: const Color(0xFF32A8C7),
      child: Column(
        children: List.generate(steps.length, (index) {
          final active = index <= currentIndex;
          final item = steps[index];
          final icon = item['icon'] as IconData;
          final title = item['title'] as String;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: active ? const Color(0xFF32A8C7) : Colors.grey.shade300,
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  if (index != steps.length - 1)
                    Container(
                      width: 2,
                      height: 30,
                      color: active ? const Color(0xFF32A8C7) : Colors.grey.shade300,
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w900 : FontWeight.w500,
                      color: active ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _deliveryPartnerCard(Map<String, dynamic> data) {
    final riderName = _text(data['deliveryPartnerName']);
    final riderPhone = _text(data['deliveryPartnerPhone']);
    final vehicle = _text(data['deliveryVehicleType']);

    if (riderName.isEmpty && riderPhone.isEmpty) {
      return _simpleCard(
        title: 'Delivery Partner',
        icon: Icons.delivery_dining,
        iconColor: Colors.indigo,
        child: Text('Delivery partner not assigned yet.', style: TextStyle(color: Colors.grey.shade700)),
      );
    }

    return _simpleCard(
      title: 'Delivery Partner',
      icon: Icons.delivery_dining,
      iconColor: Colors.indigo,
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF32A8C7),
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(riderName.isEmpty ? 'Delivery Partner' : riderName,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                if (vehicle.isNotEmpty) Text(vehicle, style: TextStyle(color: Colors.grey.shade600)),
                if (riderPhone.isNotEmpty) Text(riderPhone, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (riderPhone.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _callPhone(riderPhone),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _otpCard(Map<String, dynamic> data) {
    final otp = _text(data['deliveryOtp']);
    if (otp.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pin, color: Colors.deepPurple),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Delivery OTP', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          SelectableText(
            otp,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.deepPurple),
          ),
        ],
      ),
    );
  }

  Widget _addressCard(Map<String, dynamic> address, Map<String, dynamic> data) {
    return _simpleCard(
      title: 'Delivery Address',
      icon: Icons.location_on_outlined,
      iconColor: Colors.redAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text(address['name'] ?? data['userName'], 'Customer'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_text(address['phone'] ?? data['phone'] ?? data['userPhone'], 'N/A')),
          const SizedBox(height: 4),
          Text(_text(address['address'] ?? data['addressText'], 'N/A')),
          if (_text(address['upazila']).isNotEmpty || _text(address['district']).isNotEmpty)
            Text('${_text(address['upazila'])}, ${_text(address['district'])}'),
        ],
      ),
    );
  }

  Widget _itemsCard(List items) {
    return _simpleCard(
      title: 'Order Items',
      icon: Icons.shopping_bag_outlined,
      iconColor: Colors.orange,
      child: Column(
        children: items.map((raw) {
          if (raw is! Map) return const SizedBox.shrink();
          final item = Map<String, dynamic>.from(raw);
          final price = _toDouble(item['price']);
          final qty = _toInt(item['qty']);

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
                  width: 44,
                  height: 44,
                  child: Image.network(
                    _text(item['image']),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.medication),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_text(item['name'], 'Product')} ${_text(item['unit']).isNotEmpty ? '(${_text(item['unit'])})' : ''}\nQty: $qty',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('৳${(price * qty).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> data) {
    return _simpleCard(
      title: 'Payment Summary',
      icon: Icons.payments_outlined,
      iconColor: Colors.green,
      child: Column(
        children: [
          _amountRow('Subtotal', _toDouble(data['subtotal'])),
          _amountRow('Delivery Charge', _toDouble(data['deliveryCharge'])),
          if (_toDouble(data['couponDiscount']) > 0) _amountRow('Coupon Discount', -_toDouble(data['couponDiscount'])),
          if (_toDouble(data['ChalakCharCashUsed'] ?? data['chalakcharCashUsed']) > 0)
            _amountRow(
              'ChalakChar Cash Used',
              -_toDouble(data['ChalakCharCashUsed'] ?? data['chalakcharCashUsed']),
            ),
          const Divider(),
          _amountRow('Grand Total', _toDouble(data['grandTotal'] ?? data['finalTotal'] ?? data['total']), bold: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('Payment Method: ${_text(data['paymentMethod'], 'COD')}')),
              Text(_text(data['paymentStatus'], 'unpaid').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _simpleCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _amountRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500)),
          ),
          Text(
            formatTaka(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: bold ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }
}



