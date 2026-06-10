import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  static const String supportPhone = '01975838764';
  static const String whatsappNumber = '8801975838764';

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
      path: supportPhone,
    );

    if (!await launchUrl(phoneUri)) {
      throw Exception('Could not open phone dialer');
    }
  }

  Future<void> _openWhatsApp() async {
    final Uri whatsappUri = Uri.parse(
      'https://wa.me/$whatsappNumber?text=Assalamu%20Alaikum%2C%20ChalakChar%20Mart',
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

            InkWell(
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
    );
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
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined,
                  color: Colors.redAccent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Chalak Char Bazar Medicine Market, Monohardi, Narsingdi, Bangladesh",
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.call_outlined, color: Colors.green, size: 22),
              SizedBox(width: 10),
              Text(
                "01975-838764",
                style: TextStyle(fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.email_outlined, color: Color(0xFF32A8C7), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "chalakcharmart@gmail.com",
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "We are committed to providing authentic products and reliable healthcare services to our customers.",
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


