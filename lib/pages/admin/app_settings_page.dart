import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

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

  final tradeLicenseController = TextEditingController();
  final dbidController = TextEditingController();
  final drugLicenseController = TextEditingController();

  final minimumOrderController = TextEditingController();
  final freeDeliveryMinController = TextEditingController();
  final localDeliveryController = TextEditingController();
  final outsideDeliveryController = TextEditingController();
  final expressDeliveryController = TextEditingController();
  final autoCancelMinutesController = TextEditingController();

  final referralRewardController = TextEditingController();
  final refereeRewardController = TextEditingController();
  final maxAbdCashRedeemController = TextEditingController();

  final helpYoutubeController = TextEditingController();
  final referralYoutubeController = TextEditingController();
  final facebookController = TextEditingController();
  final messengerController = TextEditingController();
  final instagramController = TextEditingController();
  final youtubeController = TextEditingController();
  final tiktokController = TextEditingController();

  bool loading = true;
  bool saving = false;
  bool canViewSettings = false;
  bool canEditSettings = false;

  bool maintenanceMode = false;
  bool forceUpdate = false;
  bool blockRegistration = false;
  bool disableCOD = false;

  bool showFlashSale = true;
  bool showSponsoredProducts = true;
  bool showTopVendors = true;
  bool showHomeBanners = true;
  bool enableReferral = true;
  bool enableAbdCash = true;
  bool enableOrderNotifications = true;
  bool enableAdminNotifications = true;
  bool enableRiderNotifications = true;

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

    tradeLicenseController.dispose();
    dbidController.dispose();
    drugLicenseController.dispose();

    minimumOrderController.dispose();
    freeDeliveryMinController.dispose();
    localDeliveryController.dispose();
    outsideDeliveryController.dispose();
    expressDeliveryController.dispose();
    autoCancelMinutesController.dispose();

    referralRewardController.dispose();
    refereeRewardController.dispose();
    maxAbdCashRedeemController.dispose();

    helpYoutubeController.dispose();
    referralYoutubeController.dispose();
    facebookController.dispose();
    messengerController.dispose();
    instagramController.dispose();
    youtubeController.dispose();
    tiktokController.dispose();

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
      emailController.text = _text(data['email'], 'abdullahpharmacy.chalakchar@gmail.com');
      addressController.text = _text(data['address'], 'Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh');
      googleMapController.text = _text(data['googleMapLink']);
      businessHoursController.text = _text(data['businessHours'], '9:00 AM - 11:00 PM');

      tradeLicenseController.text = _text(data['tradeLicenseNo'], '528');
      dbidController.text = _text(data['dbidNo'], '000000000');
      drugLicenseController.text = _text(data['drugLicenseNo'], 'নর - ৯২৮');

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
      facebookController.text = _text(data['facebookLink']);
      messengerController.text = _text(data['messengerLink']);
      instagramController.text = _text(data['instagramLink']);
      youtubeController.text = _text(data['youtubeLink']);
      tiktokController.text = _text(data['tiktokLink']);

      maintenanceMode = _bool(data['maintenanceMode'], false);
      forceUpdate = _bool(data['forceUpdate'], false);
      blockRegistration = _bool(data['blockRegistration'], false);
      disableCOD = _bool(data['disableCOD'], false);

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

        'tradeLicenseNo': tradeLicenseController.text.trim(),
        'dbidNo': dbidController.text.trim(),
        'drugLicenseNo': drugLicenseController.text.trim(),

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
        final count = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 650
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: count == 1 ? 5.6 : 4.2,
          ),
          itemBuilder: (_, i) => children[i],
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
                  _field(
                    label: 'Drug License No',
                    controller: drugLicenseController,
                    icon: Icons.medical_information_outlined,
                  ),
                ]),
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
              title: 'Social & Help Links',
              icon: Icons.link_rounded,
              children: [
                _responsiveGrid([
                  _field(label: 'Help YouTube Link', controller: helpYoutubeController, icon: Icons.play_circle_outline_rounded),
                  _field(label: 'Referral YouTube Link', controller: referralYoutubeController, icon: Icons.ondemand_video_rounded),
                  _field(label: 'Facebook Link', controller: facebookController, icon: Icons.facebook_rounded),
                  _field(label: 'Messenger Link', controller: messengerController, icon: Icons.message_rounded),
                  _field(label: 'Instagram Link', controller: instagramController, icon: Icons.camera_alt_outlined),
                  _field(label: 'YouTube Link', controller: youtubeController, icon: Icons.smart_display_outlined),
                  _field(label: 'TikTok Link', controller: tiktokController, icon: Icons.music_note_rounded),
                ]),
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
