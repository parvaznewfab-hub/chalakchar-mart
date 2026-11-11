import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile/my_address_page.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import 'profile/edit_profile_page.dart';
import '../auth/login_page.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import 'package:flutter/foundation.dart';
import '../../services/vendor_commission_service.dart';
import '../../services/product_service.dart';
import '../../services/guest_cart_service.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String? _selectedAddressId;
  double _couponDiscount = 0;
  String? _appliedCouponCode;
  double _chalakCharCashUsed = 0;
  bool _useChalakCharCash = false;
  bool _placingOrder = false;
  bool _mergingGuestCart = false;
  int _guestCartRefresh = 0;

  double _minimumOrderAmount = 300;
  double _localDeliveryCharge = 50;
  double _outsideDeliveryCharge = 110;
  double _deliveryCharge = 0;

  // Fresh product docs fetched during _validateStock, keyed by productId.
  // Reused right after in _placeOrder so each order item can snapshot
  // source/sourceProductId/aliExpressLink from the actual product being
  // ordered without a second round of Firestore reads.
  final Map<String, Map<String, dynamic>> _checkoutProductCache = {};

  @override
  void initState() {
    super.initState();
    FirebaseService.disableExpiredCoupons();
    _loadMinimumOrderAmount();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  Future<void> _loadMinimumOrderAmount() async {
    try {
      final doc = await db.collection('settings').doc('app').get();
      final data = doc.data() ?? {};

      if (!mounted) return;

      setState(() {
        _minimumOrderAmount = _toDouble(data['minimumOrderAmount'] ?? 300);
        _localDeliveryCharge = _toDouble(data['localDeliveryCharge'] ?? 50);
        _outsideDeliveryCharge = _toDouble(data['outsideDeliveryCharge'] ?? 110);
      });
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF32A8C7)),
    );
  }

  Future<bool> _validateStock(List<QueryDocumentSnapshot<Map<String, dynamic>>> cartItems) async {
    _checkoutProductCache.clear();

    for (final doc in cartItems) {
      final data = doc.data();

      final productId = _text(data['productId']);
      final unit = _text(data['unit']);
      final qty = _toInt(data['qty'], 1);

      if (productId.isEmpty) {
        _showError("Incomplete data for ${_text(data['name'], 'item')}. Please remove and add it again.");
        return false;
      }

      final productDoc = await db.collection('products').doc(productId).get();

      if (!productDoc.exists) {
        await doc.reference.delete();
        _showError("Product ${_text(data['name'], 'item')} no longer exists and was removed from cart.");
        return false;
      }

      final product = ProductService.normalizeProductData(productDoc);
      _checkoutProductCache[productId] = product;

      if (product['isActive'] == false) {
        await doc.reference.delete();
        _showError("${_text(data['name'], 'item')} is currently unavailable and was removed from cart.");
        return false;
      }

      final availableStock = ProductService.getStock(product, unit: unit);

      if (qty > availableStock) {
        if (availableStock <= 0) {
          await doc.reference.delete();
          _showError("${_text(data['name'], 'item')} removed from cart because it is out of stock.");
        } else {
          await doc.reference.update({
            'qty': availableStock,
            'stockAtAddTime': availableStock,
            'stock': availableStock,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _showError("${_text(data['name'], 'item')} quantity adjusted to available stock ($availableStock).");
        }
        return false;
      }

      // Keep old cart items fresh without breaking checkout.
      final selectedVariant = ProductService.selectedVariant(product, unit);
      final freshPrice = ProductService.toDouble(selectedVariant['price'] ?? product['price']);
      final freshOldPrice = ProductService.toDouble(
        selectedVariant['mrp'] ?? selectedVariant['oldPrice'] ?? product['oldPrice'] ?? freshPrice,
      );

      await doc.reference.set({
        'price': freshPrice,
        'oldPrice': freshOldPrice < freshPrice ? freshPrice : freshOldPrice,
        'variantId': ProductService.text(selectedVariant['id'] ?? selectedVariant['variantId'], 'default'),
        'stockAtAddTime': availableStock,
        'stock': availableStock,
        'units': ProductService.getUnits(product),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return true;
  }

  Future<void> _applyCoupon(String code, double totalAmount) async {
    final couponCode = code.trim().toUpperCase();
    if (couponCode.isEmpty) return;

    final doc = await db.collection('coupons').doc(couponCode).get();

    if (!doc.exists) {
      _showError("Invalid coupon code");
      return;
    }

    final data = doc.data()!;

    if (data['expiry'] is Timestamp) {
      final expiryDate = (data['expiry'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiryDate)) {
        _showError("This coupon has expired");
        return;
      }
    }

    if (data['isActive'] == false) {
      _showError("This coupon is no longer active");
      return;
    }

    final minAmount = _toDouble(data['minAmount']);
    if (totalAmount < minAmount) {
      _showError("Minimum order amount ৳${minAmount.toInt()} required");
      return;
    }

    double discount = 0;
    if (_text(data['type']) == 'percent') {
      discount = totalAmount * _toDouble(data['value']) / 100;
      final maxDiscount = _toDouble(data['maxDiscount'],);
      if (maxDiscount > 0 && discount > maxDiscount) discount = maxDiscount;
    } else {
      discount = _toDouble(data['value']);
    }

    if (discount > totalAmount) discount = totalAmount;

    setState(() {
      _couponDiscount = discount;
      _appliedCouponCode = couponCode;
    });

    _showSuccess("Coupon Applied! You saved ৳${discount.toStringAsFixed(0)}");
  }

  void _showCouponDialog(double currentTotal) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apply Coupon"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Enter code",
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _applyCoupon(controller.text.trim(), currentTotal);
              }
            },
            child: const Text("Apply"),
          ),
        ],
      ),
    );
  }

  void _showOrderSuccessDialog(BuildContext context, String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text(
              "Order Confirmed!",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your order has been placed successfully.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final items = await db.collection('cart').doc(userId).collection('items').get();
                  final batch = db.batch();

                  for (final doc in items.docs) {
                    batch.delete(doc.reference);
                  }

                  await batch.commit();

                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF32A8C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  "OK",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _isProfileComplete(String uid) async {
    final doc = await db.collection("users").doc(uid).get();
    if (!doc.exists) return false;

    final data = doc.data();

    return _hasValue(data?['name']) &&
        _hasValue(data?['age']) &&
        _hasValue(data?['phone']) &&
        _hasValue(data?['address']) &&
        _hasValue(data?['division']) &&
        _hasValue(data?['district']) &&
        _hasValue(data?['upazila']);
  }

  void _showProfileWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete Profile"),
        content: const Text("Please complete your profile to place order."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage()));
            },
            child: const Text("Go to Profile"),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAddress(String userId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAddressPage()),
    );

    if (result == null || result is! String) return;

    _selectedAddressId = result;

    Map<String, dynamic> data = {};

    if (result == "profile_default") {
      final userDoc = await db.collection('users').doc(userId).get();
      data = userDoc.data() ?? {};
    } else {
      final addrDoc = await db.collection('users').doc(userId).collection('addresses').doc(result).get();
      data = addrDoc.data() ?? {};
    }

    final upazila = _text(data['upazila']).toLowerCase();

    _deliveryCharge = upazila.contains('monohardi') || upazila.contains('মনোহরদী')
        ? _localDeliveryCharge
        : _outsideDeliveryCharge;

    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _buildAddressDetails(User user) async {
    final userDoc = await db.collection('users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};
    final realUserName = _text(userData['name'], user.email ?? "User");

    if (_selectedAddressId == "profile_default") {
      return {
        'name': realUserName,
        'phone': _text(userData['phone']),
        'address': _text(userData['address']),
        'division': _text(userData['division']),
        'district': _text(userData['district']),
        'upazila': _text(userData['upazila']),
        'label': 'Default',
      };
    }

    final addrDoc = await db.collection('users').doc(user.uid).collection('addresses').doc(_selectedAddressId).get();
    final data = addrDoc.data() ?? {};

    return {
      'name': realUserName,
      'phone': _text(data['phone']),
      'address': _text(data['address']),
      'division': _text(data['division']),
      'district': _text(data['district']),
      'upazila': _text(data['upazila']),
      'label': _text(data['label'], 'Custom'),
    };
  }

  void _recalculateDeliveryCharge(Map<String, dynamic> addressDetails) {
    final upazilaText = _text(addressDetails['upazila']).toLowerCase();

    _deliveryCharge = upazilaText.contains('monohardi') || upazilaText.contains('মনোহরদী')
        ? _localDeliveryCharge
        : _outsideDeliveryCharge;
  }

  Future<void> _placeOrder(double visibleFinalTotal) async {
    if (_placingOrder) return;

    if (visibleFinalTotal < _minimumOrderAmount) {
      final needMore = _minimumOrderAmount - visibleFinalTotal;
      _showError(
        "অর্ডার করতে আরও ৳${needMore.toStringAsFixed(0)} যোগ করুন। Minimum COD order ৳${_minimumOrderAmount.toStringAsFixed(0)}",
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError("Please login first");
      return;
    }

    if (_selectedAddressId == null) {
      _showError("Please select an address first!");
      return;
    }

    setState(() => _placingOrder = true);

    try {
      final profileComplete = await _isProfileComplete(user.uid);
      if (!profileComplete) {
        if (mounted) _showProfileWarning();
        return;
      }

      final cartItemsSnapshot = await db.collection('cart').doc(user.uid).collection('items').get();

      if (cartItemsSnapshot.docs.isEmpty) {
        _showError("Your cart is empty");
        return;
      }

      final isValid = await _validateStock(cartItemsSnapshot.docs);
      if (!isValid) return;

      final addressDetails = await _buildAddressDetails(user);
      _recalculateDeliveryCharge(addressDetails);

      final userDoc = await db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final realUserName = _text(userData['name'], user.email ?? "User");

      double totalAmount = 0;
      double totalMrp = 0;
      final List<Map<String, dynamic>> items = [];

      for (final doc in cartItemsSnapshot.docs) {
        final data = doc.data();

        final price = _toDouble(data['price']);
        double oldPrice = _toDouble(data['oldPrice'] ?? data['old_price'] ?? price);
        if (oldPrice < price) oldPrice = price;

        final qty = _toInt(data['qty'], 1);
        final vendorId = _text(data['vendorId'], 'super_admin');
        final vendorName = _text(data['vendorName'], 'ChalakChar Mart');

        totalAmount += price * qty;
        totalMrp += oldPrice * qty;

        // Snapshot AliExpress sourcing from the actual product doc (fetched
        // moments ago in _validateStock) so it survives future product
        // syncs/edits/deletes instead of relying on the cart item's own copy.
        final productId = _text(data['productId']);
        final sourceProduct = _checkoutProductCache[productId] ?? <String, dynamic>{};
        final source = _text(sourceProduct['source']);
        final sourceProductId = _text(sourceProduct['sourceProductId']);
        final aliExpressLink = ProductService.aliExpressLinkFor(sourceProduct);

        items.add({
          ...data,
          'productId': productId,
          'vendorId': vendorId,
          'vendorName': vendorName,
          'isMarketplace': vendorId != 'super_admin',
          'lineTotal': price * qty,
          'lineMrpTotal': oldPrice * qty,
          'source': source,
          'sourceProductId': sourceProductId,
          'aliExpressLink': aliExpressLink,
        });
      }

      final vendorIds = items
          .map((e) => _text(e['vendorId']))
          .where((e) => e.isNotEmpty && e != 'super_admin')
          .toSet()
          .toList();

      final List<String> vendorOwnerIds = [];
      for (final vendorId in vendorIds) {
        try {
          final vendorDoc = await db.collection('vendors').doc(vendorId).get();
          final ownerId = _text(
            vendorDoc.data()?['ownerId'] ?? vendorDoc.data()?['userId'],
          );

          if (ownerId.isNotEmpty && !vendorOwnerIds.contains(ownerId)) {
            vendorOwnerIds.add(ownerId);
          }
        } catch (e) {
          debugPrint('Vendor owner lookup failed for $vendorId: $e');
        }
      }

      final hasVendorItems = vendorIds.isNotEmpty;

      final latestUserDoc = await db.collection('users').doc(user.uid).get();
      final latestPoints = _toDouble(latestUserDoc.data()?['points']);

      double chalakCharCashToUse = _useChalakCharCash ? _chalakCharCashUsed : 0;
      if (chalakCharCashToUse > latestPoints) chalakCharCashToUse = latestPoints;

      if (chalakCharCashToUse > totalAmount - _couponDiscount) {
        chalakCharCashToUse = totalAmount - _couponDiscount;
      }
      if (chalakCharCashToUse < 0) chalakCharCashToUse = 0;

      double finalTotal = totalAmount - _couponDiscount - chalakCharCashToUse + _deliveryCharge;
      if (finalTotal < 0) finalTotal = 0;

      final productDiscount = totalMrp - totalAmount;

      final orderRef = await db.collection('orders').add({
        'userId': user.uid,
        'userName': realUserName,
        'userEmail': user.email ?? "N/A",
        'userPhone': _text(addressDetails['phone']),
        'phone': _text(addressDetails['phone']),
        'status': 'pending',
        'paymentMethod': 'COD',
        'paymentStatus': 'unpaid',
        'orderType': hasVendorItems ? 'marketplace' : 'best selling',
        'hasVendorItems': hasVendorItems,
        'vendorIds': vendorIds,
        'vendorOwnerIds': vendorOwnerIds,
        'total': finalTotal,
        'grandTotal': finalTotal,
        'finalTotal': finalTotal,
        'subtotal': totalAmount,
        'deliveryCharge': _deliveryCharge,
        'totalMrp': totalMrp,
        'discount': productDiscount + _couponDiscount + chalakCharCashToUse,
        'couponCode': _appliedCouponCode,
        'couponDiscount': _couponDiscount,
        'chalakCharCashUsed': chalakCharCashToUse,
        'paymentDiscounts': {
          'productDiscount': productDiscount,
          'couponDiscount': _couponDiscount,
          'chalakCharCashUsed': chalakCharCashToUse,
        },
        'items': items,
        'address': addressDetails,
        'addressText': _text(addressDetails['address']),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (chalakCharCashToUse > 0) {
        await db.collection('users').doc(user.uid).update({
          'points': FieldValue.increment(-chalakCharCashToUse),
        });
      }

      try {
        await VendorCommissionService.createOrderCommissionLedger(
          orderId: orderRef.id,
          items: items,
        );
      } catch (e) {
        debugPrint('Vendor commission ledger failed: $e');
      }

      try {
        await NotificationService.createOrderNotifications(
          orderId: orderRef.id,
          userId: user.uid,
          items: items,
        );
      } catch (e) {
        debugPrint('Order notification failed: $e');
      }


      // Placing an order is a user action, so the browser may ask for
      // notification permission now (for order updates). Not awaited.
      unawaited(NotificationService.requestAndSaveToken(user.uid));

      if (mounted) _showOrderSuccessDialog(context, user.uid);
    } catch (e) {
      _showError("Order failed: $e");
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }


  Future<void> _showLoginPopupForCheckout() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const LoginPage(isPopup: true),
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _mergeGuestCartIfNeeded(user);
      if (mounted) setState(() {});
    }
  }

  Future<void> _mergeGuestCartIfNeeded(User user) async {
    if (_mergingGuestCart) return;

    _mergingGuestCart = true;
    try {
      await GuestCartService.mergeToUserCart(user.uid);
    } catch (e) {
      debugPrint('Guest cart merge failed: $e');
    } finally {
      _mergingGuestCart = false;
    }
  }

  Future<void> _refreshGuestCart() async {
    await GuestCartService.refreshCount();
    if (mounted) {
      setState(() => _guestCartRefresh++);
    }
  }

  Widget _buildGuestCartBody(bool isDesktop) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_guestCartRefresh),
      future: GuestCartService.getItems(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              const Expanded(child: Center(child: CircularProgressIndicator())),
              if (isDesktop) const GlobalWebFooter(),
            ],
          );
        }

        final items = snapshot.data ?? <Map<String, dynamic>>[];

        if (items.isEmpty) {
          return Column(
            children: [
              Expanded(child: _emptyCart()),
              if (isDesktop) const GlobalWebFooter(),
            ],
          );
        }

        double totalMrp = 0;
        double totalAmount = 0;

        for (final item in items) {
          final price = _toDouble(item['price']);
          double oldPrice = _toDouble(item['oldPrice'] ?? item['old_price'] ?? price);
          if (oldPrice < price) oldPrice = price;

          final qty = _toInt(item['qty'], 1);
          totalMrp += oldPrice * qty;
          totalAmount += price * qty;
        }

        final totalSavings = totalMrp - totalAmount;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _guestLoginNotice(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSectionHeader('PRODUCTS'),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildGuestCartItem(item);
                  },
                ),
              ),
              const SizedBox(height: 20),
              _guestPaymentDetails(
                totalMrp: totalMrp,
                totalAmount: totalAmount,
                totalSavings: totalSavings,
              ),
              const SizedBox(height: 30),
              if (isDesktop) const GlobalWebFooter(),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _guestLoginNotice() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD38A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFFF9900)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'You can review your cart as a guest. Please login before placing the final order.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _showLoginPopupForCheckout,
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guestPaymentDetails({
    required double totalMrp,
    required double totalAmount,
    required double totalSavings,
  }) {
    final finalTotal = totalAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('PAYMENT DETAILS'),
            const SizedBox(height: 15),
            _buildPaymentRow('MRP Total', '৳${totalMrp.toStringAsFixed(2)}'),
            _buildPaymentRow(
              'Product Discount',
              '-৳${totalSavings.toStringAsFixed(2)}',
              isDiscount: true,
            ),
            _buildPaymentRow(
              'Delivery Charge',
              'Select address after login',
            ),
            const Divider(height: 30),
            _buildPaymentRow('Cart Subtotal', '৳${finalTotal.toStringAsFixed(2)}', isBold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.login_rounded, color: Color(0xFF32A8C7), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Login is required only when you place the final order.',
                      style: TextStyle(color: Color(0xFF1A7287), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestCartItem(Map<String, dynamic> data) {
    final itemId = _text(data['id']);
    final price = _toDouble(data['price']);
    double oldPrice = _toDouble(data['oldPrice'] ?? data['old_price'] ?? price);
    if (oldPrice < price) oldPrice = price;

    final qty = _toInt(data['qty'], 1);
    final stock = _toInt(data['stock'], 999999);
    final vendorName = _text(data['vendorName']);
    final isMarketplace = _text(data['vendorId'], 'super_admin') != 'super_admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCartThumbnail(_text(data['image']), Icons.shopping_bag_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_text(data['name'], 'Product')} ${_text(data['strength'])}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '৳${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFF32A8C7),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Text(_text(data['manufacturer'], 'Manufacturer'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (vendorName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      isMarketplace ? 'Vendor: $vendorName' : 'Sold by ChalakChar Mart',
                      style: TextStyle(
                        color: isMarketplace ? Colors.deepPurple : Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (oldPrice > price)
                  Text(
                    'MRP ৳${oldPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Variant labels can be long (e.g. "XR 64g With Face ID / China Mainland"):
                    // let the label take only the leftover width and ellipsize, so the
                    // qty selector and delete button always stay on-screen.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _text(data['unit'], 'Default'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          _buildQtyBtn(Icons.chevron_left, () async {
                            if (qty > 1) {
                              await GuestCartService.updateQty(itemId, qty - 1);
                              await _refreshGuestCart();
                            }
                          }),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          _buildQtyBtn(Icons.chevron_right, () async {
                            if (qty >= stock) {
                              _showError('Only $stock available');
                              return;
                            }
                            await GuestCartService.updateQty(itemId, qty + 1);
                            await _refreshGuestCart();
                          }),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFF32A8C7), size: 22),
                      onPressed: () async {
                        await GuestCartService.removeItem(itemId);
                        await _refreshGuestCart();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null;
    final userId = user?.uid ?? '';
    final isDesktop = kIsWeb && MediaQuery.of(context).size.width >= 1024;

    if (!isGuest) {
      Future.microtask(() => _mergeGuestCartIfNeeded(user));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: isDesktop ? const GlobalWebHeader() : null,
      body: isGuest
          ? _buildGuestCartBody(isDesktop)
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('cart').doc(userId).collection('items').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Column(
              children: [
                const Expanded(child: Center(child: CircularProgressIndicator())),
                if (isDesktop) const GlobalWebFooter(),
              ],
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Column(
              children: [
                Expanded(child: _emptyCart()),
                if (isDesktop) const GlobalWebFooter(),
              ],
            );
          }

          final cartItems = snapshot.data!.docs;
          double totalMrp = 0;
          double totalAmount = 0;

          for (final item in cartItems) {
            final data = item.data();
            final price = _toDouble(data['price']);
            double oldPrice = _toDouble(data['oldPrice'] ?? data['old_price'] ?? price);
            if (oldPrice < price) oldPrice = price;

            final qty = _toInt(data['qty'], 1);
            totalMrp += oldPrice * qty;
            totalAmount += price * qty;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _addressSelector(userId),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSectionHeader("PRODUCTS"),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cartItems.length,
                    itemBuilder: (context, index) => _buildCartItem(
                      context,
                      userId,
                      cartItems[index].id,
                      cartItems[index].data(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _paymentDetails(userId, totalMrp, totalAmount),
                const SizedBox(height: 30),
                if (isDesktop) const GlobalWebFooter(),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: isGuest ? _buildGuestBottomBar(context) : _buildBottomBar(context),
    );
  }

  Widget _buildGuestBottomBar(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('guest_bottom_$_guestCartRefresh'),
      future: GuestCartService.getItems(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? <Map<String, dynamic>>[];

        double total = 0;
        for (final item in items) {
          total += _toDouble(item['price']) * _toInt(item['qty'], 1);
        }

        if (total <= 0) return const SizedBox.shrink();

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CART SUBTOTAL", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      "৳${total.toStringAsFixed(0)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF32A8C7)),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _showLoginPopupForCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF32A8C7),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    "LOGIN TO ORDER",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 82, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            "Your cart is empty",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "Add products to place an order.",
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _addressSelector(String userId) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Material(
        color: const Color(0xFF32A8C7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _selectAddress(userId),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _selectedAddressId == null ? "SELECT ADDRESS" : "ADDRESS SELECTED",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.touch_app, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentDetails(String userId, double totalMrp, double totalAmount) {
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('users').doc(userId).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final points = _toDouble(userData['points']);

        double maxUsableCash = totalAmount - _couponDiscount;
        if (maxUsableCash < 0) maxUsableCash = 0;

        final usableCash = points > maxUsableCash ? maxUsableCash : points;
        _chalakCharCashUsed = _useChalakCharCash ? usableCash : 0;

        double finalTotal = totalAmount - _couponDiscount - _chalakCharCashUsed + _deliveryCharge;
        if (finalTotal < 0) finalTotal = 0;

        final totalSavings = (totalMrp - totalAmount) + _couponDiscount + _chalakCharCashUsed;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader("PAYMENT DETAILS"),
                const SizedBox(height: 15),
                _buildPaymentRow("MRP Total", "৳${totalMrp.toStringAsFixed(2)}"),
                _buildPaymentRow(
                  "Product Discount",
                  "-৳${(totalMrp - totalAmount).toStringAsFixed(2)}",
                  isDiscount: true,
                ),
                if (_couponDiscount > 0)
                  _buildPaymentRow("Coupon Discount", "-৳${_couponDiscount.toStringAsFixed(2)}", isDiscount: true),
                _buildPaymentRow(
                  "Delivery Charge",
                  _selectedAddressId == null ? "Select address" : "৳${_deliveryCharge.toStringAsFixed(2)}",
                ),
                if (_chalakCharCashUsed > 0)
                  _buildPaymentRow("ChalakChar Mart Cash Used", "-৳${_chalakCharCashUsed.toStringAsFixed(2)}", isDiscount: true),
                const SizedBox(height: 15),
                InkWell(
                  onTap: () => _showCouponDialog(totalAmount),
                  child: Row(
                    children: [
                      const Icon(Icons.confirmation_number_outlined, color: Color(0xFF32A8C7), size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _appliedCouponCode == null ? "Apply a coupon" : "Coupon: $_appliedCouponCode Applied!",
                          style: const TextStyle(
                            color: Color(0xFF32A8C7),
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_appliedCouponCode != null)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red, size: 20),
                          onPressed: () => setState(() {
                            _couponDiscount = 0;
                            _appliedCouponCode = null;
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (points > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, color: Colors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Use ChalakChar Mart Cash ৳${usableCash.toStringAsFixed(0)}",
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal),
                          ),
                        ),
                        Switch(
                          value: _useChalakCharCash,
                          activeThumbColor: Colors.teal,
                          onChanged: (value) {
                            setState(() {
                              _useChalakCharCash = value;
                              _chalakCharCashUsed = value ? usableCash : 0;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 30),
                _buildPaymentRow("Total Amount", "৳${finalTotal.toStringAsFixed(2)}", isBold: true),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.savings_outlined, color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      const Text("Total savings", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        "৳${totalSavings.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (finalTotal < _minimumOrderAmount) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Add ৳${(_minimumOrderAmount - finalTotal).toStringAsFixed(0)} more to place your COD order. Minimum order ৳${_minimumOrderAmount.toStringAsFixed(0)}.",
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(width: 40, height: 3, color: const Color(0xFF32A8C7)),
      ],
    );
  }

  Future<void> _updateCartItemUnit({
    required String userId,
    required String itemId,
    required Map<String, dynamic> cartData,
    required String unit,
  }) async {
    final productId = _text(cartData['productId']);

    if (productId.isEmpty) {
      _showError('Product data incomplete. Please remove and add again.');
      return;
    }

    final productDoc = await db.collection('products').doc(productId).get();

    if (!productDoc.exists) {
      await db.collection('cart').doc(userId).collection('items').doc(itemId).delete();
      _showError('Product unavailable and removed from cart');
      return;
    }

    final product = ProductService.normalizeProductData(productDoc);

    if (product['isActive'] == false) {
      await db.collection('cart').doc(userId).collection('items').doc(itemId).delete();
      _showError('Product inactive and removed from cart');
      return;
    }

    final selectedVariant = ProductService.selectedVariant(product, unit);
    final stock = ProductService.getStock(product, unit: unit);
    final currentQty = _toInt(cartData['qty'], 1);
    final safeQty = stock <= 0 ? 0 : currentQty.clamp(1, stock);

    if (stock <= 0) {
      await db.collection('cart').doc(userId).collection('items').doc(itemId).delete();
      _showError('Selected variant is out of stock and removed from cart');
      return;
    }

    final payload = ProductService.buildCartItem(
      product,
      selectedVariant,
      qty: safeQty,
    );

    await db.collection('cart').doc(userId).collection('items').doc(itemId).set({
      ...payload,
      'qty': safeQty,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (safeQty != currentQty) {
      _showError('Quantity adjusted to available stock ($stock)');
    }
  }

  Future<void> _increaseCartQty({
    required String userId,
    required String itemId,
    required Map<String, dynamic> cartData,
  }) async {
    final currentQty = _toInt(cartData['qty'], 1);
    final productId = _text(cartData['productId']);
    final unit = _text(cartData['unit']);

    if (productId.isEmpty) {
      _showError('Product data incomplete. Please remove and add again.');
      return;
    }

    final productDoc = await db.collection('products').doc(productId).get();

    if (!productDoc.exists) {
      await db.collection('cart').doc(userId).collection('items').doc(itemId).delete();
      _showError('Product unavailable and removed from cart');
      return;
    }

    final product = ProductService.normalizeProductData(productDoc);

    if (product['isActive'] == false) {
      await db.collection('cart').doc(userId).collection('items').doc(itemId).delete();
      _showError('Product inactive and removed from cart');
      return;
    }

    final stock = ProductService.getStock(product, unit: unit);

    if (currentQty >= stock) {
      _showError('Only $stock available');
      return;
    }

    await db.collection('cart').doc(userId).collection('items').doc(itemId).update({
      'qty': FieldValue.increment(1),
      'stockAtAddTime': stock,
      'stock': stock,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Widget _buildCartItem(BuildContext context, String userId, String itemId, Map<String, dynamic> data) {
    final price = _toDouble(data['price']);
    double oldPrice = _toDouble(data['oldPrice'] ?? data['old_price'] ?? price);
    if (oldPrice < price) oldPrice = price;

    final units = (data['units'] as List? ?? [data['unit'] ?? 'piece'])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toSet()
        .toList();

    String currentUnit = _text(data['unit'], units.isNotEmpty ? units.first : 'piece');
    if (units.isNotEmpty && !units.contains(currentUnit)) currentUnit = units.first;

    final vendorName = _text(data['vendorName']);
    final isMarketplace = _text(data['vendorId'], 'super_admin') != 'super_admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCartThumbnail(_text(data['image']), Icons.medication),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${_text(data['name'], 'Product')} ${_text(data['strength'])}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "৳${price.toStringAsFixed(0)}",
                      style: const TextStyle(
                        color: Color(0xFF32A8C7),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Text(_text(data['manufacturer'], 'Manufacturer'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if (vendorName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      isMarketplace ? "Vendor: $vendorName" : "Sold by ChalakChar Mart",
                      style: TextStyle(
                        color: isMarketplace ? Colors.deepPurple : Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (oldPrice > price)
                  Text(
                    "MRP ৳${oldPrice.toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Variant labels can be long (e.g. "XR 64g With Face ID / China Mainland"):
                    // the dropdown takes only the leftover width and ellipsizes, so the
                    // qty selector and delete button always stay on-screen.
                    Expanded(
                      child: units.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentUnit,
                            isExpanded: true,
                            selectedItemBuilder: (_) => units
                                .map((u) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                u,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                                .toList(),
                            items: units
                                .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                                .toList(),
                            onChanged: (v) async {
                              if (v == null || v == currentUnit) return;
                              await _updateCartItemUnit(
                                userId: userId,
                                itemId: itemId,
                                cartData: data,
                                unit: v,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 34,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          _buildQtyBtn(Icons.chevron_left, () {
                            if (_toInt(data['qty'], 1) > 1) {
                              db.collection('cart').doc(userId).collection('items').doc(itemId).update({
                                'qty': FieldValue.increment(-1),
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            }
                          }),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text("${_toInt(data['qty'], 1)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          _buildQtyBtn(Icons.chevron_right, () async {
                            await _increaseCartQty(
                              userId: userId,
                              itemId: itemId,
                              cartData: data,
                            );
                          }),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFF32A8C7), size: 22),
                      onPressed: () => db.collection('cart').doc(userId).collection('items').doc(itemId).delete(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartThumbnail(String url, IconData fallbackIcon) {
    final fallback = Center(child: Icon(fallbackIcon, size: 40, color: Colors.grey));
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
      child: url.trim().isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon, size: 18, color: Colors.grey),
      ),
    );
  }

  Widget _buildPaymentRow(
      String label,
      String value, {
        bool isDiscount = false,
        bool isBold = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isDiscount ? Colors.green : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final userId = user.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('cart').doc(userId).collection('items').snapshots(),
      builder: (context, snapshot) {
        double total = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            total += _toDouble(data['price']) * _toInt(data['qty'], 1);
          }
        }

        if (total == 0) return const SizedBox.shrink();

        double finalTotal = total - _couponDiscount - _chalakCharCashUsed + _deliveryCharge;
        if (finalTotal < 0) finalTotal = 0;

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TOTAL AMOUNT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      "৳${finalTotal.toStringAsFixed(0)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF32A8C7)),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _placingOrder ? null : () => _placeOrder(finalTotal),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF32A8C7),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _placingOrder
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text(
                    "PLACE ORDER",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


