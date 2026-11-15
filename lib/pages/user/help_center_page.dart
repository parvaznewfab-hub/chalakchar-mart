import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/app_settings_service.dart';
import '../../widgets/health_gate.dart';
import '../../utils/contact_info.dart';

class HelpCenterPage extends StatefulWidget {
  final bool scrollToFaq;

  const HelpCenterPage({
    super.key,
    this.scrollToFaq = false,
  });

  // 👉 এই ২টা line MUST add
  static const String supportPhone = '01975838764';
  static const String whatsappNumber = '8801975838764';

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final GlobalKey faqKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    if (widget.scrollToFaq) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = faqKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }


  Future<void> _openYoutube() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();

      final youtubeUrl =
          doc.data()?['helpYoutubeLink'] ?? '';

      if (youtubeUrl.toString().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Video link not set"),
            ),
          );
        }
        return;
      }

      final Uri youtubeUri =
      Uri.parse(youtubeUrl);

      if (!await launchUrl(
        youtubeUri,
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open YouTube');
      }
    } catch (e) {
      debugPrint("Youtube Error: $e");
    }
  }

  static const String mapUrl =
      'https://maps.app.goo.gl/wM8fTS7vf5LHs8Bm9';

  Future<void> _callSupport() async {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: AppSettingsService.cached.supportPhone.replaceAll(RegExp(r'[^0-9+]'), ''),
    );

    if (!await launchUrl(phoneUri)) {
      throw Exception('Could not open phone dialer');
    }
  }

  Future<void> _openWhatsApp() async {
    final Uri whatsappUri = Uri.parse(
      whatsappLink(AppSettingsService.cached.whatsappNumber, message: 'Assalamu Alaikum, ChalakChar Mart'),
    );

    if (!await launchUrl(
      whatsappUri,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open WhatsApp');
    }
  }


  Future<void> _openMap() async {
    final Uri mapUri = Uri.parse(mapUrl);

    if (!await launchUrl(
      mapUri,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not open map');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Help",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _supportCard(
                    icon: Icons.call_outlined,
                    label: "Call Support",
                    iconColor: Colors.green,
                    onTap: _callSupport,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _supportCard(
                    icon: Icons.chat_bubble_outline,
                    label: "WhatsApp",
                    iconColor: Colors.green,
                    onTap: _openWhatsApp,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            HealthGate(
              child: InkWell(
              onTap: _openYoutube,
              borderRadius: BorderRadius.circular(15),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF32A8C7), Color(0xFF6DD5FA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 70,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "কিভাবে ঔষধ অর্ডার করবেন??",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),

            const SizedBox(height: 30),

            const Text(
              "Business Location",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            _businessLocationCard(),

            const SizedBox(height: 30),

            Container(
              key: faqKey,
              child: const Text(
                "সচরাচর জিজ্ঞাসা",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 15),

            HealthGate(
              fallback: Column(children: _partsFaq()),
              child: Column(
                children: [
                _faqItem(
                  "কিভাবে মেডিসিন অর্ডার করব?",
                  "আপনি আমাদের অ্যাপ থেকে যেকোনো মেডিসিন সার্চ করে কার্টে যোগ করে অর্ডার করতে পারেন অথবা প্রেসক্রিপশন আপলোড করে অর্ডার করতে পারেন।",
                ),
                _faqItem(
                  "কিভাবে ডাক্তার দেখাব?",
                  "আমাদের 'Consult Doctor' সেকশনে গিয়ে আপনি আপনার পছন্দমতো ডাক্তার সিলেক্ট করে অ্যাপয়েন্টমেন্ট বুক করতে পারেন।",
                ),
                _faqItem(
                  "ডাক্তারের সাথে কিভাবে যোগাযোগ করব?",
                  "অ্যাপয়েন্টমেন্ট কনফার্ম হওয়ার পর আপনি ডাক্তারের সাথে কথা বলতে পারবেন।",
                ),
                _faqItem(
                  "কিভাবে রিপোর্ট দেখাব?",
                  "আপনার প্রোফাইল সেকশনে 'My Reports' এ গিয়ে আপনার সকল ল্যাব রিপোর্ট দেখতে পাবেন।",
                ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// FAQ for mobile / laptop parts (no health features).
  List<Widget> _partsFaq() {
    return [
      _faqItem(
        "কীভাবে অর্ডার করব?",
        "প্রোডাক্ট সার্চ করুন বা ক্যাটাগরি থেকে বেছে নিন। মডেল/ভ্যারিয়েন্ট সিলেক্ট করে কার্টে যোগ করুন, তারপর ঠিকানা দিয়ে অর্ডার করুন। অর্ডার কনফার্ম করতে আমাদের টিম প্রয়োজনে ফোন করবে।",
      ),
      _faqItem(
        "আমার ফোন বা ল্যাপটপে পার্টসটা মিলবে কিনা কীভাবে বুঝব?",
        "প্রোডাক্ট পেজে মডেল নম্বরগুলো মিলিয়ে নিন (যেমন SM-A235F, HP 15-D)। নিশ্চিত না হলে অর্ডারের আগে WhatsApp-এ আপনার ডিভাইসের মডেল নম্বর বা পুরনো পার্টসের ছবি পাঠান, আমরা মিলিয়ে দেব।",
      ),
      _faqItem(
        "ডেলিভারি কতদিনে পাব?",
        "প্রতিটি প্রোডাক্ট পেজে আনুমানিক ডেলিভারি সময় দেখানো থাকে। দেশে স্টকে থাকা পণ্য কয়েক দিনের মধ্যে পৌঁছায়; বিদেশ থেকে আমদানি করা পণ্যে সাধারণত বেশি সময় লাগে।",
      ),
      _faqItem(
        "বিদেশ থেকে আমদানি করা পণ্য মানে কী?",
        "কিছু পার্টস আমরা আপনার অর্ডারের পর বিদেশ থেকে আনিয়ে দিই। এগুলোর পেজে \"বিদেশ থেকে আমদানি\" আর আনুমানিক ডেলিভারি সময় লেখা থাকে। অর্ডারের পর আমরা যাচাই করে কনফার্ম করি; কোনো অতিরিক্ত খরচ লাগলে কনফার্মের আগে আপনাকে জানানো হবে।",
      ),
      _faqItem(
        "ওয়ারেন্টি আছে কি?",
        "পণ্যের পেজে ওয়ারেন্টি উল্লেখ থাকলে সেই অনুযায়ী পাবেন। ডিসপ্লে, ব্যাটারি বা বোর্ড ইনস্টলের আগে অবশ্যই পরীক্ষা করে নিন; ইনস্টলের সময় ভাঙা বা ক্ষতিগ্রস্ত পার্টস ওয়ারেন্টিতে পড়ে না।",
      ),
      _faqItem(
        "পণ্য নষ্ট বা ভুল এলে কী করব?",
        "ডেলিভারির পর দ্রুত (Return Policy-তে দেওয়া সময়ের মধ্যে) ছবি/ভিডিওসহ আমাদের জানান। চালু অবস্থায় নষ্ট বা ভুল পণ্য হলে যাচাই করে বদলে দেওয়া বা টাকা ফেরত দেওয়া হয়। বিস্তারিত Return Policy পেজে আছে।",
      ),
      _faqItem(
        "পেমেন্ট কীভাবে করব?",
        "এখন ক্যাশ অন ডেলিভারি চালু আছে। অন্য পেমেন্ট পদ্ধতি চালু হলে চেকআউটে দেখা যাবে।",
      ),
    ];
  }

  Widget _businessLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront, color: Color(0xFF32A8C7), size: 30),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "ChalakChar Mart",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Same source as the footer (settings/app.address).
          StreamBuilder<AppSettings>(
            stream: AppSettingsService.watch(),
            initialData: AppSettingsService.cached,
            builder: (context, snap) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: Colors.redAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (snap.data ?? AppSettingsService.cached).address,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Phone and email as entered in Admin › Settings (same as the footer).
          StreamBuilder<AppSettings>(
            stream: AppSettingsService.watch(),
            initialData: AppSettingsService.cached,
            builder: (context, snap) => Row(
              children: [
                const Icon(Icons.call_outlined, color: Colors.green, size: 22),
                const SizedBox(width: 10),
                Text(
                  (snap.data ?? AppSettingsService.cached).supportPhone,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<AppSettings>(
            stream: AppSettingsService.watch(),
            initialData: AppSettingsService.cached,
            builder: (context, snap) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.email_outlined, color: Color(0xFF32A8C7), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (snap.data ?? AppSettingsService.cached).email,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            "We are committed to providing authentic products and reliable service to our customers.",
            style: TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text("View on Map"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF32A8C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _supportCard({
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faqItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}


