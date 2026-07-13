import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/user/help_center_page.dart';
import '../services/app_settings_service.dart';

class GlobalWebFooter extends StatelessWidget {
  const GlobalWebFooter({super.key});

  static const Color _bg = Color(0xFF0E1726);
  static const Color _bottomBg = Color(0xFF08111F);
  static const Color _card = Color(0xFF111C2E);
  static const Color _muted = Color(0xFFB8C4D9);
  static const Color _accent = Color(0xFF32A8C7);

  Future<void> _openUrl(BuildContext context, String url) async {
    final fixedUrl = _url(url);
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

  void _openRoute(BuildContext context, String route) {
    final cleanRoute = route.trim();
    if (cleanRoute.isEmpty) return;
    Navigator.of(context, rootNavigator: true).pushNamed(cleanRoute);
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  String _phoneOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _url(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('mailto:') ||
        raw.startsWith('tel:')) {
      return raw;
    }
    return 'https://$raw';
  }

  String _whatsappUrl(String value) {
    var cleaned = _phoneOnly(value);
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
    if (cleaned.startsWith('0')) cleaned = '880${cleaned.substring(1)}';
    return 'https://wa.me/$cleaned';
  }

  bool _isInternalUrl(String url, String route) {
    final clean = url.trim();
    if (clean.isEmpty) return true;
    return clean.endsWith(route);
  }

  void _openLegalOrRoute(
      BuildContext context,
      String configuredUrl,
      String route,
      ) {
    if (_isInternalUrl(configuredUrl, route)) {
      _openRoute(context, route);
    } else {
      _openUrl(context, configuredUrl);
    }
  }

  void _handleFooterAction(
      BuildContext context,
      _FooterAction action,
      AppSettings settings,
      ) {
    switch (action) {
      case _FooterAction.about:
        _openLegalOrRoute(context, settings.aboutUsUrl, '/about-us');
        return;
      case _FooterAction.terms:
        _openLegalOrRoute(context, settings.termsUrl, '/terms-conditions');
        return;
      case _FooterAction.privacy:
        _openLegalOrRoute(context, settings.privacyPolicyUrl, '/privacy-policy');
        return;
      case _FooterAction.dataDeletion:
        _openLegalOrRoute(context, settings.dataDeletionUrl, '/data-deletion');
        return;
      case _FooterAction.returnPolicy:
        _openLegalOrRoute(context, settings.returnPolicyUrl, '/return-policy');
        return;
      case _FooterAction.contact:
        if (settings.contactUrl.trim().isNotEmpty &&
            !settings.contactUrl.endsWith('/contact')) {
          _openUrl(context, settings.contactUrl);
        } else {
          _openPage(context, const HelpCenterPage());
        }
        return;
      case _FooterAction.faq:
        if (settings.faqUrl.trim().isNotEmpty &&
            !settings.faqUrl.endsWith('/faq')) {
          _openUrl(context, settings.faqUrl);
        } else {
          _openPage(context, const HelpCenterPage(scrollToFaq: true));
        }
        return;
      case _FooterAction.phone:
        _openUrl(context, 'tel:${settings.supportPhone}');
        return;
      case _FooterAction.email:
        _openUrl(context, 'mailto:${settings.email}');
        return;
      case _FooterAction.map:
        _openUrl(
          context,
          settings.googleMapLink.isNotEmpty
              ? settings.googleMapLink
              : 'https://maps.app.goo.gl/wM8fTS7vf5LHs8Bm9',
        );
        return;
      case _FooterAction.whatsapp:
        _openUrl(context, _whatsappUrl(settings.whatsappNumber));
        return;
      case _FooterAction.facebook:
        _openUrl(context, settings.facebookLink);
        return;
      case _FooterAction.messenger:
        _openUrl(context, settings.messengerLink);
        return;
      case _FooterAction.instagram:
        _openUrl(context, settings.instagramLink);
        return;
      case _FooterAction.youtube:
        _openUrl(context, settings.youtubeLink);
        return;
      case _FooterAction.tiktok:
        _openUrl(context, settings.tiktokLink);
        return;
      case _FooterAction.none:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      initialData: AppSettingsService.cached,
      builder: (context, snapshot) {
        final settings = snapshot.data ?? AppSettingsService.cached;

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

  List<_FooterItem> _quickLinks(AppSettings settings) => [
    _FooterItem(settings.footerAboutLabel, _FooterAction.about),
    _FooterItem(settings.footerTermsLabel, _FooterAction.terms),
    _FooterItem(settings.footerPrivacyLabel, _FooterAction.privacy),
    _FooterItem(settings.footerDataDeletionLabel, _FooterAction.dataDeletion),
    _FooterItem(settings.footerReturnPolicyLabel, _FooterAction.returnPolicy),
  ];

  List<_FooterItem> _supportLinks(AppSettings settings) => [
    _FooterItem(settings.footerContactLabel, _FooterAction.contact),
    _FooterItem(settings.footerFaqLabel, _FooterAction.faq),
    _FooterItem(settings.supportPhone, _FooterAction.phone),
    _FooterItem(settings.email, _FooterAction.email),
  ];

  List<_FooterItem> _addressLinks(AppSettings settings) => [
    _FooterItem(settings.address, _FooterAction.none, bullet: true),
    const _FooterItem('Google Map Location', _FooterAction.map),
  ];

  List<_FooterItem> _legalLinks(AppSettings settings) => [
    if (settings.tradeLicenseNo.isNotEmpty)
      _FooterItem('Trade License No: ${settings.tradeLicenseNo}', _FooterAction.none, bullet: true),
    if (settings.dbidNo.isNotEmpty)
      _FooterItem('DBID No: ${settings.dbidNo}', _FooterAction.none, bullet: true),
  ];

  Widget _desktopLayout(BuildContext context, AppSettings settings) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _footerBrand(settings)),
        const SizedBox(width: 32),
        Expanded(
          flex: 2,
          child: _footerColumn(
            context,
            settings,
            settings.footerQuickLinksTitle,
            _quickLinks(settings),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(
            context,
            settings,
            settings.footerSupportTitle,
            _supportLinks(settings),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(
            context,
            settings,
            settings.footerAddressTitle,
            _addressLinks(settings),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 2,
          child: _footerColumn(
            context,
            settings,
            settings.footerLegalTitle,
            _legalLinks(settings),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(flex: 2, child: _socialColumn(context, settings)),
      ],
    );
  }

  Widget _mobileLayout(BuildContext context, AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerBrand(settings),
        const SizedBox(height: 26),
        _footerColumn(context, settings, settings.footerQuickLinksTitle, _quickLinks(settings)),
        const SizedBox(height: 22),
        _footerColumn(context, settings, settings.footerSupportTitle, _supportLinks(settings)),
        const SizedBox(height: 22),
        _footerColumn(context, settings, settings.footerAddressTitle, _addressLinks(settings)),
        const SizedBox(height: 22),
        _footerColumn(context, settings, settings.footerLegalTitle, _legalLinks(settings)),
        const SizedBox(height: 22),
        _socialColumn(context, settings),
      ],
    );
  }

  Widget _footerBrand(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (settings.logoUrl.trim().isNotEmpty)
          Image.network(
            settings.logoUrl.trim(),
            height: 52,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _assetLogo(),
          )
        else
          _assetLogo(),
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
        Text(
          settings.tagline,
          style: const TextStyle(
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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

  Widget _assetLogo() {
    return Image.asset(
      'assets/images/logo.png',
      height: 52,
      errorBuilder: (_, __, ___) => Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.storefront_rounded, color: _accent),
      ),
    );
  }

  Widget _footerColumn(
      BuildContext context,
      AppSettings settings,
      String title,
      List<_FooterItem> items,
      ) {
    final cleanItems = items.where((e) => e.label.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnTitle(title),
        const SizedBox(height: 18),
        ...cleanItems.map((item) {
          final clickable = item.action != _FooterAction.none;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: clickable
                  ? () => _handleFooterAction(context, item.action, settings)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      clickable && !item.bullet
                          ? Icons.chevron_right_rounded
                          : Icons.circle,
                      color: clickable ? _accent : _muted,
                      size: clickable && !item.bullet ? 18 : 7,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.label,
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
        action: _FooterAction.whatsapp,
        icon: Icons.chat_rounded,
        color: const Color(0xFF25D366),
      ),
      if (settings.facebookLink.isNotEmpty)
        const _SocialItem(
          label: 'Facebook',
          action: _FooterAction.facebook,
          icon: Icons.facebook_rounded,
          color: Color(0xFF1877F2),
        ),
      if (settings.messengerLink.isNotEmpty)
        const _SocialItem(
          label: 'Messenger',
          action: _FooterAction.messenger,
          icon: Icons.message_rounded,
          color: Color(0xFF8A3FFC),
        ),
      if (settings.instagramLink.isNotEmpty)
        const _SocialItem(
          label: 'Instagram',
          action: _FooterAction.instagram,
          icon: Icons.camera_alt_rounded,
          color: Color(0xFFE1306C),
        ),
      if (settings.youtubeLink.isNotEmpty)
        const _SocialItem(
          label: 'YouTube',
          action: _FooterAction.youtube,
          icon: Icons.play_arrow_rounded,
          color: Color(0xFFFF0000),
        ),
      if (settings.tiktokLink.isNotEmpty)
        const _SocialItem(
          label: 'TikTok',
          action: _FooterAction.tiktok,
          icon: Icons.music_note_rounded,
          color: Color(0xFF111827),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnTitle(settings.footerSocialTitle),
        const SizedBox(height: 18),
        ...items.map(
              (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => _handleFooterAction(context, item.action, settings),
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
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
    final copyright = settings.copyrightText.trim().isNotEmpty
        ? settings.copyrightText.trim().replaceAll('{year}', '$year')
        : '© $year ${settings.pharmacyName}. All rights reserved.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 70, vertical: 16),
      decoration: BoxDecoration(
        color: _bottomBg,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: isMobile
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(copyright, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 10),
          _paymentBadges(settings),
        ],
      )
          : Row(
        children: [
          Expanded(
            child: Text(copyright, style: const TextStyle(color: _muted, fontSize: 12)),
          ),
          _paymentBadges(settings),
        ],
      ),
    );
  }

  Widget _paymentBadges(AppSettings settings) {
    final items = settings.paymentBadges;
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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

enum _FooterAction {
  none,
  about,
  terms,
  privacy,
  dataDeletion,
  returnPolicy,
  contact,
  faq,
  phone,
  email,
  map,
  whatsapp,
  facebook,
  messenger,
  instagram,
  youtube,
  tiktok,
}

class _FooterItem {
  final String label;
  final _FooterAction action;
  final bool bullet;

  const _FooterItem(this.label, this.action, {this.bullet = false});
}

class _SocialItem {
  final String label;
  final _FooterAction action;
  final IconData icon;
  final Color color;

  const _SocialItem({
    required this.label,
    required this.action,
    required this.icon,
    required this.color,
  });
}
