import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/private_profile_service.dart';
import '../../utils/private_profile_fields.dart';

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
  final shopAreaController = TextEditingController();
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
    shopAreaController.dispose();
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

      // Contact, documents and payout account are in vendor_private (14b
      // step B); an old copy in the public doc is used until it is moved.
      if (existingVendorId != null) {
        existingVendor = await PrivateProfileService.mergedVendor(existingVendorId!, existingVendor);
      }

      final data = existingVendor;

      if (data != null) {
        shopNameController.text = _text(data['shopName']);
        shopAreaController.text = _text(data['shopArea']);
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

  /// Uploads [file] and returns its Storage path. With no new file, returns
  /// [oldPath] (the path of the document already on file). Only the path is
  /// stored, never a download link: a link carries a token that opens the
  /// file for anyone who has it (14b step B / C).
  Future<String> _uploadFile({
    required XFile? file,
    required String vendorId,
    required String name,
    required String oldPath,
  }) async {
    if (file == null) return oldPath;

    final ext = _fileExtension(file.name);
    final path = 'vendors/$vendorId/documents/$name-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = storage.ref(path);

    final bytes = await file.readAsBytes();

    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentType(ext)),
    );

    return path;
  }

  Future<void> _submit() async {
    if (submitting) return;

    final user = auth.currentUser;
    if (user == null) {
      _snack('Please login first', error: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Path of a document already on file (new *Path field, or the path inside
    // an old download link). The old link itself is never written again.
    final oldTrade = vendorDocumentPath(existingVendor, 'tradeLicense');
    final oldFront = vendorDocumentPath(existingVendor, 'nidFront');
    final oldBack = vendorDocumentPath(existingVendor, 'nidBack');

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

      final tradeLicensePath = await _uploadFile(
        file: tradeLicenseFile,
        vendorId: vendorId,
        name: 'trade-license',
        oldPath: oldTrade,
      );

      final nidFrontPath = await _uploadFile(
        file: nidFrontFile,
        vendorId: vendorId,
        name: 'nid-front',
        oldPath: oldFront,
      );

      final nidBackPath = await _uploadFile(
        file: nidBackFile,
        vendorId: vendorId,
        name: 'nid-back',
        oldPath: oldBack,
      );

      final oldStatus = _text(existingVendor?['status'], 'pending');
      final nextStatus = existingVendor == null || oldStatus == 'rejected' ? 'pending' : oldStatus;

      // Public: what the shop page shows. shopArea = area/district only.
      final publicPayload = <String, dynamic>{
        'shopName': shopNameController.text.trim(),
        'shopArea': shopAreaController.text.trim(),
        'businessType': businessTypeController.text.trim().isEmpty
            ? 'general'
            : businessTypeController.text.trim(),
        'ownerId': user.uid,
        'userId': user.uid,
        'status': nextStatus,
        'isActive': existingVendor?['isActive'] == true,
        'isVerified': existingVendor?['isVerified'] == true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Private: vendor_private/{vendorId} (owner and vendor staff only).
      final privatePayload = <String, dynamic>{
        'ownerName': ownerNameController.text.trim(),
        'phone': phoneController.text.trim(),
        'email': emailController.text.trim(),
        'address': addressController.text.trim(),
        'payoutAccount': payoutAccountController.text.trim(),
        'note': noteController.text.trim(),
        'tradeLicensePath': tradeLicensePath,
        'nidFrontPath': nidFrontPath,
        'nidBackPath': nidBackPath,
      };

      // Public first: the private rules find the owner through it.
      await db.collection('vendors').doc(vendorId).set({
        ...publicPayload,
        if (existingVendor == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await PrivateProfileService.saveVendorPrivate(vendorId, privatePayload);

      final payload = {...publicPayload, ...privatePayload};

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
            _field(
              'Shop area / district (shown on your shop page, optional)',
              shopAreaController,
              Icons.map_outlined,
              locked: locked,
            ),
            const SizedBox(height: 4),
            Text(
              'Only the area, e.g. "Chalakchar, Narsingdi". Your phone and address are never shown to customers.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _field('Address (private, for ChalakChar only)', addressController, Icons.location_on,
                locked: locked, required: true, maxLines: 2),
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
              oldUrl: vendorDocumentPath(existingVendor, 'tradeLicense'),
              onTap: locked ? null : () => _chooseDocument('trade'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _docPicker(
                    title: 'NID Front',
                    file: nidFrontFile,
                    oldUrl: vendorDocumentPath(existingVendor, 'nidFront'),
                    onTap: locked ? null : () => _chooseDocument('front'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _docPicker(
                    title: 'NID Back',
                    file: nidBackFile,
                    oldUrl: vendorDocumentPath(existingVendor, 'nidBack'),
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