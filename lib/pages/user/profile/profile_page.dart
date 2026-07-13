import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/auth_service.dart';
import '../wishlist_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final user = FirebaseAuth.instance.currentUser;
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final ageController = TextEditingController();
  final addressController = TextEditingController();
  final divisionController = TextEditingController();
  final districtController = TextEditingController();
  final upazilaController = TextEditingController();
  String imageUrl = '';
  String gender = 'Male';
  String whatsappNumber = '';
  bool whatsappOptIn = false;
  bool whatsappSaving = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    ageController.dispose();
    addressController.dispose();
    divisionController.dispose();
    districtController.dispose();
    upazilaController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    setState(() {
      nameController.text = data['name'] ?? '';
      phoneController.text = data['phone'] ?? '';
      ageController.text = data['age']?.toString() ?? '';
      gender = data['gender'] ?? 'Male';
      addressController.text = data['address'] ?? '';
      divisionController.text = data['division'] ?? '';
      districtController.text = data['district'] ?? '';
      upazilaController.text = data['upazila'] ?? '';
      imageUrl = data['image'] ?? '';
      whatsappNumber = (data['whatsappNumber'] ?? '').toString();
      whatsappOptIn = data['whatsappOptIn'] == true;
    });
  }

  void _showEditProfileDialog() {
    final nameEdit = TextEditingController(text: nameController.text);
    final phoneEdit = TextEditingController(text: phoneController.text);
    final ageEdit = TextEditingController(text: ageController.text);
    final addrEdit = TextEditingController(text: addressController.text);
    final divEdit = TextEditingController(text: divisionController.text);
    final distEdit = TextEditingController(text: districtController.text);
    final upaEdit = TextEditingController(text: upazilaController.text);
    String genderEdit = gender;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(nameEdit, 'User Name'),
                _field(phoneEdit, 'Phone Number', keyboardType: TextInputType.phone),
                _field(ageEdit, 'Age', keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  initialValue: genderEdit,
                  items: ['Male', 'Female', 'Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => genderEdit = v ?? 'Male'),
                  decoration: const InputDecoration(labelText: 'Gender'),
                ),
                _field(addrEdit, 'Full Address'),
                _field(divEdit, 'Division'),
                _field(distEdit, 'District'),
                _field(upaEdit, 'Upazila'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
                  'name': nameEdit.text.trim(),
                  'phone': phoneEdit.text.trim(),
                  'age': ageEdit.text.trim(),
                  'gender': genderEdit,
                  'address': addrEdit.text.trim(),
                  'division': divEdit.text.trim(),
                  'district': distEdit.text.trim(),
                  'upazila': upaEdit.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                await loadData();
                if (mounted) {
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String l, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: c, keyboardType: keyboardType, decoration: InputDecoration(labelText: l)),
    );
  }

  Future<void> _showWhatsAppPreferencesDialog() async {
    final pageContext = context;
    final controller = TextEditingController(
      text: whatsappNumber.isNotEmpty ? whatsappNumber : phoneController.text,
    );
    bool enabled = whatsappOptIn;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('WhatsApp Offers'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Receive WhatsApp product offers'),
                  subtitle: const Text('You can unsubscribe at any time.'),
                  value: enabled,
                  onChanged: whatsappSaving ? null : (value) => setDialogState(() => enabled = value),
                ),
                if (enabled)
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp number',
                      hintText: '01XXXXXXXXX',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'By turning this on, you agree to receive promotional product messages from ChalakChar Mart on WhatsApp. Standard messaging charges may apply.',
                  style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: whatsappSaving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: whatsappSaving ? null : () async {
                setDialogState(() => whatsappSaving = true);
                try {
                  await AuthService().updateWhatsAppPreference(
                    optIn: enabled,
                    whatsappNumber: controller.text,
                  );
                  await loadData();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (pageContext.mounted) {
                    ScaffoldMessenger.of(pageContext).showSnackBar(
                      SnackBar(content: Text(enabled ? 'WhatsApp offers enabled' : 'WhatsApp offers disabled')),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                } finally {
                  whatsappSaving = false;
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _showSellerDialog() {
    final shop = TextEditingController();
    final phone = TextEditingController(text: phoneController.text);
    final address = TextEditingController(text: addressController.text);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Become a seller'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(shop, 'Shop name'),
            _field(phone, 'Business phone'),
            _field(address, 'Shop address'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (shop.text.trim().isEmpty) return;
              await AuthService().requestSellerAccount(
                shopName: shop.text,
                phone: phone.text,
                address: address.text,
              );
              if (mounted) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller request submitted')));
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Scaffold(body: Center(child: Text('Login required')));
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>? ?? {};
          final role = data['role']?.toString() ?? 'user';
          final sellerStatus = data['sellerStatus']?.toString() ?? 'none';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                          child: imageUrl.isEmpty ? const Icon(Icons.person, size: 42) : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nameController.text.isEmpty ? 'User Name' : nameController.text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              Text(user!.email ?? '', style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, children: [
                                Chip(label: Text(role.toUpperCase())),
                                if (sellerStatus != 'none') Chip(label: Text('SELLER: ${sellerStatus.toUpperCase()}')),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _showEditProfileDialog, icon: const Icon(Icons.edit)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _tile(Icons.phone, 'Phone', phoneController.text),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.chat, color: whatsappOptIn ? Colors.green : Colors.grey),
                    title: const Text('WhatsApp Offers'),
                    subtitle: Text(whatsappOptIn ? 'Subscribed: $whatsappNumber' : 'Not subscribed'),
                    trailing: Switch.adaptive(value: whatsappOptIn, onChanged: (_) => _showWhatsAppPreferencesDialog()),
                    onTap: _showWhatsAppPreferencesDialog,
                  ),
                ),
                _tile(Icons.location_on, 'Address', addressController.text),
                _tile(Icons.map, 'Area', '${divisionController.text} -> ${districtController.text} -> ${upazilaController.text}'),
                _action(Icons.favorite, 'Wishlist', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistPage()))),
                _action(Icons.storefront, sellerStatus == 'approved' ? 'Seller dashboard' : 'Become a seller', _showSellerDialog),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF32A8C7)),
        title: Text(label),
        subtitle: Text(value.trim().isEmpty ? 'Not set' : value),
      ),
    );
  }

  Widget _action(IconData icon, String title, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF32A8C7)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
