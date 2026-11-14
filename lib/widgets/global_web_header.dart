import 'dart:async';
import '../pages/user/my_appointments_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/app_settings_service.dart';
import '../services/image_search_service.dart';
import '../pages/admin/admin_dashboard_page.dart';
import '../pages/auth/login_page.dart';
import '../pages/settings_page.dart';
import '../pages/user/help_center_page.dart';
import '../pages/user/my_lists_page.dart';
import '../pages/user/profile/profile_page.dart';
import '../pages/user/referral_page.dart';
import '../pages/user/search_page.dart';
import '../pages/user/user_order_page.dart';
import '../pages/vendor/vendor_apply_page.dart';
import '../pages/vendor/vendor_dashboard_page.dart';
import '../services/auth_service.dart';
import '../services/web_url_service.dart';
import 'cart_badge.dart';
import '../pages/user/delivery/delivery_partner_apply_page.dart';
import '../pages/user/delivery/delivery_partner_dashboard_page.dart';
import '../pages/user/notifications_page.dart';

class GlobalWebHeader extends StatefulWidget implements PreferredSizeWidget {
  const GlobalWebHeader({super.key});

  @override
  State<GlobalWebHeader> createState() => _GlobalWebHeaderState();

  // Row heights laid out in build(): promo strip + main bar + category nav.
  static const double promoStripHeight = 24;
  static const double mainBarHeight = 86;
  static const double categoryNavHeight = 46;

  /// Total header height (was declared as 136, 20px short of the real 156,
  /// so the category nav overlapped page content on desktop).
  static const double height =
      promoStripHeight + mainBarHeight + categoryNavHeight;

  @override
  Size get preferredSize => const Size.fromHeight(height);
}

class _GlobalWebHeaderState extends State<GlobalWebHeader> {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchKeyboardFocusNode = FocusNode(skipTraversal: true);
  final LayerLink _searchLayerLink = LayerLink();
  final GlobalKey _searchBoxKey = GlobalKey();

  OverlayEntry? _searchOverlayEntry;
  Timer? _debounce;
  String _searchText = '';
  bool _searchFocused = false;

  static const Color dark = Color(0xFF131921);
  static const Color dark2 = Color(0xFF232F3E);
  static const Color accent = Color(0xFFFF9900);
  static const Color primary = Color(0xFF32A8C7);

  @override
  void dispose() {
    _debounce?.cancel();
    _removeSearchOverlay();
    _searchFocusNode.dispose();
    _searchKeyboardFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _goHome() {
    WebUrlService.push('/');
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/',
          (route) => false,
    );
  }

  void _showLoginPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const LoginPage(isPopup: true),
    );
  }

  void _openSearch([String query = '']) {
    _removeSearchOverlay();
    FocusScope.of(context).unfocus();

    final q = query.trim();
    if (q.isEmpty && _searchController.text.trim().isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchPage(initialQuery: _searchController.text.trim()),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(initialQuery: q),
      ),
    );
  }

  Future<void> _pickAndSearchByImage() async {
    _removeSearchOverlay();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ছবি তুলুন'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('গ্যালারি থেকে বাছুন'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ImageSearchService.searchByImage(picked);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (result == null || result.searchQuery.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ছবি থেকে প্রোডাক্ট শনাক্ত করা যায়নি।')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchPage(
            initialQuery: result.searchQuery,
            detectedLabel: result.description.isNotEmpty
                ? result.description
                : result.searchQuery,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ছবি সার্চ ব্যর্থ হয়েছে: $e')),
      );
    }
  }

  String _categorySlug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return Uri.encodeComponent(slug);
  }

  void _openCategory(String category) {
    final name = category.trim();
    if (name.isEmpty) return;

    final path = '/category/${_categorySlug(name)}';
    WebUrlService.push(path);
    Navigator.of(context, rootNavigator: true).pushNamed(path);
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Stream<List<Map<String, dynamic>>> _categoryStream() {
    return db.collection('categories').snapshots().map((snap) {
      final list = snap.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).where((e) {
        return e['isActive'] == true;
      }).toList();

      list.sort((a, b) => _toInt(a['priority']).compareTo(_toInt(b['priority'])));
      return list;
    });
  }


  double _searchOverlayWidth() {
    final context = _searchBoxKey.currentContext;
    if (context == null) return 620;

    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.size.width;
    }

    return 620;
  }

  void _showSearchOverlay() {
    if (!mounted) return;

    if (_searchOverlayEntry != null) {
      _searchOverlayEntry!.markNeedsBuild();
      return;
    }

    _searchOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeSearchOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _searchLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 54),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: _searchOverlayWidth(),
                  child: _searchSuggestions(),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_searchOverlayEntry!);
  }

  void _removeSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;

    if (mounted && _searchFocused) {
      setState(() => _searchFocused = false);
    }
  }

  Stream<List<Map<String, dynamic>>> _suggestionStream() {
    final q = _searchText.toLowerCase().trim();

    // search_logs is write-only for shoppers (see firestore.rules): it holds
    // every shopper's queries, so it must never be shown back to others as
    // "recent searches".
    if (q.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }

    return db
        .collection('products')
        .where('isActive', isEqualTo: true)
        .limit(40)
        .snapshots()
        .map((snap) {
      final results = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = _text(data['name']);
        final category = _text(data['category']);
        final generic = _text(data['generic']);
        final haystack = '$name $category $generic'.toLowerCase();

        if (haystack.contains(q)) {
          results.add({
            'title': name,
            'subtitle': category,
            'type': 'Product',
          });
        }
      }

      return results.take(8).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 900) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      builder: (context, snapshot) {
        final settings = snapshot.data;

        return Material(
          elevation: 4,
          color: dark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _promoStrip(settings),
              SizedBox(
                height: GlobalWebHeader.mainBarHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 22),

                    _HoverBox(
                      padding: const EdgeInsets.all(4),
                      onTap: _goHome,
                      child: _headerLogo(settings),
                    ),

                    const SizedBox(width: 18),

                    _locationBox(),

                    const SizedBox(width: 18),

                    Expanded(child: _searchBox(settings)),

                    const SizedBox(width: 18),

                    _accountArea(),

                    const SizedBox(width: 12),

                    _notificationBell(),

                    const SizedBox(width: 10),

                    const _HoverBox(
                      padding: EdgeInsets.all(6),
                      child: CartBadge(),
                    ),

                    const SizedBox(width: 22),
                  ],
                ),
              ),
              _categoryNav(),
            ],
          ),
        );
      },
    );
  }


  Widget _headerLogo(AppSettings? settings) {
    final showLogo = settings == null || settings.showHeaderLogo;
    final logoUrl = _text(settings?.logoUrl);
    final siteName = _text(settings?.pharmacyName, 'ChalakChar Mart');

    if (!showLogo) {
      return Text(
        siteName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    if (logoUrl.isNotEmpty) {
      return Image.network(
        logoUrl,
        height: 44,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackLogo(),
      );
    }

    return Image.asset(
      'assets/images/logo.png',
      height: 44,
      errorBuilder: (_, __, ___) => _fallbackLogo(),
    );
  }

  Widget _fallbackLogo() {
    return const Icon(
      Icons.storefront_rounded,
      color: Colors.white,
      size: 42,
    );
  }

  Widget _promoStrip(AppSettings? settings) {
    if (settings == null) {
      return const SizedBox(
        height: GlobalWebHeader.promoStripHeight,
        child: Center(
          child: Text(
            'ChalakChar Mart',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      height: GlobalWebHeader.promoStripHeight,
      width: double.infinity,
      color: settings.maintenanceMode
          ? Colors.red.shade700
          : const Color(0xFF0E1726),
      alignment: Alignment.center,
      child: Text(
        settings.maintenanceMode
            ? 'Maintenance mode is active'
            : _text(
                settings.headerNotice,
                '${settings.pharmacyName} • Support: ${settings.supportPhone} • Business Hours: ${settings.businessHours}',
              ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _locationBox() {
    return _HoverBox(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Delivering to',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined, color: Colors.white, size: 17),
              SizedBox(width: 3),
              Text(
                'Update location',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchBox(AppSettings? settings) {
    return CompositedTransformTarget(
      link: _searchLayerLink,
      child: KeyboardListener(
        focusNode: _searchKeyboardFocusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _removeSearchOverlay();
            FocusScope.of(context).unfocus();
          }
        },
        child: Container(
          key: _searchBoxKey,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _searchFocused ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _categoryStream(),
                builder: (context, snapshot) {
                  final cats = snapshot.data ?? [];

                  return PopupMenuButton<String>(
                    offset: const Offset(0, 48),
                    color: Colors.white,
                    onSelected: _openCategory,
                    itemBuilder: (_) {
                      if (cats.isEmpty) {
                        return const [
                          PopupMenuItem(
                            value: '',
                            enabled: false,
                            child: Text('No category'),
                          )
                        ];
                      }

                      return cats.map((c) {
                        return PopupMenuItem(
                          value: _text(c['name']),
                          child: Text(_text(c['name'])),
                        );
                      }).toList();
                    },
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('All', style: TextStyle(fontWeight: FontWeight.w700)),
                          Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onTap: () {
                    if (!_searchFocused) {
                      setState(() => _searchFocused = true);
                    }
                    _showSearchOverlay();
                  },
                  onSubmitted: _openSearch,
                  onChanged: (v) {
                    if (!_searchFocused) {
                      setState(() => _searchFocused = true);
                    }
                    _showSearchOverlay();

                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      setState(() => _searchText = v);
                      _searchOverlayEntry?.markNeedsBuild();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: _text(settings?.searchPlaceholder, 'Search ChalakChar Mart'),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ছবি দিয়ে খুঁজুন',
                onPressed: _pickAndSearchByImage,
                icon: const Icon(Icons.camera_alt_outlined, color: Colors.black54),
              ),
              InkWell(
                onTap: () => _openSearch(),
                child: Container(
                  height: 48,
                  width: 58,
                  decoration: const BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(6),
                    ),
                  ),
                  child: const Icon(Icons.search_rounded, color: Colors.black, size: 29),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchSuggestions() {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(12),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _suggestionStream(),
        builder: (context, snapshot) {
          final list = snapshot.data ?? [];

          if (list.isEmpty) {
            return const SizedBox.shrink();
          }

          return Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = list[i];
                final title = _text(item['title']);
                final subtitle = _text(item['subtitle'] ?? item['type']);

                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.search_rounded),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () {
                    _searchController.text = title;
                    setState(() {
                      _searchText = title;
                    });
                    _removeSearchOverlay();
                    FocusScope.of(context).unfocus();
                    _openSearch(title);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _accountArea() {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return _signInAction();
        return _userAction(user);
      },
    );
  }

  Widget _signInAction() {
    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      offset: const Offset(45, 8),
      color: Colors.white,
      onSelected: (_) => _showLoginPopup(),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 280,
              maxWidth: 340,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showLoginPopup();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD814),
                    foregroundColor: Colors.black,
                    elevation: 0,
                  ),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 12),

                InkWell(
                  onTap: () {
                    Navigator.pop(context);

                    showDialog(
                      context: context,
                      barrierColor: Colors.black54,
                      builder: (_) => const LoginPage(
                        isPopup: true,
                        createAccountMode: true,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9900).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: const Color(0xFFFF9900).withValues(alpha: 0.22),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 18,
                            color: Color(0xFFFF9900),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'New customer? Create account with OTP',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFB56A00),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 24),
                _guestMenu('My Orders'),
                _guestMenu('My Lists'),
                _guestMenu('My Appointments'),
                _guestMenu('Help Center'),
                _guestMenu('Seller Account'),
                _guestMenu('Delivery Partner'),
              ],
            ),
          ),
        ),
      ],
      child: const _HeaderTextButton(
        small: 'Hello, sign in',
        bold: 'Account & Lists',
        icon: Icons.arrow_drop_down,
      ),
    );
  }

  Widget _guestMenu(String text) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _showLoginPopup();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _userAction(User user) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = _text(data['name'], user.displayName ?? 'User');
        final role = _text(data['role']);
        final roles = List<String>.from(data['roles'] ?? []);

        final bool isAdmin =
            role == 'admin' ||
                role == 'superAdmin' ||
                role == 'staff' ||
                roles.contains('admin') ||
                roles.contains('superAdmin') ||
                roles.contains('staff');

        final displayRole = role.isEmpty
            ? (roles.isNotEmpty ? roles.first : 'user')
            : role;
        final sellerStatus = _text(data['sellerStatus']);

        return PopupMenuButton<String>(
          position: PopupMenuPosition.under,
          offset: const Offset(45, 8),
          color: Colors.white,
          elevation: 10,
          onSelected: _handleAccountMenu,
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: SizedBox(
                width: 310,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: primary.withValues(alpha: 0.12),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Role: $displayRole   •   Seller: ${sellerStatus.isEmpty ? "none" : sellerStatus}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const Divider(height: 24),
                    _accountMenuText('My Orders', 'orders'),
                    _accountMenuText('My Lists', 'lists'),
                    _accountMenuText('My Appointments', 'appointments'),
                    _accountMenuText('My Profile', 'account'),
                    _accountMenuText('Referral', 'referral'),
                    _accountMenuText('Help Center', 'help'),
                    _accountMenuText('Settings', 'settings'),
                    _accountMenuText('Your Seller Account', 'seller'),
                    _accountMenuText('Delivery Partner', 'delivery_partner'),
                    if (isAdmin)
                      _accountMenuText('Admin Dashboard', 'admin'),
                    const Divider(),
                    _accountMenuText('Logout', 'logout', danger: true),
                  ],
                ),
              ),
            ),
          ],
          child: _HeaderTextButton(
            small: 'Hello, ${name.split(" ").first}',
            bold: 'Account & Lists',
            icon: Icons.arrow_drop_down,
          ),
        );
      },
    );
  }

  Widget _accountMenuText(String text, String value, {bool danger = false}) {
    return InkWell(
      onTap: () => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          text,
          style: TextStyle(
            color: danger ? Colors.red : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _notificationBell() {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) {
          return _HoverBox(
            onTap: _showLoginPopup,
            padding: const EdgeInsets.all(9),
            child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('notifications')
              .where('userId', isEqualTo: user.uid)
              .where('isRead', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;

            return PopupMenuButton<String>(
              offset: const Offset(-260, 48),
              color: Colors.white,
              onSelected: (value) {
                if (value == 'all') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsPage()),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: db
                              .collection('notifications')
                              .where('userId', isEqualTo: user.uid)
                              .snapshots(),
                          builder: (context, snap) {
                            final docs = [...(snap.data?.docs ?? [])];

                            docs.sort((a, b) {
                              final ta = a.data()['createdAt'];
                              final tb = b.data()['createdAt'];

                              if (ta is! Timestamp || tb is! Timestamp) return 0;

                              return tb.compareTo(ta);
                            });

                            final latestDocs = docs.take(5).toList();

                            if (docs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('No notifications'),
                              );
                            }

                            return Column(
                              children: latestDocs.map((doc) {
                                final d = doc.data();
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.notifications_active_rounded,
                                    color: d['isRead'] == true ? Colors.grey : primary,
                                  ),
                                  title: Text(
                                    _text(d['title'], 'Notification'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    _text(d['body']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const Divider(),
                        InkWell(
                          onTap: () => Navigator.pop(context, 'all'),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'View all notifications',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              child: _HoverBox(
                padding: const EdgeInsets.all(9),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    if (count > 0)
                      Positioned(
                        right: -7,
                        top: -7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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

  Widget _categoryNav() {
    return Container(
      height: GlobalWebHeader.categoryNavHeight,
      color: dark2,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _categoryStream(),
        builder: (context, snapshot) {
          final cats = snapshot.data ?? [];

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              PopupMenuButton<String>(
                offset: const Offset(0, 42),
                color: Colors.white,
                onSelected: _openCategory,
                itemBuilder: (_) {
                  if (cats.isEmpty) {
                    return const [
                      PopupMenuItem(
                        enabled: false,
                        value: '',
                        child: Text('No category'),
                      ),
                    ];
                  }

                  return cats.map((c) {
                    return PopupMenuItem(
                      value: _text(c['name']),
                      child: Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_text(c['name']))),
                        ],
                      ),
                    );
                  }).toList();
                },
                child: const _HoverBox(
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      Icon(Icons.menu_rounded, color: Colors.white, size: 25),
                      SizedBox(width: 6),
                      Text(
                        'All',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              ...cats.take(16).map((c) {
                final name = _text(c['name']);
                return _topMenuItem(name);
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _topMenuItem(String title, {VoidCallback? onTap}) {
    return _HoverBox(
      onTap: onTap ?? () => _openCategory(title),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Future<void> _handleAccountMenu(String value) async {
    if (value == 'account') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
    } else if (value == 'orders') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderPage()));
    } else if (value == 'lists') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyListsPage()));
    } else if (value == 'appointments') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAppointmentsPage()));
    } else if (value == 'referral') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralPage()));
    } else if (value == 'help') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterPage()));
    } else if (value == 'settings') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    } else if (value == 'seller') {
      await _openSellerAccount();
    } else if (value == 'delivery_partner') {
      await _openDeliveryPartner();
    } else if (value == 'admin') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    } else if (value == 'logout') {
      await _authService.signOut();
    }
  }

  Future<void> _openSellerAccount() async {
    final user = auth.currentUser;
    if (user == null) {
      _showLoginPopup();
      return;
    }

    try {
      await _authService.createOrGetUser();
      if (!mounted) return;

      final userDoc = await db.collection('users').doc(user.uid).get();
      if (!mounted) return;

      final userData = userDoc.data() ?? {};

      final userRole = _text(userData['role']);
      final adminRoles = List<String>.from(userData['roles'] ?? []);

      final isAdmin = userRole == 'admin' ||
          userRole == 'superAdmin' ||
          userRole == 'staff' ||
          adminRoles.contains('admin') ||
          adminRoles.contains('superAdmin') ||
          adminRoles.contains('staff');

      if (isAdmin) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
        return;
      }


      final sellerStatus = _text(userData['sellerStatus']);
      final roles = userData['roles'];

      final isVendorRole = userRole == 'vendor' ||
          (roles is List && roles.map((e) => e.toString()).contains('vendor'));

      if ((isVendorRole || sellerStatus == 'approved') &&
          sellerStatus != 'suspended' &&
          sellerStatus != 'rejected') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorDashboardPage()));
        return;
      }

      if (sellerStatus == 'pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your seller application is pending admin approval.')),
        );
        return;
      }

      if (sellerStatus == 'suspended') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your seller account is suspended. Please contact admin.')),
        );
        return;
      }

      if (sellerStatus == 'rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your seller application was rejected. You can apply again.')),
        );
      }

      Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorApplyPage()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seller account check failed: $e')),
      );
    }
  }

  Future<void> _openDeliveryPartner() async {
    final user = auth.currentUser;

    if (user == null) {
      _showLoginPopup();
      return;
    }

    try {
      await _authService.createOrGetUser();
      if (!mounted) return;

      final partnerDoc =
      await db.collection('deliveryPartners').doc(user.uid).get();

      if (!mounted) return;

      if (!partnerDoc.exists) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeliveryPartnerApplyPage(),
          ),
        );
        return;
      }

      final partnerData = partnerDoc.data() ?? {};
      final status = _text(partnerData['status'], 'pending');
      final isActive = partnerData['isActive'] == true;

      if (status == 'approved' && isActive) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeliveryPartnerDashboardPage(),
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DeliveryPartnerApplyPage(),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delivery partner status: ${status.toUpperCase()}. Admin approval required.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delivery partner check failed: $e')),
      );
    }
  }

}

class _HeaderTextButton extends StatelessWidget {
  final String small;
  final String bold;
  final IconData icon;

  const _HeaderTextButton({
    required this.small,
    required this.bold,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverBox(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            small,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bold,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoverBox extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final EdgeInsets padding;

  const _HoverBox({
    required this.child,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(vertical: 6),
    this.padding = const EdgeInsets.all(6),
  });

  @override
  State<_HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<_HoverBox> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: widget.margin,
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hovering ? Colors.white : Colors.transparent,
              width: 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
