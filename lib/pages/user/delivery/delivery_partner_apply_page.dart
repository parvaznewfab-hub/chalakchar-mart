import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class DeliveryPartnerApplyPage extends StatefulWidget {
  const DeliveryPartnerApplyPage({super.key});

  @override
  State<DeliveryPartnerApplyPage> createState() => _DeliveryPartnerApplyPageState();
}

class _DeliveryPartnerApplyPageState extends State<DeliveryPartnerApplyPage> {
  final _formKey = GlobalKey<FormState>();

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;
  final ImagePicker picker = ImagePicker();

  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final nidCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final noteCtrl = TextEditingController();

  String vehicleType = 'Bicycle';
  bool loading = false;

  XFile? nidFrontFile;
  XFile? nidBackFile;
  Uint8List? nidFrontBytes;
  Uint8List? nidBackBytes;

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    nidCtrl.dispose();
    addressCtrl.dispose();
    areaCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : const Color(0xFF32A8C7),
      ),
    );
  }

  Future<void> _pickIdImage({required bool front}) async {
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();

      if (bytes.length > 5 * 1024 * 1024) {
        _snack('Image too large. Please upload under 5 MB.', error: true);
        return;
      }

      setState(() {
        if (front) {
          nidFrontFile = file;
          nidFrontBytes = bytes;
        } else {
          nidBackFile = file;
          nidBackBytes = bytes;
        }
      });
    } catch (e) {
      _snack('Image pick failed: $e', error: true);
    }
  }

  Future<Map<String, String>> _uploadIdImage({
    required String uid,
    required XFile file,
    required Uint8List bytes,
    required String side,
  }) async {
    final ext = _extension(file.name);
    final path = 'delivery_partner_documents/$uid/${side}_$uid.$ext';

    final ref = storage.ref(path);

    final metadata = SettableMetadata(
      contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
      customMetadata: {
        'uid': uid,
        'side': side,
        'module': 'delivery_partner_apply',
      },
    );

    await ref.putData(bytes, metadata);

    final url = await ref.getDownloadURL();

    return {
      'url': url,
      'path': path,
    };
  }

  String _extension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    return 'jpg';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (nidFrontFile == null || nidFrontBytes == null) {
      _snack('Please upload NID / ID front side image', error: true);
      return;
    }

    if (nidBackFile == null || nidBackBytes == null) {
      _snack('Please upload NID / ID back side image', error: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please login first', error: true);
      return;
    }

    setState(() => loading = true);

    try {
      final ref = db.collection('deliveryPartners').doc(user.uid);
      final oldDoc = await ref.get();

      if (oldDoc.exists) {
        final status = oldDoc.data()?['status'] ?? 'pending';
        _snack('You already applied. Current status: $status');
        return;
      }

      final front = await _uploadIdImage(
        uid: user.uid,
        file: nidFrontFile!,
        bytes: nidFrontBytes!,
        side: 'nid_front',
      );

      final back = await _uploadIdImage(
        uid: user.uid,
        file: nidBackFile!,
        bytes: nidBackBytes!,
        side: 'nid_back',
      );

      await ref.set({
        'uid': user.uid,
        'email': user.email,
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'nidNumber': nidCtrl.text.trim(),
        'nidFrontUrl': front['url'],
        'nidFrontPath': front['path'],
        'nidBackUrl': back['url'],
        'nidBackPath': back['path'],
        'documentStatus': 'submitted',
        'documentUploadedAt': FieldValue.serverTimestamp(),
        'address': addressCtrl.text.trim(),
        'preferredArea': areaCtrl.text.trim(),
        'vehicleType': vehicleType,
        'note': noteCtrl.text.trim(),
        'status': 'pending',
        'isActive': false,
        'totalDeliveries': 0,
        'totalEarning': 0,
        'withdrawnAmount': 0,
        'pendingAmount': 0,
        'codDue': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _snack('Application submitted successfully. Admin approval required.');

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Submit failed: $e', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join as Delivery Partner'),
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('Please login first'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('deliveryPartners').doc(user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasData && snap.data!.exists) {
            final data = snap.data!.data() ?? {};
            final status = (data['status'] ?? 'pending').toString();

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          status == 'approved'
                              ? Icons.verified
                              : status == 'rejected'
                              ? Icons.cancel
                              : Icons.pending_actions,
                          size: 70,
                          color: status == 'approved'
                              ? Colors.green
                              : status == 'rejected'
                              ? Colors.red
                              : Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Application Status: ${status.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status == 'approved'
                              ? 'Your delivery partner account is approved.'
                              : 'Admin will review your delivery partner request and ID documents.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoBox(),
                      const SizedBox(height: 18),
                      _sectionTitle('Personal Information'),
                      _field(nameCtrl, 'Full Name', Icons.person, validator: _required),
                      _field(
                        phoneCtrl,
                        'Phone Number',
                        Icons.phone,
                        validator: _required,
                        keyboard: TextInputType.phone,
                      ),
                      _field(nidCtrl, 'NID / ID Number', Icons.badge, validator: _required),
                      const SizedBox(height: 4),
                      _sectionTitle('NID / ID Document Images'),
                      _documentGrid(),
                      const SizedBox(height: 16),
                      _sectionTitle('Delivery Information'),
                      _field(
                        addressCtrl,
                        'Current Address',
                        Icons.home,
                        validator: _required,
                        maxLines: 2,
                      ),
                      _field(
                        areaCtrl,
                        'Preferred Delivery Area',
                        Icons.location_on,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      const Text('Vehicle Type', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: vehicleType,
                        decoration: _inputDecoration(Icons.delivery_dining),
                        items: const [
                          DropdownMenuItem(value: 'Bicycle', child: Text('Bicycle')),
                          DropdownMenuItem(value: 'Motorbike', child: Text('Motorbike')),
                          DropdownMenuItem(value: 'Walking', child: Text('Walking')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: loading ? null : (v) => setState(() => vehicleType = v ?? 'Bicycle'),
                      ),
                      const SizedBox(height: 14),
                      _field(noteCtrl, 'Extra Note (Optional)', Icons.note_alt, maxLines: 3),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: loading ? null : _submit,
                          icon: loading
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(Icons.send),
                          label: Text(loading ? 'Submitting...' : 'Submit Application'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF32A8C7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _documentGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 620;

        final children = [
          _documentPickerCard(
            title: 'NID / ID Front Side',
            subtitle: 'Upload clear front side image',
            bytes: nidFrontBytes,
            onTap: loading ? null : () => _pickIdImage(front: true),
          ),
          _documentPickerCard(
            title: 'NID / ID Back Side',
            subtitle: 'Upload clear back side image',
            bytes: nidBackBytes,
            onTap: loading ? null : () => _pickIdImage(front: false),
          ),
        ];

        if (!isWide) {
          return Column(
            children: [
              children[0],
              const SizedBox(height: 12),
              children[1],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }

  Widget _documentPickerCard({
    required String title,
    required String subtitle,
    required Uint8List? bytes,
    required VoidCallback? onTap,
  }) {
    final hasImage = bytes != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? const Color(0xFF32A8C7) : Colors.grey.shade300,
            width: hasImage ? 1.5 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                bytes,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$title uploaded',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ],
        )
            : Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_upload_outlined, size: 44, color: Color(0xFF32A8C7)),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                'JPG/PNG • Max 5 MB',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF32A8C7).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF32A8C7).withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF32A8C7)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Apply to work as a local delivery partner. NID / ID front and back images are required for admin verification.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
      TextEditingController controller,
      String label,
      IconData icon, {
        String? Function(String?)? validator,
        TextInputType keyboard = TextInputType.text,
        int maxLines = 1,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboard,
        maxLines: maxLines,
        enabled: !loading,
        decoration: _inputDecoration(icon).copyWith(labelText: label),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF32A8C7)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF32A8C7), width: 1.4),
      ),
    );
  }
}
