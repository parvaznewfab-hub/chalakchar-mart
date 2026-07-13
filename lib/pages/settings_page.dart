import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import 'main_navigation_page.dart';
import 'user/help_center_page.dart';
import 'user/settings_details_pages.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _section("General"),

              _card(
                child: ListTile(
                  leading: const Icon(
                    Icons.language,
                    color: Color(0xFFFF9900),
                  ),
                  title: const Text(
                    "Language",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: DropdownButton<String>(
                    value: settings.language,
                    underline: const SizedBox(),
                    items: ["English", "Bangla"]
                        .map(
                          (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ),
                    )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        settings.changeLanguage(val);
                      }
                    },
                  ),
                ),
              ),

              _card(
                child: SwitchListTile(
                  value: settings.isDark,
                  onChanged: settings.toggleDark,
                  title: const Text(
                    "Dark Mode",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  secondary: const Icon(
                    Icons.dark_mode,
                    color: Color(0xFFFF9900),
                  ),
                ),
              ),

              _section("Legal"),

              _item(context, "About Us", Icons.info_outline, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutUsPage()),
                );
              }),

              _item(context, "Permissions", Icons.security, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PermissionsPage()),
                );
              }),

              _item(context, "Privacy Policy", Icons.privacy_tip, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                );
              }),

              _item(context, "Terms & Conditions", Icons.description, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TermsConditionsPage()),
                );
              }),

              _item(context, "Return Policy", Icons.assignment_return, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReturnPolicyPage()),
                );
              }),

              _section("Support"),

              _item(context, "Contact Us", Icons.support_agent, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpCenterPage()),
                );
              }),

              _item(context, "App Version", Icons.info, () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("App Version"),
                    content: const Text(
                      "ChalakChar Mart\nVersion: 1.0.0",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
              }),

              _section("Account"),

              _item(context, "Delete Account", Icons.delete, () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Delete Account"),
                    content: const Text(
                      "Are you sure you want to delete your account? This action cannot be undone.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await FirebaseAuth.instance.currentUser?.delete();
                        },
                        child: const Text(
                          "Delete",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              _item(context, "Log Out", Icons.logout, () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to logout?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _logout(context);
                        },
                        child: const Text(
                          "Logout",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
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
      child: child,
    );
  }

  Widget _item(
      BuildContext context,
      String title,
      IconData icon,
      VoidCallback onTap,
      ) {
    final bool danger = title == "Log Out" || title == "Delete Account";

    return _card(
      child: ListTile(
        leading: Icon(
          icon,
          color: danger ? Colors.red : const Color(0xFFFF9900),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: danger ? Colors.red : Colors.black,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }

  void _logout(BuildContext context) async {
    await AuthService().signOut();

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const MainNavigation(role: 'user', initialIndex: 0),
        ),
            (route) => false,
      );
    }
  }
}
