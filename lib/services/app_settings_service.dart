import 'package:cloud_firestore/cloud_firestore.dart';

class AppSettingsService {
  AppSettingsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('settings').doc('app');

  static AppSettings? _cached;
  static Stream<AppSettings>? _sharedStream;

  /// Enterprise single pipeline:
  /// Header, footer, legal pages and other widgets can listen to this method.
  /// The underlying Firestore listener is shared while active, and the latest
  /// settings object is kept in memory for instant fallback rendering.
  static Stream<AppSettings> watch() {
    _sharedStream ??= _ref.snapshots().map((doc) {
      final settings = AppSettings.fromMap(doc.data() ?? {});
      _cached = settings;
      return settings;
    }).asBroadcastStream();

    return _sharedStream!;
  }

  static AppSettings get cached => _cached ?? AppSettings.defaults();

  static Future<AppSettings> getOnce({bool forceServer = false}) async {
    if (!forceServer && _cached != null) return _cached!;
    final doc = await _ref.get();
    final settings = AppSettings.fromMap(doc.data() ?? {});
    _cached = settings;
    return settings;
  }
}

class AppSettings {
  final String pharmacyName;
  final String supportPhone;
  final String whatsappNumber;
  final String email;
  final String address;
  final String googleMapLink;
  final String businessHours;

  final String websiteUrl;
  final String appDomain;
  final String privacyPolicyUrl;
  final String termsUrl;
  final String dataDeletionUrl;
  final String aboutUsUrl;
  final String contactUrl;
  final String faqUrl;
  final String returnPolicyUrl;

  final String logoUrl;
  final String faviconUrl;
  final bool showHeaderLogo;
  final String headerNotice;
  final String searchPlaceholder;
  final String tagline;

  final String footerQuickLinksTitle;
  final String footerSupportTitle;
  final String footerAddressTitle;
  final String footerLegalTitle;
  final String footerSocialTitle;
  final String footerAboutLabel;
  final String footerTermsLabel;
  final String footerPrivacyLabel;
  final String footerDataDeletionLabel;
  final String footerReturnPolicyLabel;
  final String footerContactLabel;
  final String footerFaqLabel;
  final String copyrightText;
  final List<String> paymentBadges;

  final String tradeLicenseNo;
  final String dbidNo;

  final bool maintenanceMode;
  final bool forceUpdate;
  final bool blockRegistration;
  final bool disableCOD;

  final bool showFlashSale;
  final bool showSponsoredProducts;
  final bool showTopVendors;
  final bool showHomeBanners;

  final bool enableReferral;
  final bool enableChalakCharCash;
  final bool enableOrderNotifications;
  final bool enableAdminNotifications;
  final bool enableRiderNotifications;

  final String facebookLink;
  final String messengerLink;
  final String instagramLink;
  final String youtubeLink;
  final String tiktokLink;
  final String helpYoutubeLink;
  final String referralYoutubeLink;

  const AppSettings({
    required this.pharmacyName,
    required this.supportPhone,
    required this.whatsappNumber,
    required this.email,
    required this.address,
    required this.googleMapLink,
    required this.businessHours,
    required this.websiteUrl,
    required this.appDomain,
    required this.privacyPolicyUrl,
    required this.termsUrl,
    required this.dataDeletionUrl,
    required this.aboutUsUrl,
    required this.contactUrl,
    required this.faqUrl,
    required this.returnPolicyUrl,
    required this.logoUrl,
    required this.faviconUrl,
    required this.showHeaderLogo,
    required this.headerNotice,
    required this.searchPlaceholder,
    required this.tagline,
    required this.footerQuickLinksTitle,
    required this.footerSupportTitle,
    required this.footerAddressTitle,
    required this.footerLegalTitle,
    required this.footerSocialTitle,
    required this.footerAboutLabel,
    required this.footerTermsLabel,
    required this.footerPrivacyLabel,
    required this.footerDataDeletionLabel,
    required this.footerReturnPolicyLabel,
    required this.footerContactLabel,
    required this.footerFaqLabel,
    required this.copyrightText,
    required this.paymentBadges,
    required this.tradeLicenseNo,
    required this.dbidNo,
    required this.maintenanceMode,
    required this.forceUpdate,
    required this.blockRegistration,
    required this.disableCOD,
    required this.showFlashSale,
    required this.showSponsoredProducts,
    required this.showTopVendors,
    required this.showHomeBanners,
    required this.enableReferral,
    required this.enableChalakCharCash,
    required this.enableOrderNotifications,
    required this.enableAdminNotifications,
    required this.enableRiderNotifications,
    required this.facebookLink,
    required this.messengerLink,
    required this.instagramLink,
    required this.youtubeLink,
    required this.tiktokLink,
    required this.helpYoutubeLink,
    required this.referralYoutubeLink,
  });

  factory AppSettings.defaults() => AppSettings.fromMap(const {});

  factory AppSettings.fromMap(Map<String, dynamic> data) {
    String text(dynamic value, String fallback) {
      final t = (value ?? '').toString().trim();
      return t.isEmpty ? fallback : t;
    }

    bool boolValue(dynamic value, bool fallback) {
      if (value == null) return fallback;
      if (value is bool) return value;
      final t = value.toString().trim().toLowerCase();
      if (t == 'true' || t == '1' || t == 'yes') return true;
      if (t == 'false' || t == '0' || t == 'no') return false;
      return fallback;
    }

    Map<String, dynamic> mapValue(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    List<String> stringList(dynamic value, List<String> fallback) {
      if (value is List) {
        final list = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return list.isEmpty ? fallback : list;
      }
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) return fallback;
      final list = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return list.isEmpty ? fallback : list;
    }

    String cleanSiteUrl(String value) {
      var v = value.trim();
      if (v.isEmpty) return 'https://chalakcharmart.com';
      if (!v.startsWith('http://') && !v.startsWith('https://')) {
        v = 'https://$v';
      }
      return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
    }

    String domainFromUrl(String url) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) return uri.host.replaceFirst('www.', '');
      return url.replaceAll('https://', '').replaceAll('http://', '').split('/').first.replaceFirst('www.', '');
    }

    String urlFrom(dynamic value, String path, String websiteUrl) {
      final raw = (value ?? '').toString().trim();
      if (raw.isNotEmpty) return raw;
      return '$websiteUrl$path';
    }

    final socialLinks = mapValue(data['socialLinks']);
    final websiteUrl = cleanSiteUrl(text(data['websiteUrl'] ?? data['companyWebsite'], 'https://chalakcharmart.com'));
    final appDomain = text(data['appDomain'] ?? data['domain'], domainFromUrl(websiteUrl));

    return AppSettings(
      pharmacyName: text(data['pharmacyName'] ?? data['companyName'], 'ChalakChar Mart'),
      supportPhone: text(data['supportPhone'], '01975838764'),
      whatsappNumber: text(data['whatsappNumber'] ?? socialLinks['whatsapp'], '01975838764'),
      email: text(data['email'] ?? data['supportEmail'], 'chalakcharmart@gmail.com'),
      address: text(data['address'], 'Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh'),
      googleMapLink: text(data['googleMapLink'], ''),
      businessHours: text(data['businessHours'], '9:00 AM - 11:00 PM'),

      websiteUrl: websiteUrl,
      appDomain: appDomain,
      privacyPolicyUrl: urlFrom(data['privacyPolicyUrl'], '/privacy-policy', websiteUrl),
      termsUrl: urlFrom(data['termsUrl'] ?? data['termsOfServiceUrl'], '/terms-conditions', websiteUrl),
      dataDeletionUrl: urlFrom(data['dataDeletionUrl'], '/data-deletion', websiteUrl),
      aboutUsUrl: urlFrom(data['aboutUsUrl'], '/about-us', websiteUrl),
      contactUrl: urlFrom(data['contactUrl'], '/contact', websiteUrl),
      faqUrl: urlFrom(data['faqUrl'], '/faq', websiteUrl),
      returnPolicyUrl: urlFrom(data['returnPolicyUrl'], '/return-policy', websiteUrl),

      logoUrl: text(data['logoUrl'], ''),
      faviconUrl: text(data['faviconUrl'], ''),
      showHeaderLogo: boolValue(data['showHeaderLogo'], true),
      headerNotice: text(data['headerNotice'], ''),
      searchPlaceholder: text(data['searchPlaceholder'], 'Search ChalakChar Mart'),
      tagline: text(data['tagline'], 'সব প্রয়োজন, এক জায়গায়'),

      footerQuickLinksTitle: text(data['footerQuickLinksTitle'], 'Quick Links'),
      footerSupportTitle: text(data['footerSupportTitle'], 'Support'),
      footerAddressTitle: text(data['footerAddressTitle'], 'Address'),
      footerLegalTitle: text(data['footerLegalTitle'], 'Legal'),
      footerSocialTitle: text(data['footerSocialTitle'], 'Social'),
      footerAboutLabel: text(data['footerAboutLabel'], 'About us'),
      footerTermsLabel: text(data['footerTermsLabel'], 'Terms & Conditions'),
      footerPrivacyLabel: text(data['footerPrivacyLabel'], 'Privacy Policy'),
      footerDataDeletionLabel: text(data['footerDataDeletionLabel'], 'Data Deletion'),
      footerReturnPolicyLabel: text(data['footerReturnPolicyLabel'], 'Return Policy'),
      footerContactLabel: text(data['footerContactLabel'], 'Contact Us'),
      footerFaqLabel: text(data['footerFaqLabel'], 'FAQ'),
      copyrightText: text(data['copyrightText'], ''),
      paymentBadges: stringList(data['paymentBadges'], const ['COD', 'bKash', 'Nagad', 'Card']),

      tradeLicenseNo: text(data['tradeLicenseNo'], ''),
      dbidNo: text(data['dbidNo'], ''),

      maintenanceMode: boolValue(data['maintenanceMode'], false),
      forceUpdate: boolValue(data['forceUpdate'], false),
      blockRegistration: boolValue(data['blockRegistration'], false),
      disableCOD: boolValue(data['disableCOD'], false),

      showFlashSale: boolValue(data['showFlashSale'], true),
      showSponsoredProducts: boolValue(data['showSponsoredProducts'], true),
      showTopVendors: boolValue(data['showTopVendors'], true),
      showHomeBanners: boolValue(data['showHomeBanners'], true),

      enableReferral: boolValue(data['enableReferral'], true),
      enableChalakCharCash: boolValue(data['enableChalakCharCash'] ?? data['enableAbdCash'], true),
      enableOrderNotifications: boolValue(data['enableOrderNotifications'], true),
      enableAdminNotifications: boolValue(data['enableAdminNotifications'], true),
      enableRiderNotifications: boolValue(data['enableRiderNotifications'], true),

      facebookLink: text(data['facebookLink'] ?? socialLinks['facebook'], ''),
      messengerLink: text(data['messengerLink'] ?? socialLinks['messenger'], ''),
      instagramLink: text(data['instagramLink'] ?? socialLinks['instagram'], ''),
      youtubeLink: text(data['youtubeLink'] ?? socialLinks['youtube'], ''),
      tiktokLink: text(data['tiktokLink'] ?? socialLinks['tiktok'], ''),
      helpYoutubeLink: text(data['helpYoutubeLink'], ''),
      referralYoutubeLink: text(data['referralYoutubeLink'], ''),
    );
  }
}
