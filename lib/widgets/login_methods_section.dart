import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Settings -> which sign-in methods open this account (Google, Facebook,
/// phone). Linked ones show what they sign in with; read from Firebase Auth.
class LoginMethodsSection extends StatelessWidget {
  const LoginMethodsSection({super.key});

  static const Color _accent = Color(0xFFFF9900);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        final user = snap.data ?? FirebaseAuth.instance.currentUser;
        if (user == null) return const SizedBox.shrink();

        UserInfo? find(String id) {
          for (final info in user.providerData) {
            if (info.providerId == id) return info;
          }
          return null;
        }

        Widget row(String id, String name, Widget icon, String? detail) {
          final linked = find(id) != null;
          return ListTile(
            leading: icon,
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              linked ? ((detail ?? '').isNotEmpty ? detail! : 'যুক্ত আছে') : 'যুক্ত নেই',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              linked ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
              color: linked ? Colors.green : Colors.grey.shade400,
            ),
          );
        }

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'এগুলোর যেকোনোটি দিয়ে একই অ্যাকাউন্টে ঢুকতে পারবেন।',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              row('google.com', 'Google', const Icon(Icons.g_mobiledata_rounded, color: _accent, size: 30),
                  find('google.com')?.email),
              const Divider(height: 1, indent: 16, endIndent: 16),
              row('facebook.com', 'Facebook', const Icon(Icons.facebook, color: _accent),
                  find('facebook.com')?.email),
              const Divider(height: 1, indent: 16, endIndent: 16),
              row('phone', 'ফোন OTP', const Icon(Icons.sms_outlined, color: _accent),
                  find('phone')?.phoneNumber ?? user.phoneNumber),
            ],
          ),
        );
      },
    );
  }
}
