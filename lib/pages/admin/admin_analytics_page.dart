import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  String range = '30';

  DateTime get _rangeStart {
    final days = int.tryParse(range) ?? 30;
    return DateTime.now().subtract(Duration(days: days));
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  DateTime? _createdAt(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();
    return null;
  }

  bool _insideRange(Map<String, dynamic> data) {
    final created = _createdAt(data);
    if (created == null) return true;
    return created.isAfter(_rangeStart);
  }

  double _orderTotal(Map<String, dynamic> data) {
    return _toDouble(
      data['grandTotal'] ??
          data['finalTotal'] ??
          data['total'] ??
          data['totalAmount'] ??
          0,
    );
  }

  bool _isDelivered(Map<String, dynamic> data) {
    final status = _text(data['status']).toLowerCase();
    return status == 'delivered' || status == 'completed';
  }

  Future<Map<String, dynamic>> _loadAnalytics() async {
    final results = await Future.wait([
      db.collection('orders').limit(1000).get(),
      db.collection('products').limit(1000).get(),
      db.collection('users').limit(1000).get(),
      db.collection('lists').limit(500).get(),
      db.collection('vendors').limit(500).get(),
      db.collection('referrals').limit(500).get(),
    ]);

    final orders = results[0].docs;
    final products = results[1].docs;
    final users = results[2].docs;
    final lists = results[3].docs;
    final vendors = results[4].docs;
    final referrals = results[5].docs;

    final rangedOrders = orders.where((d) => _insideRange(d.data())).toList();

    double totalRevenue = 0;
    double deliveredRevenue = 0;
    int pendingOrders = 0;
    int deliveredOrders = 0;
    int cancelledOrders = 0;
    int draftOrders = 0;

    final statusCounts = <String, int>{};
    final productSales = <String, Map<String, dynamic>>{};
    final vendorSales = <String, Map<String, dynamic>>{};
    final dailyRevenue = <String, double>{};

    for (final doc in rangedOrders) {
      final data = doc.data();
      final status = _text(data['status'], 'pending').toLowerCase();

      statusCounts[status] = (statusCounts[status] ?? 0) + 1;

      if (status == 'pending') pendingOrders++;
      if (status == 'cancelled') cancelledOrders++;
      if (status == 'draft' || data['isDraft'] == true) draftOrders++;

      final total = _orderTotal(data);
      totalRevenue += total;

      if (_isDelivered(data)) {
        deliveredOrders++;
        deliveredRevenue += total;
      }

      final created = _createdAt(data);
      if (created != null) {
        final key = '${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';
        dailyRevenue[key] = (dailyRevenue[key] ?? 0) + total;
      }

      final items = data['items'] is List ? data['items'] as List : [];
      for (final item in items) {
        if (item is! Map) continue;

        final name = _text(item['name'], 'Unknown Product');
        final qty = _toInt(item['qty'], 1);
        final price = _toDouble(item['price']);
        final vendorId = _text(item['vendorId']);

        final current = productSales[name] ?? {
          'name': name,
          'qty': 0,
          'revenue': 0.0,
        };

        current['qty'] = _toInt(current['qty']) + qty;
        current['revenue'] = _toDouble(current['revenue']) + (price * qty);
        productSales[name] = current;

        if (vendorId.isNotEmpty) {
          final vendor = vendorSales[vendorId] ?? {
            'vendorId': vendorId,
            'qty': 0,
            'revenue': 0.0,
          };

          vendor['qty'] = _toInt(vendor['qty']) + qty;
          vendor['revenue'] = _toDouble(vendor['revenue']) + (price * qty);
          vendorSales[vendorId] = vendor;
        }
      }
    }

    int lowStock = 0;
    int outOfStock = 0;
    int activeProducts = 0;
    final lowStockProducts = <Map<String, dynamic>>[];

    for (final doc in products) {
      final data = doc.data();
      final stock = _toInt(data['stock']);

      if (data['isActive'] != false) activeProducts++;
      if (stock <= 0) outOfStock++;
      if (stock <= 5) {
        lowStock++;
        lowStockProducts.add({
          'id': doc.id,
          'name': _text(data['name'], 'Product'),
          'stock': stock,
          'category': _text(data['category']),
        });
      }
    }

    int admins = 0;
    int vendorsUsers = 0;
    int blockedUsers = 0;
    int newUsers = 0;

    for (final doc in users) {
      final data = doc.data();
      final role = _text(data['role'], 'user');
      final roles = List<String>.from(data['roles'] ?? []);

      if (role == 'admin' || role == 'superAdmin' || roles.contains('admin') || roles.contains('superAdmin')) {
        admins++;
      }
      if (role == 'vendor' || roles.contains('vendor') || data['sellerStatus'] == 'approved') {
        vendorsUsers++;
      }
      if (data['isActive'] == false || data['isBanned'] == true) {
        blockedUsers++;
      }
      if (_insideRange(data)) {
        newUsers++;
      }
    }

    int pendingLists = 0;
    int acceptedLists = 0;
    int rejectedLists = 0;

    for (final doc in lists) {
      final data = doc.data();
      final status = _text(data['status'], 'pending');

      if (status == 'Accepted') {
        acceptedLists++;
      } else if (status == 'Rejected') {
        rejectedLists++;
      } else {
        pendingLists++;
      }
    }

    int approvedVendors = 0;
    int pendingVendors = 0;
    int suspendedVendors = 0;

    final vendorNames = <String, String>{};

    for (final doc in vendors) {
      final data = doc.data();
      final status = _text(data['status'], 'pending');

      vendorNames[doc.id] = _text(data['shopName'], doc.id);

      if (status == 'approved') approvedVendors++;
      if (status == 'pending') pendingVendors++;
      if (status == 'suspended') suspendedVendors++;
    }

    int referralPending = 0;
    int referralApproved = 0;
    int referralRejected = 0;
    int referralRewardPaid = 0;

    for (final doc in referrals) {
      final data = doc.data();
      final status = _text(data['status'], 'Pending');

      if (status == 'Approved') {
        referralApproved++;
        referralRewardPaid += _toInt(data['referrerReward']) + _toInt(data['refereeReward']);
      } else if (status == 'Rejected') {
        referralRejected++;
      } else {
        referralPending++;
      }
    }

    final topProducts = productSales.values.toList()
      ..sort((a, b) => _toDouble(b['revenue']).compareTo(_toDouble(a['revenue'])));

    final topVendors = vendorSales.values.map((v) {
      final vendorId = _text(v['vendorId']);
      return {
        ...v,
        'name': vendorNames[vendorId] ?? vendorId,
      };
    }).toList()
      ..sort((a, b) => _toDouble(b['revenue']).compareTo(_toDouble(a['revenue'])));

    final dailyList = dailyRevenue.entries.map((e) => {'day': e.key, 'revenue': e.value}).toList()
      ..sort((a, b) => _text(a['day']).compareTo(_text(b['day'])));

    return {
      'orders': orders.length,
      'rangedOrders': rangedOrders.length,
      'totalRevenue': totalRevenue,
      'deliveredRevenue': deliveredRevenue,
      'pendingOrders': pendingOrders,
      'deliveredOrders': deliveredOrders,
      'cancelledOrders': cancelledOrders,
      'draftOrders': draftOrders,
      'statusCounts': statusCounts,
      'products': products.length,
      'activeProducts': activeProducts,
      'lowStock': lowStock,
      'outOfStock': outOfStock,
      'lowStockProducts': lowStockProducts,
      'users': users.length,
      'admins': admins,
      'vendorsUsers': vendorsUsers,
      'blockedUsers': blockedUsers,
      'newUsers': newUsers,
      'lists': lists.length,
      'pendingLists': pendingLists,
      'acceptedLists': acceptedLists,
      'rejectedLists': rejectedLists,
      'vendors': vendors.length,
      'approvedVendors': approvedVendors,
      'pendingVendors': pendingVendors,
      'suspendedVendors': suspendedVendors,
      'referralPending': referralPending,
      'referralApproved': referralApproved,
      'referralRejected': referralRejected,
      'referralRewardPaid': referralRewardPaid,
      'topProducts': topProducts.take(10).toList(),
      'topVendors': topVendors.take(10).toList(),
      'dailyRevenue': dailyList,
    };
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(Map<String, dynamic> data) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 1100 ? 4 : c.maxWidth >= 760 ? 3 : 2;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 2 ? 1.55 : 2.05,
          children: [
            _summaryCard(
              title: 'Total Revenue',
              value: '৳${_toDouble(data['totalRevenue']).toStringAsFixed(0)}',
              icon: Icons.payments_rounded,
              color: Colors.green,
              subtitle: 'Selected range',
            ),
            _summaryCard(
              title: 'Delivered Revenue',
              value: '৳${_toDouble(data['deliveredRevenue']).toStringAsFixed(0)}',
              icon: Icons.verified_rounded,
              color: Colors.teal,
              subtitle: 'Completed orders only',
            ),
            _summaryCard(
              title: 'Orders',
              value: '${data['rangedOrders'] ?? 0}',
              icon: Icons.shopping_bag_rounded,
              color: Colors.blue,
              subtitle: 'Pending ${data['pendingOrders'] ?? 0}',
            ),
            _summaryCard(
              title: 'Cancelled',
              value: '${data['cancelledOrders'] ?? 0}',
              icon: Icons.cancel_rounded,
              color: Colors.red,
              subtitle: 'Draft ${data['draftOrders'] ?? 0}',
            ),
            _summaryCard(
              title: 'Products',
              value: '${data['activeProducts'] ?? 0}',
              icon: Icons.inventory_2_rounded,
              color: Colors.indigo,
              subtitle: 'Low stock ${data['lowStock'] ?? 0}',
            ),
            _summaryCard(
              title: 'Users',
              value: '${data['users'] ?? 0}',
              icon: Icons.people_alt_rounded,
              color: Colors.deepPurple,
              subtitle: 'New ${data['newUsers'] ?? 0}',
            ),
            _summaryCard(
              title: 'Lists',
              value: '${data['lists'] ?? 0}',
              icon: Icons.medical_information_rounded,
              color: Colors.orange,
              subtitle: 'Pending ${data['pendingLists'] ?? 0}',
            ),
            _summaryCard(
              title: 'Vendors',
              value: '${data['approvedVendors'] ?? 0}',
              icon: Icons.storefront_rounded,
              color: Colors.brown,
              subtitle: 'Pending ${data['pendingVendors'] ?? 0}',
            ),
          ],
        );
      },
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
                  child: Icon(icon, color: const Color(0xFF1592B3)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _barList({
    required List<Map<String, dynamic>> items,
    required String labelKey,
    required String valueKey,
    String suffix = '',
    int maxItems = 8,
  }) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('No data found')),
      );
    }

    final maxValue = items
        .take(maxItems)
        .map((e) => _toDouble(e[valueKey]))
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: items.take(maxItems).map((item) {
        final value = _toDouble(item[valueKey]);
        final progress = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _text(item[labelKey], 'Unknown'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    suffix == '৳'
                        ? '৳${value.toStringAsFixed(0)}'
                        : '${value.toStringAsFixed(0)}$suffix',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _statusOverview(Map<String, dynamic> data) {
    final statusCounts = Map<String, int>.from(data['statusCounts'] ?? {});

    if (statusCounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('No order status data')),
      );
    }

    final total = statusCounts.values.fold<int>(0, (a, b) => a + b);

    Color colorFor(String status) {
      if (status == 'delivered' || status == 'completed') return Colors.green;
      if (status == 'pending') return Colors.orange;
      if (status == 'cancelled') return Colors.red;
      if (status == 'draft') return Colors.blueGrey;
      return Colors.blue;
    }

    final entries = statusCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: entries.map((entry) {
        final progress = total == 0 ? 0.0 : entry.value / total;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  entry.key.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    color: colorFor(entry.key),
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text(
                  '${entry.value}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _lowStockList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('No low stock products')),
      );
    }

    items.sort((a, b) => _toInt(a['stock']).compareTo(_toInt(b['stock'])));

    return Column(
      children: items.take(10).map((item) {
        final stock = _toInt(item['stock']);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: stock <= 0 ? Colors.red.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
            child: Icon(
              stock <= 0 ? Icons.remove_shopping_cart_rounded : Icons.warning_amber_rounded,
              color: stock <= 0 ? Colors.red : Colors.orange,
            ),
          ),
          title: Text(_text(item['name'], 'Product'), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_text(item['category'], 'No category')),
          trailing: Text(
            'Stock $stock',
            style: TextStyle(
              color: stock <= 0 ? Colors.red : Colors.orange,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _miniStats(Map<String, dynamic> data) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 2 : 1;

        final cards = [
          _miniCard('Admins', '${data['admins'] ?? 0}', Icons.admin_panel_settings_rounded, Colors.deepPurple),
          _miniCard('Vendor Users', '${data['vendorsUsers'] ?? 0}', Icons.store_mall_directory_rounded, Colors.orange),
          _miniCard('Blocked Users', '${data['blockedUsers'] ?? 0}', Icons.block_rounded, Colors.red),
          _miniCard('Referral Paid', '৳${data['referralRewardPaid'] ?? 0}', Icons.share_rounded, Colors.green),
        ];

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 1 ? 5.4 : 3.6,
          children: cards,
        );
      },
    );
  }

  Widget _miniCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _dailyRevenueList(List<Map<String, dynamic>> items) {
    return _barList(
      items: items,
      labelKey: 'day',
      valueKey: 'revenue',
      suffix: '৳',
      maxItems: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: authService.hasPermission('analytics.view'),
      builder: (context, permissionSnap) {
        if (permissionSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FB),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (permissionSnap.data != true) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FB),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 42, color: Colors.red),
                      SizedBox(height: 12),
                      Text('Analytics access denied', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text('You need analytics.view permission to open this page.', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _loadAnalytics(),
            builder: (context, snap) {
              final data = snap.data;

              return RefreshIndicator(
                onRefresh: () async => setState(() {}),
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Analytics Center Pro',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                        ),
                        DropdownButton<String>(
                          value: range,
                          items: const [
                            DropdownMenuItem(value: '7', child: Text('Last 7 days')),
                            DropdownMenuItem(value: '30', child: Text('Last 30 days')),
                            DropdownMenuItem(value: '90', child: Text('Last 90 days')),
                            DropdownMenuItem(value: '365', child: Text('Last 365 days')),
                          ],
                          onChanged: (v) => setState(() => range = v ?? '30'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (snap.connectionState == ConnectionState.waiting && data == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snap.hasError)
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Analytics load failed: ${snap.error}'),
                        ),
                      )
                    else if (data != null) ...[
                        _summaryGrid(data),
                        const SizedBox(height: 16),
                        _sectionCard(
                          title: 'Order Status Overview',
                          icon: Icons.pie_chart_rounded,
                          child: _statusOverview(data),
                        ),
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth >= 1000;

                            final left = _sectionCard(
                              title: 'Top Selling Products',
                              icon: Icons.trending_up_rounded,
                              child: _barList(
                                items: List<Map<String, dynamic>>.from(data['topProducts'] ?? []),
                                labelKey: 'name',
                                valueKey: 'revenue',
                                suffix: '৳',
                              ),
                            );

                            final right = _sectionCard(
                              title: 'Top Vendors',
                              icon: Icons.storefront_rounded,
                              child: _barList(
                                items: List<Map<String, dynamic>>.from(data['topVendors'] ?? []),
                                labelKey: 'name',
                                valueKey: 'revenue',
                                suffix: '৳',
                              ),
                            );

                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: left),
                                  const SizedBox(width: 16),
                                  Expanded(child: right),
                                ],
                              );
                            }

                            return Column(children: [left, right]);
                          },
                        ),
                        LayoutBuilder(
                          builder: (context, c) {
                            final wide = c.maxWidth >= 1000;

                            final left = _sectionCard(
                              title: 'Daily Revenue',
                              icon: Icons.show_chart_rounded,
                              child: _dailyRevenueList(
                                List<Map<String, dynamic>>.from(data['dailyRevenue'] ?? []),
                              ),
                            );

                            final right = _sectionCard(
                              title: 'Low Stock Alerts',
                              icon: Icons.warning_amber_rounded,
                              child: _lowStockList(
                                List<Map<String, dynamic>>.from(data['lowStockProducts'] ?? []),
                              ),
                            );

                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: left),
                                  const SizedBox(width: 16),
                                  Expanded(child: right),
                                ],
                              );
                            }

                            return Column(children: [left, right]);
                          },
                        ),
                        _sectionCard(
                          title: 'User / Referral / Marketplace Summary',
                          icon: Icons.insights_rounded,
                          child: _miniStats(data),
                        ),
                      ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
