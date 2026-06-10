import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'user/cart_page.dart';
import '../widgets/cart_badge.dart';
import 'admin/admin_dashboard_page.dart';
import 'auth/login_page.dart';
import 'settings_page.dart';
import 'user/delivery/delivery_partner_apply_page.dart';
import 'user/help_center_page.dart';
import 'user/home_page.dart';
import 'user/my_lists_page.dart';
import 'user/profile/my_address_page.dart';
import 'user/profile/profile_page.dart';
import 'user/user_order_page.dart';
import 'vendor/vendor_apply_page.dart';
import 'vendor/vendor_dashboard_page.dart';
import 'user/my_appointments_page.dart';

class MainNavigation extends StatefulWidget {
  final String role;
  final int initialIndex;

  const MainNavigation({
    super.key,
    this.role = 'user',
    this.initialIndex = 0,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  int _currentIndex = 0;
  bool _loginDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 2);
  }

  bool _isAdminRole(String role) {
    return role == 'admin' || role == 'superAdmin' || role == 'staff';
  }

  bool _isVendorRole(String role) {
    return role == 'vendor';
  }

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  void _setTab(int index) {
    if (!mounted) return;
    if (index < 0 || index > 2) return;
    setState(() => _currentIndex = index);
  }

  Future<String> _resolveUserRole(User user) async {
    try {
      final doc = await db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final role = _text(data['role'], widget.role);
      final roles = List<String>.from(data['roles'] ?? []);

      if (role == 'superAdmin' ||
          roles.contains('superAdmin')) {
        return 'superAdmin';
      }

      if (role == 'admin' ||
          roles.contains('admin')) {
        return 'admin';
      }

      if (role == 'staff' || roles.contains('staff')) return 'staff';

      if (role == 'vendor' ||
          roles.contains('vendor') ||
          data['sellerStatus'] == 'approved') {
        return 'vendor';
      }

      final vendorDoc = await db.collection('vendors').doc(user.uid).get();
      final vendor = vendorDoc.data() ?? {};
      if (vendor['status'] == 'approved' && vendor['isActive'] != false) {
        return 'vendor';
      }
    } catch (_) {}

    return widget.role;
  }

  void _showLoginPopup() {
    if (_loginDialogOpen) return;

    _loginDialogOpen = true;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const LoginPage(isPopup: true),
    ).whenComplete(() {
      _loginDialogOpen = false;
      if (mounted) setState(() {});
    });
  }

  bool _requireLogin() {
    if (_isLoggedIn) return true;
    _showLoginPopup();
    return false;
  }

  void _openPage(Widget page, {bool loginRequired = true}) {
    Navigator.pop(context);

    if (loginRequired && !_isLoggedIn) {
      _showLoginPopup();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _logout() async {
    Navigator.pop(context);
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    setState(() => _currentIndex = 0);
  }

  void _openMenuHub() {
    final user = FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;

    final displayName = loggedIn
        ? ((user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : 'ChalakChar Mart User')
        : 'Guest User';

    final email = loggedIn ? (user.email ?? 'Logged in user') : 'Please login to manage account';
    final firstLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF4E5), Color(0xFFEFFFFB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFFF9900).withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.14),
                            child: Text(
                              firstLetter,
                              style: const TextStyle(
                                color: Color(0xFF32A8C7),
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!loggedIn)
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showLoginPopup();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF32A8C7),
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              child: const Text('Login'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                      children: [
                        _sectionTitle('Account'),
                        _menuTile(
                          icon: Icons.person_outline,
                          title: 'My Profile',
                          subtitle: 'View and update your profile',
                          onTap: () => _openPage(const ProfilePage()),
                        ),
                        _menuTile(
                          icon: Icons.shopping_bag_outlined,
                          title: 'My Orders',
                          subtitle: 'Track orders and order history',
                          onTap: () => _openPage(const OrderPage()),
                        ),
                        _menuTile(
                          icon: Icons.upload_file_outlined,
                          title: 'My Lists',
                          subtitle: 'Uploaded list history',
                          onTap: () => _openPage(const MyListsPage()),
                        ),
                        _menuTile(
                          icon: Icons.calendar_month_outlined,
                          title: 'My Appointments',
                          subtitle: 'View your doctor booking history',
                          onTap: () => _openPage(const MyAppointmentsPage()),
                        ),
                        _menuTile(
                          icon: Icons.location_on_outlined,
                          title: 'My Addresses',
                          subtitle: 'Delivery address and location',
                          onTap: () => _openPage(const MyAddressPage()),
                        ),
                        _sectionTitle('Business & Services'),
                        Row(
                          children: [
                            Expanded(
                              child: _actionCard(
                                icon: Icons.storefront_outlined,
                                title: 'Seller Account',
                                color: const Color(0xFFFF9900),
                                onTap: () => _openPage(const VendorApplyPage()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionCard(
                                icon: Icons.delivery_dining_outlined,
                                title: 'Delivery Partner',
                                color: Colors.green,
                                onTap: () => _openPage(const DeliveryPartnerApplyPage()),
                              ),
                            ),
                          ],
                        ),
                        _sectionTitle('Support'),
                        _menuTile(
                          icon: Icons.help_outline,
                          title: 'Help Center',
                          subtitle: 'Support, FAQ and contact',
                          onTap: () => _openPage(const HelpCenterPage(), loginRequired: false),
                        ),
                        _menuTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          subtitle: 'App settings and preferences',
                          onTap: () => _openPage(const SettingsPage(), loginRequired: false),
                        ),
                        const SizedBox(height: 8),
                        if (loggedIn) _logoutTile() else _loginTile(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.black54,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF32A8C7).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: const Color(0xFF32A8C7)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 94,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoutTile() {
    return InkWell(
      onTap: _logout,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.10)),
        ),
        child: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Logout',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginTile() {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _showLoginPopup();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF32A8C7).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF32A8C7).withValues(alpha: 0.14)),
        ),
        child: const Row(
          children: [
            Icon(Icons.login_rounded, color: Color(0xFF32A8C7)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Login / Sign up',
                style: TextStyle(
                  color: Color(0xFF32A8C7),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guardedIndexedPage({
    required Widget page,
    required String label,
  }) {
    if (_isLoggedIn) return page;

    return _LoginRequiredPage(
      title: label,
      onLogin: _showLoginPopup,
      onHome: () => _setTab(0),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdminRole(widget.role)) {
      return const Scaffold(body: AdminDashboard());
    }

    if (_isVendorRole(widget.role)) {
      return const Scaffold(body: VendorDashboardPage());
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final user = authSnap.data;

        if (user == null) {
          return _buildUserShell(role: 'user');
        }

        return FutureBuilder<String>(
          future: _resolveUserRole(user),
          builder: (context, roleSnap) {
            final role = roleSnap.data ?? widget.role;

            if (roleSnap.connectionState == ConnectionState.waiting) {
              return _buildUserShell(role: 'user');
            }

            if (_isAdminRole(role)) {
              return const Scaffold(body: AdminDashboard());
            }

            if (_isVendorRole(role)) {
              return const Scaffold(body: VendorDashboardPage());
            }

            return _buildUserShell(role: role);
          },
        );
      },
    );
  }

  Widget _buildUserShell({required String role}) {
    final double width = MediaQuery.of(context).size.width;
    final bool showBottomNav = width < 1024;

    final pages = [
      const ProductHomePage(),
      _guardedIndexedPage(page: const ProfilePage(), label: 'Profile'),
      const CartPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: showBottomNav ? _bottomNavigationBar() : null,
    );
  }

  Widget _bottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFFFF9900),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          elevation: 0,
          onTap: (index) {
            if (index == 3) {
              _openMenuHub();
              return;
            }

            if (index == 1 && !_requireLogin()) {
              return;
            }

            _setTab(index);
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: CartBadge(iconColor: Colors.grey),
              activeIcon: CartBadge(iconColor: Color(0xFFFF9900)),
              label: 'Cart',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_outlined),
              activeIcon: Icon(Icons.menu),
              label: 'Menu',
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginRequiredPage extends StatelessWidget {
  final String title;
  final VoidCallback onLogin;
  final VoidCallback onHome;

  const _LoginRequiredPage({
    required this.title,
    required this.onLogin,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(22),
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
                    backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF32A8C7),
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$title requires login',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please login to continue. Main navigation will stay here after login.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onLogin,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Login / Sign up'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF32A8C7),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onHome,
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
