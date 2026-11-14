import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'providers/settings_provider.dart';
import 'services/notification_service.dart';

import 'pages/main_navigation_page.dart';
import 'pages/user/settings_details_pages.dart';
import 'pages/user/data_deletion_page.dart';
import 'pages/user/delivery/delivery_partner_dashboard_page.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'pages/admin/admin_dashboard_page.dart';
import 'pages/admin/admin_edit_order_page.dart';
import 'pages/admin/admin_notifications_page.dart';
import 'pages/admin/admin_lists_page.dart';
import 'pages/user/product_seo_loader_page.dart';
import 'pages/user/category_products_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/user/cart_page.dart';
import 'services/seo_route_observer.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // Only what the first frame truly needs is awaited here. Notification
  // permission and FCM must never be: a browser prompt the visitor ignores
  // used to keep the page blank forever.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
  } catch (e, stack) {
    developer.log(
      'Initialization Error',
      error: e,
      stackTrace: stack,
      name: 'main.dart',
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initMessagingAfterFirstFrame();
  });
}

// Runs after the first frame and is never awaited, so nothing here can delay
// or block rendering. Every failure (unsupported browser, Firebase not
// initialized, network) is logged and ignored.
Future<void> _initMessagingAfterFirstFrame() async {
  try {
    await NotificationService.init();

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleMessage(initialMessage);
  } catch (e, stack) {
    developer.log(
      'Messaging init skipped',
      error: e,
      stackTrace: stack,
      name: 'main.dart',
    );
  }
}

void _handleMessage(RemoteMessage message) {
  final data = message.data;
  final type = (data['type'] ?? '').toString();
  final orderId = data['orderId']?.toString();
  final listId = data['listId']?.toString();

  if (orderId != null && orderId.isNotEmpty) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AdminEditOrderPage(orderId: orderId),
      ),
    );
    return;
  }

  if (type.contains('list') || (listId != null && listId.isNotEmpty)) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const AdminListsPage(),
      ),
    );
    return;
  }

  if (type.contains('admin') || type.contains('notification')) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const AdminNotificationsPage(),
      ),
    );
    return;
  }

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => const MainNavigation(role: 'user'),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> checkFirstSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('seenOnboard') ?? false;
  }

  Future<void> _saveTokenSafely(User user) async {
    try {
      await NotificationService.saveToken(user.uid);
    } catch (e, stack) {
      developer.log(
        'FCM token save failed',
        error: e,
        stackTrace: stack,
        name: 'main.dart',
      );
    }
  }

  bool _canAccessAdmin(Map<String, dynamic> data) {
    final role = (data['role'] ?? 'user').toString();
    final roles = data['roles'] is List
        ? List<String>.from((data['roles'] as List).map((e) => e.toString()))
        : <String>[];

    final active = data['isActive'] != false;
    final banned = data['isBanned'] == true;

    if (!active || banned) return false;

    return role == 'admin' ||
        role == 'superAdmin' ||
        roles.contains('admin') ||
        roles.contains('superAdmin');
  }

  bool _canAccessDeliveryPartner(Map<String, dynamic>? userData, Map<String, dynamic>? partnerData) {
    final data = userData ?? <String, dynamic>{};
    final role = (data['role'] ?? 'user').toString();
    final roles = data['roles'] is List
        ? List<String>.from((data['roles'] as List).map((e) => e.toString()))
        : <String>[];

    final userActive = data['isActive'] != false;
    final banned = data['isBanned'] == true;
    if (!userActive || banned) return false;

    final roleAllowed = role == 'deliveryPartner' || roles.contains('deliveryPartner');
    final partnerApproved = partnerData != null &&
        (partnerData['status'] ?? '').toString() == 'approved' &&
        partnerData['isActive'] != false;

    return roleAllowed || partnerApproved;
  }

  Widget _loadingScreen([String text = 'Loading ChalakChar Mart...']) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 78,
              width: 78,
              decoration: BoxDecoration(
                color: const Color(0xFF32A8C7).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.business_rounded,
                color: Color(0xFF1592B3),
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            const CircularProgressIndicator(
              color: Color(0xFF32A8C7),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _safeUserHome() {
    return const MainNavigation(role: 'user');
  }

  Widget _homePage() {
    return FutureBuilder<bool>(
      future: checkFirstSeen(),
      builder: (context, seenSnap) {
        if (seenSnap.connectionState == ConnectionState.waiting) {
          return _loadingScreen();
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnap) {
            if (authSnap.connectionState == ConnectionState.waiting) {
              return _loadingScreen('Checking login...');
            }

            final user = authSnap.data;

            if (user == null) {
              return _safeUserHome();
            }

            Future.microtask(() => _saveTokenSafely(user));

            return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
              future: Future.wait([
                FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
                FirebaseFirestore.instance.collection('deliveryPartners').doc(user.uid).get(),
              ]),
              builder: (context, roleSnap) {
                if (roleSnap.connectionState == ConnectionState.waiting) {
                  return _loadingScreen('Checking permissions...');
                }

                if (roleSnap.hasError) {
                  developer.log(
                    'Role loading failed',
                    error: roleSnap.error,
                    name: 'main.dart',
                  );
                  return _safeUserHome();
                }

                final userData = roleSnap.data?[0].data() ?? <String, dynamic>{};
                final partnerData = roleSnap.data?[1].data();

                if (_canAccessAdmin(userData)) {
                  return const AdminDashboard();
                }

                if (_canAccessDeliveryPartner(userData, partnerData)) {
                  return const DeliveryPartnerDashboardPage();
                }

                final role = (userData['role'] ?? 'user').toString();

                final roles = userData['roles'] is List
                    ? List<String>.from(
                  (userData['roles'] as List).map((e) => e.toString()),
                )
                    : <String>[];

                final sellerStatus = (userData['sellerStatus'] ?? '').toString();

                final isVendor = role == 'vendor' || roles.contains('vendor');

                if (isVendor && sellerStatus == 'approved') {
                  return const MainNavigation(role: 'vendor');
                }

                return MainNavigation(role: role);
              },
            );
          },
        );
      },
    );
  }

  /// Bundled fallback holding the Taka sign (see pubspec `fonts:`), so
  /// prices never show a blank box while web fallback fonts download.
  static const List<String> _fontFallback = ['TakaFallback'];

  ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: _fontFallback,
      colorSchemeSeed: const Color(0xFF32A8C7),
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF32A8C7),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: _fontFallback,
      colorSchemeSeed: const Color(0xFF32A8C7),
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [SeoRouteObserver()],
      debugShowCheckedModeBanner: false,
      title: 'ChalakChar Mart',
      routes: {
        '/': (context) => _homePage(),
        '/about-us': (context) => const AboutUsPage(),
        '/permissions': (context) => const PermissionsPage(),
        '/privacy-policy': (context) => const PrivacyPolicyPage(),
        '/terms-conditions': (context) => const TermsConditionsPage(),
        '/return-policy': (context) => const ReturnPolicyPage(),
        '/data-deletion': (context) => const DataDeletionPage(),
        '/admin': (context) => const AdminDashboard(),
        '/admin/notifications': (context) => const AdminNotificationsPage(),
        '/admin/lists': (context) => const AdminListsPage(),
        '/login': (context) => const Scaffold(body: LoginPage()),
        '/cart': (context) => const CartPage(),
      },
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        if (uri.pathSegments.length == 2 &&
            uri.pathSegments.first == 'product') {

          final productId = uri.pathSegments[1];

          return MaterialPageRoute(
            builder: (_) => ProductSeoLoaderPage(
              productId: productId,
            ),
          );
        }

        if (uri.pathSegments.length == 2 &&
            uri.pathSegments.first == 'category') {
          final categorySlug = Uri.decodeComponent(uri.pathSegments[1]);

          return MaterialPageRoute(
            builder: (_) => CategoryProductsPage(
              category: categorySlug,
              initialSub: uri.queryParameters['sub'],
            ),
          );
        }

        return null;
      },


      themeMode: settings.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
    );
  }
}
