import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/referral_service.dart';

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  final TextEditingController _codeController = TextEditingController();
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  String? myReferralCode;

  @override
  void initState() {
    super.initState();
    _loadMyCode();
  }

  void _loadMyCode() async {
    if (uid.isNotEmpty) {
      String code = await ReferralService.getOrCreateReferralCode(uid);
      setState(() {
        myReferralCode = code;
      });
    }
  }

  void _applyReferral() async {
    String code = _codeController.text.trim();
    if (code.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String result = await ReferralService.applyReferral(code);
    
    if (mounted) {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _codeController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Refer & Earn", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: ReferralService.getUserData(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          int points = userData['points'] ?? 0;
          int totalEarnings = userData['totalEarnings'] ?? 0;
          int referralCount = userData['referralCount'] ?? 0;
          bool alreadyReferred = userData.containsKey('referredBy');

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // 🏆 Balance Card
                _buildProfessionalEarningsCard(points, totalEarnings, referralCount),

                const SizedBox(height: 16),
                
                // 📺 Watch Tutorial Section
                _buildProfessionalTutorialSection(),

                const SizedBox(height: 24),

                // 🎁 Referral Code Section
                _buildSectionHeader("Your Referral Code", Icons.qr_code_2),
                const SizedBox(height: 12),
                _buildCodeCard(),

                const SizedBox(height: 24),

                // 📝 Apply Code Section
                if (!alreadyReferred) ...[
                  _buildSectionHeader("Apply Invite Code", Icons.local_offer_outlined),
                  const SizedBox(height: 12),
                  _buildApplyInput(),
                  const SizedBox(height: 24),
                ],

                // ❓ FAQ Section
                Text(
                  "Frequently Asked Questions",
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.cyan[700],
                  ),
                ),
                const SizedBox(height: 12),
                _buildFAQSection(),
                
                const SizedBox(height: 30),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfessionalEarningsCard(int points, int total, int count) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  "ChalakChar Cash Balance",
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      "৳",
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "$points",
                      style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _proStatTile("Total Earned", "৳$total"),
                      Container(width: 1, height: 30, color: Colors.white24),
                      _proStatTile("Referrals", "$count"),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _proStatTile(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildProfessionalTutorialSection() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data =
          snapshot.data!.data()
          as Map<String, dynamic>?;

          final videoUrl =
              data?['referralYoutubeLink'] ?? "";
          if (videoUrl.isNotEmpty) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: ListTile(
                onTap: () async {
                  final url = Uri.parse(videoUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.amber, size: 28),
                ),
                title: const Text(
                  "How it works?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Text("Watch a short video to learn more"),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              ),
            );
          }
        }
        return const SizedBox();
      },
    );
  }

  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SHARE THIS CODE",
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  myReferralCode ?? "---",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 2),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.teal,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (myReferralCode != null) {
                  Share.share("Join ChalakChar Mart and use my code $myReferralCode to get rewards! Download now.");
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text("SHARE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildApplyInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeController,
              decoration: InputDecoration(
                hintText: "Enter friend's code",
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _applyReferral,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("APPLY", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQSection() {
    return Column(
      children: [
        _faqItem(
          "রেফারেল প্রোগ্রাম কি?",
          "রেফারেল প্রোগ্রাম হলো, আপনার বন্ধুদের এবং পরিবারের সদস্যদের ChalakChar Mart থেকে সেবা নেওয়ার জন্য রেফার করার একটি সহজ উপায়।",
        ),
        _faqItem(
          "আমি কিভাবে রেফারেল প্রোগ্রামে অংশগ্রহণ করব?",
          "অংশগ্রহণ করতে, আপনার ChalakChar Mart অ্যাকাউন্টে লগইন করে রেফারেল সেকশনে যেতে হবে। সেখানে আপনি আপনার রেফারেল কোডটি পাবেন যা আপনি আপনার বন্ধু ও পরিবারের সাথে সোশ্যাল মিডিয়া, ইমেইল বা অন্য যেকোনো মাধ্যমে শেয়ার করতে পারবেন।",
        ),
        _faqItem(
          "বন্ধুদের রেফার করে আমি কোন পুরস্কার পেতে পারি?",
          "যখন আপনার বন্ধু আপনার রেফারেল কোড ব্যবহার করে সাইন-আপ করবে, তখন আপনি একটি নির্দিষ্ট পরিমাণ ক্যাশব্যাক বা ChalakChar Mart Cash পাবেন যা ভবিষ্যতে সেবার জন্য ব্যবহার করতে পারবেন।",
        ),
        _faqItem(
          "আমি কতজন বন্ধুকে রেফার করতে পারব?",
          "আপনি যত বেশি বন্ধু রেফার করবেন, তত বেশি ক্যাশব্যাক বা রিওয়ার্ড পেতে পারবেন। রেফারের কোনো নির্দিষ্ট সীমা নেই।",
        ),
        _faqItem(
          "আমি কীভাবে সফল রেফারেলের সংখ্যা জানতে পারবো?",
          "ChalakChar Mart অ্যাপের মেনু থেকে “Referral” অপশনে গিয়ে আপনি আপনার সফল রেফারেলের সংখ্যা সহজেই দেখতে পারবেন।",
        ),
        _faqItem(
          "আমি কি এমন কাউকে রেফার করতে পারি যিনি ইতিমধ্যে ChalakChar Mart ব্যবহার করছেন?",
          "না, রেফারেল প্রোগ্রাম শুধুমাত্র নতুন ব্যবহারকারীদের জন্য প্রযোজ্য, যারা আগে কখনো ChalakChar Mart অ্যাপে অ্যাকাউন্ট তৈরি করেননি।",
        ),
        _faqItem(
          "সাইন আপ করার সময় আমার বন্ধু যদি আমার রেফারেল কোড ব্যবহার করতে ভুলে যায়, তাহলে কী হবে?",
          "আপনার বন্ধুকে ChalakChar Mart অ্যাপে লগইন করে রেফারেল অপশনে যেতে হবে। সেখানে “Add Referral” অপশন থেকে আপনার শেয়ার করা কোডটি ব্যবহার করলে, তার অ্যাকাউন্টে রিওয়ার্ড (যেমন ৫০ টাকা ChalChar Mart Cash) যোগ হবে।",
        ),
      ],
    );
  }

  Widget _faqItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          question,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text(
              answer,
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.teal),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ],
    );
  }
}



