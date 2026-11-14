import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/category_section.dart';
import 'profile/edit_profile_page.dart';
import '../../services/image_upload_service.dart';
import 'chalakchar_cash_wallet_page.dart';
import '../auth/login_page.dart';
import 'my_lists_page.dart';
import '../../widgets/global_web_header.dart';
import '../../widgets/global_web_footer.dart';
import '../../widgets/category_sidebar.dart';
import '../../widgets/home_category_grid.dart';
import '../../widgets/collection_banner_card.dart';
import 'profile/my_address_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'doctor_departments_page.dart';
import 'search_page.dart';
import '../../services/category_service.dart';
import '../../services/web_url_service.dart';
import '../../services/image_search_service.dart';



/// The main home page for the product shop, providing access to products,
/// lists, doctor consultations, and user profile management.
class ProductHomePage extends StatefulWidget {
  const ProductHomePage({super.key});

  @override
  State<ProductHomePage> createState() => _ProductHomePageState();
}

class _ProductHomePageState extends State<ProductHomePage> {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  String search = "";
  bool _isUploading = false;
  String? userName;

  /// Horizontal scroll of the home banner row (when there is more than one).
  final ScrollController _bannerScrollController = ScrollController();

  /// Distance between the starts of two banner cards; set during build.
  double _bannerStep = 0;
  final ScrollController _mobileScrollController = ScrollController();
  double _mobileScrollOffset = 0;
  Timer? _timer;
  int _currentPage = 0;
  OverlayEntry? overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();

    _mobileScrollController.addListener(() {
      if (!mounted || !_mobileScrollController.hasClients) return;

      final nextOffset = _mobileScrollController.offset
          .clamp(0.0, 46.0)
          .toDouble();

      if ((nextOffset - _mobileScrollOffset).abs() >= 10) {
        setState(() => _mobileScrollOffset = nextOffset);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  /// Loads current user information from Firestore.
  Future<void> _loadUserInfo() async {
    final user = auth.currentUser;
    if (user == null) {
      setState(() => userName = null);
      return;
    }

    final snap = await db.collection('users').doc(user.uid).get();
    if (mounted) {
      if (snap.exists) {
        setState(() => userName = snap.data()?['name']);
      } else {
        setState(() => userName = user.displayName ?? "User");
      }
    }
  }

  /// Displays an animation when an item is added to the cart.
  void runAddToCartAnimation(GlobalKey key) {
    if (key.currentContext == null) return;

    final renderBox = key.currentContext!.findRenderObject() as RenderBox;
    final startPosition = renderBox.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: startPosition.dx,
          top: startPosition.dy,
          child: TweenAnimationBuilder(
            tween: Tween<Offset>(
              begin: const Offset(0, 0),
              end: const Offset(200, -400),
            ),
            duration: const Duration(milliseconds: 800),
            builder: (context, Offset value, child) {
              double opacity = 1.0 - (value.dy.abs() / 400).clamp(0.0, 1.0);
              return Transform.translate(
                offset: value,
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              );
            },
            child: const Icon(Icons.shopping_bag, size: 40, color: Color(0xFF32A8C7)),
          ),
        );
      },
    );

    overlay.insert(overlayEntry!);

    Future.delayed(const Duration(milliseconds: 800), () {
      overlayEntry?.remove();
      overlayEntry = null;
    });
  }

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  /// Checks if the user's profile is complete (name, age, address, phone).
  Future<bool> _isProfileComplete() async {
    final user = auth.currentUser;
    if (user == null) return false;

    final doc = await db.collection("users").doc(user.uid).get();
    if (!doc.exists) return false;

    final data = doc.data();
    return _hasValue(data?['name']) &&
        _hasValue(data?['age']) &&
        _hasValue(data?['address']) &&
        _hasValue(data?['phone']);
  }

  /// Shows a dialog prompting the user to complete their profile.
  void _showProfileWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete Profile"),
        content: const Text("Please complete your profile to use this feature."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EditProfilePage()));
            },
            child: const Text("Go to Profile"),
          ),
        ],
      ),
    );
  }

  /// Starts the auto-scroll timer for the banner.
  void _startTimer(int count) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_currentPage < count - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      final controller = _bannerScrollController;
      if (controller.hasClients && _bannerStep > 0) {
        final target = (_currentPage * _bannerStep)
            .clamp(0.0, controller.position.maxScrollExtent);
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  /// Shows the login popup dialog.
  void _showLoginPopup() {
    final width = MediaQuery.of(context).size.width;
    final isDesktopWeb = kIsWeb && width >= 1024;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => LoginPage(
        isPopup: isDesktopWeb,
      ),
    );
  }

  /// Ensures the user is logged in before proceeding with an action.
  bool _ensureLoggedIn() {
    if (auth.currentUser == null) {
      _showLoginPopup();
      return false;
    }
    return true;
  }

  /// Shows the bottom sheet to select image source for list upload.
  void _showImageSourcePicker() async {
    if (!_ensureLoggedIn()) return;

    bool complete = await _isProfileComplete();
    if (!complete) {
      if (mounted) _showProfileWarning();
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  /// top handle
                  Container(
                    width: 55,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    "Select List Source",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Upload your shopping list easily",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    children: [

                      Expanded(
                        child: _modernSourceButton(
                          icon: Icons.camera_alt_rounded,
                          label: "Camera",
                          color: const Color(0xFF32A8C7),
                          onTap: () {
                            Navigator.pop(context);
                            _uploadList(ImageSource.camera);
                          },
                        ),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: _modernSourceButton(
                          icon: Icons.photo_library_rounded,
                          label: "Gallery",
                          color: Colors.orange,
                          onTap: () {
                            Navigator.pop(context);
                            _uploadList(ImageSource.gallery);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _modernSourceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          children: [

            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 34,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// Handles the list upload process.
  Future<void> _uploadList(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = auth.currentUser;

      if (user == null) {
        _showLoginPopup();
        return;
      }

      String imageUrl = "";

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        imageUrl = await ImageUploadService.upload(
          null,
          webImage: bytes,
          folder: 'lists/${user.uid}',
        );
      } else {
        imageUrl = await ImageUploadService.upload(
          File(image.path),
          folder: 'lists/${user.uid}',
        );
      }

      if (imageUrl.isNotEmpty) {
        await db.collection('lists').add({
          'userId': user.uid,
          'userEmail': user.email,
          'imageUrl': imageUrl,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("List uploaded successfully!")),
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyListsPage()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Opens an external URL.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open link")),
        );
      }
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

  void _openCategorySeo(String categoryName) {
    final name = categoryName.trim();
    if (name.isEmpty) return;

    final path = '/category/${_categorySlug(name)}';
    WebUrlService.push(path);
    Navigator.of(context, rootNavigator: true).pushNamed(path);
  }

  void _openSearch([String query = '']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(initialQuery: query.trim()),
      ),
    );
  }

  Future<void> _pickAndSearchByImage() async {
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

    setState(() => _isUploading = true);

    try {
      final result = await ImageSearchService.searchByImage(picked);
      if (!mounted) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ছবি সার্চ ব্যর্থ হয়েছে: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openProductById(String productId) async {
    final id = productId.trim();
    if (id.isEmpty) return;

    final path = '/product/$id';
    WebUrlService.push(path);
    Navigator.of(context, rootNavigator: true).pushNamed(path);
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktopWeb = kIsWeb && width >= 1024;
    const Color primaryColor = Color(0xFF32A8C7);

    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ Desktop web only: GlobalWebHeader.
      // ✅ Mobile app / mobile web: no AppBar/header.
      // Search bar is fixed inside _buildMobileLayout(), like Amazon mobile app.
      appBar: isDesktopWeb ? const GlobalWebHeader() : null,

      // Mobile web drawer only if needed. Mobile app has no drawer/header.
      drawer: null,

      body: Stack(
        children: [
          if (isDesktopWeb)
            _buildWebLayout(primaryColor)
          else
            _buildMobileLayout(primaryColor),

          if (isDesktopWeb)
            Positioned(
              right: 18,
              bottom: 22,
              child: Column(
                children: [
                  _floatingChatButton(
                    icon: Icons.message,
                    label: "WhatsApp",
                    color: Colors.green,
                    onTap: () {
                      _openUrl(
                        "https://wa.me/8801975838764?text=Assalamu%20Alaikum%2C%20ChalakChar%20Mart",
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _floatingChatButton(
                    icon: Icons.facebook,
                    label: "Messenger",
                    color: Colors.blue,
                    onTap: () {
                      _openUrl("https://m.me/parvaz.newfab");
                    },
                  ),
                ],
              ),
            ),

          if (_isUploading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _floatingChatButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () async {
        FocusScope.of(context).unfocus();
        await Future.delayed(const Duration(milliseconds: 80));

        if (context.mounted) {
          onTap();
        }
      },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the layout for desktop/web screens.
  Widget _buildWebLayout(Color color) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FBFB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🔴 LEFT CATEGORY (FIXED)
          if (screenWidth >= 1024)
            Container(
              width: 260,
              height: MediaQuery.of(context).size.height,
              padding: const EdgeInsets.fromLTRB(40, 30, 0, 30),
              child: _buildWebCategoryBox(),
            ),

          /// 👉 RIGHT SIDE SCROLL
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 40, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDynamicBanner(),
                    const SizedBox(height: 30),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Product Categories",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        TextButton(
                          onPressed: () => _openSearch(),
                          child: const Text(
                            "See All",
                            style: TextStyle(
                                color: Color(0xFF32A8C7),
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    StreamBuilder<List<CategoryModel>>(
                      stream: CategoryService.watchHomeCategories(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox();
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Category error: ${snapshot.error}',
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          );
                        }

                        final categories = snapshot.data ?? const <CategoryModel>[];
                        if (categories.isEmpty) return const SizedBox();

                        return HomeCategoryGrid(
                          categories: categories,
                          onTap: (category) => _openCategorySeo(category.name),
                        );
                      },
                    ),

                    const SizedBox(height: 40),
                    _buildWebPrefixSection(),
                    const SizedBox(height: 40),

                    StreamBuilder<List<CategoryModel>>(
                      stream: CategoryService.watchHomeCategories(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox();
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Category error: ${snapshot.error}',
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          );
                        }

                        final categories = snapshot.data ?? const <CategoryModel>[];
                        if (categories.isEmpty) return const SizedBox();

                        return Column(
                          children: categories.map((category) {
                            if (category.name.isEmpty) return const SizedBox.shrink();

                            return CategorySection(
                              title: category.name,
                              onAddToCart: runAddToCartAnimation,
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 50),
                    const GlobalWebFooter(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the list and consultation section for web.
  Widget _buildWebPrefixSection() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: const Color(0xFF32A8C7).withValues(alpha: 0.15),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _webActionCard(
                  icon: Icons.upload_file,
                  title: "Order with List",
                  subtitle: "Upload your list and get products delivered quickly.",
                  buttonText: "Upload List",
                  onTap: _showImageSourcePicker,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: _webActionCard(
                  icon: Icons.medical_services,
                  title: "Consult Doctor",
                  subtitle: "Book appointment with experienced doctors easily.",
                  buttonText: "Book Appointment",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DoctorDepartmentsPage()),
                    );
                  },
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: _webActionCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: "ChalakChar Cash",
                  subtitle: "Check rewards, referral code, cash balance, and cash history.",
                  buttonText: "View Wallet",
                  onTap: () async {
                    if (_ensureLoggedIn()) {
                      final complete = await _isProfileComplete();
                      if (complete) {
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ChalakCharCashWalletPage(),
                            ),
                          );
                        }
                      } else {
                        if (mounted) _showProfileWarning();
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    Future<void> handleTap() async {
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 80));

      if (context.mounted) {
        onTap();
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: handleTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF32A8C7).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF32A8C7).withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF32A8C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF32A8C7), size: 42),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: handleTap,
                        icon: Icon(
                          buttonText.contains("Upload")
                              ? Icons.cloud_upload_outlined
                              : Icons.calendar_month,
                          size: 18,
                        ),
                        label: Text(
                          buttonText,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF32A8C7),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
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


  /// Builds Amazon-style home layout for mobile app / mobile web only.
  /// ✅ Desired behavior:
  /// 1) Search bar stays fixed at the top.
  /// 2) Delivery location starts under search, then scrolls away/gets hidden.
  /// 3) Category strip moves up and becomes sticky just under the search bar.
  /// 4) Banner is the first real scrolling content after the sticky category strip.
  Widget _buildMobileLayout(Color color) {
    final media = MediaQuery.of(context);
    final double safeTop = media.padding.top;

    const double searchHeight = 44;
    const double deliveryHeight = 42;
    const double categoryStripHeight = 92;

    final double searchTopPadding = kIsWeb ? 2 : 8;
    const double searchBottomPadding = 2;

    final double deliveryTopPadding = kIsWeb ? 0 : 2;
    const double deliveryBottomPadding = 2;

    final double searchBlockHeight =
        safeTop + searchTopPadding + searchHeight + searchBottomPadding;

    final double deliveryBlockHeight =
        deliveryTopPadding + deliveryHeight + deliveryBottomPadding;

    /// Category initial position:
    /// - At page top: under delivery location.
    /// - While scrolling: it moves upward.
    /// - After delivery is hidden: it sticks directly under search bar.
    final double categoryTop =
        searchBlockHeight +
            (deliveryBlockHeight - _mobileScrollOffset)
                .clamp(0.0, deliveryBlockHeight);

    return Container(
      color: const Color(0xFFEAEDED),
      child: Stack(
        children: [
          /// ✅ Real page scroll:
          /// Search is fixed above this scroll area.
          /// Delivery is scrollable and will disappear behind the fixed search bar.
          /// Category's place is reserved here, but the visible category is pinned overlay.
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _mobileScrollController,
              padding: EdgeInsets.only(
                top: searchBlockHeight,
                bottom: 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      deliveryTopPadding,
                      10,
                      deliveryBottomPadding,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFE9C6F5),
                          Color(0xFFDDB7F0),
                          Color(0xFFF1D7F7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: _buildDeliveryLocationBar(),
                  ),

                  /// Placeholder for the sticky category strip.
                  /// The actual category strip is drawn in the fixed overlay below.
                  const SizedBox(height: categoryStripHeight),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                    child: _buildDynamicBanner(),
                  ),
                  const SizedBox(height: 10),
                  _buildMobileQuickActions(color),
                  const SizedBox(height: 10),
                  _buildWelcomeDealsCard(),
                  const SizedBox(height: 10),
                  _buildMobileCategorySections(),
                ],
              ),
            ),
          ),

          /// ✅ Fixed search bar only.
          /// It stays above everything and hides the delivery location while scrolling.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE9C6F5),
                    Color(0xFFDDB7F0),
                    Color(0xFFF1D7F7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    searchTopPadding,
                    10,
                    searchBottomPadding,
                  ),
                  child: _buildStickyMobileSearchBar(),
                ),
              ),
            ),
          ),

          /// ✅ Sticky category strip.
          /// It starts below delivery location, then sticks under search bar.
          Positioned(
            top: categoryTop,
            left: 0,
            right: 0,
            child: Material(
              elevation: _mobileScrollOffset > 1 ? 4 : 0,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: _buildMobileCategoryStrip(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyMobileSearchBar() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSearch(search),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: Colors.black87, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  search.trim().isEmpty ? "Search ChalakChar Mart" : search.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
              ),
              IconButton(
                tooltip: "ছবি দিয়ে খুঁজুন",
                onPressed: _pickAndSearchByImage,
                icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFFFF9900), size: 21),
              ),
              IconButton(
                tooltip: "Search",
                onPressed: () => _openSearch(search),
                icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black87, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryLocationBar() {
    final user = auth.currentUser;

    if (user == null) {
      return Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: _showLoginPopup,
          borderRadius: BorderRadius.circular(22),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, size: 20, color: Colors.black87),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Delivering to your door - Update location",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.black87),
              ],
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection("users").doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        String locationText = "your door - Update location";

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;

          final upazila = data["upazila"]?.toString().trim() ?? "";
          final district = data["district"]?.toString().trim() ?? "";
          final division = data["division"]?.toString().trim() ?? "";
          final address = data["address"]?.toString().trim() ?? "";

          final areaParts = [upazila, district, division]
              .where((e) => e.isNotEmpty)
              .toList();

          if (areaParts.isNotEmpty) {
            locationText = areaParts.join(", ");
          } else if (address.isNotEmpty) {
            locationText = address;
          }
        }

        return Container(
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyAddressPage()),
              );
              if (mounted) _loadUserInfo();
            },
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 20, color: Colors.black87),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Delivering to $locationText",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.black87),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileCategoryStrip() {
    return Container(
      height: 92,
      color: Colors.white,
      child: StreamBuilder<List<CategoryModel>>(
        stream: CategoryService.watchHomeCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Category error: ${snapshot.error}',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            );
          }

          final categories = snapshot.data ?? const <CategoryModel>[];
          if (categories.isEmpty) return const SizedBox.shrink();

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              if (category.name.isEmpty) return const SizedBox.shrink();

              return InkWell(
                onTap: () {
                  _openCategorySeo(category.name);
                },
                child: SizedBox(
                  width: 76,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 46,
                        width: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: category.imageUrl.isNotEmpty
                            ? Image.network(
                          category.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.category, color: Colors.grey),
                        )
                            : const Icon(Icons.category, color: Colors.grey),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMobileQuickActions(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: _amazonActionTile(
              title: "Order with\nList",
              icon: Icons.upload_file,
              color: color,
              onTap: _showImageSourcePicker,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _amazonActionTile(
              title: "Consult\nDoctor",
              icon: Icons.medical_services_outlined,
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DoctorDepartmentsPage()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _amazonActionTile(
              title: "ChalakChar Mart Cash\n& Rewards",
              icon: Icons.verified_outlined,
              color: Colors.orange,
              onTap: () async {
                if (_ensureLoggedIn()) {
                  final complete = await _isProfileComplete();
                  if (complete) {
                    if (mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ChalakCharCashWalletPage()));
                    }
                  } else {
                    if (mounted) _showProfileWarning();
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _amazonActionTile({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeDealsCard() {
    final bool loggedIn = auth.currentUser != null;

    if (loggedIn) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE4C9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your welcome deals await!",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Login to unlock your welcome deals",
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _showLoginPopup,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text(
                      "Login / Sign Up",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9900),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 100,
            width: 95,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(
              Icons.inventory_2,
              size: 58,
              color: Color(0xFFFF9900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCategorySections() {
    return StreamBuilder<List<CategoryModel>>(
      stream: CategoryService.watchHomeCategories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Category error: ${snapshot.error}',
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          );
        }

        final categories = snapshot.data ?? const <CategoryModel>[];
        if (categories.isEmpty) return const SizedBox.shrink();

        final visibleCategories = categories
            .where((category) => category.name.isNotEmpty)
            .take(kIsWeb ? 4 : categories.length)
            .toList();

        return Column(
          children: visibleCategories.map((category) {
            if (category.name.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: CategorySection(
                title: category.name,
                onAddToCart: runAddToCartAnimation,
                limit: kIsWeb ? 6 : 10,
              ),
            );
          }).toList(),
        );
      },
    );
  }


  /// Builds the dynamic home banner system.
  /// Supports:
  /// normal, amazon_grid, hero_deal, vendor_spotlight, category_tiles.
  /// Compatible with old banner docs too.
  Widget _buildDynamicBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final bool isDesktop =
            kIsWeb && MediaQuery.of(context).size.width >= 1024;
        final double bannerHeight = isDesktop ? 320.0 : 392.0;

        if (snap.connectionState == ConnectionState.waiting) {
          return _bannerSkeleton(bannerHeight, isDesktop: isDesktop);
        }

        if (snap.hasError) {
          return _buildFallbackBanner(bannerHeight, isDesktop: isDesktop);
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _buildFallbackBanner(bannerHeight, isDesktop: isDesktop);
        }

        final now = DateTime.now();

        final banners = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // Optional start/end schedule support from admin.
          final startAt = _toDateTime(data['startAt']);
          final endAt = _toDateTime(data['endAt']);
          if (startAt != null && now.isBefore(startAt)) return false;
          if (endAt != null && now.isAfter(endAt)) return false;

          final layoutType = data['layoutType']?.toString() ?? 'normal';

          if (layoutType == 'amazon_grid') {
            return CollectionBannerItem.listFrom(data['items']).isNotEmpty;
          }

          if (layoutType == 'category_tiles' ||
              layoutType == 'vendor_spotlight') {
            final items = data['items'];
            return items is List && items.isNotEmpty;
          }

          return _bannerImageUrl(data, isDesktop: isDesktop).isNotEmpty;
        }).toList();

        banners.sort((a, b) {
          final ad = a.data() as Map<String, dynamic>;
          final bd = b.data() as Map<String, dynamic>;
          final ap = _asInt(ad['priority'], fallback: 0);
          final bp = _asInt(bd['priority'], fallback: 0);
          if (ap != bp) return bp.compareTo(ap);
          final at = _toDateTime(ad['createdAt']) ?? DateTime(2000);
          final bt = _toDateTime(bd['createdAt']) ?? DateTime(2000);
          return bt.compareTo(at);
        });

        if (banners.isEmpty) {
          return _buildFallbackBanner(bannerHeight, isDesktop: isDesktop);
        }

        if (_timer == null && banners.length > 1) {
          _startTimer(banners.length);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final double available = constraints.maxWidth;
            // One card: full width. Several: each card is a share of the
            // width so the next card peeks in from the right.
            final bool single = banners.length == 1;
            final double cardWidth =
                single ? available : available * _multiBannerWidthFraction;
            final double gap = isDesktop ? 12 : 8;
            _bannerStep = cardWidth + gap;

            Widget card(Map<String, dynamic> data) => _buildBannerCard(
                  data: data,
                  width: cardWidth,
                  height: bannerHeight,
                  isDesktop: isDesktop,
                );

            if (single) {
              return card(banners.first.data() as Map<String, dynamic>);
            }

            return SingleChildScrollView(
              controller: _bannerScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < banners.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    card(banners[i].data() as Map<String, dynamic>),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Share of the available width one banner card takes when there are
  /// several, leaving part of the next card visible.
  static const double _multiBannerWidthFraction = 0.85;

  /// One banner card at [width]. The collection (amazon_grid) card sizes its
  /// own height from its content; the other types keep [height].
  Widget _buildBannerCard({
    required Map<String, dynamic> data,
    required double width,
    required double height,
    required bool isDesktop,
  }) {
    final layoutType = data['layoutType']?.toString() ?? 'normal';
    if (layoutType == 'amazon_grid') {
      return CollectionBannerCard(
        title: data['title']?.toString().trim() ?? '',
        subtitle: data['subtitle']?.toString().trim() ?? '',
        items: CollectionBannerItem.listFrom(data['items']),
        width: width,
        isDesktop: isDesktop,
        onHeaderTap: () => _handleBannerTap(data),
        onItemTap: (item) => _handleCollectionItemTap(item, data),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 13),
        child: _clickableBanner(
          data: data,
          child: _buildBannerByType(
            data: data,
            height: height,
            isDesktop: isDesktop,
          ),
        ),
      ),
    );
  }

  /// Opens a collection banner item's own page (product, subcategory, ...);
  /// items without their own target fall back to the banner's action.
  Future<void> _handleCollectionItemTap(
    CollectionBannerItem item,
    Map<String, dynamic> banner,
  ) async {
    final value = item.actionValue;
    switch (item.actionType) {
      case 'product':
        if (value.isNotEmpty) return _openProductById(value);
        break;
      case 'subcategory':
        final categoryName = item.categoryName.isNotEmpty
            ? item.categoryName
            : banner['categoryName']?.toString().trim() ?? '';
        if (value.isNotEmpty && categoryName.isNotEmpty) {
          final path = '/category/${_categorySlug(categoryName)}'
              '?sub=${Uri.encodeQueryComponent(value)}';
          WebUrlService.push(path);
          Navigator.of(context, rootNavigator: true).pushNamed(path);
          return;
        }
        break;
      case 'category':
        // Older items store a category id here; only a name is navigable.
        if (item.categoryName.isNotEmpty) {
          return _openCategorySeo(item.categoryName);
        }
        break;
      case 'url':
        if (value.startsWith('http://') || value.startsWith('https://')) {
          return _openUrl(value);
        }
        break;
      case 'search':
        if (value.isNotEmpty) return _openSearch(value);
        break;
      case 'none':
        return;
    }
    return _handleBannerTap(banner);
  }

  Widget _clickableBanner({
    required Map<String, dynamic> data,
    required Widget child,
  }) {
    return InkWell(
      onTap: () => _handleBannerTap(data),
      child: child,
    );
  }

  Future<void> _handleBannerTap(Map<String, dynamic> data) async {
    // The admin form writes clickActionType/clickValue; older docs used
    // actionType/actionValue. The new fields win, the old ones are fallback.
    final clickType =
        data['clickActionType']?.toString().trim().toLowerCase() ?? '';
    final usesClickFields = clickType.isNotEmpty;
    final actionType = usesClickFields
        ? clickType
        : data['actionType']?.toString().trim().toLowerCase() ?? '';
    final actionValue = usesClickFields
        ? data['clickValue']?.toString().trim() ?? ''
        : data['actionValue']?.toString().trim() ?? '';
    if (actionType == 'none') return;
    final categoryName = data['categoryName']?.toString().trim() ?? '';
    final productId = data['productId']?.toString().trim() ?? '';
    final searchQuery = data['searchQuery']?.toString().trim() ?? '';
    final vendorName = data['vendorName']?.toString().trim() ?? '';
    final url = data['urlLink']?.toString().trim() ??
        data['externalUrl']?.toString().trim() ??
        '';

    if ((actionType == 'url' || actionType == 'external') && actionValue.isNotEmpty) {
      await _openUrl(actionValue);
      return;
    }

    if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
      await _openUrl(url);
      return;
    }

    if (actionType == 'product' && actionValue.isNotEmpty) {
      await _openProductById(actionValue);
      return;
    }

    if (productId.isNotEmpty) {
      await _openProductById(productId);
      return;
    }

    if (actionType == 'search' && actionValue.isNotEmpty) {
      _openSearch(actionValue);
      return;
    }

    if (searchQuery.isNotEmpty) {
      _openSearch(searchQuery);
      return;
    }

    if (actionType == 'vendor' && actionValue.isNotEmpty) {
      _openSearch(actionValue);
      return;
    }

    if (vendorName.isNotEmpty) {
      _openSearch(vendorName);
      return;
    }

    if ((actionType == 'category' && actionValue.isNotEmpty) ||
        categoryName.isNotEmpty) {
      // clickValue holds a category id (not routable), so the admin form's
      // banners open by categoryName; old actionValue was already a name.
      _openCategorySeo(
        usesClickFields || actionValue.isEmpty ? categoryName : actionValue,
      );
      return;
    }
  }

  Widget _buildBannerByType({
    required Map<String, dynamic> data,
    required double height,
    required bool isDesktop,
  }) {
    final layoutType = data['layoutType']?.toString() ?? 'normal';

    if (layoutType == 'hero_deal') {
      return _buildHeroDealBanner(
        data: data,
        height: height,
        isDesktop: isDesktop,
      );
    }

    if (layoutType == 'category_tiles') {
      return _buildCategoryTilesBanner(
        data: data,
        height: height,
        isDesktop: isDesktop,
      );
    }

    if (layoutType == 'vendor_spotlight') {
      return _buildVendorSpotlightBanner(
        data: data,
        height: height,
        isDesktop: isDesktop,
      );
    }

    final url = _bannerImageUrl(data, isDesktop: isDesktop);

    if (url.isEmpty) return _buildBannerError(height);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => _buildBannerError(height),
        ),
        if ((data['title']?.toString().trim() ?? '').isNotEmpty)
          Positioned(
            left: isDesktop ? 30 : 18,
            bottom: isDesktop ? 30 : 22,
            right: isDesktop ? 30 : 18,
            child: _bannerTextOverlay(data, isDesktop: isDesktop),
          ),
      ],
    );
  }

  String _bannerImageUrl(Map<String, dynamic> data, {required bool isDesktop}) {
    final desktopUrl = data['desktopUrl']?.toString().trim() ?? '';
    final mobileUrl = data['mobileUrl']?.toString().trim() ?? '';
    final commonUrl = data['url']?.toString().trim() ?? '';
    if (isDesktop && desktopUrl.isNotEmpty) return desktopUrl;
    if (!isDesktop && mobileUrl.isNotEmpty) return mobileUrl;
    return commonUrl.isNotEmpty ? commonUrl : (isDesktop ? mobileUrl : desktopUrl);
  }

  Widget _bannerTextOverlay(Map<String, dynamic> data, {required bool isDesktop}) {
    final title = data['title']?.toString().trim() ?? '';
    final subtitle = data['subtitle']?.toString().trim() ?? '';
    final badge = data['badge']?.toString().trim() ?? '';

    return Container(
      constraints: BoxConstraints(maxWidth: isDesktop ? 520 : 260),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9900),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: isDesktop ? 28 : 20,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: isDesktop ? 15 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroDealBanner({
    required Map<String, dynamic> data,
    required double height,
    required bool isDesktop,
  }) {
    final title = data['title']?.toString().trim() ?? 'Mega deals';
    final subtitle = data['subtitle']?.toString().trim() ?? 'Best offers for you';
    final badge = data['badge']?.toString().trim() ?? 'TODAY';
    final url = _bannerImageUrl(data, isDesktop: isDesktop);

    return Container(
      height: height,
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: isDesktop ? 5 : 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9900),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isDesktop ? 34 : 25,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: isDesktop ? 16 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Shop now',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: isDesktop ? 4 : 5,
            child: url.isNotEmpty
                ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                height: double.infinity,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_offer,
                  color: Colors.white,
                  size: 80,
                ),
              ),
            )
                : const Icon(Icons.local_offer, color: Colors.white, size: 90),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTilesBanner({
    required Map<String, dynamic> data,
    required double height,
    required bool isDesktop,
  }) {
    final title = data['title']?.toString().trim() ?? 'Shop by category';
    final rawItems = data['items'];

    final List<Map<String, dynamic>> items = rawItems is List
        ? rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['imageUrl']?.toString().trim() ?? '').isNotEmpty)
        .take(isDesktop ? 6 : 4)
        .toList()
        : <Map<String, dynamic>>[];

    return Container(
      height: height,
      padding: EdgeInsets.all(isDesktop ? 18 : 12),
      color: const Color(0xFFFFFBEB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isDesktop ? 3 : 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isDesktop ? 2.0 : 1.15,
              ),
              itemBuilder: (_, index) {
                final item = items[index];
                return _promoTile(
                  imageUrl: item['imageUrl']?.toString().trim() ?? '',
                  title: item['title']?.toString().trim() ?? 'Category',
                  dense: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorSpotlightBanner({
    required Map<String, dynamic> data,
    required double height,
    required bool isDesktop,
  }) {
    final title = data['title']?.toString().trim() ?? 'Top vendors';
    final subtitle = data['subtitle']?.toString().trim() ?? 'Trusted sellers near you';
    final rawItems = data['items'];

    final List<Map<String, dynamic>> items = rawItems is List
        ? rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['imageUrl']?.toString().trim() ?? '').isNotEmpty)
        .take(isDesktop ? 5 : 4)
        .toList()
        : <Map<String, dynamic>>[];

    return Container(
      height: height,
      padding: EdgeInsets.all(isDesktop ? 20 : 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFECFEFF), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: isDesktop ? 25 : 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF0E7490), fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final item = items[index];
                return SizedBox(
                  width: isDesktop ? 190 : 135,
                  child: _promoTile(
                    imageUrl: item['imageUrl']?.toString().trim() ?? '',
                    title: item['title']?.toString().trim() ?? 'Vendor',
                    dense: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _promoTile({
    required String imageUrl,
    required String title,
    required bool dense,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Image.network(
              imageUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 6 : 9,
              vertical: dense ? 5 : 8,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 11 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerSkeleton(double height, {required bool isDesktop}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 13),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Widget _buildFallbackBanner(double height, {required bool isDesktop}) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 13),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFE4C9), Color(0xFFFFC881)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Welcome to ChalakChar Mart",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerError(double height) {
    return Container(
      height: height,
      color: const Color(0xFFFFE4C9),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 42),
      ),
    );
  }


  /// Builds the category box for the web version.
  Widget _buildWebCategoryBox() {
    return SizedBox(
      height: MediaQuery.of(context).size.height - 140,
      child: const CategorySidebar(),
    );
  }
}
