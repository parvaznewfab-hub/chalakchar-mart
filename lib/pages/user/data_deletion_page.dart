import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_settings_service.dart';
import '../../widgets/global_web_footer.dart';
import '../../widgets/global_web_header.dart';

class DataDeletionPage extends StatelessWidget {
  const DataDeletionPage({super.key});

  Future<void> _openEmail(String email) async {
    final cleanEmail = email.trim().isEmpty ? 'chalacharmart@gmail.com' : email.trim();
    final uri = Uri(
      scheme: 'mailto',
      path: cleanEmail,
      queryParameters: {
        'subject': 'Facebook Data Deletion Request - ChalakChar Mart',
        'body': 'Hello ChalakChar Mart Team,\n\nPlease delete my account data and Facebook login data associated with my ChalakChar Mart account.\n\nRegistered phone/email:\nFacebook profile name:\n\nThank you.',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MediaQuery.of(context).size.width < 900
          ? AppBar(
        title: const Text('Data Deletion'),
      )
          : null,
      body: StreamBuilder<AppSettings>(
        stream: AppSettingsService.watch(),
        builder: (context, snapshot) {
          final settings = snapshot.data;
          final brandName = settings?.pharmacyName ?? 'ChalakChar Mart';
          final email = settings?.email ?? 'chalacharmart@gmail.com';

          return SingleChildScrollView(
            child: Column(
              children: [
                if (MediaQuery.of(context).size.width >= 900)
                  const GlobalWebHeader(),
                Container(
                  width: double.infinity,
                  color: const Color(0xFFF5F7FB),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.privacy_tip_rounded,
                                color: Color(0xFF32A8C7),
                                size: 42,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'User Data Deletion Instructions',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'This page explains how Facebook Login users can request deletion of data from $brandName.',
                                style: const TextStyle(fontSize: 15, height: 1.6),
                              ),
                              const SizedBox(height: 22),
                              _section(
                                title: 'How to request deletion',
                                children: [
                                  'Login to your $brandName account.',
                                  'Open Profile or Help Center and contact support.',
                                  'Send a data deletion request with your registered phone/email or Facebook profile name.',
                                ],
                              ),
                              const SizedBox(height: 18),
                              _section(
                                title: 'What we delete',
                                children: const [
                                  'Account profile information stored in Firebase.',
                                  'Facebook Login identifier connected with your account.',
                                  'Saved addresses and related user preferences where applicable.',
                                  'Marketing profile data connected with your user account.',
                                ],
                              ),
                              const SizedBox(height: 18),
                              _section(
                                title: 'Processing time',
                                children: const [
                                  'We process verified deletion requests within 30 days.',
                                  'Some order, payment, tax, fraud-prevention, or legal records may be retained where required by law.',
                                ],
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _openEmail(email),
                                    icon: const Icon(Icons.email_rounded),
                                    label: const Text('Request by Email'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).pushNamed('/privacy-policy'),
                                    icon: const Icon(Icons.policy_rounded),
                                    label: const Text('Privacy Policy'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Contact email: $email',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const GlobalWebFooter(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section({required String title, required List<String> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ...children.map(
              (text) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF32A8C7)),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
