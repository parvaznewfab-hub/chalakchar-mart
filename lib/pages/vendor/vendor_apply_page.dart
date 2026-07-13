import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class VendorApplyPage extends StatefulWidget {
  const VendorApplyPage({super.key});

  @override
  State<VendorApplyPage> createState() => _VendorApplyPageState();
}

class _VendorApplyPageState extends State<VendorApplyPage> {
  final _formKey = GlobalKey<FormState>();

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;
  final ImagePicker picker = ImagePicker();

  final shopNameController = TextEditingController();
  final ownerNameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final addressController = TextEditingController();
  final businessTypeController = TextEditingController(text: 'general');
  final payoutAccountController = TextEditingController();
  final noteController = TextEditingController();

  XFile? tradeLicenseFile;
  XFile? nidFrontFile;
  XFile? nidBackFile;

  bool loading = true;
  bool submitting = false;

  String? existingVendorId;
  Map<String, dynamic>? existingVendor;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndVendor();
  }

  @override
  void dispose() {
    shopNameController.dispose();
    ownerNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    businessTypeController.dispose();
    payoutAccountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'jpg';

    final ext = parts.last.toLowerCase().trim();
    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) return ext;
    return 'jpg';
  }

  String _contentType(String ext) {
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : const Color(0xFF32A8C7),
      ),
    );
  }

  Future<void> _loadCurrentUserAndVendor() async {
    final user = auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      emailController.text = user.email ?? '';

      final userDoc = await db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      ownerNameController.text = _text(userData['name'], user.displayName ?? '');
      phoneController.text = _text(userData['phone']);
      addressController.text = _text(userData['address']);

      final userVendorId = _text(userData['vendorId']);

      DocumentSnapshot<Map<String, dynamic>>? vendorDoc;

      if (userVendorId.isNotEmpty) {
        final doc = await db.collection('vendors').doc(userVendorId).get();
        if (doc.exists) vendorDoc = doc;
      }

      vendorDoc ??= await db.collection('vendors').doc(user.uid).get();

      if (!vendorDoc.exists) {
        final query = await db
            .collection('vendors')
            .where('ownerId', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          existingVendorId = query.docs.first.id;
          existingVendor = query.docs.first.data();
        }
      } else {
        existingVendorId = vendorDoc.id;
        existingVendor = vendorDoc.data();
      }

      final data = existingVendor;

      if (data != null) {
        shopNameController.text = _text(data['shopName']);
        ownerNameController.text = _text(data['ownerName'], ownerNameController.text);
        phoneController.text = _text(data['phone'], phoneController.text);
        emailController.text = _text(data['email'], emailController.text);
        addressController.text = _text(data['address'], addressController.text);
        businessTypeController.text = _text(data['businessType'], 'general');
        payoutAccountController.text = _text(data['payoutAccount']);
        noteController.text = _text(data['note']);
      }
    } catch (e) {
      _snack('Vendor info load failed: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<XFile?> _pickImage() {
    return picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
  }

  Future<void> _chooseDocument(String type) async {
    final file = await _pickImage();
    if (file == null) return;

    setState(() {
      if (type == 'trade') tradeLicenseFile = file;
      if (type == 'front') nidFrontFile = file;
      if (type == 'back') nidBackFile = file;
    });
  }

  Future<String> _uploadFile({
    required XFile? file,
    required String vendorId,
    required String name,
    required String oldUrl,
  }) async {
    if (file == null) return oldUrl;

    final ext = _fileExtension(file.name);
    final path = 'vendors/$vendorId/documents/$name-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = storage.ref(path);

    final bytes = await file.readAsBytes();

    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentType(ext)),
    );

    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (submitting) return;

    final user = auth.currentUser;
    if (user == null) {
      _snack('Please login first', error: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final oldTrade = _text(existingVendor?['tradeLicense']);
    final oldFront = _text(existingVendor?['nidFront']);
    final oldBack = _text(existingVendor?['nidBack']);

    if (oldTrade.isEmpty && tradeLicenseFile == null) {
      _snack('Trade License / Citizen Certificate image required', error: true);
      return;
    }

    if (oldFront.isEmpty && nidFrontFile == null) {
      _snack('NID Front image required', error: true);
      return;
    }

    if (oldBack.isEmpty && nidBackFile == null) {
      _snack('NID Back image required', error: true);
      return;
    }

    setState(() => submitting = true);

    try {
      final vendorId = existingVendorId ?? user.uid;

      final tradeLicenseUrl = await _uploadFile(
        file: tradeLicenseFile,
        vendorId: vendorId,
        name: 'trade-license',
        oldUrl: oldTrade,
      );

      final nidFrontUrl = await _uploadFile(
        file: nidFrontFile,
        vendorId: vendorId,
        name: 'nid-front',
        oldUrl: oldFront,
      );

      final nidBackUrl = await _uploadFile(
        file: nidBackFile,
        vendorId: vendorId,
        name: 'nid-back',
        oldUrl: oldBack,
      );

      final oldStatus = _text(existingVendor?['status'], 'pending');
      final nextStatus = existingVendor == null || oldStatus == 'rejected' ? 'pending' : oldStatus;

      final payload = <String, dynamic>{
        'shopName': shopNameController.text.trim(),
        'ownerName': ownerNameController.text.trim(),
        'phone': phoneController.text.trim(),
        'email': emailController.text.trim(),
        'address': addressController.text.trim(),
        'businessType': businessTypeController.text.trim().isEmpty
            ? 'general'
            : businessTypeController.text.trim(),
        'payoutAccount': payoutAccountController.text.trim(),
        'note': noteController.text.trim(),
        'ownerId': user.uid,
        'userId': user.uid,
        'tradeLicense': tradeLicenseUrl,
        'nidFront': nidFrontUrl,
        'nidBack': nidBackUrl,
        'status': nextStatus,
        'isActive': existingVendor?['isActive'] == true,
        'isVerified': existingVendor?['isVerified'] == true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await db.collection('vendors').doc(vendorId).set({
        ...payload,
        if (existingVendor == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await db.collection('users').doc(user.uid).set({
        'vendorId': vendorId,
        'sellerStatus': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      existingVendorId = vendorId;
      existingVendor = {
        ...(existingVendor ?? {}),
        ...payload,
      };

      tradeLicenseFile = null;
      nidFrontFile = null;
      nidBackFile = null;

      if (mounted) setState(() {});

      _snack(
        nextStatus == 'approved'
            ? 'Seller information updated.'
            : 'Vendor application submitted. Admin approval pending.',
      );
    } catch (e) {
      _snack('Submit failed: $e', error: true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;

    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Seller Account')),
        body: const Center(
          child: Text('Please login to apply for seller account.'),
        ),
      );
    }

    final status = _text(existingVendor?['status'], 'new');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Seller Account Application'),
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1050),
                child: wide
                    ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _form(status)),
                    const SizedBox(width: 16),
                    Expanded(child: _sideInfo(status)),
                  ],
                )
                    : Column(
                  children: [
                    _sideInfo(status),
                    const SizedBox(height: 16),
                    _form(status),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _form(String status) {
    final locked = status == 'approved' || submitting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Business Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _field('Shop Name', shopNameController, Icons.storefront, locked: locked, required: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field('Owner Name', ownerNameController, Icons.person, locked: locked, required: true)),
                const SizedBox(width: 10),
                Expanded(child: _field('Phone', phoneController, Icons.call, locked: locked, required: true)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field('Email', emailController, Icons.email, locked: locked)),
                const SizedBox(width: 10),
                Expanded(child: _field('Business Type', businessTypeController, Icons.business_center, locked: locked)),
              ],
            ),
            const SizedBox(height: 12),
            _field('Shop Address', addressController, Icons.location_on, locked: locked, required: true, maxLines: 2),
            const SizedBox(height: 12),
            _field(
              'Payout Account / bKash / Bank',
              payoutAccountController,
              Icons.account_balance_wallet,
              locked: locked,
              required: true,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _field('Note optional', noteController, Icons.note_alt, locked: locked, maxLines: 3),
            const SizedBox(height: 18),
            const Text('Verification Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _docPicker(
              title: 'Trade License / Citizen Certificate',
              file: tradeLicenseFile,
              oldUrl: _text(existingVendor?['tradeLicense']),
              onTap: locked ? null : () => _chooseDocument('trade'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _docPicker(
                    title: 'NID Front',
                    file: nidFrontFile,
                    oldUrl: _text(existingVendor?['nidFront']),
                    onTap: locked ? null : () => _chooseDocument('front'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _docPicker(
                    title: 'NID Back',
                    file: nidBackFile,
                    oldUrl: _text(existingVendor?['nidBack']),
                    onTap: locked ? null : () => _chooseDocument('back'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: locked ? null : _submit,
                icon: submitting
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.send),
                label: Text(
                  submitting
                      ? 'Submitting...'
                      : status == 'new'
                      ? 'SUBMIT APPLICATION'
                      : 'UPDATE APPLICATION',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF32A8C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (status == 'approved') ...[
              const SizedBox(height: 10),
              const Text(
                'Your seller account is approved. Contact admin to change approved business documents.',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(
      String label,
      TextEditingController controller,
      IconData icon, {
        bool locked = false,
        bool required = false,
        int maxLines = 1,
      }) {
    return TextFormField(
      controller: controller,
      enabled: !locked,
      maxLines: maxLines,
      validator: required ? (v) => _text(v).isEmpty ? '$label required' : null : null,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _docPicker({
    required String title,
    required XFile? file,
    required String oldUrl,
    required VoidCallback? onTap,
  }) {
    final hasFile = file != null;
    final hasOld = oldUrl.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hasFile || hasOld ? Colors.green : Colors.grey.shade300),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasFile || hasOld ? Icons.check_circle : Icons.upload_file,
                  color: hasFile || hasOld ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasFile
                  ? file.name
                  : hasOld
                  ? 'Already uploaded. Tap to replace.'
                  : 'Tap to upload image',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideInfo(String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, color: Color(0xFF32A8C7)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Application Status', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              _statusChip(status),
            ],
          ),
          const Divider(height: 24),
          _infoLine('1', 'Submit your shop information.'),
          _infoLine('2', 'Upload Trade License / Citizen Certificate and NID both sides.'),
          _infoLine('3', 'Admin will verify and approve.'),
          _infoLine('4', 'After approval, seller dashboard will be available.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: const Text(
              'Use clear document images. Wrong or unclear documents may be rejected.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, child: Text(number, style: const TextStyle(fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;

    switch (status) {
      case 'approved':
        color = Colors.green;
        label = 'APPROVED';
        break;
      case 'rejected':
        color = Colors.red;
        label = 'REJECTED';
        break;
      case 'suspended':
        color = Colors.deepOrange;
        label = 'SUSPENDED';
        break;
      case 'pending':
        color = Colors.orange;
        label = 'PENDING';
        break;
      default:
        color = Colors.blueGrey;
        label = 'NEW';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}