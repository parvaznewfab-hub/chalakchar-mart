import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';

class AdminEditOrderPage extends StatefulWidget {
  final String orderId;

  const AdminEditOrderPage({super.key, required this.orderId});

  @override
  State<AdminEditOrderPage> createState() => _AdminEditOrderPageState();
}

class _AdminEditOrderPageState extends State<AdminEditOrderPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  final TextEditingController discountController = TextEditingController();
  final TextEditingController deliveryChargeController = TextEditingController();

  List<Map<String, dynamic>> items = [];

  double total = 0;
  double discount = 0;
  double totalMrp = 0;
  double deliveryCharge = 0;
  double grandTotal = 0;

  String userId = '';
  bool loading = true;
  bool saving = false;
  bool permissionLoading = true;

  bool canViewOrder = false;
  bool canEditItems = false;
  bool canEditDiscount = false;
  bool canConfirmOrder = false;
  bool canSendNotification = false;

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await _loadPermissions();

    if (!mounted) return;

    if (!canViewOrder) {
      setState(() {
        loading = false;
        permissionLoading = false;
      });
      return;
    }

    await _loadOrder();

    if (mounted) {
      setState(() => permissionLoading = false);
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final view = await authService.hasPermission('orders.view');
      final edit = await authService.hasPermission('orders.edit');
      final discountPermission = await authService.hasPermission('orders.discount');
      final confirmPermission = await authService.hasPermission('orders.confirm');
      final notificationPermission = await authService.hasPermission('notifications.send');

      if (!mounted) return;

      setState(() {
        canViewOrder = view || edit || confirmPermission;
        canEditItems = edit;
        canEditDiscount = discountPermission || edit;
        canConfirmOrder = confirmPermission || edit;
        canSendNotification = notificationPermission;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        canViewOrder = false;
        canEditItems = false;
        canEditDiscount = false;
        canConfirmOrder = false;
        canSendNotification = false;
      });
    }
  }

  bool get _hasAnyEditPermission => canEditItems || canEditDiscount || canConfirmOrder;

  bool _requirePermission(bool allowed, String message) {
    if (allowed) return true;
    _snack(message, color: Colors.red);
    return false;
  }

  @override
  void dispose() {
    discountController.dispose();
    deliveryChargeController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) => ProductService.toDouble(value);

  int _toInt(dynamic value, {int fallback = 0}) => ProductService.toInt(value, fallback);

  String _cleanText(dynamic value, [String fallback = '']) => ProductService.text(value, fallback);

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _loadOrder() async {
    try {
      final doc = await db.collection('orders').doc(widget.orderId).get();

      if (!doc.exists) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final data = doc.data() ?? {};
      final paymentDiscounts = data['paymentDiscounts'] as Map? ?? {};

      items = List<Map<String, dynamic>>.from(
        (data['items'] as List? ?? []).whereType<Map>().map((e) {
          final item = Map<String, dynamic>.from(e);
          return {
            ...item,
            'productId': _cleanText(item['productId']),
            'name': _cleanText(item['name'], 'Product'),
            'price': _toDouble(item['price']),
            'oldPrice': _toDouble(item['oldPrice'] ?? item['price']),
            'qty': _toInt(item['qty'], fallback: 1),
            'stock': _toInt(item['stock']),
            'unit': _cleanText(item['unit'] ?? item['variantName']),
            'variantId': _cleanText(item['variantId'], 'default'),
          };
        }),
      );

      discount = _toDouble(paymentDiscounts['productDiscount'] ?? data['discount']);
      deliveryCharge = _toDouble(data['deliveryCharge']);
      userId = _cleanText(data['userId']);

      discountController.text = discount == 0 ? '' : discount.toStringAsFixed(0);
      deliveryChargeController.text = deliveryCharge == 0 ? '' : deliveryCharge.toStringAsFixed(0);

      _calculateTotal(refresh: false);
    } catch (e) {
      _snack('Order load failed: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _calculateTotal({bool refresh = true}) {
    totalMrp = 0;

    for (final item in items) {
      final price = _toDouble(item['price']);
      final qty = _toInt(item['qty'], fallback: 1);
      totalMrp += price * qty;
    }

    total = totalMrp - discount;
    if (total < 0) total = 0;

    grandTotal = total + deliveryCharge;
    if (grandTotal < 0) grandTotal = 0;

    if (refresh && mounted) setState(() {});
  }

  Future<void> _saveOrderDraft({bool closeDraft = false}) async {
    if (!_hasAnyEditPermission) {
      _snack('You do not have permission to edit this order.', color: Colors.red);
      return;
    }

    _calculateTotal(refresh: false);

    await db.collection('orders').doc(widget.orderId).update({
      'items': items,
      'totalMrp': totalMrp,
      'total': total,
      'discount': discount,
      'deliveryCharge': deliveryCharge,
      'grandTotal': grandTotal,
      'paymentDiscounts.productDiscount': discount,
      'couponDiscount': 0,
      'abdCashUsed': 0,
      'isDraft': !closeDraft,
      'isEdited': closeDraft ? true : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) setState(() {});
  }

  Future<void> _autoSave() async {
    try {
      await _saveOrderDraft();
    } catch (e) {
      _snack('Auto save failed: $e', color: Colors.red);
    }
  }

  Future<void> _addProduct({
    required Map<String, dynamic> product,
    required Map<String, dynamic> selectedVariant,
  }) async {
    if (!_requirePermission(canEditItems, 'orders.edit permission required to add products.')) {
      return;
    }

    final normalized = ProductService.normalizeProductData(product);
    final cartItem = ProductService.buildCartItem(
      normalized,
      selectedVariant,
      qty: 1,
    );

    final stock = _toInt(cartItem['stockAtAddTime'] ?? cartItem['stock']);
    if (stock <= 0) {
      _snack('Out of stock', color: Colors.red);
      return;
    }

    final productId = _cleanText(cartItem['productId']);
    final unit = _cleanText(cartItem['unit']);
    final variantId = _cleanText(cartItem['variantId'], 'default');

    final existingIndex = items.indexWhere((item) {
      final sameProduct = _cleanText(item['productId']) == productId;
      final sameVariant = _cleanText(item['variantId'], 'default') == variantId;
      final sameUnit = _cleanText(item['unit']).toLowerCase() == unit.toLowerCase();
      return sameProduct && (sameVariant || sameUnit);
    });

    if (existingIndex >= 0) {
      final currentQty = _toInt(items[existingIndex]['qty'], fallback: 1);
      if (currentQty >= stock) {
        _snack('Cannot exceed available stock', color: Colors.red);
        return;
      }

      items[existingIndex] = {
        ...items[existingIndex],
        'qty': currentQty + 1,
        'stock': stock,
        'stockAtAddTime': stock,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    } else {
      items.add({
        ...cartItem,
        'qty': 1,
        'lineTotal': _toDouble(cartItem['price']),
        'lineMrpTotal': _toDouble(cartItem['oldPrice']),
      });
    }

    await _autoSave();
  }

  Future<void> _syncStockForCurrentItems(Map<String, dynamic> orderData) async {
    final alreadyReduced = orderData['stockReduced'] == true;

    // Safety: old confirmed orders without stockReducedItems cannot calculate delta.
    // We only save current reduced list and avoid double-reducing.
    if (alreadyReduced &&
        (orderData['stockReducedItems'] is! List ||
            (orderData['stockReducedItems'] as List).isEmpty)) {
      final currentMap = ProductService.buildStockMapFromItems(items);
      await db.collection('orders').doc(widget.orderId).update({
        'stockReducedItems': ProductService.stockMapToList(currentMap),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    await ProductService.syncStockForOrderEdit(
      previousReducedItems: alreadyReduced ? orderData['stockReducedItems'] : const [],
      currentItems: items,
    );

    final currentMap = ProductService.buildStockMapFromItems(items);
    await db.collection('orders').doc(widget.orderId).set({
      'stockReduced': true,
      'stockReducedAt': FieldValue.serverTimestamp(),
      'stockReducedItems': ProductService.stockMapToList(currentMap),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _confirmOrder() async {
    if (!_requirePermission(canConfirmOrder, 'orders.confirm permission required to confirm orders.')) {
      return;
    }

    if (saving) return;

    setState(() => saving = true);

    try {
      _calculateTotal(refresh: false);

      final orderRef = db.collection('orders').doc(widget.orderId);
      final orderSnap = await orderRef.get();
      final orderData = orderSnap.data() ?? {};

      await orderRef.update({
        'items': items,
        'totalMrp': totalMrp,
        'total': total,
        'discount': discount,
        'deliveryCharge': deliveryCharge,
        'grandTotal': grandTotal,
        'paymentDiscounts.productDiscount': discount,
        'couponDiscount': 0,
        'abdCashUsed': 0,
        'status': 'confirmed',
        'isEdited': true,
        'isDraft': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _syncStockForCurrentItems(orderData);

      if (userId.isNotEmpty && canSendNotification) {
        await NotificationService.sendNotification(
          userId: userId,
          title: 'Order Confirmed! 📦',
          body:
          'Your order has been confirmed and is being prepared. Total: ৳${grandTotal.toStringAsFixed(0)}',
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Confirmation Error: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _selectProduct() {
    if (!_requirePermission(canEditItems, 'orders.edit permission required to add products.')) {
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        final TextEditingController search = TextEditingController();
        List<QueryDocumentSnapshot<Map<String, dynamic>>> allProducts = [];
        List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = [];

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Search Product'),
              content: SizedBox(
                width: 440,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        hintText: 'Search product...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          final q = val.toLowerCase().trim();
                          filtered = allProducts.where((doc) {
                            final p = ProductService.normalizeProductData(doc);
                            return ProductService.text(p['name']).toLowerCase().contains(q) ||
                                ProductService.text(p['generic']).toLowerCase().contains(q) ||
                                ProductService.text(p['manufacturer']).toLowerCase().contains(q);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        future: db
                            .collection('products')
                            .where('isActive', isEqualTo: true)
                            .limit(300)
                            .get(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (snap.hasError) {
                            return Center(child: Text('Product load failed: ${snap.error}'));
                          }

                          allProducts = snap.data?.docs ?? [];
                          if (search.text.trim().isEmpty) filtered = allProducts;

                          if (filtered.isEmpty) {
                            return const Center(child: Text('No product found'));
                          }

                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final doc = filtered[index];
                              final product = ProductService.normalizeProductData(doc);
                              final variants = ProductService.normalizeVariants(
                                product['variants'],
                                fallbackUnit: product['unit'],
                                fallbackPrice: product['price'],
                                fallbackMrp: product['oldPrice'] ?? product['mrp'],
                                fallbackStock: product['stock'],
                              );

                              return ExpansionTile(
                                title: Text(ProductService.text(product['name'], 'Product')),
                                subtitle: Text(
                                  '${ProductService.text(product['category'], 'Other')} • Total Stock: ${ProductService.getStock(product)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                children: variants.map((variant) {
                                  final unit = ProductService.text(variant['name'], 'Default');
                                  final price = ProductService.toDouble(variant['price']);
                                  final mrp = ProductService.toDouble(variant['mrp'] ?? variant['oldPrice'] ?? price);
                                  final stock = ProductService.toInt(variant['stock']);

                                  return ListTile(
                                    dense: true,
                                    enabled: stock > 0,
                                    title: Text(unit),
                                    subtitle: Text(
                                      '৳${price.toStringAsFixed(2)}'
                                          '${mrp > price ? '  MRP ৳${mrp.toStringAsFixed(2)}' : ''}'
                                          '  Stock: $stock',
                                    ),
                                    trailing: stock > 0
                                        ? const Icon(Icons.add_circle_outline)
                                        : const Text('Out', style: TextStyle(color: Colors.red)),
                                    onTap: stock <= 0
                                        ? null
                                        : () {
                                      Navigator.pop(context);
                                      _addProduct(
                                        product: product,
                                        selectedVariant: variant,
                                      );
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<int> _latestStockForItem(Map<String, dynamic> item) async {
    final productId = _cleanText(item['productId']);
    if (productId.isEmpty) return _toInt(item['stock']);

    final doc = await db.collection('products').doc(productId).get();
    if (!doc.exists) return 0;

    final product = ProductService.normalizeProductData(doc);
    if (product['isActive'] == false) return 0;

    final variantId = _cleanText(item['variantId']);
    final unit = _cleanText(item['unit']);

    return ProductService.getStock(
      product,
      variantId: variantId.isEmpty || variantId == 'default' ? null : variantId,
      unit: unit,
    );
  }

  Widget _buildItemCard(int i) {
    final item = items[i];
    final qty = _toInt(item['qty'], fallback: 1);
    final stock = _toInt(item['stockAtAddTime'] ?? item['stock']);
    final unit = _cleanText(item['unit']);
    final oldPrice = _toDouble(item['oldPrice'] ?? item['price']);
    final price = _toDouble(item['price']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(_cleanText(item['name'], 'Product')),
        subtitle: Text(
          '৳${price.toStringAsFixed(2)}'
              '${oldPrice > price ? '  MRP ৳${oldPrice.toStringAsFixed(2)}' : ''}'
              '${unit.isNotEmpty ? ' | Unit: $unit' : ''}'
              ' | Max: $stock',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Decrease',
              icon: const Icon(Icons.remove),
              onPressed: saving || !canEditItems
                  ? null
                  : () async {
                if (qty > 1) {
                  item['qty'] = qty - 1;
                  await _autoSave();
                }
              },
            ),
            Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              tooltip: 'Increase',
              icon: const Icon(Icons.add),
              onPressed: saving || !canEditItems
                  ? null
                  : () async {
                final latestStock = await _latestStockForItem(item);
                if (latestStock <= 0) {
                  _snack('Out of stock', color: Colors.red);
                  return;
                }

                if (qty >= latestStock) {
                  _snack('Cannot exceed available stock ($latestStock)', color: Colors.red);
                  return;
                }

                item['qty'] = qty + 1;
                item['stock'] = latestStock;
                item['stockAtAddTime'] = latestStock;
                await _autoSave();
              },
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: saving || !canEditItems
                  ? null
                  : () async {
                items.removeAt(i);
                await _autoSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading || permissionLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewOrder) {
      return const _AccessDeniedPage(
        title: 'Order access denied',
        message: 'orders.view permission is required to open this page.',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Order')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No products added yet'))
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _buildItemCard(i),
              ),
            ),
            if (canEditItems)
              ElevatedButton.icon(
                onPressed: saving ? null : _selectProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              )
            else
              _PermissionNotice(
                icon: Icons.lock_outline,
                text: 'You can view this order, but orders.edit permission is required to add/remove products or change quantity.',
              ),
            const SizedBox(height: 10),
            TextField(
              controller: discountController,
              enabled: !saving && canEditDiscount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Discount',
                border: OutlineInputBorder(),
                prefixText: '৳ ',
              ),
              onChanged: (v) async {
                if (!canEditDiscount) return;
                discount = double.tryParse(v) ?? 0;
                await _autoSave();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: deliveryChargeController,
              enabled: !saving && canEditDiscount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Delivery Charge',
                border: OutlineInputBorder(),
                prefixText: '৳ ',
              ),
              onChanged: (v) async {
                if (!canEditDiscount) return;
                deliveryCharge = double.tryParse(v) ?? 0;
                await _autoSave();
              },
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                Text('Product Price: ৳${totalMrp.toStringAsFixed(2)}'),
                if (discount > 0)
                  Text(
                    'Discount: -৳${discount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.red),
                  ),
                Text('After Discount: ৳${total.toStringAsFixed(2)}'),
                Text(
                  'Delivery Charge: +৳${deliveryCharge.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.green),
                ),
                const SizedBox(height: 5),
                Text(
                  'Grand Total: ৳${grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!canEditDiscount)
              const _PermissionNotice(
                icon: Icons.price_change_outlined,
                text: 'orders.discount permission required to edit discount or delivery charge.',
              ),
            if (!canSendNotification)
              const _PermissionNotice(
                icon: Icons.notifications_off_outlined,
                text: 'Order can be confirmed, but customer notification will be skipped without notifications.send permission.',
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: saving || !canConfirmOrder ? null : _confirmOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: saving
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text(
                'Confirm Order',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _PermissionNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionNotice({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessDeniedPage extends StatelessWidget {
  final String title;
  final String message;

  const _AccessDeniedPage({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.red.withValues(alpha: 0.10),
                child: const Icon(Icons.lock_outline_rounded, color: Colors.red, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
