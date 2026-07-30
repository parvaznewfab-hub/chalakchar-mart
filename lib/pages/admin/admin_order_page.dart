import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/vendor_commission_service.dart';
import '../../services/thermal_invoice_service.dart';
import 'admin_edit_order_page.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  String searchText = '';
  String statusFilter = 'all';

  bool _permissionLoading = true;
  bool _canViewOrders = false;
  bool _canEditOrders = false;
  bool _canAssignRider = false;
  bool _canInvoice = false;
  bool _canSettleCod = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final canAccess = await authService.canAccessAdminPanel();
      final canView = await authService.hasPermission('orders.view');
      final canEdit = await authService.hasPermission('orders.edit');
      final canAssign = await authService.hasPermission('orders.assign_rider');
      final canInvoice = await authService.hasPermission('orders.invoice');
      final canSettle = await authService.hasPermission('orders.settle_cod');

      if (!mounted) return;
      setState(() {
        _canViewOrders = canAccess && (canView || canEdit);
        _canEditOrders = canAccess && canEdit;
        _canAssignRider = canAccess && (canAssign || canEdit);
        _canInvoice = canAccess && canInvoice;
        _canSettleCod = canAccess && (canSettle || canEdit);
        _permissionLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canViewOrders = false;
        _canEditOrders = false;
        _canAssignRider = false;
        _canInvoice = false;
        _canSettleCod = false;
        _permissionLoading = false;
      });
    }
  }

  bool _deny(String message) {
    _snack(message);
    return false;
  }


  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, {int fallback = 1}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  Map<String, double> _breakdown(Map<String, dynamic> data) {
    final items = data['items'] as List? ?? [];

    // ✅ IMPORTANT:
    // item['price'] is already the selling price.
    // item['oldPrice'] / item['lineMrpTotal'] is only for showing MRP saving.
    // So product discount must NOT be deducted again from the payable total.
    double sellingSubtotal = 0;
    double mrpTotal = 0;

    for (final item in items) {
      if (item is! Map) continue;

      final qty = _toInt(item['qty']);
      final sellingPrice = _toDouble(item['price']);

      double oldPrice = _toDouble(
        item['oldPrice'] ?? item['old_price'] ?? item['mrp'] ?? sellingPrice,
      );

      if (oldPrice < sellingPrice) oldPrice = sellingPrice;

      sellingSubtotal += sellingPrice * qty;
      mrpTotal += oldPrice * qty;
    }

    final paymentDiscounts = data['paymentDiscounts'] as Map? ?? {};

    final couponDiscount = _toDouble(
      paymentDiscounts['couponDiscount'] ?? data['couponDiscount'],
    );

    final chalakCharCashUsed = _toDouble(
      paymentDiscounts['chalakCharCashUsed'] ??
          data['chalakCharCashUsed'] ??
          data['abdCashUsed'],
    );

    final deliveryCharge = _toDouble(data['deliveryCharge']);

    // ✅ This is only display saving from MRP, not payable deduction.
    final mrpSaving = (mrpTotal - sellingSubtotal).clamp(0, double.infinity).toDouble();

    // ✅ If order already has final total from checkout, trust it first.
    final savedGrandTotal = _toDouble(data['grandTotal'] ?? data['finalTotal'] ?? data['total']);

    double grandTotal = savedGrandTotal > 0
        ? savedGrandTotal
        : sellingSubtotal - couponDiscount - chalakCharCashUsed + deliveryCharge;

    if (grandTotal < 0) grandTotal = 0;

    final subtotalAfterDiscount = (grandTotal - deliveryCharge).clamp(0, double.infinity).toDouble();

    return {
      'totalMrp': mrpTotal > 0 ? mrpTotal : sellingSubtotal,
      'sellingSubtotal': sellingSubtotal,
      'productDiscount': mrpSaving,
      'couponDiscount': couponDiscount,
      'abdCashUsed': chalakCharCashUsed,
      'deliveryCharge': deliveryCharge,
      'subtotalAfterDiscount': subtotalAfterDiscount,
      'grandTotal': grandTotal,
    };
  }

  List<QueryDocumentSnapshot> _filterOrders(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status']).isEmpty ? 'pending' : _text(data['status']);

      if (statusFilter != 'all' && status != statusFilter) return false;

      if (s.isEmpty) return true;

      final userName = _text(data['userName']).toLowerCase();
      final phone = _text(data['phone'] ?? data['userPhone']).toLowerCase();
      final id = doc.id.toLowerCase();

      return userName.contains(s) || phone.contains(s) || id.contains(s);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'ready_for_pickup':
        return Colors.purple;
      case 'assigned_to_rider':
        return Colors.indigo;
      case 'picked_up':
        return Colors.deepPurple;
      case 'on_the_way':
        return Colors.teal;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);

    return Chip(
      label: Text(status.replaceAll('_', ' ').toUpperCase()),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    );
  }

  Future<void> _updateStatus(String orderId, String status) async {
    if (!_canEditOrders) {
      _deny('You do not have permission to update order status.');
      return;
    }
    final orderDoc = await db.collection('orders').doc(orderId).get();
    final data = orderDoc.data() ?? {};

    final vendorIds = data['vendorIds'] is List
        ? List<String>.from(data['vendorIds'].map((e) => e.toString()))
        : <String>[];

    final updateData = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (status == 'cancelled' || status == 'delivered') {
      for (final vendorId in vendorIds) {
        updateData['vendorStatusUpdates.$vendorId'] = {
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }
    }

    if (status == 'delivered') {
      updateData['paymentStatus'] = 'paid';
      updateData['deliveredAt'] = FieldValue.serverTimestamp();
    }

    if (status == 'cancelled') {
      updateData['cancelledAt'] = FieldValue.serverTimestamp();
    }

    await db.collection('orders').doc(orderId).update(updateData);

    if (status == 'delivered') {
      await VendorCommissionService.markOrderDelivered(orderId: orderId);
    }

    if (status == 'cancelled') {
      await VendorCommissionService.markOrderCancelled(orderId: orderId);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Order status updated to $status')),
    );
  }


  String _generateDeliveryOtp() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (1000 + (ms % 9000)).toString();
  }

  bool _isLocalDeliveryOrder(Map<String, dynamic> data) {
    final address = data['address'] as Map? ?? {};
    final upazila = _text(address['upazila']).toLowerCase();
    final addressText = _text(address['address'] ?? data['addressText'] ?? data['address']).toLowerCase();

    return upazila.contains('monohardi') ||
        upazila.contains('মনোহরদী') ||
        addressText.contains('monohardi') ||
        addressText.contains('মনোহরদী');
  }

  Future<void> _updateDeliveryStatus(String orderId, String deliveryStatus) async {
    if (!_canAssignRider) {
      _deny('You do not have permission to update delivery status.');
      return;
    }
    final Map<String, dynamic> updateData = {
      'deliveryStatus': deliveryStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (deliveryStatus == 'picked_up') {
      updateData['status'] = 'picked_up';
      updateData['pickedUpAt'] = FieldValue.serverTimestamp();
    } else if (deliveryStatus == 'on_the_way') {
      updateData['status'] = 'on_the_way';
      updateData['onTheWayAt'] = FieldValue.serverTimestamp();
    } else if (deliveryStatus == 'delivered') {
      updateData['status'] = 'delivered';
      updateData['paymentStatus'] = 'paid';
      updateData['deliveredAt'] = FieldValue.serverTimestamp();
    }

    await db.collection('orders').doc(orderId).update(updateData);
    if (deliveryStatus == 'delivered') {
      await VendorCommissionService.markOrderDelivered(orderId: orderId);
    }
    _snack('Delivery status updated to ${deliveryStatus.replaceAll('_', ' ')}');
  }

  Future<void> _assignDeliveryPartner({
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    if (!_canAssignRider) {
      _deny('You do not have permission to assign delivery partner.');
      return;
    }
    QueryDocumentSnapshot<Map<String, dynamic>>? selectedPartner;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assign Delivery Partner'),
              content: SizedBox(
                width: 460,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('deliveryPartners')
                      .where('status', isEqualTo: 'approved')
                      .where('isActive', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final partners = snap.data!.docs;

                    if (partners.isEmpty) {
                      return const Text('No approved active delivery partner found.');
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<QueryDocumentSnapshot<Map<String, dynamic>>>(
                          initialValue: selectedPartner,
                          decoration: const InputDecoration(
                            labelText: 'Select delivery partner',
                            border: OutlineInputBorder(),
                          ),
                          items: partners.map((doc) {
                            final p = doc.data();
                            final name = _text(p['name']).isEmpty ? 'Delivery Partner' : _text(p['name']);
                            final area = _text(p['preferredArea']);
                            final phone = _text(p['phone']);

                            return DropdownMenuItem(
                              value: doc,
                              child: Text(
                                '$name${area.isNotEmpty ? ' • $area' : ''}${phone.isNotEmpty ? ' • $phone' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setDialogState(() => selectedPartner = v),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Assign করলে order status "Assigned to rider" হবে এবং delivery OTP তৈরি হবে.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: selectedPartner == null
                      ? null
                      : () async {
                    final p = selectedPartner!.data();
                    final currentOtp = _text(orderData['deliveryOtp']);
                    final otp = currentOtp.isNotEmpty ? currentOtp : _generateDeliveryOtp();

                    await db.collection('orders').doc(orderId).update({
                      'deliveryPartnerId': selectedPartner!.id,
                      'deliveryPartnerName': _text(p['name'],),
                      'deliveryPartnerPhone': _text(p['phone']),
                      'deliveryPartnerArea': _text(p['preferredArea']),
                      'deliveryVehicleType': _text(p['vehicleType']),
                      'deliveryStatus': 'assigned',
                      'deliveryOtp': otp,
                      'status': 'assigned_to_rider',
                      'assignedAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    _snack('Delivery partner assigned');
                  },
                  icon: const Icon(Icons.delivery_dining),
                  label: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _settleRiderCash({
    required String orderId,
    required String riderId,
    required double amount,
  }) async {
    if (!_canSettleCod) {
      _deny('You do not have permission to settle rider COD.');
      return;
    }
    if (orderId.isEmpty || riderId.isEmpty || amount <= 0) return;

    final orderRef = db.collection('orders').doc(orderId);
    final partnerRef = db.collection('deliveryPartners').doc(riderId);

    try {
      await db.runTransaction((transaction) async {
        final orderSnap = await transaction.get(orderRef);
        final partnerSnap = await transaction.get(partnerRef);

        final order = orderSnap.data() ?? <String, dynamic>{};
        final partner = partnerSnap.data() ?? <String, dynamic>{};

        if (order['riderCashSettled'] == true) {
          throw Exception('This COD has already been settled.');
        }

        final currentCodDue = _toDouble(partner['codDue']);
        final newCodDue = currentCodDue - amount;

        transaction.set(partnerRef, {
          'codDue': newCodDue < 0 ? 0 : newCodDue,
          'lastCodSettlementAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(orderRef, {
          'riderCashSettled': true,
          'riderCashSettledAt': FieldValue.serverTimestamp(),
          'riderCashSettledAmount': amount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      _snack('Rider COD settled');
    } catch (e) {
      _snack('COD settle failed: $e');
    }
  }

  Widget _deliveryInfoPanel(String orderId, Map<String, dynamic> data) {
    final isLocal = _isLocalDeliveryOrder(data);
    final partnerId = _text(data['deliveryPartnerId']);
    final partnerName = _text(data['deliveryPartnerName']);
    final partnerPhone = _text(data['deliveryPartnerPhone']);
    final deliveryStatus = _text(data['deliveryStatus']).isEmpty ? 'not_assigned' : _text(data['deliveryStatus']);
    final deliveryOtp = _text(data['deliveryOtp']);
    final riderCashSettled = data['riderCashSettled'] == true;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLocal ? Colors.teal.withValues(alpha:0.06) : Colors.blueGrey.withValues(alpha:0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocal ? Colors.teal.withValues(alpha:0.24) : Colors.blueGrey.withValues(alpha:0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLocal ? Icons.delivery_dining_rounded : Icons.local_shipping_outlined,
                color: isLocal ? Colors.teal : Colors.blueGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLocal ? 'Local Delivery Control' : 'Delivery Control',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _statusChip(deliveryStatus),
            ],
          ),
          const SizedBox(height: 10),
          if (partnerId.isEmpty)
            Text(
              'No delivery partner assigned yet.',
              style: TextStyle(color: Colors.grey.shade700),
            )
          else ...[
            _infoRow(Icons.person, 'Rider: $partnerName'),
            _infoRow(Icons.call, 'Rider phone: $partnerPhone'),
            if (deliveryOtp.isNotEmpty) _infoRow(Icons.pin, 'Delivery OTP: $deliveryOtp'),
            if (riderCashSettled) _infoRow(Icons.verified, 'COD settlement: Done'),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_canAssignRider)
                _actionButton(
                  icon: partnerId.isEmpty ? Icons.person_add_alt_1 : Icons.swap_horiz,
                  label: partnerId.isEmpty ? 'Assign Rider' : 'Change Rider',
                  color: Colors.indigo,
                  onTap: () => _assignDeliveryPartner(orderId: orderId, orderData: data),
                ),
              if (partnerId.isNotEmpty && _canAssignRider) ...[
                _actionButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Picked Up',
                  color: Colors.deepPurple,
                  onTap: () => _updateDeliveryStatus(orderId, 'picked_up'),
                ),
                _actionButton(
                  icon: Icons.directions_bike,
                  label: 'On The Way',
                  color: Colors.teal,
                  onTap: () => _updateDeliveryStatus(orderId, 'on_the_way'),
                ),
                _actionButton(
                  icon: Icons.done_all_rounded,
                  label: 'Delivered',
                  color: Colors.green,
                  onTap: () => _updateDeliveryStatus(orderId, 'delivered'),
                ),
                if (_canSettleCod && deliveryStatus == 'delivered' && partnerId.isNotEmpty && !riderCashSettled)
                  _actionButton(
                    icon: Icons.payments_rounded,
                    label: 'Settle COD',
                    color: Colors.green,
                    onTap: () async {
                      final amount = _toDouble(
                        data['grandTotal'] ?? data['finalTotal'] ?? data['total'],
                      );

                      await _settleRiderCash(
                        orderId: orderId,
                        riderId: partnerId,
                        amount: amount,
                      );
                    },
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }


  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty) {
      _snack('Phone number not found');
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsAppCustomer(String phone, String orderId) async {
    if (phone.isEmpty) {
      _snack('Phone number not found');
      return;
    }

    String clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('0')) {
      clean = '88$clean';
    }

    final msg = Uri.encodeComponent(
      'Hello, your order #${orderId.substring(0, 8)} from ChalakChar Mart is being processed.',
    );

    final uri = Uri.parse('https://wa.me/$clean?text=$msg');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _generateInvoice({
    required BuildContext context,
    required String orderId,
    required Map<String, dynamic> data,
  }) async {
    if (!_canInvoice) {
      _deny('You do not have permission to generate invoice.');
      return;
    }
    final b = _breakdown(data);
    final items = data['items'] as List? ?? [];
    final address = data['address'] as Map? ?? {};

    final pdf = pw.Document();

    final createdAt = data['createdAt'] is Timestamp
        ? DateFormat('dd MMM yyyy, hh:mm a').format(
      (data['createdAt'] as Timestamp).toDate(),
    )
        : 'N/A';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ChalakChar Mart',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('Chalak Char Bazar, Monohardi, Narsingdi'),
                  pw.Text('Phone: 01975838764'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('#${orderId.substring(0, 8)}'),
                  pw.Text(createdAt),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 10),

          pw.Text(
            'Customer Information',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Name: ${_text(data['userName'])}'),
          pw.Text('Phone: ${_text(data['phone'] ?? data['userPhone'])}'),
          pw.Text(
            'Address: ${_text(address['address'] ?? data['addressText'] ?? data['address'])}',
          ),

          pw.SizedBox(height: 18),

          pw.TableHelper.fromTextArray(
            headers: [
              'SL',
              'Product',
              'Qty',
              pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            ],
            data: List.generate(items.length, (index) {
              final item = items[index] as Map;
              final price = _toDouble(item['price']);
              final qty = _toInt(item['qty']);
              return [
                '${index + 1}',
                '${_text(item['name'])} ${_text(item['unit']).isEmpty ? '' : '(${_text(item['unit'])})'}',
                '$qty',
                price.toStringAsFixed(2),
                (price * qty).toStringAsFixed(2),
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            textStyleBuilder: (index, data, rowNum) =>
                index == 3 || index == 4 ? const pw.TextStyle(fontSize: 9) : null,
            columnWidths: {
              0: const pw.FixedColumnWidth(30),   // SL
              1: const pw.FlexColumnWidth(4),     // Product name
              2: const pw.FixedColumnWidth(36),   // Qty
              3: const pw.FixedColumnWidth(75),   // Price
              4: const pw.FixedColumnWidth(75),   // Total
            },
          ),

          pw.SizedBox(height: 18),

          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 240,
              child: pw.Column(
                children: [
                  _pdfAmountRow('Total MRP', b['totalMrp']!),
                  _pdfAmountRow('Product Discount', -b['productDiscount']!),
                  _pdfAmountRow('Coupon Discount', -b['couponDiscount']!),
                  _pdfAmountRow('ChalakChar Mart Cash Used', -b['abdCashUsed']!),
                  _pdfAmountRow('Delivery Charge', b['deliveryCharge']!),
                  pw.Divider(),
                  _pdfAmountRow(
                    'Grand Total',
                    b['grandTotal']!,
                    bold: true,
                  ),
                ],
              ),
            ),
          ),

          pw.SizedBox(height: 30),
          pw.Text('Thank you for shopping with ChalakChar Mart.'),
        ],
      ),
    );

    final bytes = await pdf.save();
    final fileName = 'invoice_${orderId.substring(0, 8)}.pdf';

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = fileName
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    }
  }

  pw.Widget _pdfAmountRow(String title, double amount, {bool bold = false}) {
    final style = bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: style),
          pw.Text(amount.toStringAsFixed(2), style: style),
        ],
      ),
    );
  }

  Future<void> _posPrint(String orderId, Map<String, dynamic> data) async {
    if (!_canInvoice) {
      _deny('You do not have permission to print invoice.');
      return;
    }
    try {
      await ThermalInvoiceService.printOrderReceipt(
        printerIp: '192.168.0.100',
        orderId: orderId,
        order: data,
        breakdown: _breakdown(data),
      );

      _snack('POS receipt printed successfully');
    } catch (e) {
      _snack('POS print failed: $e');
    }
  }

  Future<void> _openEdit(String orderId) async {
    if (!_canEditOrders) {
      _deny('You do not have permission to edit orders.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEditOrderPage(orderId: orderId),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha:0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_canViewOrders) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. You need orders.view permission.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Order Manager Pro',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: db
                          .collection('orders')
                          .where('status', isEqualTo: 'pending')
                          .snapshots(),
                      builder: (context, snap) {
                        final count = snap.data?.docs.length ?? 0;
                        return Chip(
                          avatar: const Icon(Icons.pending_actions, size: 18),
                          label: Text('$count Pending'),
                          backgroundColor: Colors.orange.withValues(alpha:0.12),
                          labelStyle: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    final isSmall = c.maxWidth < 800;

                    final search = TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by order id, customer, phone...',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => searchText = v),
                    );

                    final filter = DropdownButtonFormField<String>(
                      initialValue: statusFilter,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                        DropdownMenuItem(value: 'ready_for_pickup', child: Text('Ready Pickup')),
                        DropdownMenuItem(value: 'assigned_to_rider', child: Text('Assigned Rider')),
                        DropdownMenuItem(value: 'picked_up', child: Text('Picked Up')),
                        DropdownMenuItem(value: 'on_the_way', child: Text('On The Way')),
                        DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                        DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                      ],
                      onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
                    );

                    if (isSmall) {
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
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('orders')
                  .orderBy('createdAt', descending: true)
                  .limit(300)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('No orders found'));
                }

                final orders = _filterOrders(snap.data!.docs);

                if (orders.isEmpty) {
                  return const Center(child: Text('No matching orders'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = orders[index];
                    final id = doc.id;
                    final data = doc.data() as Map<String, dynamic>;
                    final items = data['items'] as List? ?? [];
                    final address = data['address'] as Map? ?? {};
                    final status = _text(data['status']).isEmpty
                        ? 'pending'
                        : _text(data['status']);
                    final b = _breakdown(data);

                    final createdAt = data['createdAt'] is Timestamp
                        ? DateFormat('dd MMM yyyy, hh:mm a').format(
                      (data['createdAt'] as Timestamp).toDate(),
                    )
                        : 'N/A';

                    final phone = _text(data['phone'] ?? data['userPhone']);
                    final addressText = _text(
                      address['address'] ?? data['addressText'] ?? data['address'],
                    );

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Order #${id.substring(0, 8)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _statusChip(status),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _text(data['userName']).isEmpty
                                    ? 'Customer'
                                    : _text(data['userName']),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              _infoRow(Icons.access_time, createdAt),
                              _infoRow(Icons.call, phone),
                              _infoRow(Icons.location_on_outlined, addressText),
                              const SizedBox(height: 6),
                              Text(
                                'Grand Total: ৳${b['grandTotal']!.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        children: [
                          const Divider(),

                          Row(
                            children: [
                              const Text(
                                'Update Status:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: status,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                                    DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                                    DropdownMenuItem(value: 'ready_for_pickup', child: Text('Ready for pickup')),
                                    DropdownMenuItem(value: 'assigned_to_rider', child: Text('Assigned to rider')),
                                    DropdownMenuItem(value: 'picked_up', child: Text('Picked up')),
                                    DropdownMenuItem(value: 'on_the_way', child: Text('On the way')),
                                    DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                                  ],
                                  onChanged: _canEditOrders
                                      ? (v) {
                                    if (v != null && v != status) {
                                      _updateStatus(id, v);
                                    }
                                  }
                                      : null,
                                ),
                              ),
                            ],
                          ),

                          _deliveryInfoPanel(id, data),

                          const SizedBox(height: 16),

                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Order Items',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          ...items.map((item) {
                            if (item is! Map) return const SizedBox.shrink();

                            final price = _toDouble(item['price']);
                            final qty = _toInt(item['qty']);
                            final vendorId = _text(item['vendorId']).isEmpty
                                ? 'super_admin'
                                : _text(item['vendorId']);

                            final vendorName = _text(item['vendorName']).isEmpty
                                ? 'ChalakChar Mart'
                                : _text(item['vendorName']);

                            final isMarketplace = vendorId != 'super_admin';
                            final aliExpressLink = _text(item['aliExpressLink']);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isMarketplace
                                          ? Colors.deepPurple.withValues(alpha: 0.08)
                                          : Colors.green.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isMarketplace
                                          ? 'Vendor: $vendorName'
                                          : 'Sold by: ChalakChar Mart',
                                      style: TextStyle(
                                        color: isMarketplace ? Colors.deepPurple : Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_text(item['name'])} ${_text(item['unit']).isEmpty ? '' : '(${_text(item['unit'])})'}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text('x$qty'),
                                      const SizedBox(width: 14),
                                      Text(
                                        '৳${(price * qty).toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  if (aliExpressLink.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () => launchUrl(
                                        Uri.parse(aliExpressLink),
                                        mode: LaunchMode.externalApplication,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.shopping_bag_outlined, size: 15, color: Colors.deepOrange),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Buy on AliExpress',
                                              style: const TextStyle(
                                                color: Colors.deepOrange,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                decoration: TextDecoration.underline,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),

                          const SizedBox(height: 12),

                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 320,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                children: [
                                  _amountRow('Total MRP', b['totalMrp']!),
                                  _amountRow('Product Discount', -b['productDiscount']!),
                                  _amountRow('Coupon Discount', -b['couponDiscount']!),
                                  _amountRow('ChalakChar Mart Cash Used', -b['abdCashUsed']!),
                                  _amountRow('Delivery Charge', b['deliveryCharge']!),
                                  const Divider(),
                                  _amountRow(
                                    'Grand Total',
                                    b['grandTotal']!,
                                    bold: true,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_canEditOrders)
                                _actionButton(
                                  icon: Icons.edit_rounded,
                                  label: 'Edit',
                                  color: Colors.orange,
                                  onTap: () => _openEdit(id),
                                ),
                              if (_canInvoice)
                                _actionButton(
                                  icon: Icons.picture_as_pdf_rounded,
                                  label: 'Invoice',
                                  color: Colors.redAccent,
                                  onTap: () => _generateInvoice(
                                    context: context,
                                    orderId: id,
                                    data: data,
                                  ),
                                ),
                              if (_canInvoice)
                                _actionButton(
                                  icon: Icons.print_rounded,
                                  label: 'POS Print',
                                  color: Colors.teal,
                                  onTap: () => _posPrint(id, data),
                                ),
                              _actionButton(
                                icon: Icons.call_rounded,
                                label: 'Call',
                                color: Colors.blue,
                                onTap: () => _callCustomer(phone),
                              ),
                              _actionButton(
                                icon: Icons.chat_rounded,
                                label: 'WhatsApp',
                                color: Colors.green,
                                onTap: () => _whatsAppCustomer(phone, id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String title, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            '৳${amount.toStringAsFixed(2)}',
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
