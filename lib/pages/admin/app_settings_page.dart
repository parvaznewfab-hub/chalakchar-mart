import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/image_upload_service.dart';
import '../../services/tiktok_connection_service.dart';


class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  final formKey = GlobalKey<FormState>();

  final pharmacyNameController = TextEditingController();
  final supportPhoneController = TextEditingController();
  final whatsappController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  final googleMapController = TextEditingController();
  final businessHoursController = TextEditingController();
  final logoUrlController = TextEditingController();
  final faviconUrlController = TextEditingController();
  final websiteUrlController = TextEditingController();
  final appDomainController = TextEditingController();
  final privacyPolicyUrlController = TextEditingController();
  final termsUrlController = TextEditingController();
  final dataDeletionUrlController = TextEditingController();
  final headerNoticeController = TextEditingController();
  final searchPlaceholderController = TextEditingController();
  final taglineController = TextEditingController();
  final footerQuickLinksTitleController = TextEditingController();
  final footerSupportTitleController = TextEditingController();
  final footerAddressTitleController = TextEditingController();
  final footerLegalTitleController = TextEditingController();
  final footerSocialTitleController = TextEditingController();
  final footerAboutLabelController = TextEditingController();
  final footerTermsLabelController = TextEditingController();
  final footerPrivacyLabelController = TextEditingController();
  final footerDataDeletionLabelController = TextEditingController();
  final footerReturnPolicyLabelController = TextEditingController();
  final footerContactLabelController = TextEditingController();
  final footerFaqLabelController = TextEditingController();
  final copyrightTextController = TextEditingController();
  final paymentBadgesController = TextEditingController();

  final tradeLicenseController = TextEditingController();
  final dbidController = TextEditingController();

  final minimumOrderController = TextEditingController();
  final freeDeliveryMinController = TextEditingController();
  final localDeliveryController = TextEditingController();
  final outsideDeliveryController = TextEditingController();
  final expressDeliveryController = TextEditingController();
  final autoCancelMinutesController = TextEditingController();

  final referralRewardController = TextEditingController();
  final refereeRewardController = TextEditingController();
  final maxAbdCashRedeemController = TextEditingController();
  final referralSearchController = TextEditingController();

  final helpYoutubeController = TextEditingController();
  final referralYoutubeController = TextEditingController();
  final facebookController = TextEditingController();
  final messengerController = TextEditingController();
  final instagramController = TextEditingController();
  final youtubeController = TextEditingController();
  final tiktokController = TextEditingController();

  final facebookPageIdController = TextEditingController();
  final facebookPageTokenController = TextEditingController();
  final instagramBusinessIdController = TextEditingController();
  final instagramAccessTokenController = TextEditingController();
  final whatsappPhoneNumberIdController = TextEditingController();
  final whatsappAccessTokenController = TextEditingController();
  final whatsappTemplateController = TextEditingController();
  final tiktokClientKeyController = TextEditingController();
  // tiktokClientSecretController removed: the client secret must live only in
  // Firebase Secret Manager (functions/tiktok/config.js), never in the
  // world-readable settings/app document or a Flutter text field.
  final defaultMarketingCaptionController = TextEditingController();

  final aliExpressMarkupController = TextEditingController();
  final importExchangeRateController = TextEditingController();
  final importMinimumProfitController = TextEditingController();
  final importCurrencyController = TextEditingController();

  bool loading = true;
  bool saving = false;
  bool uploadingLogo = false;
  bool uploadingFavicon = false;
  bool canViewSettings = false;
  bool canEditSettings = false;

  bool maintenanceMode = false;
  bool forceUpdate = false;
  bool blockRegistration = false;
  bool disableCOD = false;
  bool showHeaderLogo = true;

  bool showFlashSale = true;
  bool showSponsoredProducts = true;
  bool showTopVendors = true;
  bool showHomeBanners = true;
  bool enableReferral = true;
  bool enableAbdCash = true;
  bool enableOrderNotifications = true;
  bool enableAdminNotifications = true;
  bool enableRiderNotifications = true;

  bool autoMarketingEnabled = true;
  bool defaultPushMarketing = true;
  bool defaultInAppMarketing = true;
  bool defaultFacebookQueue = false;
  bool defaultInstagramQueue = false;
  bool defaultWhatsappQueue = false;
  bool defaultMessengerQueue = false;
  bool defaultTiktokQueue = false;
  bool hideSocialTokens = true;

  bool importAutoPublish = false;
  bool importEnableAi = true;
  bool importEnableSeo = true;
  bool importEnableMarketing = true;
  String importRoundingMode = 'none';

  String defaultMarketingAudience = 'everyone';
  String defaultMarketingPublishTime = 'immediately';

  String referralStatusFilter = 'all';
  String referralSearchText = '';

  @override
  void initState() {
    super.initState();
    _initPermissionAndLoad();
  }

  Future<void> _initPermissionAndLoad() async {
    try {
      final canAccessAdmin = await authService.canAccessAdminPanel();
      final view = await authService.hasPermission('settings.view');
      final edit = await authService.hasPermission('settings.edit');

      if (!mounted) return;
      setState(() {
        canViewSettings = canAccessAdmin && (view || edit);
        canEditSettings = canAccessAdmin && edit;
      });

      if (canViewSettings) {
        await _loadSettings();
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Permission check failed: $e');
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    pharmacyNameController.dispose();
    supportPhoneController.dispose();
    whatsappController.dispose();
    emailController.dispose();
    addressController.dispose();
    googleMapController.dispose();
    businessHoursController.dispose();
    logoUrlController.dispose();
    faviconUrlController.dispose();
    websiteUrlController.dispose();
    appDomainController.dispose();
    privacyPolicyUrlController.dispose();
    termsUrlController.dispose();
    dataDeletionUrlController.dispose();
    headerNoticeController.dispose();
    searchPlaceholderController.dispose();
    taglineController.dispose();
    footerQuickLinksTitleController.dispose();
    footerSupportTitleController.dispose();
    footerAddressTitleController.dispose();
    footerLegalTitleController.dispose();
    footerSocialTitleController.dispose();
    footerAboutLabelController.dispose();
    footerTermsLabelController.dispose();
    footerPrivacyLabelController.dispose();
    footerDataDeletionLabelController.dispose();
    footerReturnPolicyLabelController.dispose();
    footerContactLabelController.dispose();
    footerFaqLabelController.dispose();
    copyrightTextController.dispose();
    paymentBadgesController.dispose();

    tradeLicenseController.dispose();
    dbidController.dispose();

    minimumOrderController.dispose();
    freeDeliveryMinController.dispose();
    localDeliveryController.dispose();
    outsideDeliveryController.dispose();
    expressDeliveryController.dispose();
    autoCancelMinutesController.dispose();

    referralRewardController.dispose();
    refereeRewardController.dispose();
    maxAbdCashRedeemController.dispose();
    referralSearchController.dispose();

    helpYoutubeController.dispose();
    referralYoutubeController.dispose();
    facebookController.dispose();
    messengerController.dispose();
    instagramController.dispose();
    youtubeController.dispose();
    tiktokController.dispose();

    facebookPageIdController.dispose();
    facebookPageTokenController.dispose();
    instagramBusinessIdController.dispose();
    instagramAccessTokenController.dispose();
    whatsappPhoneNumberIdController.dispose();
    whatsappAccessTokenController.dispose();
    whatsappTemplateController.dispose();
    tiktokClientKeyController.dispose();
    defaultMarketingCaptionController.dispose();
    aliExpressMarkupController.dispose();
    importExchangeRateController.dispose();
    importMinimumProfitController.dispose();
    importCurrencyController.dispose();

    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _double(dynamic value, double fallback) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _int(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  bool _bool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    return value == true;
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await db.collection('settings').doc('app').get();
      final data = doc.data() ?? {};

      pharmacyNameController.text = _text(data['pharmacyName'], 'ChalakChar Mart');
      supportPhoneController.text = _text(data['supportPhone'], '01975838764');
      whatsappController.text = _text(data['whatsappNumber'], '01975838764');
      emailController.text = _text(data['email'], 'chalakcharmart@gmail.com');
      addressController.text = _text(data['address'], 'Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh');
      googleMapController.text = _text(data['googleMapLink']);
      businessHoursController.text = _text(data['businessHours'], '9:00 AM - 11:00 PM');
      logoUrlController.text = _text(data['logoUrl']);
      faviconUrlController.text = _text(data['faviconUrl']);
      websiteUrlController.text = _text(data['websiteUrl'], 'https://chalakcharmart.com');
      appDomainController.text = _text(data['appDomain'], 'chalakcharmart.com');
      privacyPolicyUrlController.text = _text(data['privacyPolicyUrl'], 'https://chalakcharmart.com/privacy-policy');
      termsUrlController.text = _text(data['termsUrl'] ?? data['termsOfServiceUrl'], 'https://chalakcharmart.com/terms-conditions');
      dataDeletionUrlController.text = _text(data['dataDeletionUrl'], 'https://chalakcharmart.com/data-deletion');
      headerNoticeController.text = _text(data['headerNotice']);
      searchPlaceholderController.text = _text(data['searchPlaceholder'], 'Search ChalakChar Mart');
      taglineController.text = _text(data['tagline'], 'সব প্রয়োজন, এক জায়গায়');
      footerQuickLinksTitleController.text = _text(data['footerQuickLinksTitle'], 'Quick Links');
      footerSupportTitleController.text = _text(data['footerSupportTitle'], 'Support');
      footerAddressTitleController.text = _text(data['footerAddressTitle'], 'Address');
      footerLegalTitleController.text = _text(data['footerLegalTitle'], 'Legal');
      footerSocialTitleController.text = _text(data['footerSocialTitle'], 'Social');
      footerAboutLabelController.text = _text(data['footerAboutLabel'], 'About us');
      footerTermsLabelController.text = _text(data['footerTermsLabel'], 'Terms & Conditions');
      footerPrivacyLabelController.text = _text(data['footerPrivacyLabel'], 'Privacy Policy');
      footerDataDeletionLabelController.text = _text(data['footerDataDeletionLabel'], 'Data Deletion');
      footerReturnPolicyLabelController.text = _text(data['footerReturnPolicyLabel'], 'Return Policy');
      footerContactLabelController.text = _text(data['footerContactLabel'], 'Contact Us');
      footerFaqLabelController.text = _text(data['footerFaqLabel'], 'FAQ');
      copyrightTextController.text = _text(data['copyrightText'], '');
      final paymentBadges = data['paymentBadges'];
      paymentBadgesController.text = paymentBadges is List
          ? paymentBadges.map((e) => e.toString()).join(', ')
          : _text(paymentBadges, 'COD, bKash, Nagad, Card');

      tradeLicenseController.text = _text(data['tradeLicenseNo'], '528');
      dbidController.text = _text(data['dbidNo'], '000000000');

      minimumOrderController.text = _double(data['minimumOrderAmount'], 300).toStringAsFixed(0);
      freeDeliveryMinController.text = _double(data['freeDeliveryMinAmount'], 0).toStringAsFixed(0);
      localDeliveryController.text = _double(data['localDeliveryCharge'], 50).toStringAsFixed(0);
      outsideDeliveryController.text = _double(data['outsideDeliveryCharge'], 110).toStringAsFixed(0);
      expressDeliveryController.text = _double(data['expressDeliveryCharge'], 0).toStringAsFixed(0);
      autoCancelMinutesController.text = _int(data['autoCancelMinutes'], 60).toString();

      referralRewardController.text = _double(data['referralReward'], 50).toStringAsFixed(0);
      refereeRewardController.text = _double(data['refereeReward'], 50).toStringAsFixed(0);
      maxAbdCashRedeemController.text = _double(data['maxAbdCashRedeem'], 100).toStringAsFixed(0);

      helpYoutubeController.text = _text(data['helpYoutubeLink']);
      referralYoutubeController.text = _text(data['referralYoutubeLink']);

      final socialLinks = data['socialLinks'] is Map
          ? Map<String, dynamic>.from(data['socialLinks'] as Map)
          : <String, dynamic>{};

      facebookController.text = _text(data['facebookLink'] ?? socialLinks['facebook']);
      messengerController.text = _text(data['messengerLink'] ?? socialLinks['messenger']);
      instagramController.text = _text(data['instagramLink'] ?? socialLinks['instagram']);
      youtubeController.text = _text(data['youtubeLink'] ?? socialLinks['youtube']);
      tiktokController.text = _text(data['tiktokLink'] ?? socialLinks['tiktok']);

      final socialApi = data['socialApi'] is Map
          ? Map<String, dynamic>.from(data['socialApi'] as Map)
          : <String, dynamic>{};

      final marketingDefaults = data['marketingDefaults'] is Map
          ? Map<String, dynamic>.from(data['marketingDefaults'] as Map)
          : <String, dynamic>{};

      final importSettings = data['importSettings'] is Map
          ? Map<String, dynamic>.from(data['importSettings'] as Map)
          : <String, dynamic>{};

      facebookPageIdController.text = _text(socialApi['facebookPageId'] ?? data['facebookPageId']);
      facebookPageTokenController.text = _text(socialApi['facebookPageAccessToken'] ?? data['facebookPageAccessToken']);
      instagramBusinessIdController.text = _text(socialApi['instagramBusinessId'] ?? data['instagramBusinessId']);
      instagramAccessTokenController.text = _text(socialApi['instagramAccessToken'] ?? data['instagramAccessToken']);
      whatsappPhoneNumberIdController.text = _text(socialApi['whatsappPhoneNumberId'] ?? data['whatsappPhoneNumberId']);
      whatsappAccessTokenController.text = _text(socialApi['whatsappAccessToken'] ?? data['whatsappAccessToken']);
      whatsappTemplateController.text = _text(socialApi['whatsappTemplateName'] ?? data['whatsappTemplateName'], 'new_product_alert');
      tiktokClientKeyController.text = _text(socialApi['tiktokClientKey'] ?? data['tiktokClientKey']);
      defaultMarketingCaptionController.text = _text(
        marketingDefaults['captionTemplate'] ?? data['defaultMarketingCaption'],
        '🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}',
      );

      autoMarketingEnabled = _bool(marketingDefaults['enabled'] ?? data['autoMarketingEnabled'], true);
      defaultPushMarketing = _bool(marketingDefaults['pushNotification'] ?? data['defaultPushMarketing'], true);
      defaultInAppMarketing = _bool(marketingDefaults['inAppNotification'] ?? data['defaultInAppMarketing'], true);
      defaultFacebookQueue = _bool(marketingDefaults['facebook'] ?? data['defaultFacebookQueue'], false);
      defaultInstagramQueue = _bool(marketingDefaults['instagram'] ?? data['defaultInstagramQueue'], false);
      defaultWhatsappQueue = _bool(marketingDefaults['whatsapp'] ?? data['defaultWhatsappQueue'], false);
      defaultMessengerQueue = _bool(marketingDefaults['messenger'] ?? data['defaultMessengerQueue'], false);
      defaultTiktokQueue = _bool(marketingDefaults['tiktok'] ?? data['defaultTiktokQueue'], false);
      defaultMarketingAudience = _text(marketingDefaults['audience'] ?? data['defaultMarketingAudience'], 'everyone');
      defaultMarketingPublishTime = _text(marketingDefaults['publishTime'] ?? data['defaultMarketingPublishTime'], 'immediately');

      aliExpressMarkupController.text = _double(importSettings['aliExpressMarkupPercent'], 10).toStringAsFixed(2);
      importExchangeRateController.text = _double(importSettings['exchangeRate'], 1).toStringAsFixed(4);
      importMinimumProfitController.text = _double(importSettings['minimumProfit'], 0).toStringAsFixed(2);
      importCurrencyController.text = _text(importSettings['currency'], 'BDT').toUpperCase();
      importAutoPublish = _bool(importSettings['autoPublish'], false);
      importEnableAi = _bool(importSettings['enableAi'], true);
      importEnableSeo = _bool(importSettings['enableSeo'], true);
      importEnableMarketing = _bool(importSettings['enableMarketing'], true);
      importRoundingMode = _text(importSettings['roundingMode'], 'none');

      maintenanceMode = _bool(data['maintenanceMode'], false);
      forceUpdate = _bool(data['forceUpdate'], false);
      blockRegistration = _bool(data['blockRegistration'], false);
      disableCOD = _bool(data['disableCOD'], false);
      showHeaderLogo = _bool(data['showHeaderLogo'], true);

      showFlashSale = _bool(data['showFlashSale'], true);
      showSponsoredProducts = _bool(data['showSponsoredProducts'], true);
      showTopVendors = _bool(data['showTopVendors'], true);
      showHomeBanners = _bool(data['showHomeBanners'], true);

      enableReferral = _bool(data['enableReferral'], true);
      enableAbdCash = _bool(data['enableAbdCash'], true);
      enableOrderNotifications = _bool(data['enableOrderNotifications'], true);
      enableAdminNotifications = _bool(data['enableAdminNotifications'], true);
      enableRiderNotifications = _bool(data['enableRiderNotifications'], true);
    } catch (e) {
      _snack('Settings load failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!canEditSettings) {
      _snack('You do not have permission to edit settings.');
      return;
    }

    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      await db.collection('settings').doc('app').set({
        'pharmacyName': pharmacyNameController.text.trim(),
        'supportPhone': supportPhoneController.text.trim(),
        'whatsappNumber': whatsappController.text.trim(),
        'email': emailController.text.trim(),
        'address': addressController.text.trim(),
        'googleMapLink': googleMapController.text.trim(),
        'businessHours': businessHoursController.text.trim(),
        'logoUrl': logoUrlController.text.trim(),
        'faviconUrl': faviconUrlController.text.trim(),
        'showHeaderLogo': showHeaderLogo,
        'websiteUrl': websiteUrlController.text.trim(),
        'appDomain': appDomainController.text.trim(),
        'privacyPolicyUrl': privacyPolicyUrlController.text.trim(),
        'termsUrl': termsUrlController.text.trim(),
        'dataDeletionUrl': dataDeletionUrlController.text.trim(),
        'headerNotice': headerNoticeController.text.trim(),
        'searchPlaceholder': searchPlaceholderController.text.trim(),
        'tagline': taglineController.text.trim(),
        'footerQuickLinksTitle': footerQuickLinksTitleController.text.trim(),
        'footerSupportTitle': footerSupportTitleController.text.trim(),
        'footerAddressTitle': footerAddressTitleController.text.trim(),
        'footerLegalTitle': footerLegalTitleController.text.trim(),
        'footerSocialTitle': footerSocialTitleController.text.trim(),
        'footerAboutLabel': footerAboutLabelController.text.trim(),
        'footerTermsLabel': footerTermsLabelController.text.trim(),
        'footerPrivacyLabel': footerPrivacyLabelController.text.trim(),
        'footerDataDeletionLabel': footerDataDeletionLabelController.text.trim(),
        'footerReturnPolicyLabel': footerReturnPolicyLabelController.text.trim(),
        'footerContactLabel': footerContactLabelController.text.trim(),
        'footerFaqLabel': footerFaqLabelController.text.trim(),
        'copyrightText': copyrightTextController.text.trim(),
        'paymentBadges': paymentBadgesController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),

        'tradeLicenseNo': tradeLicenseController.text.trim(),
        'dbidNo': dbidController.text.trim(),

        'minimumOrderAmount': double.tryParse(minimumOrderController.text.trim()) ?? 300,
        'freeDeliveryMinAmount': double.tryParse(freeDeliveryMinController.text.trim()) ?? 0,
        'localDeliveryCharge': double.tryParse(localDeliveryController.text.trim()) ?? 50,
        'outsideDeliveryCharge': double.tryParse(outsideDeliveryController.text.trim()) ?? 110,
        'expressDeliveryCharge': double.tryParse(expressDeliveryController.text.trim()) ?? 0,
        'autoCancelMinutes': int.tryParse(autoCancelMinutesController.text.trim()) ?? 60,

        'referralReward': double.tryParse(referralRewardController.text.trim()) ?? 50,
        'refereeReward': double.tryParse(refereeRewardController.text.trim()) ?? 50,
        'maxAbdCashRedeem': double.tryParse(maxAbdCashRedeemController.text.trim()) ?? 100,

        'helpYoutubeLink': helpYoutubeController.text.trim(),
        'referralYoutubeLink': referralYoutubeController.text.trim(),
        'facebookLink': facebookController.text.trim(),
        'messengerLink': messengerController.text.trim(),
        'instagramLink': instagramController.text.trim(),
        'youtubeLink': youtubeController.text.trim(),
        'tiktokLink': tiktokController.text.trim(),

        'socialLinks': {
          'facebook': facebookController.text.trim(),
          'messenger': messengerController.text.trim(),
          'instagram': instagramController.text.trim(),
          'youtube': youtubeController.text.trim(),
          'tiktok': tiktokController.text.trim(),
          'whatsapp': whatsappController.text.trim(),
        },

        'socialApi': {
          'facebookPageId': facebookPageIdController.text.trim(),
          'facebookPageAccessToken': facebookPageTokenController.text.trim(),
          'instagramBusinessId': instagramBusinessIdController.text.trim(),
          'instagramAccessToken': instagramAccessTokenController.text.trim(),
          'whatsappPhoneNumberId': whatsappPhoneNumberIdController.text.trim(),
          'whatsappAccessToken': whatsappAccessTokenController.text.trim(),
          'whatsappTemplateName': whatsappTemplateController.text.trim(),
          'tiktokClientKey': tiktokClientKeyController.text.trim(),
          // tiktokClientSecret intentionally not written here — see removal
          // note on the controller declaration above.
        },

        'importSettings': {
          'aliExpressMarkupPercent': double.tryParse(aliExpressMarkupController.text.trim()) ?? 10,
          'exchangeRate': double.tryParse(importExchangeRateController.text.trim()) ?? 1,
          'minimumProfit': double.tryParse(importMinimumProfitController.text.trim()) ?? 0,
          'currency': importCurrencyController.text.trim().toUpperCase().isEmpty
              ? 'BDT'
              : importCurrencyController.text.trim().toUpperCase(),
          'roundingMode': importRoundingMode,
          'autoPublish': importAutoPublish,
          'enableAi': importEnableAi,
          'enableSeo': importEnableSeo,
          'enableMarketing': importEnableMarketing,
        },

        'marketingDefaults': {
          'enabled': autoMarketingEnabled,
          'pushNotification': defaultPushMarketing,
          'inAppNotification': defaultInAppMarketing,
          'facebook': defaultFacebookQueue,
          'instagram': defaultInstagramQueue,
          'whatsapp': defaultWhatsappQueue,
          'messenger': defaultMessengerQueue,
          'tiktok': defaultTiktokQueue,
          'audience': defaultMarketingAudience,
          'publishTime': defaultMarketingPublishTime,
          'captionTemplate': defaultMarketingCaptionController.text.trim(),
        },

        'maintenanceMode': maintenanceMode,
        'forceUpdate': forceUpdate,
        'blockRegistration': blockRegistration,
        'disableCOD': disableCOD,

        'showFlashSale': showFlashSale,
        'showSponsoredProducts': showSponsoredProducts,
        'showTopVendors': showTopVendors,
        'showHomeBanners': showHomeBanners,

        'enableReferral': enableReferral,
        'enableAbdCash': enableAbdCash,
        'enableOrderNotifications': enableOrderNotifications,
        'enableAdminNotifications': enableAdminNotifications,
        'enableRiderNotifications': enableRiderNotifications,

        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('Settings updated successfully');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }


  Future<void> _pickAndUploadBrandImage({required bool favicon}) async {
    if (!canEditSettings) {
      _snack('You do not have permission to edit settings.');
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: favicon ? 90 : 92,
      maxWidth: favicon ? 512 : 1200,
      maxHeight: favicon ? 512 : 600,
    );

    if (pickedFile == null) return;

    setState(() {
      if (favicon) {
        uploadingFavicon = true;
      } else {
        uploadingLogo = true;
      }
    });

    try {
      final folder = favicon ? 'branding/favicons' : 'branding/logos';
      final fileName = '${favicon ? 'favicon' : 'logo'}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String url = '';

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        url = await ImageUploadService.upload(null, webImage: bytes, folder: folder, fileName: fileName);
      } else {
        url = await ImageUploadService.upload(File(pickedFile.path), folder: folder, fileName: fileName);
      }

      if (url.trim().isEmpty) {
        _snack('Upload failed. Please try again.');
        return;
      }

      setState(() {
        if (favicon) {
          faviconUrlController.text = url;
        } else {
          logoUrlController.text = url;
          showHeaderLogo = true;
        }
      });

      await db.collection('settings').doc('app').set({
        favicon ? 'faviconUrl' : 'logoUrl': url,
        if (!favicon) 'showHeaderLogo': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack(favicon ? 'Favicon uploaded successfully' : 'Header logo uploaded successfully');
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (favicon) {
            uploadingFavicon = false;
          } else {
            uploadingLogo = false;
          }
        });
      }
    }
  }

  Future<void> _removeBrandImage({required bool favicon}) async {
    if (!canEditSettings) {
      _snack('You do not have permission to edit settings.');
      return;
    }

    setState(() {
      if (favicon) {
        faviconUrlController.clear();
      } else {
        logoUrlController.clear();
      }
    });

    await db.collection('settings').doc('app').set({
      favicon ? 'faviconUrl' : 'logoUrl': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _snack(favicon ? 'Favicon removed' : 'Header logo removed');
  }

  Widget _brandImageManager({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required bool favicon,
    required bool uploading,
  }) {
    final url = controller.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: favicon ? 54 : 110,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                clipBehavior: Clip.antiAlias,
                child: url.isEmpty
                    ? Icon(favicon ? Icons.web_asset_rounded : Icons.image_rounded, color: Colors.grey)
                    : Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.red),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            enabled: canEditSettings,
            decoration: InputDecoration(
              labelText: favicon ? 'Favicon URL' : 'Header Logo URL',
              prefixIcon: Icon(favicon ? Icons.web_asset_rounded : Icons.image_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: uploading || !canEditSettings ? null : () => _pickAndUploadBrandImage(favicon: favicon),
                icon: uploading
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_rounded),
                label: Text(uploading ? 'Uploading...' : 'Upload'),
              ),
              OutlinedButton.icon(
                onPressed: !canEditSettings || url.isEmpty ? null : () => _removeBrandImage(favicon: favicon),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  String? _number(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Required';
    if (double.tryParse(text) == null) return 'Enter valid number';
    return null;
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    String? hint,
    bool number = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: canEditSettings,
      maxLines: maxLines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }


  Widget _secretField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      enabled: canEditSettings,
      obscureText: hideSocialTokens,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: IconButton(
          tooltip: hideSocialTokens ? 'Show tokens' : 'Hide tokens',
          onPressed: () => setState(() => hideSocialTokens = !hideSocialTokens),
          icon: Icon(
            hideSocialTokens
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  bool _tiktokActionInFlight = false;
  Future<({String redirectUri, bool clientKeyConfigured})>? _tiktokOAuthConfigFuture;

  ({String label, Color color}) _tiktokStatusPresentation(TikTokConnectionStatus status) {
    switch (status) {
      case TikTokConnectionStatus.connected:
        return (label: 'Connected', color: Colors.green.shade700);
      case TikTokConnectionStatus.connecting:
        return (label: 'Connecting…', color: Colors.blue.shade700);
      case TikTokConnectionStatus.tokenExpiring:
        return (label: 'Token expiring soon', color: Colors.orange.shade800);
      case TikTokConnectionStatus.authorizationRevoked:
        return (label: 'Authorization revoked', color: Colors.red.shade700);
      case TikTokConnectionStatus.reconnectRequired:
        return (label: 'Reconnect required', color: Colors.red.shade700);
      case TikTokConnectionStatus.notConnected:
        return (label: 'Not connected', color: Colors.grey.shade600);
    }
  }

  Future<void> _handleTikTokConnect() async {
    setState(() => _tiktokActionInFlight = true);
    try {
      await TikTokConnectionService.instance.startConnect();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the TikTok connection. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _tiktokActionInFlight = false);
    }
  }

  Future<void> _handleTikTokDisconnect(String? connectionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect TikTok?'),
        content: const Text(
          'This revokes the stored access to this TikTok account. Product posting to TikTok will stop until it is reconnected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Disconnect')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _tiktokActionInFlight = true);
    try {
      await TikTokConnectionService.instance.disconnect(connectionId: connectionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('TikTok account disconnected.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not disconnect the TikTok account. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _tiktokActionInFlight = false);
    }
  }

  Widget _buildTikTokConnectionCard() {
    return StreamBuilder<TikTokConnectionInfo>(
      stream: TikTokConnectionService.instance.watchStatus(),
      initialData: TikTokConnectionInfo.notConnected,
      builder: (context, snapshot) {
        final info = snapshot.data ?? TikTokConnectionInfo.notConnected;
        final presentation = _tiktokStatusPresentation(info.status);
        final busy = _tiktokActionInFlight || info.status == TikTokConnectionStatus.connecting;

        final connectLabel = info.status == TikTokConnectionStatus.notConnected
            ? 'Connect TikTok'
            : 'Reconnect TikTok';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note_rounded),
                  const SizedBox(width: 8),
                  const Text('TikTok Connection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh status',
                    onPressed: busy ? null : () => TikTokConnectionService.instance.refreshNow(),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: presentation.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(presentation.label, style: TextStyle(color: presentation.color, fontWeight: FontWeight.w700)),
                  if (info.lastConnectedAt != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Connected ${info.lastConnectedAt}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (info.status != TikTokConnectionStatus.connected)
                    ElevatedButton.icon(
                      onPressed: (!canEditSettings || busy) ? null : _handleTikTokConnect,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(connectLabel),
                    ),
                  if (info.isActionable)
                    OutlinedButton.icon(
                      onPressed: (!canEditSettings || busy) ? null : () => _handleTikTokDisconnect(info.connectionId),
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Disconnect'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildTikTokRedirectUriInfo(),
            ],
          ),
        );
      },
    );
  }

  /// Read-only display of the backend's fixed OAuth callback URL, for
  /// registering in the TikTok Developer Portal. Not an input — this value
  /// cannot be changed from Flutter and does not control backend behavior.
  Widget _buildTikTokRedirectUriInfo() {
    _tiktokOAuthConfigFuture ??= TikTokConnectionService.instance.fetchOAuthConfig();

    return FutureBuilder<({String redirectUri, bool clientKeyConfigured})>(
      future: _tiktokOAuthConfigFuture,
      builder: (context, snapshot) {
        final config = snapshot.data;
        final redirectUri = config?.redirectUri ?? '';

        String helperText;
        if (snapshot.connectionState != ConnectionState.done) {
          helperText = 'Loading backend configuration…';
        } else if (redirectUri.isEmpty) {
          helperText = 'Not configured on the backend yet — set TIKTOK_REDIRECT_URI at deploy time.';
        } else {
          helperText = 'Register this exact URL in the TikTok Developer Portal. Configured on the backend only — not editable here.';
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OAuth callback URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              SelectableText(
                redirectUri.isEmpty ? '—' : redirectUri,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(helperText, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
            ],
          ),
        );
      },
    );
  }

  Widget _marketingDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    IconData? icon,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items,
      onChanged: canEditSettings ? onChanged : null,
    );
  }

  Widget _smallSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: canEditSettings ? onChanged : null,
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: const Color(0xFF1592B3)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
                  child: Icon(icon, color: const Color(0xFF1592B3)),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    bool danger = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: danger ? Colors.red.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: danger ? Colors.red.withValues(alpha: 0.25) : const Color(0xFFE5E7EB),
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: canEditSettings ? onChanged : null,
        secondary: icon == null ? null : Icon(icon, color: danger ? Colors.red : const Color(0xFF1592B3)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _responsiveGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemWidth = maxWidth >= 1150
            ? (maxWidth - 24) / 3
            : maxWidth >= 720
            ? (maxWidth - 12) / 2
            : maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map(
                (child) => SizedBox(
              width: itemWidth.clamp(260.0, maxWidth),
              child: child,
            ),
          )
              .toList(),
        );
      },
    );
  }


  Widget _quickStatsCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('settings').doc('app').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _quickPill('COD Min', '৳${_double(data['minimumOrderAmount'], 300).toStringAsFixed(0)}'),
              _quickPill('Local Delivery', '৳${_double(data['localDeliveryCharge'], 50).toStringAsFixed(0)}'),
              _quickPill('Outside', '৳${_double(data['outsideDeliveryCharge'], 110).toStringAsFixed(0)}'),
              _quickPill('Referral', '৳${_double(data['referralReward'], 50).toStringAsFixed(0)}'),
              _quickPill('Maintenance', data['maintenanceMode'] == true ? 'ON' : 'OFF'),
              _quickPill('COD', data['disableCOD'] == true ? 'OFF' : 'ON'),
            ],
          ),
        );
      },
    );
  }

  Widget _quickPill(String title, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }



  String _short(dynamic value) {
    final id = _text(value);
    return id.length > 8 ? '${id.substring(0, 8)}...' : id;
  }

  String _date(dynamic value) {
    if (value is! Timestamp) return 'N/A';
    final d = value.toDate();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  Future<Map<String, dynamic>> _userInfo(String uid) async {
    if (uid.isEmpty) return {};
    final doc = await db.collection('users').doc(uid).get();
    return doc.data() ?? {};
  }

  Future<bool?> _confirmReferralAction({
    required String title,
    required String message,
    required String confirmText,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _approveReferral(String docId, Map<String, dynamic> data) async {
    if (!canEditSettings) {
      _snack('You do not have permission to approve referrals.');
      return;
    }
    if (data['status'] == 'Approved') {
      _snack('Already approved');
      return;
    }

    final ok = await _confirmReferralAction(
      title: 'Approve Referral?',
      message: 'Reward will be added to referrer and referee accounts.',
      confirmText: 'Approve',
    );
    if (ok != true) return;

    try {
      final referrerId = _text(data['referrerId']);
      final refereeId = _text(data['refereeId']);
      final referrerReward = _int(data['referrerReward'], 0);
      final refereeReward = _int(data['refereeReward'], 0);

      if (referrerId.isEmpty || refereeId.isEmpty) {
        _snack('Invalid referral user ids');
        return;
      }

      final batch = db.batch();
      batch.update(db.collection('users').doc(referrerId), {
        'points': FieldValue.increment(referrerReward),
        'totalEarnings': FieldValue.increment(referrerReward),
        'referralCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(db.collection('users').doc(refereeId), {
        'points': FieldValue.increment(refereeReward),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(db.collection('referrals').doc(docId), {
        'status': 'Approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      _snack('Referral approved');
    } catch (e) {
      _snack('Approve failed: $e');
    }
  }

  Future<void> _rejectReferral(String docId) async {
    if (!canEditSettings) {
      _snack('You do not have permission to reject referrals.');
      return;
    }
    final ok = await _confirmReferralAction(
      title: 'Reject Referral?',
      message: 'This referral will be marked as rejected.',
      confirmText: 'Reject',
      danger: true,
    );
    if (ok != true) return;

    try {
      await db.collection('referrals').doc(docId).update({
        'status': 'Rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _snack('Referral rejected');
    } catch (e) {
      _snack('Reject failed: $e');
    }
  }

  List<QueryDocumentSnapshot> _filterReferrals(List<QueryDocumentSnapshot> docs) {
    final s = referralSearchText.toLowerCase().trim();
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'Pending');
      if (referralStatusFilter != 'all' && status != referralStatusFilter) return false;
      if (s.isEmpty) return true;
      return doc.id.toLowerCase().contains(s) ||
          _text(data['referrerId']).toLowerCase().contains(s) ||
          _text(data['refereeId']).toLowerCase().contains(s);
    }).toList();
  }

  Widget _referralApprovalsSection() {
    return _section(
      title: 'Referral Approvals',
      icon: Icons.verified_rounded,
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: db.collection('referrals').orderBy('createdAt', descending: true).limit(300).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final allDocs = snapshot.data!.docs;
            final docs = _filterReferrals(allDocs);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryGrid(allDocs),
                const SizedBox(height: 14),
                _referralFilters(),
                const SizedBox(height: 12),
                Text('Referrals (${docs.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                if (docs.isEmpty)
                  const Card(
                    elevation: 0,
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('No matching referrals')),
                    ),
                  )
                else
                  ...docs.map((doc) => _referralCard(doc.id, doc.data() as Map<String, dynamic>)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int pending = 0;
    int approved = 0;
    int rejected = 0;
    int rewardPaid = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'Pending');
      if (status == 'Approved') {
        approved++;
        rewardPaid += _int(data['referrerReward'], 0) + _int(data['refereeReward'], 0);
      } else if (status == 'Rejected') {
        rejected++;
      } else {
        pending++;
      }
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 2 : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 1 ? 4.5 : 2.15,
          children: [
            _summaryCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.orange),
            _summaryCard('Approved', '$approved', Icons.verified_rounded, Colors.green),
            _summaryCard('Rejected', '$rejected', Icons.cancel_rounded, Colors.red),
            _summaryCard('Reward Paid', '৳$rewardPaid', Icons.payments_rounded, Colors.blue),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _referralFilters() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final small = c.maxWidth < 760;
            final search = TextField(
              controller: referralSearchController,
              decoration: const InputDecoration(
                hintText: 'Search referral, referrer id, referee id...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => referralSearchText = v),
            );
            final status = DropdownButtonFormField<String>(
              initialValue: referralStatusFilter,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (v) => setState(() => referralStatusFilter = v ?? 'all'),
            );
            if (small) return Column(children: [search, const SizedBox(height: 8), status]);
            return Row(children: [Expanded(flex: 2, child: search), const SizedBox(width: 8), Expanded(child: status)]);
          },
        ),
      ),
    );
  }

  Widget _referralCard(String id, Map<String, dynamic> data) {
    final status = _text(data['status'], 'Pending');
    final referrerId = _text(data['referrerId']);
    final refereeId = _text(data['refereeId']);
    final color = status == 'Approved' ? Colors.green : status == 'Rejected' ? Colors.red : Colors.orange;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait([_userInfo(referrerId), _userInfo(refereeId)]),
      builder: (context, snap) {
        final referrer = snap.data != null && snap.data!.isNotEmpty ? snap.data![0] : <String, dynamic>{};
        final referee = snap.data != null && snap.data!.length > 1 ? snap.data![1] : <String, dynamic>{};

        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(Icons.share_rounded, color: color)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Referral #${_short(id)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                    _chip(status, color),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final referrerBox = _userBox('Referrer', referrerId, referrer, _int(data['referrerReward'], 0), Icons.person_add_alt_1_rounded);
                    final refereeBox = _userBox('Referee', refereeId, referee, _int(data['refereeReward'], 0), Icons.person_rounded);
                    if (c.maxWidth < 700) return Column(children: [referrerBox, const SizedBox(height: 8), refereeBox]);
                    return Row(children: [Expanded(child: referrerBox), const SizedBox(width: 8), Expanded(child: refereeBox)]);
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Created ${_date(data['createdAt'])}', Colors.blueGrey),
                    _chip('Total ৳${_int(data['referrerReward'], 0) + _int(data['refereeReward'], 0)}', Colors.blue),
                  ],
                ),
                if (status == 'Pending') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: canEditSettings ? () => _approveReferral(id, data) : null,
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canEditSettings ? () => _rejectReferral(id) : null,
                          icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                          label: const Text('Reject', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _userBox(String title, String id, Map<String, dynamic> user, int reward, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1592B3)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(_text(user['name'], _short(id)), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_text(user['phone']).isNotEmpty)
                  Text(_text(user['phone']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text('৳$reward', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewSettings) {
      return const _NoSettingsPermissionPage();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Settings Center Pro',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : _loadSettings,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reload'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: saving || !canEditSettings ? null : _saveSettings,
                  icon: saving
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving...' : 'Save Settings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            if (!canEditSettings)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility_rounded, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Read only mode: you can view settings, but cannot edit or save.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            _quickStatsCard(),
            const SizedBox(height: 16),

            _section(
              title: 'Store Information',
              icon: Icons.storefront_rounded,
              children: [
                _responsiveGrid([
                  _field(label: 'Business Name', controller: pharmacyNameController, icon: Icons.business, validator: _required),
                  _field(label: 'Support Phone', controller: supportPhoneController, icon: Icons.call, validator: _required),
                  _field(label: 'WhatsApp Number', controller: whatsappController, icon: Icons.chat),
                  _field(label: 'Email', controller: emailController, icon: Icons.email_outlined),
                  _field(label: 'Business Hours', controller: businessHoursController, icon: Icons.access_time),
                ]),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final logo = _brandImageManager(
                      title: 'Header Logo',
                      subtitle: 'Shown in global website header. Recommended transparent PNG/JPG.',
                      controller: logoUrlController,
                      favicon: false,
                      uploading: uploadingLogo,
                    );
                    final favicon = _brandImageManager(
                      title: 'Favicon',
                      subtitle: 'Shown in browser tab/app shortcut when implemented.',
                      controller: faviconUrlController,
                      favicon: true,
                      uploading: uploadingFavicon,
                    );
                    if (c.maxWidth < 760) {
                      return Column(children: [logo, const SizedBox(height: 12), favicon]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: logo),
                        const SizedBox(width: 12),
                        Expanded(child: favicon),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _switchTile(
                  title: 'Show Header Logo',
                  subtitle: 'Turn off to hide the logo from the global web header.',
                  value: showHeaderLogo,
                  icon: Icons.image_outlined,
                  onChanged: (v) => setState(() => showHeaderLogo = v),
                ),
                const SizedBox(height: 12),
                _field(label: 'Address', controller: addressController, icon: Icons.location_on_outlined, maxLines: 2, validator: _required),
                const SizedBox(height: 12),
                _field(label: 'Google Map Link', controller: googleMapController, icon: Icons.map_outlined),
                const SizedBox(height: 12),
                _responsiveGrid([
                  _field(
                    label: 'Trade License No',
                    controller: tradeLicenseController,
                    icon: Icons.badge_outlined,
                  ),
                  _field(
                    label: 'DBID No',
                    controller: dbidController,
                    icon: Icons.verified_user_outlined,
                  ),
                ]),
              ],
            ),


            _section(
              title: 'Website, Domain & Legal URLs',
              icon: Icons.language_rounded,
              children: [
                _responsiveGrid([
                  _field(
                    label: 'Website URL',
                    controller: websiteUrlController,
                    icon: Icons.public_rounded,
                    hint: 'https://chalakcharmart.com',
                    validator: _required,
                  ),
                  _field(
                    label: 'App Domain',
                    controller: appDomainController,
                    icon: Icons.domain_rounded,
                    hint: 'chalakcharmart.com',
                    validator: _required,
                  ),
                  _field(
                    label: 'Search Placeholder',
                    controller: searchPlaceholderController,
                    icon: Icons.search_rounded,
                    hint: 'Search ChalakChar Mart',
                  ),
                ]),
                const SizedBox(height: 12),
                _field(
                  label: 'Header Notice / Promo Strip',
                  controller: headerNoticeController,
                  icon: Icons.campaign_rounded,
                  hint: 'Leave empty to auto show business name, support and hours',
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Footer Tagline',
                  controller: taglineController,
                  icon: Icons.short_text_rounded,
                  hint: 'সব প্রয়োজন, এক জায়গায়',
                ),
                const SizedBox(height: 12),
                _responsiveGrid([
                  _field(
                    label: 'Privacy Policy URL',
                    controller: privacyPolicyUrlController,
                    icon: Icons.privacy_tip_outlined,
                    hint: 'https://chalakcharmart.com/privacy-policy',
                    validator: _required,
                  ),
                  _field(
                    label: 'Terms & Conditions URL',
                    controller: termsUrlController,
                    icon: Icons.description_outlined,
                    hint: 'https://chalakcharmart.com/terms-conditions',
                    validator: _required,
                  ),
                  _field(
                    label: 'Data Deletion URL',
                    controller: dataDeletionUrlController,
                    icon: Icons.delete_forever_outlined,
                    hint: 'https://chalakcharmart.com/data-deletion',
                    validator: _required,
                  ),
                ]),
              ],
            ),


            _section(
              title: 'Footer CMS & Payment Badges',
              icon: Icons.view_stream_rounded,
              children: [
                _responsiveGrid([
                  _field(label: 'Quick Links Title', controller: footerQuickLinksTitleController, icon: Icons.link_rounded),
                  _field(label: 'Support Title', controller: footerSupportTitleController, icon: Icons.support_agent_rounded),
                  _field(label: 'Address Title', controller: footerAddressTitleController, icon: Icons.location_city_rounded),
                  _field(label: 'Legal Title', controller: footerLegalTitleController, icon: Icons.gavel_rounded),
                  _field(label: 'Social Title', controller: footerSocialTitleController, icon: Icons.share_rounded),
                  _field(label: 'Payment Badges', controller: paymentBadgesController, icon: Icons.payments_rounded, hint: 'COD, bKash, Nagad, Card'),
                ]),
                const SizedBox(height: 12),
                _responsiveGrid([
                  _field(label: 'About Label', controller: footerAboutLabelController, icon: Icons.info_outline_rounded),
                  _field(label: 'Terms Label', controller: footerTermsLabelController, icon: Icons.description_outlined),
                  _field(label: 'Privacy Label', controller: footerPrivacyLabelController, icon: Icons.privacy_tip_outlined),
                  _field(label: 'Data Deletion Label', controller: footerDataDeletionLabelController, icon: Icons.delete_forever_outlined),
                  _field(label: 'Return Policy Label', controller: footerReturnPolicyLabelController, icon: Icons.assignment_return_rounded),
                  _field(label: 'Contact Label', controller: footerContactLabelController, icon: Icons.contact_support_outlined),
                  _field(label: 'FAQ Label', controller: footerFaqLabelController, icon: Icons.quiz_outlined),
                ]),
                const SizedBox(height: 12),
                _field(
                  label: 'Copyright Text',
                  controller: copyrightTextController,
                  icon: Icons.copyright_rounded,
                  hint: 'Use {year} for current year. Empty = auto generated.',
                ),
              ],
            ),

            _section(
              title: 'Order & Delivery Settings',
              icon: Icons.local_shipping_rounded,
              children: [
                _responsiveGrid([
                  _field(label: 'Minimum COD Order', controller: minimumOrderController, icon: Icons.payments_outlined, number: true, validator: _number),
                  _field(label: 'Free Delivery Minimum', controller: freeDeliveryMinController, icon: Icons.card_giftcard_rounded, number: true, validator: _number),
                  _field(label: 'Local Delivery Charge', controller: localDeliveryController, icon: Icons.delivery_dining_rounded, number: true, validator: _number),
                  _field(label: 'Outside Delivery Charge', controller: outsideDeliveryController, icon: Icons.route_rounded, number: true, validator: _number),
                  _field(label: 'Express Delivery Charge', controller: expressDeliveryController, icon: Icons.flash_on_rounded, number: true, validator: _number),
                  _field(label: 'Auto Cancel Minutes', controller: autoCancelMinutesController, icon: Icons.timer_off_rounded, number: true, validator: _number),
                ]),
                const SizedBox(height: 12),
                _switchTile(
                  title: 'Disable COD',
                  subtitle: 'Turn off cash on delivery for all users.',
                  value: disableCOD,
                  danger: true,
                  icon: Icons.money_off_rounded,
                  onChanged: (v) => setState(() => disableCOD = v),
                ),
              ],
            ),

            _section(
              title: 'Referral & ChalaChar Mart Cash',
              icon: Icons.account_balance_wallet_rounded,
              children: [
                _responsiveGrid([
                  _field(label: 'Referral Reward', controller: referralRewardController, icon: Icons.person_add_alt_1_rounded, number: true, validator: _number),
                  _field(label: 'Referee Reward', controller: refereeRewardController, icon: Icons.redeem_rounded, number: true, validator: _number),
                  _field(label: 'Max ChalakChar Mart Cash Redeem', controller: maxAbdCashRedeemController, icon: Icons.wallet_rounded, number: true, validator: _number),
                ]),
                const SizedBox(height: 12),
                _switchTile(
                  title: 'Enable Referral',
                  subtitle: 'Allow users to earn by referral system.',
                  value: enableReferral,
                  icon: Icons.group_add_rounded,
                  onChanged: (v) => setState(() => enableReferral = v),
                ),
                _switchTile(
                  title: 'Enable ChalakChar Mart Cash',
                  subtitle: 'Allow users to use ChalakChar Mart Cash rewards.',
                  value: enableAbdCash,
                  icon: Icons.savings_rounded,
                  onChanged: (v) => setState(() => enableAbdCash = v),
                ),
              ],
            ),

            _referralApprovalsSection(),

            _section(
              title: 'Homepage Controls',
              icon: Icons.home_work_rounded,
              children: [
                _switchTile(
                  title: 'Show Home Banners',
                  subtitle: 'Control homepage banner carousel/grid visibility.',
                  value: showHomeBanners,
                  icon: Icons.campaign_rounded,
                  onChanged: (v) => setState(() => showHomeBanners = v),
                ),
                _switchTile(
                  title: 'Show Flash Sale',
                  subtitle: 'Display flash sale products on homepage.',
                  value: showFlashSale,
                  icon: Icons.flash_on_rounded,
                  onChanged: (v) => setState(() => showFlashSale = v),
                ),
                _switchTile(
                  title: 'Show Sponsored Products',
                  subtitle: 'Display sponsored products section.',
                  value: showSponsoredProducts,
                  icon: Icons.workspace_premium_rounded,
                  onChanged: (v) => setState(() => showSponsoredProducts = v),
                ),
                _switchTile(
                  title: 'Show Top Vendors',
                  subtitle: 'Display marketplace vendor section.',
                  value: showTopVendors,
                  icon: Icons.store_mall_directory_rounded,
                  onChanged: (v) => setState(() => showTopVendors = v),
                ),
              ],
            ),

            _section(
              title: 'Notification Controls',
              icon: Icons.notifications_active_rounded,
              children: [
                _switchTile(
                  title: 'Order Notifications',
                  subtitle: 'Send notification updates for user orders.',
                  value: enableOrderNotifications,
                  icon: Icons.shopping_bag_rounded,
                  onChanged: (v) => setState(() => enableOrderNotifications = v),
                ),
                _switchTile(
                  title: 'Admin Notifications',
                  subtitle: 'Notify admins for new orders, stock, lists.',
                  value: enableAdminNotifications,
                  icon: Icons.admin_panel_settings_rounded,
                  onChanged: (v) => setState(() => enableAdminNotifications = v),
                ),
                _switchTile(
                  title: 'Rider Notifications',
                  subtitle: 'Enable delivery/rider notification flow.',
                  value: enableRiderNotifications,
                  icon: Icons.two_wheeler_rounded,
                  onChanged: (v) => setState(() => enableRiderNotifications = v),
                ),
              ],
            ),

            _section(
              title: 'Marketplace Import Settings',
              icon: Icons.public_rounded,
              children: [
                Text(
                  'These rules are applied by Firebase Functions to every imported AliExpress product. Products remain drafts until reviewed unless Auto Publish is enabled.',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                ),
                const SizedBox(height: 12),
                _responsiveGrid([
                  _field(label: 'AliExpress Markup (%)', controller: aliExpressMarkupController, icon: Icons.percent_rounded, number: true, validator: _number),
                  _field(label: 'Exchange Rate to BDT', controller: importExchangeRateController, icon: Icons.currency_exchange_rounded, number: true, validator: _number),
                  _field(label: 'Minimum Profit (BDT)', controller: importMinimumProfitController, icon: Icons.savings_rounded, number: true, validator: _number),
                  _field(label: 'Target Currency', controller: importCurrencyController, icon: Icons.payments_rounded),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: importRoundingMode,
                  decoration: const InputDecoration(
                    labelText: 'Price Rounding',
                    prefixIcon: Icon(Icons.calculate_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Exact (2 decimals)')),
                    DropdownMenuItem(value: '00', child: Text('Round up to whole amount')),
                    DropdownMenuItem(value: '99', child: Text('End price with .99')),
                  ],
                  onChanged: canEditSettings ? (v) => setState(() => importRoundingMode = v ?? 'none') : null,
                ),
                const SizedBox(height: 12),
                _switchTile(
                  title: 'Auto Publish Imported Products',
                  subtitle: 'Keep OFF for Admin review before product and social publishing.',
                  value: importAutoPublish,
                  icon: Icons.publish_rounded,
                  onChanged: (v) => setState(() => importAutoPublish = v),
                ),
                _switchTile(
                  title: 'Enable AI for Imports',
                  subtitle: 'Store the AI optimization preference for imported products.',
                  value: importEnableAi,
                  icon: Icons.auto_awesome_rounded,
                  onChanged: (v) => setState(() => importEnableAi = v),
                ),
                _switchTile(
                  title: 'Enable SEO for Imports',
                  subtitle: 'Generate and retain SEO-ready import metadata.',
                  value: importEnableSeo,
                  icon: Icons.manage_search_rounded,
                  onChanged: (v) => setState(() => importEnableSeo = v),
                ),
                _switchTile(
                  title: 'Enable Marketing after Publish',
                  subtitle: 'Allow approved imported products to enter the existing social marketing queue.',
                  value: importEnableMarketing,
                  icon: Icons.campaign_rounded,
                  onChanged: (v) => setState(() => importEnableMarketing = v),
                ),
              ],
            ),

            _section(
              title: 'Social Marketing & API Integration',
              icon: Icons.campaign_rounded,
              children: [
                const Text(
                  'Public links',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _responsiveGrid([
                  _field(label: 'Help YouTube Link', controller: helpYoutubeController, icon: Icons.play_circle_outline_rounded),
                  _field(label: 'Referral YouTube Link', controller: referralYoutubeController, icon: Icons.ondemand_video_rounded),
                  _field(label: 'Facebook Page URL', controller: facebookController, icon: Icons.facebook_rounded),
                  _field(label: 'Messenger Link', controller: messengerController, icon: Icons.message_rounded),
                  _field(label: 'Instagram URL', controller: instagramController, icon: Icons.camera_alt_outlined),
                  _field(label: 'YouTube URL', controller: youtubeController, icon: Icons.smart_display_outlined),
                  _field(label: 'TikTok URL', controller: tiktokController, icon: Icons.music_note_rounded),
                ]),
                const SizedBox(height: 18),
                const Text(
                  'Official API credentials',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'These values are saved under settings/app and used by Cloud Functions for queued social campaigns. Keep tokens private.',
                  style: TextStyle(color: Colors.grey.shade700, height: 1.45),
                ),
                const SizedBox(height: 12),
                _responsiveGrid([
                  _field(label: 'Facebook Page ID', controller: facebookPageIdController, icon: Icons.badge_outlined),
                  _secretField(label: 'Facebook Page Access Token', controller: facebookPageTokenController, icon: Icons.key_rounded),
                  _field(label: 'Instagram Business Account ID', controller: instagramBusinessIdController, icon: Icons.camera_alt_outlined),
                  _secretField(label: 'Instagram Access Token', controller: instagramAccessTokenController, icon: Icons.key_rounded),
                  _field(label: 'WhatsApp Phone Number ID', controller: whatsappPhoneNumberIdController, icon: Icons.chat_bubble_outline_rounded),
                  _secretField(label: 'WhatsApp Access Token', controller: whatsappAccessTokenController, icon: Icons.key_rounded),
                  _field(label: 'WhatsApp Template Name', controller: whatsappTemplateController, icon: Icons.text_snippet_outlined),
                  _field(label: 'TikTok Client Key', controller: tiktokClientKeyController, icon: Icons.music_note_rounded),
                ]),
                const SizedBox(height: 18),
                _buildTikTokConnectionCard(),
                const SizedBox(height: 18),
                const Text(
                  'Default marketing behavior',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _switchTile(
                  title: 'Enable Marketing Automation',
                  subtitle: 'Allow Product Manager to create marketing queue items using these default settings.',
                  value: autoMarketingEnabled,
                  icon: Icons.auto_awesome_rounded,
                  onChanged: (v) => setState(() => autoMarketingEnabled = v),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final items = [
                      _smallSwitch(
                        title: 'Push Notification',
                        subtitle: 'Default product campaign sends FCM push.',
                        value: defaultPushMarketing,
                        icon: Icons.notifications_active_rounded,
                        onChanged: (v) => setState(() => defaultPushMarketing = v),
                      ),
                      _smallSwitch(
                        title: 'In-App Notification',
                        subtitle: 'Create app notification documents.',
                        value: defaultInAppMarketing,
                        icon: Icons.notifications_none_rounded,
                        onChanged: (v) => setState(() => defaultInAppMarketing = v),
                      ),
                      _smallSwitch(
                        title: 'Facebook Queue',
                        subtitle: 'Queue posts for Facebook Page API.',
                        value: defaultFacebookQueue,
                        icon: Icons.facebook_rounded,
                        onChanged: (v) => setState(() => defaultFacebookQueue = v),
                      ),
                      _smallSwitch(
                        title: 'Instagram Queue',
                        subtitle: 'Queue posts for Instagram Business API.',
                        value: defaultInstagramQueue,
                        icon: Icons.camera_alt_outlined,
                        onChanged: (v) => setState(() => defaultInstagramQueue = v),
                      ),
                      _smallSwitch(
                        title: 'WhatsApp Broadcast',
                        subtitle: 'Queue approved WhatsApp template campaign.',
                        value: defaultWhatsappQueue,
                        icon: Icons.chat_bubble_outline_rounded,
                        onChanged: (v) => setState(() => defaultWhatsappQueue = v),
                      ),
                      _smallSwitch(
                        title: 'Messenger Campaign',
                        subtitle: 'Queue Messenger customer campaign.',
                        value: defaultMessengerQueue,
                        icon: Icons.message_rounded,
                        onChanged: (v) => setState(() => defaultMessengerQueue = v),
                      ),
                      _smallSwitch(
                        title: 'TikTok Queue',
                        subtitle: 'Prepare TikTok campaign queue.',
                        value: defaultTiktokQueue,
                        icon: Icons.music_note_rounded,
                        onChanged: (v) => setState(() => defaultTiktokQueue = v),
                      ),
                    ];

                    final itemWidth = c.maxWidth >= 980
                        ? (c.maxWidth - 12) / 2
                        : c.maxWidth;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: items
                          .map(
                            (item) => SizedBox(
                          width: itemWidth.clamp(280.0, c.maxWidth),
                          child: item,
                        ),
                      )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final audience = _marketingDropdown(
                      label: 'Default Audience',
                      value: defaultMarketingAudience,
                      icon: Icons.groups_rounded,
                      items: const [
                        DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(value: 'wishlist_users', child: Text('Wishlist Users')),
                        DropdownMenuItem(value: 'category_interested', child: Text('Category Interested')),
                        DropdownMenuItem(value: 'previous_buyers', child: Text('Previous Buyers')),
                      ],
                      onChanged: (v) => setState(() => defaultMarketingAudience = v ?? 'everyone'),
                    );
                    final publish = _marketingDropdown(
                      label: 'Default Publish Time',
                      value: defaultMarketingPublishTime,
                      icon: Icons.schedule_rounded,
                      items: const [
                        DropdownMenuItem(value: 'immediately', child: Text('Immediately')),
                        DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                        DropdownMenuItem(value: 'manual_review', child: Text('Manual Review')),
                      ],
                      onChanged: (v) => setState(() => defaultMarketingPublishTime = v ?? 'immediately'),
                    );
                    if (c.maxWidth < 760) {
                      return Column(children: [audience, const SizedBox(height: 12), publish]);
                    }
                    return Row(children: [Expanded(child: audience), const SizedBox(width: 12), Expanded(child: publish)]);
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Default Marketing Caption Template',
                  controller: defaultMarketingCaptionController,
                  icon: Icons.text_fields_rounded,
                  maxLines: 3,
                  hint: 'Use {productName}, {price}, {productUrl}, {category}',
                ),
              ],
            ),

            _section(
              title: 'Security & App Control',
              icon: Icons.security_rounded,
              children: [
                _switchTile(
                  title: 'Maintenance Mode',
                  subtitle: 'Temporarily block customer access while maintaining app.',
                  value: maintenanceMode,
                  danger: true,
                  icon: Icons.construction_rounded,
                  onChanged: (v) => setState(() => maintenanceMode = v),
                ),
                _switchTile(
                  title: 'Force Update',
                  subtitle: 'Show force update message in app when implemented.',
                  value: forceUpdate,
                  danger: true,
                  icon: Icons.system_update_alt_rounded,
                  onChanged: (v) => setState(() => forceUpdate = v),
                ),
                _switchTile(
                  title: 'Block New Registration',
                  subtitle: 'Stop new customer registration temporarily.',
                  value: blockRegistration,
                  danger: true,
                  icon: Icons.person_off_rounded,
                  onChanged: (v) => setState(() => blockRegistration = v),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: saving || !canEditSettings ? null : _saveSettings,
                icon: saving
                    ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save_rounded),
                label: Text(saving ? 'Saving Settings...' : 'Save All Settings'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _NoSettingsPermissionPage extends StatelessWidget {
  const _NoSettingsPermissionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Color(0xFFFFF3E0),
                child: Icon(Icons.lock_outline_rounded, color: Colors.orange, size: 34),
              ),
              SizedBox(height: 16),
              Text(
                'Settings access denied',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'You need settings.view or settings.edit permission to open this page.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
