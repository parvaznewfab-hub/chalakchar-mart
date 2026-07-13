import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'vendor_orders_page.dart';
import 'vendor_products_page.dart';
import 'vendor_withdraw_page.dart';
import 'vendor_shop_page.dart';

class VendorDashboardPage extends StatefulWidget {
  const VendorDashboardPage({super.key});

  @override
  State<VendorDashboardPage> createState() => _VendorDashboardPageState();
}

class _VendorDashboardPageState extends State<VendorDashboardPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String _vendorId = '';
  bool _loadingVendorId = true;


  @override
  void initState() {
    super.initState();
    _loadVendorId();
  }

  Future<void> _loadVendorId() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _vendorId = '';
        _loadingVendorId = false;
      });
      return;
    }

    String resolvedVendorId = '';

    try {
      final userDoc = await db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final userVendorId = _text(userData['vendorId']);
      final sellerStatus = _text(userData['sellerStatus']).toLowerCase();

      if (userVendorId.isNotEmpty) {
        final vendorDoc = await db.collection('vendors').doc(userVendorId).get();
        final vendorData = vendorDoc.data() ?? <String, dynamic>{};
        final ownerId = _text(vendorData['ownerId'] ?? vendorData['userId']);

        if (vendorDoc.exists && (ownerId == user.uid || sellerStatus == 'approved')) {
          resolvedVendorId = userVendorId;
        }
      }

      if (resolvedVendorId.isEmpty) {
        final directVendorDoc = await db.collection('vendors').doc(user.uid).get();
        if (directVendorDoc.exists) {
          final vendorData = directVendorDoc.data() ?? <String, dynamic>{};
          final ownerId = _text(vendorData['ownerId'] ?? vendorData['userId'], user.uid);
          if (ownerId == user.uid) {
            resolvedVendorId = directVendorDoc.id;
          }
        }
      }

      if (resolvedVendorId.isEmpty) {
        final query = await db
            .collection('vendors')
            .where('ownerId', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          resolvedVendorId = query.docs.first.id;
        }
      }
    } catch (e) {
      debugPrint('Vendor id resolve failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _vendorId = resolvedVendorId;
      _loadingVendorId = false;
    });
  }

  bool _isCurrentVendorOwner(Map<String, dynamic> vendor) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final ownerId = _text(vendor['ownerId'] ?? vendor['userId']);
    return ownerId == uid;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    return 'N/A';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'suspended':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text(
          'Vendor Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Logout?'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
          ),
        ],
      ),
      body: _loadingVendorId
          ? const Center(child: CircularProgressIndicator())
          : _vendorId.isEmpty
          ? const Center(child: Text('Vendor not found'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('vendors').doc(_vendorId).snapshots(),
        builder: (context, vendorSnap) {
          if (vendorSnap.hasError) {
            return _errorView(
              title: 'Vendor data load failed',
              message: vendorSnap.error.toString(),
            );
          }

          if (vendorSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!vendorSnap.hasData || !vendorSnap.data!.exists) {
            return _errorView(
              title: 'Vendor profile not found',
              message: 'No vendor document found for this account. Please make sure the vendor application is approved and users.vendorId is correct.',
            );
          }

          final vendor = vendorSnap.data?.data() ?? {};
          if (!_isCurrentVendorOwner(vendor)) {
            return _errorView(
              title: 'Vendor access denied',
              message: 'This vendor profile is not linked with your logged-in account.',
            );
          }

          final shopName = _text(vendor['shopName'], 'Vendor Panel');
          final status = _text(vendor['status'], 'pending');
          final withdrawableBalance =
          _toDouble(vendor['withdrawableBalance']);
          final pendingWithdraw =
          _toDouble(vendor['withdrawPendingBalance']).abs();
          final totalCommission =
          _toDouble(vendor['totalCommission']);

          if (status != 'approved') {
            return _pendingApprovalView(
              shopName: shopName,
              status: status,
              totalCommission: totalCommission,
              withdrawableBalance: withdrawableBalance,
              pendingWithdraw: pendingWithdraw,
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('products')
                .where('vendorId', isEqualTo: _vendorId)
                .snapshots(),
            builder: (context, productSnap) {
              if (productSnap.hasError) {
                return _errorView(
                  title: 'Products load failed',
                  message: productSnap.error.toString(),
                );
              }

              if (productSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!productSnap.hasData) {
                return _errorView(
                  title: 'Products not available',
                  message: 'No product data returned for this vendor.',
                );
              }

              final products = productSnap.data!.docs;
              final totalProducts = products.length;
              int activeProducts = 0;
              int lowStock = 0;

              for (final doc in products) {
                final data = doc.data();
                if (data['isActive'] == true) activeProducts++;

                int stock = _toInt(data['stock']);
                final variants = data['variants'];

                if (variants is List && variants.isNotEmpty) {
                  stock = 0;
                  for (final v in variants) {
                    if (v is Map) stock += _toInt(v['stock']);
                  }
                }

                if (stock <= 5) lowStock++;
              }

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('orders')
                    .where('vendorIds', arrayContains: _vendorId)
                    .snapshots(),
                builder: (context, orderSnap) {
                  if (orderSnap.hasError) {
                    return _errorView(
                      title: 'Orders load failed',
                      message: orderSnap.error.toString(),
                    );
                  }

                  if (orderSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final orders = orderSnap.data?.docs.toList() ??
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  orders.sort((a, b) {
                    final ad = a.data()['createdAt'];
                    final bd = b.data()['createdAt'];
                    final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
                    final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);
                    return bt.compareTo(at);
                  });

                  int pendingOrders = 0;
                  int processingOrders = 0;
                  int completedOrders = 0;
                  double revenue = 0;

                  for (final orderDoc in orders) {
                    final order = orderDoc.data();
                    final vendorStatus = _text(order['vendorStatus']).toLowerCase();
                    final statusText = _text(order['status'], 'pending').toLowerCase();

                    final items = order['items'];
                    double vendorOrderTotal = 0;
                    if (items is List) {
                      for (final item in items) {
                        if (item is Map && _text(item['vendorId']) == _vendorId) {
                          vendorOrderTotal += _toDouble(item['price']) * _toInt(item['qty']);
                        }
                      }
                    }

                    if (statusText == 'delivered' || vendorStatus == 'delivered') {
                      completedOrders++;
                      revenue += vendorOrderTotal;
                    } else if (
                    statusText == 'pending' ||
                        vendorStatus == 'pending' ||
                        vendorStatus.isEmpty
                    ) {
                      pendingOrders++;
                    } else {
                      processingOrders++;
                    }
                  }

                  final calculatedWithdrawable =
                  (revenue - pendingWithdraw - totalCommission)
                      .clamp(0.0, double.infinity);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _topBanner(
                              shopName: shopName,
                              status: status,
                              revenue: revenue,
                              orders: orders.length,
                            ),
                            const SizedBox(height: 18),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final count = width >= 1000
                                    ? 4
                                    : width >= 720
                                    ? 3
                                    : width >= 480
                                    ? 3
                                    : 2;

                                return GridView.count(
                                  crossAxisCount: count,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: width < 480 ? 1.05 : width > 1100 ? 2.1 : 1.85,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  children: [
                                    _statCard(
                                      title: 'Products',
                                      value: '$totalProducts',
                                      subtitle: '$activeProducts active',
                                      icon: Icons.inventory_2_outlined,
                                      color: const Color(0xFF2563EB),
                                    ),
                                    _statCard(
                                      title: 'Pending Orders',
                                      value: '$pendingOrders',
                                      subtitle: '$processingOrders processing',
                                      icon: Icons.shopping_bag_outlined,
                                      color: const Color(0xFFF59E0B),
                                    ),
                                    _statCard(
                                      title: 'Revenue',
                                      value: '৳${revenue.toStringAsFixed(0)}',
                                      subtitle: '${orders.length} total orders',
                                      icon: Icons.payments_outlined,
                                      color: const Color(0xFF16A34A),
                                    ),
                                    _statCard(
                                      title: 'Withdrawable',
                                      value: '৳${calculatedWithdrawable.toStringAsFixed(0)}',
                                      subtitle: 'Available balance',
                                      icon: Icons.account_balance_wallet_outlined,
                                      color: const Color(0xFF0D9488),
                                    ),
                                    _statCard(
                                      title: 'Pending Withdraw',
                                      value: '৳${pendingWithdraw.toStringAsFixed(0)}',
                                      subtitle: 'Waiting admin',
                                      icon: Icons.hourglass_top_rounded,
                                      color: const Color(0xFF7C3AED),
                                    ),
                                    _statCard(
                                      title: 'Commission',
                                      value: '৳${totalCommission.toStringAsFixed(0)}',
                                      subtitle: 'Admin commission',
                                      icon: Icons.percent_rounded,
                                      color: const Color(0xFF4F46E5),
                                    ),
                                    _statCard(
                                      title: 'Low Stock',
                                      value: '$lowStock',
                                      subtitle: 'Stock <= 5',
                                      icon: Icons.warning_amber_rounded,
                                      color: const Color(0xFFDC2626),
                                    ),
                                    _statCard(
                                      title: 'Completed',
                                      value: '$completedOrders',
                                      subtitle: 'Delivered orders',
                                      icon: Icons.task_alt_rounded,
                                      color: const Color(0xFF92400E),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            _sectionHeader(
                              title: 'Quick Actions',
                              subtitle: 'Manage your shop faster from here',
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final itemWidth = width >= 900
                                    ? (width - 36) / 4
                                    : width >= 600
                                    ? (width - 12) / 2
                                    : width;

                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _actionButton(
                                        width: width > 1100 ? 250 : itemWidth,
                                        title: 'Manage Products',
                                        subtitle: 'Add, edit and stock',
                                        icon: Icons.inventory,
                                        color: const Color(0xFF2563EB),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const VendorProductsPage(),
                                            ),
                                          );
                                        },
                                      ),
                                      _actionButton(
                                        width: width > 1100 ? 250 : itemWidth,
                                        title: 'Vendor Orders',
                                        subtitle: 'Process customer orders',
                                        icon: Icons.shopping_cart_checkout,
                                        color: const Color(0xFF16A34A),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const VendorOrdersPage(),
                                            ),
                                          );
                                        },
                                      ),
                                      _actionButton(
                                        width: width > 1100 ? 250 : itemWidth,
                                        title: 'Withdraw Balance',
                                        subtitle: 'Request payout',
                                        icon: Icons.account_balance_wallet,
                                        color: const Color(0xFF0D9488),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const VendorWithdrawPage(),
                                            ),
                                          );
                                        },
                                      ),
                                      _actionButton(
                                        width: width > 1100 ? 250 : itemWidth,
                                        title: 'My Shop',
                                        subtitle: 'Preview shop profile',
                                        icon: Icons.storefront,
                                        color: const Color(0xFF7C3AED),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => VendorShopPage(
                                                vendorId: _vendorId,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 26),
                            _sectionHeader(
                              title: 'Recent Vendor Orders',
                              subtitle: 'Latest orders from your shop',
                            ),
                            const SizedBox(height: 12),
                            if (orders.isEmpty)
                              _emptyOrders()
                            else
                              _ordersPanel(orders),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }




  Widget _pendingApprovalView({
    required String shopName,
    required String status,
    required double totalCommission,
    required double withdrawableBalance,
    required double pendingWithdraw,
  }) {
    final normalizedStatus = status.toLowerCase().trim();
    final isRejected = normalizedStatus == 'rejected';
    final isSuspended = normalizedStatus == 'suspended';
    final statusColor = _statusColor(normalizedStatus);

    String title = 'Vendor Approval Pending';
    String message =
        'Your seller account is under review. After admin approval, products, orders, withdraw and full vendor dashboard features will become available.';

    if (isRejected) {
      title = 'Vendor Application Rejected';
      message =
      'Your seller application was rejected by admin. Please update your information and submit again from Seller Account Application.';
    } else if (isSuspended) {
      title = 'Vendor Account Suspended';
      message =
      'Your vendor account is currently suspended. Please contact admin support for details.';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topBanner(
                shopName: shopName,
                status: normalizedStatus.isEmpty ? 'pending' : normalizedStatus,
                revenue: 0,
                orders: 0,
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: statusColor.withValues(alpha: 0.45)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.055),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      isRejected
                          ? Icons.cancel_outlined
                          : isSuspended
                          ? Icons.report_problem_outlined
                          : Icons.hourglass_top_rounded,
                      color: statusColor,
                      size: 62,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        (normalizedStatus.isEmpty ? 'pending' : normalizedStatus).toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final count = width >= 720 ? 3 : width >= 480 ? 3 : 2;

                  return GridView.count(
                    crossAxisCount: count,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: width < 480 ? 1.05 : 1.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _statCard(
                        title: 'Products',
                        value: '0',
                        subtitle: 'Available after approval',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF2563EB),
                      ),
                      _statCard(
                        title: 'Orders',
                        value: '0',
                        subtitle: 'Available after approval',
                        icon: Icons.shopping_bag_outlined,
                        color: const Color(0xFFF59E0B),
                      ),
                      _statCard(
                        title: 'Withdrawable',
                        value: '৳${withdrawableBalance.toStringAsFixed(0)}',
                        subtitle: 'Available after approval',
                        icon: Icons.account_balance_wallet_outlined,
                        color: const Color(0xFF0D9488),
                      ),
                      _statCard(
                        title: 'Pending Withdraw',
                        value: '৳${pendingWithdraw.toStringAsFixed(0)}',
                        subtitle: 'Waiting admin',
                        icon: Icons.hourglass_top_rounded,
                        color: const Color(0xFF7C3AED),
                      ),
                      _statCard(
                        title: 'Commission',
                        value: '৳${totalCommission.toStringAsFixed(0)}',
                        subtitle: 'Admin commission',
                        icon: Icons.percent_rounded,
                        color: const Color(0xFF4F46E5),
                      ),
                      _statCard(
                        title: 'Status',
                        value: (normalizedStatus.isEmpty ? 'pending' : normalizedStatus).toUpperCase(),
                        subtitle: 'Seller application',
                        icon: Icons.verified_user_outlined,
                        color: statusColor,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView({
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFCA5A5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 46,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadVendorId,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0891B2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBanner({
    required String shopName,
    required String status,
    required double revenue,
    required int orders,
  }) {
    final statusColor = _statusColor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0891B2), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;

          final left = Row(
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Manage products, orders, withdraw and sales.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final right = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _bannerMiniStat(
                title: 'Revenue',
                value: '৳${revenue.toStringAsFixed(0)}',
              ),
              const SizedBox(width: 10),
              _bannerMiniStat(
                title: 'Orders',
                value: '$orders',
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: right,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              right,
            ],
          );
        },
      ),
    );
  }

  Widget _bannerMiniStat({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({required String title, required String subtitle}) {
    return Row(
      children: [
        Container(
          height: 34,
          width: 5,
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 180;

          return compact
              ? Row(
            children: [
              _iconBox(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(child: _statTexts(title, value, subtitle)),
            ],
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBox(icon: icon, color: color),
              const Spacer(),
              _statTexts(title, value, subtitle),
            ],
          );
        },
      ),
    );
  }

  Widget _iconBox({required IconData icon, required Color color}) {
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _statTexts(String title, String value, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF374151),
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required double width,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                _iconBox(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ordersPanel(List<QueryDocumentSnapshot<Map<String, dynamic>>> orders) {
    final recent = orders.take(6).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < recent.length; i++) ...[
            _orderRow(recent[i]),
            if (i != recent.length - 1)
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ],
        ],
      ),
    );
  }

  Widget _orderRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    double total = 0;
    final items = data['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map && _text(item['vendorId']) == _vendorId) {
          total += _toDouble(item['price']) * _toInt(item['qty']);
        }
      }
    }
    if (total <= 0) total = _toDouble(data['total']);
    final status = _text(data['status'], 'pending').toLowerCase();
    final date = _dateText(data['createdAt']);
    final color = status == 'pending'
        ? const Color(0xFFF59E0B)
        : status == 'cancelled'
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);

    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.shopping_bag_outlined, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${doc.id.length > 8 ? doc.id.substring(0, 8) : doc.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  date,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '৳${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyOrders() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            height: 88,
            width: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No vendor orders yet',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'When customers order your products, they will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
