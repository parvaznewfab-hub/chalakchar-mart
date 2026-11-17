import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Settings -> notification choices (signed-in users only).
///
/// "অর্ডারের আপডেট" is always on. "নতুন পণ্য ও অফার" is stored as
/// users/{uid}.notificationPrefs.marketing; when false the Cloud Functions
/// send that user no new-product/offer push or in-app notification.
class NotificationPrefsSection extends StatelessWidget {
  const NotificationPrefsSection({super.key});

  static const Color _accent = Color(0xFFFF9900);

  static bool marketingOn(Map<String, dynamic>? user) {
    final prefs = user?['notificationPrefs'];
    return !(prefs is Map && prefs['marketing'] == false);
  }

  Future<void> _setMarketing(BuildContext context, String uid, bool on) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notificationPrefs': {
          'marketing': on,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সেভ করা যায়নি। আবার চেষ্টা করুন।')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) return const SizedBox.shrink();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, snap) {
            final marketing = marketingOn(snap.data?.data());

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SwitchListTile(
                    value: true,
                    onChanged: null,
                    secondary: Icon(Icons.shopping_bag_outlined, color: _accent),
                    title: Text('অর্ডারের আপডেট', style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text('সবসময় চালু থাকে, বন্ধ করা যায় না'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    value: marketing,
                    onChanged: snap.hasData ? (v) => _setMarketing(context, user.uid, v) : null,
                    secondary: const Icon(Icons.local_offer_outlined, color: _accent),
                    title: const Text('নতুন পণ্য ও অফার', style: TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(marketing ? 'চালু' : 'বন্ধ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
