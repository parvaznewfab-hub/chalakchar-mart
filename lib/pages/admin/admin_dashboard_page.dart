import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';

import 'admin_analytics_page.dart';
import 'admin_doctor_appointments_page.dart';
import 'admin_notifications_page.dart';
import 'admin_marketing_page.dart';
import 'tiktok_publish_queue_page.dart';
import 'admin_order_page.dart';
import 'admin_lists_page.dart';
import 'app_settings_page.dart';
import 'manage_banners_page.dart';
import 'manage_categories_page.dart';
import 'manage_coupons_page.dart';
import 'manage_doctor_departments_page.dart';
import 'manage_doctors_page.dart';
import 'manage_products_page.dart';
import 'admin_users_page.dart';
import 'admin_vendors_page.dart';
import 'admin_vendor_payout_page.dart';
import 'admin_vendor_products_page.dart';
import 'admin_delivery_partner_approval_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  String selectedKey = 'dashboard';

  static const List<_AdminMenuItem> allMenuItems = [
    _AdminMenuItem(
      key: 'dashboard',
      title: 'Dashboard',
      icon: Icons.dashboard_rounded,
      permission: 'dashboard.view',
    ),
    _AdminMenuItem(
      key: 'analytics',
      title: 'Analytics',
      icon: Icons.insights_rounded,
      permission: 'analytics.view',
    ),
    _AdminMenuItem(
      key: 'notifications',
      title: 'Notifications',
      icon: Icons.notifications_active_rounded,
      permission: 'notifications.view',
    ),
    _AdminMenuItem(
      key: 'marketing',
      title: 'Marketing Center',
      icon: Icons.campaign_rounded,
      permission: 'marketing.view',
    ),
    _AdminMenuItem(
      key: 'tiktokPublishQueue',
      title: 'TikTok Publish Queue',
      icon: Icons.music_note_rounded,
      permission: 'marketing.manage',
    ),
    _AdminMenuItem(
      key: 'users',
      title: 'Users',
      icon: Icons.people_alt_rounded,
      permission: 'users.view',
    ),
    _AdminMenuItem(
      key: 'vendors',
      title: 'Vendors',
      icon: Icons.storefront_rounded,
      permission: 'vendors.view',
    ),
    _AdminMenuItem(
      key: 'payouts',
      title: 'Payouts',
      icon: Icons.account_balance_wallet_rounded,
      permission: 'vendors.payouts',
    ),
    _AdminMenuItem(
      key: 'vendorProducts',
      title: 'Vendor Products',
      icon: Icons.approval_rounded,
      permission: 'vendor_products.view',
    ),
    _AdminMenuItem(
      key: 'products',
      title: 'Products',
      icon: Icons.inventory_2_rounded,
      permission: 'products.view',
    ),
    _AdminMenuItem(
      key: 'categories',
      title: 'Categories',
      icon: Icons.category_rounded,
      permission: 'categories.view',
    ),
    _AdminMenuItem(
      key: 'banners',
      title: 'Banners',
      icon: Icons.campaign_rounded,
      permission: 'banners.view',
    ),
    _AdminMenuItem(
      key: 'orders',
      title: 'Orders',
      icon: Icons.local_shipping_rounded,
      permission: 'orders.view',
    ),
    _AdminMenuItem(
      key: 'lists',
      title: 'Lists',
      icon: Icons.fact_check_rounded,
      permission: 'lists.view',
    ),
    _AdminMenuItem(
      key: 'coupons',
      title: 'Coupons',
      icon: Icons.confirmation_number_rounded,
      permission: 'coupons.view',
    ),
    _AdminMenuItem(
      key: 'doctorDept',
      title: 'Doctor Dept',
      icon: Icons.medical_information_rounded,
      permission: 'doctors.view',
    ),
    _AdminMenuItem(
      key: 'doctors',
      title: 'Doctors',
      icon: Icons.health_and_safety_rounded,
      permission: 'doctors.view',
    ),
    _AdminMenuItem(
      key: 'appointments',
      title: 'Appointments',
      icon: Icons.calendar_month_rounded,
      permission: 'appointments.view',
    ),
    _AdminMenuItem(
      key: 'deliveryPartners',
      title: 'Delivery Partners',
      icon: Icons.delivery_dining_rounded,
      permission: 'delivery.view',
    ),
    _AdminMenuItem(
      key: 'settings',
      title: 'Settings',
      icon: Icons.settings_rounded,
      permission: 'settings.view',
    ),
  ];

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  List<String> _roles(Map<String, dynamic> data) {
    final roles = <String>{};
    final primaryRole = _text(data['role'], 'user');
    if (primaryRole.isNotEmpty) roles.add(primaryRole);

    final rawRoles = data['roles'];
    if (rawRoles is List) {
      for (final role in rawRoles) {
        final clean = _text(role);
        if (clean.isNotEmpty) roles.add(clean);
      }
    }
    return roles.toList();
  }

  bool _isSuperAdmin(Map<String, dynamic> data) {
    return _roles(data).contains('superAdmin');
  }

  bool _isAdmin(Map<String, dynamic> data) {
    return _roles(data).contains('admin');
  }

  bool _isStaff(Map<String, dynamic> data) {
    return _roles(data).contains('staff');
  }

  bool _isAllowedAccount(Map<String, dynamic> data) {
    return data['isActive'] != false && data['isBanned'] != true;
  }

  static const Set<String> _defaultAdminPermissions = {
    'dashboard.view',
    'analytics.view',
    'orders.view',
    'orders.edit',
    'orders.assign_rider',
    'orders.invoice',
    'orders.settle_cod',
    'orders.discount',
    'orders.confirm',
    'products.view',
    'products.edit',
    'products.delete',
    'products.bulk',
    'products.status',
    'vendor_products.view',
    'vendor_products.edit',
    'vendor_products.approve',
    'vendor_products.delete',
    'vendor_products.status',
    'categories.view',
    'categories.edit',
    'categories.delete',
    'categories.status',
    'banners.view',
    'banners.edit',
    'banners.delete',
    'banners.status',
    'banners.priority',
    'coupons.view',
    'coupons.edit',
    'coupons.delete',
    'coupons.status',
    'lists.view',
    'lists.edit',
    'doctors.view',
    'doctors.edit',
    'appointments.view',
    'appointments.edit',
    'vendors.view',
    'vendors.edit',
    'vendors.approve',
    'vendors.delete',
    'vendors.status',
    'vendors.documents',
    'vendors.contact',
    'vendors.payouts',
    'delivery.view',
    'delivery.approve',
    'delivery.block',
    'delivery.withdraw',
    'delivery.settle_cod',
    'delivery.documents',
    'delivery.contact',
    'referrals.view',
    'referrals.edit',
    'notifications.view',
    'notifications.send',
    'notifications.manage',
    'notifications.delete',
    'notifications.open_related',
    'settings.view',
  };

  static const Set<String> _defaultStaffPermissions = {
    'dashboard.view',
  };

  bool _can(Map<String, dynamic> data, String permission) {
    if (_isSuperAdmin(data)) return true;

    final rawPermissions = data['permissions'];
    final permissions = rawPermissions is List ? List<String>.from(rawPermissions) : <String>[];

    if (permissions.isNotEmpty) {
      return permissions.contains(permission);
    }

    if (_isAdmin(data)) {
      return _defaultAdminPermissions.contains(permission);
    }

    if (_isStaff(data)) {
      return _defaultStaffPermissions.contains(permission);
    }

    return false;
  }

  bool _canAny(Map<String, dynamic> data, List<String> permissions) {
    return permissions.any((permission) => _can(data, permission));
  }

  List<_AdminMenuItem> _allowedMenus(Map<String, dynamic> data) {
    return allMenuItems.where((item) => _can(data, item.permission)).toList();
  }

  Widget _pageByKey(String key, Map<String, dynamic> userData) {
    _AdminMenuItem? item;
    for (final menuItem in allMenuItems) {
      if (menuItem.key == key) {
        item = menuItem;
        break;
      }
    }

    if (item == null || !_can(userData, item.permission)) {
      return _AccessDeniedPage(
        title: 'Access denied',
        message: 'You do not have permission to open this admin section.',
      );
    }

    switch (key) {
      case 'analytics':
        return const AdminAnalyticsPage();
      case 'notifications':
        return const AdminNotificationsPage();
      case 'marketing':
        return const AdminMarketingPage();
      case 'tiktokPublishQueue':
        return const TikTokPublishQueuePage();
      case 'users':
        return const AdminUsersPage();
      case 'vendors':
        return const AdminVendorsPage();
      case 'payouts':
        return const AdminVendorPayoutPage();
      case 'vendorProducts':
        return const AdminVendorProductsPage();
      case 'products':
        return const ManageProductsPage();
      case 'categories':
        return const ManageCategoriesPage();
      case 'banners':
        return const ManageBannersProPage();
      case 'orders':
        return const AdminOrdersPage();
      case 'lists':
        return const AdminListsPage();
      case 'coupons':
        return const ManageCouponsPage();
      case 'doctorDept':
        return const ManageDoctorDepartmentsPage();
      case 'doctors':
        return const ManageDoctorsPage();
      case 'appointments':
        return const AdminDoctorAppointmentsPage();
      case 'deliveryPartners':
        return const AdminDeliveryPartnerApprovalPage();
      case 'settings':
        return const AppSettingsPage();
      case 'dashboard':
      default:
        return _DashboardHome(
          userData: userData,
          canOrders: _can(userData, 'orders.view'),
          canProducts: _can(userData, 'products.view'),
          canUsers: _can(userData, 'users.view'),
          canLists: _can(userData, 'lists.view'),
          canCoupons: _can(userData, 'coupons.view'),
          canNotifications: _can(userData, 'notifications.view'),
          canMarketing: _can(userData, 'marketing.view'),
          canAnalytics: _can(userData, 'analytics.view'),
          onNotifyTap: () => _selectMenu('notifications'),
          onMarketingTap: () => _selectMenu('marketing'),
          onAnalyticsTap: () => _selectMenu('analytics'),
          onUsersTap: () => _selectMenu('users'),
          onOrdersTap: () => _selectMenu('orders'),
          onProductsTap: () => _selectMenu('products'),
          onListsTap: () => _selectMenu('lists'),
          onCouponsTap: () => _selectMenu('coupons'),
        );
    }
  }

  void _selectMenu(String key) {
    if (!mounted) return;
    setState(() => selectedKey = key);

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout from admin panel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await authService.signOut();
    }
  }

  Future<void> _showNotificationDialog(Map<String, dynamic> userData) async {
    if (!_can(userData, 'notifications.send')) {
      _snack('You do not have permission to send notifications', isError: true);
      return;
    }

    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool sending = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> send() async {
            final title = titleController.text.trim();
            final body = bodyController.text.trim();

            if (title.isEmpty || body.isEmpty) {
              _snack('Title and message required', isError: true);
              return;
            }

            setDialogState(() => sending = true);

            try {
              await NotificationService.sendToAll(title: title, body: body);

              if (context.mounted) {
                Navigator.pop(context);
                _snack('Notification saved for all users');
              }
            } catch (e) {
              _snack('Send failed: $e', isError: true);
            } finally {
              if (context.mounted) setDialogState(() => sending = false);
            }
          }

          return AlertDialog(
            title: const Text('Send Notification'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: sending ? null : send,
                icon: sending
                    ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.send_rounded),
                label: Text(sending ? 'Sending...' : 'Send'),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    bodyController.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: authService.currentUserData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FB),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = snapshot.data;
        if (userData == null || !_isAllowedAccount(userData)) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FB),
            body: _AccessDeniedPage(
              title: 'Admin access denied',
              message: 'Your account is not allowed to access the admin panel.',
              actionLabel: 'Logout',
              onAction: _logout,
            ),
          );
        }

        if (!_canAny(userData, const [
          'dashboard.view',
          'analytics.view',
          'orders.view',
          'products.view',
          'users.view',
          'settings.view',
          'notifications.view',
          'vendors.view',
          'delivery.view',
        ])) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FB),
            body: _AccessDeniedPage(
              title: 'No admin permission',
              message: 'This account has an admin/staff role but no usable admin permissions.',
              actionLabel: 'Logout',
              onAction: _logout,
            ),
          );
        }

        final allowedMenus = _allowedMenus(userData);
        if (allowedMenus.isEmpty) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FB),
            body: _AccessDeniedPage(
              title: 'No menu access',
              message: 'No admin menu is available for this account.',
              actionLabel: 'Logout',
              onAction: _logout,
            ),
          );
        }

        if (!allowedMenus.any((item) => item.key == selectedKey)) {
          selectedKey = allowedMenus.first.key;
        }

        final selectedItem = allowedMenus.firstWhere(
              (item) => item.key == selectedKey,
          orElse: () => allowedMenus.first,
        );
        final isDesktop = MediaQuery.of(context).size.width >= 1000;
        final canSendNotification = _can(userData, 'notifications.send');

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          drawer: isDesktop
              ? null
              : _AdminSidebar(
            selectedKey: selectedKey,
            items: allowedMenus,
            onSelect: _selectMenu,
            onLogout: _logout,
          ),
          body: Row(
            children: [
              if (isDesktop)
                _AdminSidebar(
                  selectedKey: selectedKey,
                  items: allowedMenus,
                  onSelect: _selectMenu,
                  onLogout: _logout,
                ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: selectedItem.title,
                      isDesktop: isDesktop,
                      onLogout: _logout,
                      canSendNotification: canSendNotification,
                      onSendNotification: () => _showNotificationDialog(userData),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(
                          key: ValueKey<String>(selectedKey),
                          child: _pageByKey(selectedKey, userData),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardHome extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool canOrders;
  final bool canProducts;
  final bool canUsers;
  final bool canLists;
  final bool canCoupons;
  final bool canNotifications;
  final bool canMarketing;
  final bool canAnalytics;
  final VoidCallback onNotifyTap;
  final VoidCallback onMarketingTap;
  final VoidCallback onAnalyticsTap;
  final VoidCallback onUsersTap;
  final VoidCallback onOrdersTap;
  final VoidCallback onProductsTap;
  final VoidCallback onListsTap;
  final VoidCallback onCouponsTap;

  const _DashboardHome({
    required this.userData,
    required this.canOrders,
    required this.canProducts,
    required this.canUsers,
    required this.canLists,
    required this.canCoupons,
    required this.canNotifications,
    required this.canMarketing,
    required this.canAnalytics,
    required this.onNotifyTap,
    required this.onMarketingTap,
    required this.onAnalyticsTap,
    required this.onUsersTap,
    required this.onOrdersTap,
    required this.onProductsTap,
    required this.onListsTap,
    required this.onCouponsTap,
  });

  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  Future<Map<String, dynamic>> _loadStats() async {
    final db = FirebaseFirestore.instance;

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    final keys = <String>[];

    void add(String key, Query<Map<String, dynamic>> query) {
      keys.add(key);
      futures.add(query.get());
    }

    if (widget.canOrders) add('orders', db.collection('orders').limit(1000));
    if (widget.canProducts) {
      add(
        'products',
        db.collection('products').where('isActive', isEqualTo: true).limit(1000),
      );
    }
    if (widget.canUsers) add('users', db.collection('users').limit(1000));
    if (widget.canLists) add('lists', db.collection('lists').limit(500));
    if (widget.canCoupons) {
      add(
        'coupons',
        db.collection('coupons').where('isActive', isEqualTo: true).limit(300),
      );
    }
    if (widget.canUsers) add('vendors', db.collection('vendors').limit(500));
    if (widget.canNotifications) {
      add(
        'notifications',
        db.collection('notifications').where('isRead', isEqualTo: false).limit(300),
      );
    }
    if (widget.canMarketing) {
      add('marketingOutbox', db.collection('marketing_outbox').limit(500));
      add('marketingLogs', db.collection('marketing_logs').limit(500));
      add('marketingScores', db.collection('product_marketing_scores').limit(500));
    }
    if (widget.canUsers) add('referrals', db.collection('referrals').limit(500));
    if (widget.canUsers) {
      add('deliveryPartners', db.collection('deliveryPartners').limit(500));
    }

    final results = await Future.wait(futures);
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (int i = 0; i < keys.length; i++) {
      map[keys[i]] = results[i].docs;
    }

    final orders = map['orders'] ?? [];
    final products = map['products'] ?? [];
    final users = map['users'] ?? [];
    final lists = map['lists'] ?? [];
    final coupons = map['coupons'] ?? [];
    final vendors = map['vendors'] ?? [];
    final unreadNotifications = map['notifications'] ?? [];
    final marketingOutbox = map['marketingOutbox'] ?? [];
    final marketingLogs = map['marketingLogs'] ?? [];
    final marketingScores = map['marketingScores'] ?? [];
    final referrals = map['referrals'] ?? [];
    final deliveryPartners = map['deliveryPartners'] ?? [];

    int pendingOrders = 0;
    int deliveredOrders = 0;
    double totalRevenue = 0;

    for (final doc in orders) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending').toString().toLowerCase();

      if (status == 'pending') pendingOrders++;
      if (status == 'delivered' || status == 'completed') deliveredOrders++;

      totalRevenue += _toDouble(
        data['grandTotal'] ?? data['finalTotal'] ?? data['total'] ?? data['totalAmount'],
      );
    }

    int lowStock = 0;
    for (final doc in products) {
      final data = doc.data();
      final stock = int.tryParse((data['stock'] ?? 0).toString()) ?? 0;
      if (stock <= 5) lowStock++;
    }

    int pendingLists = 0;
    for (final doc in lists) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending').toString();
      if (status == 'pending') pendingLists++;
    }

    int approvedVendors = 0;
    int pendingVendors = 0;
    for (final doc in vendors) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending').toString();
      if (status == 'approved') approvedVendors++;
      if (status == 'pending') pendingVendors++;
    }

    int pendingReferrals = 0;
    for (final doc in referrals) {
      final data = doc.data();
      final status = (data['status'] ?? 'Pending').toString();
      if (status == 'Pending') pendingReferrals++;
    }

    int approvedDeliveryPartners = 0;
    int pendingDeliveryPartners = 0;
    for (final doc in deliveryPartners) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending').toString();
      if (status == 'approved') approvedDeliveryPartners++;
      if (status == 'pending') pendingDeliveryPartners++;
    }

    return {
      'orders': orders.length,
      'pendingOrders': pendingOrders,
      'deliveredOrders': deliveredOrders,
      'products': products.length,
      'lowStock': lowStock,
      'users': users.length,
      'lists': lists.length,
      'pendingLists': pendingLists,
      'coupons': coupons.length,
      'vendors': vendors.length,
      'approvedVendors': approvedVendors,
      'pendingVendors': pendingVendors,
      'unreadNotifications': unreadNotifications.length,
      'marketingOutbox': marketingOutbox.length,
      'marketingLogs': marketingLogs.length,
      'marketingScores': marketingScores.length,
      'pendingReferrals': pendingReferrals,
      'approvedDeliveryPartners': approvedDeliveryPartners,
      'pendingDeliveryPartners': pendingDeliveryPartners,
      'totalRevenue': totalRevenue,
    };
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _displayName() {
    final name = (widget.userData['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (widget.userData['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email.split('@').first;
    return 'Administrator';
  }

  Future<void> _refresh() async {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, ${_displayName()} 👋',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your admin control center is permission protected.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (widget.canAnalytics)
                    ElevatedButton.icon(
                      onPressed: widget.onAnalyticsTap,
                      icon: const Icon(Icons.insights_rounded),
                      label: const Text('Analytics'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                const LinearProgressIndicator(),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width > 1200
                      ? 4
                      : width > 760
                      ? 3
                      : 2;

                  final cards = <Widget>[];

                  if (widget.canOrders) {
                    cards.addAll([
                      _StatCard(
                        title: 'Total Revenue',
                        value: '৳${_toDouble(stats['totalRevenue']).toStringAsFixed(0)}',
                        icon: Icons.payments_rounded,
                        color: Colors.green,
                        onTap: widget.onAnalyticsTap,
                      ),
                      _StatCard(
                        title: 'Total Orders',
                        value: '${stats['orders'] ?? 0}',
                        icon: Icons.shopping_cart_checkout_rounded,
                        color: Colors.blue,
                        onTap: widget.onOrdersTap,
                      ),
                      _StatCard(
                        title: 'Pending Orders',
                        value: '${stats['pendingOrders'] ?? 0}',
                        icon: Icons.pending_actions_rounded,
                        color: Colors.orange,
                        onTap: widget.onOrdersTap,
                      ),
                      _StatCard(
                        title: 'Delivered Orders',
                        value: '${stats['deliveredOrders'] ?? 0}',
                        icon: Icons.verified_rounded,
                        color: Colors.teal,
                        onTap: widget.onOrdersTap,
                      ),
                    ]);
                  }

                  if (widget.canProducts) {
                    cards.addAll([
                      _StatCard(
                        title: 'Active Products',
                        value: '${stats['products'] ?? 0}',
                        icon: Icons.inventory_2_rounded,
                        color: Colors.indigo,
                        onTap: widget.onProductsTap,
                      ),
                      _StatCard(
                        title: 'Low Stock',
                        value: '${stats['lowStock'] ?? 0}',
                        icon: Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        onTap: widget.onProductsTap,
                      ),
                    ]);
                  }

                  if (widget.canUsers) {
                    cards.addAll([
                      _StatCard(
                        title: 'Customers',
                        value: '${stats['users'] ?? 0}',
                        icon: Icons.people_alt_rounded,
                        color: Colors.purple,
                        onTap: widget.onUsersTap,
                      ),
                      _StatCard(
                        title: 'Approved Vendors',
                        value: '${stats['approvedVendors'] ?? 0}',
                        icon: Icons.storefront_rounded,
                        color: Colors.green,
                      ),
                      _StatCard(
                        title: 'Pending Vendors',
                        value: '${stats['pendingVendors'] ?? 0}',
                        icon: Icons.store_mall_directory_rounded,
                        color: Colors.orange,
                      ),
                      _StatCard(
                        title: 'Pending Referrals',
                        value: '${stats['pendingReferrals'] ?? 0}',
                        icon: Icons.share_rounded,
                        color: Colors.brown,
                      ),
                      _StatCard(
                        title: 'Approved Riders',
                        value: '${stats['approvedDeliveryPartners'] ?? 0}',
                        icon: Icons.delivery_dining_rounded,
                        color: Colors.teal,
                      ),
                      _StatCard(
                        title: 'Pending Riders',
                        value: '${stats['pendingDeliveryPartners'] ?? 0}',
                        icon: Icons.pending_actions_rounded,
                        color: Colors.deepOrange,
                      ),
                    ]);
                  }

                  if (widget.canNotifications) {
                    cards.add(
                      _StatCard(
                        title: 'Notifications',
                        value: '${stats['unreadNotifications'] ?? 0}',
                        icon: Icons.notifications_active_rounded,
                        color: Colors.deepOrange,
                        onTap: widget.onNotifyTap,
                      ),
                    );
                  }

                  if (widget.canMarketing) {
                    cards.addAll([
                      _StatCard(
                        title: 'Marketing Queue',
                        value: '${stats['marketingOutbox'] ?? 0}',
                        icon: Icons.campaign_rounded,
                        color: Colors.pink,
                        onTap: widget.onMarketingTap,
                      ),
                      _StatCard(
                        title: 'Marketing Logs',
                        value: '${stats['marketingLogs'] ?? 0}',
                        icon: Icons.history_rounded,
                        color: Colors.indigo,
                        onTap: widget.onMarketingTap,
                      ),
                      _StatCard(
                        title: 'Product Scores',
                        value: '${stats['marketingScores'] ?? 0}',
                        icon: Icons.trending_up_rounded,
                        color: Colors.green,
                        onTap: widget.onMarketingTap,
                      ),
                    ]);
                  }

                  if (widget.canLists) {
                    cards.addAll([
                      _StatCard(
                        title: 'Lists',
                        value: '${stats['lists'] ?? 0}',
                        icon: Icons.medical_information_rounded,
                        color: Colors.red,
                        onTap: widget.onListsTap,
                      ),
                      _StatCard(
                        title: 'Pending Rx',
                        value: '${stats['pendingLists'] ?? 0}',
                        icon: Icons.fact_check_rounded,
                        color: Colors.pink,
                        onTap: widget.onListsTap,
                      ),
                    ]);
                  }

                  if (widget.canCoupons) {
                    cards.add(
                      _StatCard(
                        title: 'Active Coupons',
                        value: '${stats['coupons'] ?? 0}',
                        icon: Icons.confirmation_number_rounded,
                        color: Colors.cyan,
                        onTap: widget.onCouponsTap,
                      ),
                    );
                  }

                  if (cards.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.lock_outline_rounded,
                      title: 'Dashboard access granted',
                      message: 'No dashboard widgets are assigned. Give orders.view, products.view, users.view or another data permission to show cards here.',
                    );
                  }

                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: width > 760 ? 2.18 : 1.55,
                    children: cards,
                  );
                },
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final sections = <Widget>[];

                  if (widget.canOrders) {
                    sections.add(_SectionCard(title: 'Recent Orders', child: _RecentOrdersList()));
                  }

                  if (widget.canProducts) {
                    sections.add(_SectionCard(title: 'Low Stock Products', child: _LowStockList()));
                  }

                  if (sections.isEmpty) return const SizedBox.shrink();

                  if (wide && sections.length >= 2) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: sections[0]),
                        const SizedBox(width: 16),
                        Expanded(child: sections[1]),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      for (int i = 0; i < sections.length; i++) ...[
                        sections[i],
                        if (i != sections.length - 1) const SizedBox(height: 16),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentOrdersList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No recent orders'),
          );
        }

        return Column(
          children: snap.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final total = _numToDouble(data['grandTotal'] ?? data['total'] ?? data['finalTotal']);

            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEAF6FA),
                child: Text(
                  doc.id.substring(0, 2).toUpperCase(),
                  style: const TextStyle(color: Color(0xFF1592B3), fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                data['userName']?.toString() ?? 'Customer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('Order #${doc.id.substring(0, 8)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('৳${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    data['status']?.toString() ?? 'pending',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LowStockList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('products')
          .where('isActive', isEqualTo: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final lowStock = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final stock = int.tryParse((data['stock'] ?? 0).toString()) ?? 0;
          return stock <= 5;
        }).toList();

        if (lowStock.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No low stock products right now'),
          );
        }

        return Column(
          children: lowStock.take(8).map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final stock = int.tryParse((data['stock'] ?? 0).toString()) ?? 0;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                stock <= 0 ? Icons.remove_shopping_cart_rounded : Icons.warning_amber_rounded,
                color: stock <= 0 ? Colors.red : Colors.orange,
              ),
              title: Text(
                data['name']?.toString() ?? 'Product',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(data['category']?.toString() ?? 'No category'),
              trailing: Text(
                'Stock: $stock',
                style: TextStyle(
                  color: stock <= 0 ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final String selectedKey;
  final List<_AdminMenuItem> items;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;

  const _AdminSidebar({
    required this.selectedKey,
    required this.items,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.centerLeft,
              child: const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFF32A8C7),
                    child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Admin Pro',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = selectedKey == item.key;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Material(
                      color: selected ? const Color(0xFF32A8C7) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onSelect(item.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          child: Row(
                            children: [
                              Icon(item.icon, color: selected ? Colors.white : Colors.white70, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    color: selected ? Colors.white : Colors.white70,
                                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              onTap: onLogout,
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final bool isDesktop;
  final VoidCallback onLogout;
  final bool canSendNotification;
  final VoidCallback onSendNotification;

  const _TopBar({
    required this.title,
    required this.isDesktop,
    required this.onLogout,
    required this.canSendNotification,
    required this.onSendNotification,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (canSendNotification)
            IconButton(
              tooltip: 'Send Notification',
              onPressed: onSendNotification,
              icon: const Icon(Icons.campaign_rounded),
            ),
          IconButton(
            tooltip: 'Logout',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AccessDeniedPage extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _AccessDeniedPage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
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
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: Colors.grey),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _AdminMenuItem {
  final String key;
  final String title;
  final IconData icon;
  final String permission;

  const _AdminMenuItem({
    required this.key,
    required this.title,
    required this.icon,
    required this.permission,
  });
}

double _numToDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
