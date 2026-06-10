import 'package:cloud_firestore/cloud_firestore.dart';

class AppSettingsService {
  AppSettingsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection('settings').doc('app');

  static Stream<AppSettings> watch() {
    return _ref.snapshots().map((doc) {
      return AppSettings.fromMap(doc.data() ?? {});
    });
  }

  static Future<AppSettings> getOnce() async {
    final doc = await _ref.get();
    return AppSettings.fromMap(doc.data() ?? {});
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

  final String tradeLicenseNo;
  final String dbidNo;
  final String drugLicenseNo;

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
    required this.tradeLicenseNo,
    required this.dbidNo,
    required this.drugLicenseNo,
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

  factory AppSettings.fromMap(Map<String, dynamic> data) {
    String text(dynamic value, String fallback) {
      final t = (value ?? '').toString().trim();
      return t.isEmpty ? fallback : t;
    }

    bool boolValue(dynamic value, bool fallback) {
      if (value == null) return fallback;
      return value == true;
    }

    return AppSettings(
      pharmacyName: text(data['pharmacyName'], 'ChalakChar Mart'),
      supportPhone: text(data['supportPhone'], '01975838764'),
      whatsappNumber: text(data['whatsappNumber'], '01975838764'),
      email: text(data['email'], 'chalakcharmart@gmail.com'),
      address: text(data['address'], 'Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh'),
      googleMapLink: text(data['googleMapLink'], ''),
      businessHours: text(data['businessHours'], '9:00 AM - 11:00 PM'),

      tradeLicenseNo: text(data['tradeLicenseNo'], ''),
      dbidNo: text(data['dbidNo'], ''),
      drugLicenseNo: text(data['drugLicenseNo'], ''),

      maintenanceMode: boolValue(data['maintenanceMode'], false),
      forceUpdate: boolValue(data['forceUpdate'], false),
      blockRegistration: boolValue(data['blockRegistration'], false),
      disableCOD: boolValue(data['disableCOD'], false),

      showFlashSale: boolValue(data['showFlashSale'], true),
      showSponsoredProducts: boolValue(data['showSponsoredProducts'], true),
      showTopVendors: boolValue(data['showTopVendors'], true),
      showHomeBanners: boolValue(data['showHomeBanners'], true),

      enableReferral: boolValue(data['enableReferral'], true),enableChalakCharCash: boolValue(
      data['enableChalakCharCash'] ?? data['enableAbdCash'],
      true,
    ),
      enableOrderNotifications: boolValue(data['enableOrderNotifications'], true),
      enableAdminNotifications: boolValue(data['enableAdminNotifications'], true),
      enableRiderNotifications: boolValue(data['enableRiderNotifications'], true),

      facebookLink: text(data['facebookLink'], ''),
      messengerLink: text(data['messengerLink'], ''),
      instagramLink: text(data['instagramLink'], ''),
      youtubeLink: text(data['youtubeLink'], ''),
      tiktokLink: text(data['tiktokLink'], ''),
      helpYoutubeLink: text(data['helpYoutubeLink'], ''),
      referralYoutubeLink: text(data['referralYoutubeLink'], ''),
    );
  }
}