import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/user/help_center_page.dart';
import '../pages/user/settings_details_pages.dart';
import '../services/app_settings_service.dart';

class GlobalWebFooter extends StatelessWidget {
  const GlobalWebFooter({super.key});

  static const Color _bg = Color(0xFF0E1726);
  static const Color _bottomBg = Color(0xFF08111F);
  static const Color _card = Color(0xFF111C2E);
  static const Color _muted = Color(0xFFB8C4D9);
  static const Color _accent = Color(0xFF32A8C7);

  Future<void> _openUrl(BuildContext context, String url) async {
    final fixedUrl = url.trim();
    if (fixedUrl.isEmpty) return;

    final uri = Uri.tryParse(fixedUrl);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid link')),
        );
      }
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  String _phoneOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  void _handleFooterClick(
      BuildContext context,
      String label,
      AppSettings settings,
      ) {
    switch (label) {
      case 'About us':
        _openPage(context, const AboutUsPage());
        return;
      case 'Privacy Policy':
        _openPage(context, const PrivacyPolicyPage());
        return;
      case 'Terms & Conditions':
        _openPage(context, const TermsConditionsPage());
        return;
      case 'Medical Disclaimer':
        _openPage(context, const MedicalDisclaimerPage());
        return;
      case 'Return Policy':
        _openPage(context, const ReturnPolicyPage());
        return;
      case 'Contact Us':
        _openPage(context, const HelpCenterPage());
        return;
      case 'FAQ':
        _openPage(context, const HelpCenterPage(scrollToFaq: true));
        return;
      case 'Google Map Location':
        _openUrl(
          context,
          settings.googleMapLink.isNotEmpty
              ? settings.googleMapLink
              : 'https://maps.app.goo.gl/wM8fTS7vf5LHs8Bm9',
        );
        return;
      case 'Facebook':
        _openUrl(context, settings.facebookLink);
        return;
      case 'Messenger':
        _openUrl(context, settings.messengerLink);
        return;
      case 'Instagram':
        _openUrl(context, settings.instagramLink);
        return;
      case 'YouTube':
        _openUrl(context, settings.youtubeLink);
        return;
      case 'TikTok':
        _openUrl(context, settings.tiktokLink);
        return;
    }

    if (label.startsWith('WhatsApp')) {
      final cleaned = _phoneOnly(settings.whatsappNumber);
      if (cleaned.isNotEmpty) _openUrl(context, 'https://wa.me/$cleaned');
    } else if (label == settings.supportPhone) {
      _openUrl(context, 'tel:${settings.supportPhone}');
    } else if (label.contains('@')) {
      _openUrl(context, 'mailto:$label');
    }
  }

  bool _isClickable(String item, AppSettings settings) {
    return item == 'About us' ||
        item == 'Terms & Conditions' ||
        item == 'Privacy Policy' ||
        item == 'Medical Disclaimer' ||
        item == 'Return Policy' ||
        item == 'Contact Us' ||
        item == 'FAQ' ||
        item == 'Google Map Location' ||
        item == 'Facebook' ||
        item == 'Messenger' ||
        item == 'Instagram' ||
        item == 'YouTube' ||
        item == 'TikTok' ||
        item.startsWith('WhatsApp') ||
        item == settings.supportPhone ||
        item.contains('@');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      builder: (context, snapshot) {
        final settings = snapshot.data;

        if (settings == null) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;

            return Container(
              width: double.infinity,
              color: _bg,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 20 : 70,
                      isMobile ? 28 : 52,
                      isMobile ? 20 : 70,
                      28,
                    ),
                    child: isMobile
                        ? _mobileLayout(context, settings)
                        : _desktopLayout(context, settings),
                  ),
                  _bottomBar(settings, isMobile),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _desktopLayout(BuildContext context, AppSettings settings) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: _footerBrand(settings),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: _footerColumn(context, settings, 'Quick Links', [
            'About us',
            'Terms & Conditions',
            'Privacy Policy',
            'Medical Disclaimer',
            'Return Policy',
          ]),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(context, settings, 'Support', [
            'Contact Us',
            'FAQ',
            settings.supportPhone,
            settings.email,
          ]),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(context, settings, 'Address', [
            settings.address,
            'Google Map Location',
          ]),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(context, settings, 'Legal', [
            if (settings.tradeLicenseNo.isNotEmpty)
              'Trade License No: ${settings.tradeLicenseNo}',
            if (settings.dbidNo.isNotEmpty) 'DBID No: ${settings.dbidNo}',
            if (settings.drugLicenseNo.isNotEmpty)
              'Drug License No: ${settings.drugLicenseNo}',
          ]),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _socialColumn(context, settings),
        ),
      ],
    );
  }

  Widget _mobileLayout(BuildContext context, AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerBrand(settings),
        const SizedBox(height: 26),
        _footerColumn(context, settings, 'Quick Links', [
          'About us',
          'Terms & Conditions',
          'Privacy Policy',
          'Medical Disclaimer',
          'Return Policy',
        ]),
        const SizedBox(height: 22),
        _footerColumn(context, settings, 'Support', [
          'Contact Us',
          'FAQ',
          settings.supportPhone,
          settings.email,
        ]),
        const SizedBox(height: 22),
        _footerColumn(context, settings, 'Address', [
          settings.address,
          'Google Map Location',
        ]),
        const SizedBox(height: 22),
        _footerColumn(context, settings, 'Legal', [
          if (settings.tradeLicenseNo.isNotEmpty)
            'Trade License No: ${settings.tradeLicenseNo}',
          if (settings.dbidNo.isNotEmpty) 'DBID No: ${settings.dbidNo}',
          if (settings.drugLicenseNo.isNotEmpty)
            'Drug License No: ${settings.drugLicenseNo}',
        ]),
        const SizedBox(height: 22),
        _socialColumn(context, settings),
      ],
    );
  }

  Widget _footerBrand(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 52,
          errorBuilder: (_, __, ___) => Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded, color: _accent),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          settings.pharmacyName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'সব প্রয়োজন, এক জায়গায়',
          style: TextStyle(
            color: _muted,
            height: 1.5,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_rounded, color: _accent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Open: ${settings.businessHours}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerColumn(
      BuildContext context,
      AppSettings settings,
      String title,
      List<String> items,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnTitle(title),
        const SizedBox(height: 18),
        ...items.where((e) => e.trim().isNotEmpty).map((e) {
          final clickable = _isClickable(e, settings);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: clickable ? () => _handleFooterClick(context, e, settings) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      clickable ? Icons.chevron_right_rounded : Icons.circle,
                      color: clickable ? _accent : _muted,
                      size: clickable ? 18 : 7,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          color: clickable ? Colors.white : _muted,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: clickable ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _socialColumn(BuildContext context, AppSettings settings) {
    final items = <_SocialItem>[
      _SocialItem(
        label: 'WhatsApp:\n${settings.whatsappNumber}',
        key: 'WhatsApp: ${settings.whatsappNumber}',
        icon: Icons.chat_rounded,
        color: const Color(0xFF25D366),
      ),
      if (settings.facebookLink.isNotEmpty)
        const _SocialItem(
          label: 'Facebook',
          key: 'Facebook',
          icon: Icons.facebook_rounded,
          color: Color(0xFF1877F2),
        ),
      if (settings.messengerLink.isNotEmpty)
        const _SocialItem(
          label: 'Messenger',
          key: 'Messenger',
          icon: Icons.message_rounded,
          color: Color(0xFF8A3FFC),
        ),
      if (settings.instagramLink.isNotEmpty)
        const _SocialItem(
          label: 'Instagram',
          key: 'Instagram',
          icon: Icons.camera_alt_rounded,
          color: Color(0xFFE1306C),
        ),
      if (settings.youtubeLink.isNotEmpty)
        const _SocialItem(
          label: 'YouTube',
          key: 'YouTube',
          icon: Icons.play_arrow_rounded,
          color: Color(0xFFFF0000),
        ),
      if (settings.tiktokLink.isNotEmpty)
        const _SocialItem(
          label: 'TikTok',
          key: 'TikTok',
          icon: Icons.music_note_rounded,
          color: Color(0xFF111827),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnTitle('Social'),
        const SizedBox(height: 18),
        ...items.map(
              (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => _handleFooterClick(context, item.key, settings),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 22,
                      width: 22,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
                      ),
                      child: Icon(item.icon, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.label,
                        softWrap: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _columnTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 3,
          width: 36,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(AppSettings settings, bool isMobile) {
    final year = DateTime.now().year;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 18 : 70,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: _bottomBg,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '© $year ${settings.pharmacyName}. All rights reserved.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _paymentBadges(),
        ],
      )
          : Row(
        children: [
          Expanded(
            child: Text(
              '© $year ${settings.pharmacyName}. All rights reserved.',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          _paymentBadges(),
        ],
      ),
    );
  }

  Widget _paymentBadges() {
    final items = ['COD', 'bKash', 'Nagad', 'Card'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Text(
            e,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SocialItem {
  final String label;
  final String key;
  final IconData icon;
  final Color color;

  const _SocialItem({
    required this.label,
    required this.key,
    required this.icon,
    required this.color,
  });
}
