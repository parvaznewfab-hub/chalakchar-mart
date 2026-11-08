import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/image_upload_service.dart';
import '../../services/category_service.dart';
import '../../services/category_resolver_service.dart';
import '../../utils/variant_merge.dart';

class VendorProductsPage extends StatefulWidget {
  const VendorProductsPage({super.key});

  @override
  State<VendorProductsPage> createState() => _VendorProductsPageState();
}

class _VendorProductsPageState extends State<VendorProductsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String searchText = '';
  String stockFilter = 'all';
  String statusFilter = 'all';

  String _vendorId = '';
  bool _loadingVendor = true;

  String get vendorId => _vendorId;

  @override
  void initState() {
    super.initState();
    _resolveVendorId();
  }

  Future<void> _resolveVendorId() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => _loadingVendor = false);
      return;
    }

    String resolved = '';

    try {
      final userDoc = await db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final userVendorId = _text(userData['vendorId']);
      final sellerStatus = _text(userData['sellerStatus']).toLowerCase();

      if (userVendorId.isNotEmpty) {
        final vendorDoc = await db.collection('vendors').doc(userVendorId).get();
        final vendor = vendorDoc.data() ?? <String, dynamic>{};
        final ownerId = _text(vendor['ownerId'] ?? vendor['userId']);
        final status = _text(vendor['status']).toLowerCase();

        if (vendorDoc.exists && ownerId == user.uid && (status == 'approved' || sellerStatus == 'approved')) {
          resolved = userVendorId;
        }
      }

      // Legacy fallback for old data where vendor document id was the Firebase Auth UID.
      if (resolved.isEmpty) {
        final directDoc = await db.collection('vendors').doc(user.uid).get();
        final vendor = directDoc.data() ?? <String, dynamic>{};
        final ownerId = _text(vendor['ownerId'] ?? vendor['userId']);
        final status = _text(vendor['status']).toLowerCase();

        if (directDoc.exists && ownerId == user.uid && status == 'approved') {
          resolved = directDoc.id;
        }
      }

      if (resolved.isEmpty) {
        final q = await db
            .collection('vendors')
            .where('ownerId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'approved')
            .limit(1)
            .get();

        if (q.docs.isNotEmpty) resolved = q.docs.first.id;
      }
    } catch (e) {
      debugPrint('Vendor product vendorId resolve failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _vendorId = resolved;
      _loadingVendor = false;
    });
  }

  double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Future<String> _uploadPickedImage(XFile file) async {
    final folder = 'vendor_products/$vendorId';

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return ImageUploadService.upload(null, webImage: bytes, folder: folder);
    }

    return ImageUploadService.upload(File(file.path), folder: folder);
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = _text(data['name']).toLowerCase();
      final category = _text(data['category']).toLowerCase();
      final manufacturer = _text(data['manufacturer']).toLowerCase();
      final stock = _toInt(data['stock']);
      final isActive = data['isActive'] == true;
      final approvalStatus = _text(data['approvalStatus'], 'pending').toLowerCase();
      final displayActive = approvalStatus == 'approved' && isActive;

      final s = searchText.toLowerCase().trim();
      if (s.isNotEmpty &&
          !name.contains(s) &&
          !category.contains(s) &&
          !manufacturer.contains(s)) {
        return false;
      }

      if (stockFilter == 'in' && stock <= 0) return false;
      if (stockFilter == 'out' && stock > 0) return false;
      if (stockFilter == 'low' && stock > 5) return false;

      if (statusFilter == 'active' && !displayActive) return false;
      if (statusFilter == 'inactive' && displayActive) return false;
      if (statusFilter == 'pending' && approvalStatus != 'pending') return false;
      if (statusFilter == 'approved' && approvalStatus != 'approved') return false;
      if (statusFilter == 'rejected' && approvalStatus != 'rejected') return false;

      return true;
    }).toList();
  }

  Future<void> _toggleProduct(String id, bool active) async {
    // Vendor can show/hide only their own approved product.
    // Do not update approvalStatus, isPublished or showOnHome from vendor side.
    await db.collection('products').doc(id).update({
      'isActive': active,
      'isVisible': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteProduct(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text('This will remove the product permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('products').doc(id).delete();
    }
  }

  Future<Map<String, dynamic>> _vendorInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || vendorId.isEmpty) return {};

    final doc = await db.collection('vendors').doc(vendorId).get();
    final data = doc.data() ?? <String, dynamic>{};
    final ownerId = _text(data['ownerId'] ?? data['userId']);
    final status = _text(data['status']).toLowerCase();

    if (!doc.exists || ownerId != user.uid || status != 'approved') {
      throw Exception('Vendor account not approved or not linked with this login.');
    }

    return data;
  }

  Future<void> _showProductDialog({
    String? id,
    Map<String, dynamic>? data,
  }) async {
    final vendor = await _vendorInfo();
    if (!mounted) return;

    final name = TextEditingController(text: _text(data?['name']));
    final generic = TextEditingController(text: _text(data?['generic']));
    final manufacturer = TextEditingController(text: _text(data?['manufacturer']));
    final type = TextEditingController(text: _text(data?['type']));
    final strength = TextEditingController(text: _text(data?['strength']));
    final overview = TextEditingController(text: _text(data?['overview']));

    String? category = _text(data?['category']).isEmpty ? null : _text(data?['category']);
    String imageUrl = _text(data?['image']);
    List<String> images = List<String>.from(data?['images'] ?? []);
    final dialogApprovalStatus = _text(data?['approvalStatus'], id == null ? 'pending' : 'approved').toLowerCase();
    bool isActive = dialogApprovalStatus == 'approved' && data?['isActive'] == true;
    bool saving = false;
    bool uploading = false;

    final List<Map<String, TextEditingController>> variants = [];
    // Parallel to `variants` (same length/index): the exact original
    // variant map each row was seeded from, or null for a row added fresh
    // during this edit session. Kept in sync on add/delete.
    final List<Map<String, dynamic>?> variantOriginals = [];

    final oldVariants = data?['variants'];
    if (oldVariants is List && oldVariants.isNotEmpty) {
      for (final v in oldVariants) {
        if (v is! Map) continue;
        variants.add({
          'name': TextEditingController(text: _text(v['name'], 'Default')),
          'price': TextEditingController(text: _toDouble(v['price']).toStringAsFixed(0)),
          'mrp': TextEditingController(text: _toDouble(v['mrp'] ?? v['oldPrice']).toStringAsFixed(0)),
          'stock': TextEditingController(text: _toInt(v['stock']).toString()),
        });
        variantOriginals.add(Map<String, dynamic>.from(v));
      }
    } else {
      variants.add({
        'name': TextEditingController(text: _text(data?['unit'], 'Default')),
        'price': TextEditingController(text: _toDouble(data?['price']).toStringAsFixed(0)),
        'mrp': TextEditingController(text: _toDouble(data?['oldPrice']).toStringAsFixed(0)),
        'stock': TextEditingController(text: _toInt(data?['stock']).toString()),
      });
      variantOriginals.add(null);
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickImage({bool main = false}) async {
            final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
            if (picked == null) return;

            setDialogState(() => uploading = true);
            try {
              final url = await _uploadPickedImage(picked);
              setDialogState(() {
                if (main) imageUrl = url;
                if (!images.contains(url)) images.add(url);
                if (imageUrl.isEmpty) imageUrl = url;
              });
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
              }
            } finally {
              setDialogState(() => uploading = false);
            }
          }

          void addVariant() {
            setDialogState(() {
              variants.add({
                'name': TextEditingController(text: 'Default'),
                'price': TextEditingController(text: '0'),
                'mrp': TextEditingController(text: '0'),
                'stock': TextEditingController(text: '0'),
              });
              variantOriginals.add(null);
            });
          }

          Future<void> save() async {
            final productName = name.text.trim();
            if (productName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product name required')));
              return;
            }

            if (category == null || category!.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category required')));
              return;
            }
            final variantNames = <String>{};

            for (final v in variants) {
              final n = v['name']!.text.trim().toLowerCase();
              if (n.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variant name required')));
                return;
              }
              if (variantNames.contains(n)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Duplicate variant: $n')));
                return;
              }
              variantNames.add(n);
            }

            // ১. রুলস-ফ্রেন্ডলি ভ্যারিয়েন্ট লিস্ট তৈরি (কোনো এক্সট্রা ইন্টারনাল আইডি ছাড়া)
            final variantList = <Map<String, dynamic>>[
              for (var i = 0; i < variants.length; i++)
                mergeVariantEdit(
                  variantOriginals[i],
                  {
                    'name': variants[i]['name']!.text.trim().isEmpty
                        ? 'Default'
                        : variants[i]['name']!.text.trim(),
                    'price': _toDouble(variants[i]['price']!.text),
                    'mrp': _toDouble(variants[i]['mrp']!.text),
                    'stock': _toInt(variants[i]['stock']!.text),
                  },
                ),
            ];

            final firstVariant = variantList.first;
            final totalStock = variants.fold<int>(
              0,
                  (currentTotal, v) => currentTotal + _toInt(v['stock']),
            );
            final firstPrice = _toDouble(firstVariant['price']);
            final firstMrp = _toDouble(firstVariant['mrp'], firstPrice);
            final firstUnit = _text(firstVariant['name'], 'Default');

            setDialogState(() => saving = true);

            try {
              final vendorShopName = _text(vendor['shopName'], 'Vendor');
              final ownerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (ownerUid.isEmpty) {
                throw Exception('Please login again before saving product.');
              }

              // Category Manager is the single source of truth: resolve
              // (or auto-create, pending admin approval — vendors never get
              // an immediately-visible category) through the shared backend
              // resolver. The backend derives vendor-tier defaults from this
              // caller's own authenticated role, never from anything sent
              // here. Falls back to the raw typed name on any resolver
              // error so a transient failure never blocks a product save.
              String resolvedCategoryName = category!;
              String? resolvedCategoryId;
              try {
                final resolution = await CategoryResolverService.resolve(category!);
                if (resolution != null) {
                  resolvedCategoryName = resolution.categoryName;
                  resolvedCategoryId = resolution.categoryId;
                }
              } catch (_) {
                // ignore — fall back to the raw typed category name
              }

              // ২. সরাসরি কাস্টম ক্লিন পেলোড তৈরি (যা সিকিউরিটি রুলস ১০০% পাস করবে)
              final Map<String, dynamic> cleanPayload = {
                'name': productName,
                'category': resolvedCategoryName,
                if (resolvedCategoryId != null) 'categoryId': resolvedCategoryId,
                'generic': generic.text.trim(),
                'manufacturer': manufacturer.text.trim(),
                'type': type.text.trim(),
                'strength': strength.text.trim(),
                'overview': overview.text.trim(),
                'image': imageUrl,
                'imageUrl': imageUrl,
                'images': images,
                'variants': variantList,

                // Top-level product fields required by product cards, cart,
                // admin approval page and Firestore rules/schema validators.
                'price': firstPrice,
                'piecePrice': firstPrice,
                'oldPrice': firstMrp,
                'mrp': firstMrp,
                'unit': firstUnit,
                'stock': totalStock,
                'vendorName': vendorShopName,
                'shopName': vendorShopName,

                // ওনারশিপ এবং রুলস ভ্যালিডেশন ফিল্ডস
                'vendorId': vendorId,
                'sellerId': vendorId,
                'vendorOwnerId': ownerUid,
                'vendorOwnerIds': [ownerUid],
                'sellerUid': ownerUid,

                // New vendor products must wait for admin approval.
                // Existing approved products keep vendor-selected active/visible status.
                'isMarketplace': true,
                'approvalStatus': id == null ? 'pending' : dialogApprovalStatus,
                'isActive': id != null && dialogApprovalStatus == 'approved' ? isActive : false,
                'showOnHome': id != null && dialogApprovalStatus == 'approved' ? isActive : false,
                'isVisible': id != null && dialogApprovalStatus == 'approved' ? isActive : false,
                'isPublished': id != null && dialogApprovalStatus == 'approved' ? isActive : false,

                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (id == null) {
                // নতুন প্রোডাক্ট তৈরির সময় ক্রিয়েট টাইম যুক্ত করা
                cleanPayload['createdAt'] = FieldValue.serverTimestamp();
                await db.collection('products').add(cleanPayload);
              } else {
                // আপডেট করার সময় ওনারশিপ ফিল্ডগুলো রুলস অনুযায়ী পরিবর্তন করা সম্পূর্ণ নিষিদ্ধ (!changedAny)
                cleanPayload.remove('vendorId');
                cleanPayload.remove('sellerId');
                cleanPayload.remove('vendorOwnerId');
                cleanPayload.remove('vendorOwnerIds');
                cleanPayload.remove('sellerUid');
                cleanPayload.remove('isMarketplace');
                cleanPayload.remove('approvalStatus');
                cleanPayload.remove('isPublished');
                cleanPayload.remove('showOnHome');

                await db.collection('products').doc(id).update(cleanPayload);
              }

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              debugPrint('SAVE ERROR: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
              }
            } finally {
              setDialogState(() => saving = false);
            }
          }

          return AlertDialog(
            title: Text(id == null ? 'Add Vendor Product' : 'Edit Product'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final isMobileDialog = c.maxWidth < 520;

                        final imageBox = GestureDetector(
                          onTap: uploading ? null : () => pickImage(main: true),
                          child: Container(
                            height: 110,
                            width: 110,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: uploading
                                ? const Center(child: CircularProgressIndicator())
                                : imageUrl.isNotEmpty
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image),
                              ),
                            )
                                : const Icon(Icons.add_a_photo_rounded, size: 36),
                          ),
                        );

                        final imageButtons = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: uploading ? null : () => pickImage(main: true),
                              icon: const Icon(Icons.image_rounded),
                              label: const Text('Main Image'),
                            ),
                            OutlinedButton.icon(
                              onPressed: uploading ? null : () => pickImage(main: false),
                              icon: const Icon(Icons.collections_rounded),
                              label: const Text('Add Gallery'),
                            ),
                          ],
                        );

                        final activeBox = Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Active Product',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: dialogApprovalStatus == 'approved'
                                ? null
                                : const Text(
                              'Waiting for admin approval',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            value: isActive,
                            onChanged: dialogApprovalStatus == 'approved'
                                ? (v) => setDialogState(() => isActive = v)
                                : null,
                          ),
                        );

                        if (isMobileDialog) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              imageBox,
                              const SizedBox(height: 12),
                              imageButtons,
                              const SizedBox(height: 12),
                              activeBox,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            imageBox,
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  imageButtons,
                                  const SizedBox(height: 12),
                                  activeBox,
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final url = images[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    url,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 72,
                                      height: 72,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: InkWell(
                                    onTap: () => setDialogState(() => images.removeAt(i)),
                                    child: Container(
                                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Product Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: generic,
                            decoration: const InputDecoration(labelText: 'Generic', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: manufacturer,
                            decoration: const InputDecoration(labelText: 'Manufacturer', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: type,
                            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: strength,
                            decoration: const InputDecoration(labelText: 'Strength', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<CategoryModel>>(
                      stream: CategoryService.watchActiveCategories(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              'Category load failed: ${snap.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }

                        final cats = (snap.data ?? const <CategoryModel>[])
                            .map((e) => e.name.trim())
                            .where((e) => e.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort();

                        if (category != null &&
                            category!.isNotEmpty &&
                            !cats.contains(category)) {
                          cats.insert(0, category!);
                        }

                        return DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                          ),
                          items: cats
                              .map(
                                (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                              .toList(),
                          onChanged: cats.isEmpty
                              ? null
                              : (v) => setDialogState(() => category = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: overview,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Overview', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Variants', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                        OutlinedButton.icon(
                          onPressed: addVariant,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...variants.asMap().entries.map((entry) {
                      final i = entry.key;
                      final v = entry.value;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Variant ${i + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: variants.length <= 1
                                      ? null
                                      : () => setDialogState(() {
                                          variants.removeAt(i);
                                          variantOriginals.removeAt(i);
                                        }),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: v['name'],
                              decoration: const InputDecoration(
                                labelText: 'Unit / Size',
                                hintText: 'Example: 10 pcs, 100 ml, 1 strip',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: v['price'],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Selling Price',
                                      hintText: '৳',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: v['mrp'],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'MRP',
                                      hintText: '৳',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: v['stock'],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Stock Quantity',
                                hintText: 'Example: 20',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingVendor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (vendorId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Vendor account not found or not approved. Please contact admin.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Vendor Products'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('products')
            .where('vendorId', isEqualTo: vendorId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Products load failed: ${snap.error}'));
          }

          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = _filterDocs(snap.data!.docs).toList();

          docs.sort((a, b) {
            final ad = (a.data() as Map<String, dynamic>)['createdAt'];
            final bd = (b.data() as Map<String, dynamic>)['createdAt'];

            final at = ad is Timestamp ? ad.toDate() : DateTime(2000);
            final bt = bd is Timestamp ? bd.toDate() : DateTime(2000);

            return bt.compareTo(at);
          });

          return Column(
            children: [
              _filters(),
              Expanded(
                child: docs.isEmpty
                    ? _empty()
                    : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _productCard(doc.id, data);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search product...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            ),
          ),
          DropdownButton<String>(
            value: stockFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All stock')),
              DropdownMenuItem(value: 'in', child: Text('In stock')),
              DropdownMenuItem(value: 'low', child: Text('Low stock')),
              DropdownMenuItem(value: 'out', child: Text('Out stock')),
            ],
            onChanged: (v) => setState(() => stockFilter = v ?? 'all'),
          ),
          DropdownButton<String>(
            value: statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All status')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
            onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
          ),
        ],
      ),
    );
  }

  Widget _productCard(String id, Map<String, dynamic> data) {
    final image = _text(data['image']);
    final name = _text(data['name'], 'Product');
    final stock = _toInt(data['stock']);
    final price = _toDouble(data['price']);
    final isActive = data['isActive'] == true;
    final approvalStatus = _text(data['approvalStatus'], 'pending').toLowerCase();
    final displayActive = approvalStatus == 'approved' && isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 700;

          final info = Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: image.isNotEmpty
                    ? Image.network(image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported))
                    : const Icon(Icons.inventory_2_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(_text(data['category'], 'No category'), style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip('৳${price.toStringAsFixed(0)}', Colors.green),
                        _chip('Stock: $stock', stock <= 5 ? Colors.red : Colors.blue),
                        _chip(
                          approvalStatus == 'approved'
                              ? (displayActive ? 'Active' : 'Inactive')
                              : approvalStatus.toUpperCase(),
                          approvalStatus == 'approved'
                              ? (displayActive ? Colors.green : Colors.grey)
                              : approvalStatus == 'rejected'
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              IconButton(
                tooltip: 'Edit',
                onPressed: () => _showProductDialog(id: id, data: data),
                icon: const Icon(Icons.edit, color: Colors.blue),
              ),
              IconButton(
                tooltip: approvalStatus == 'approved'
                    ? (displayActive ? 'Visible - click to hide' : 'Hidden - click to show')
                    : 'Waiting for admin approval',
                onPressed: approvalStatus == 'approved'
                    ? () => _toggleProduct(id, !isActive)
                    : null,
                icon: Icon(
                  displayActive ? Icons.visibility : Icons.visibility_off,
                  color: approvalStatus == 'approved'
                      ? (displayActive ? Colors.green : Colors.orange)
                      : Colors.grey,
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteProduct(id),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const Divider(height: 18),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: info),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 82, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('No vendor products found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
    );
  }
}

class FirebaseAuthSafe {
  static String get currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
}