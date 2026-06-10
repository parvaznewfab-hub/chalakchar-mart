import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/image_upload_service.dart';
import '../../services/category_service.dart';
import '../../services/product_service.dart';

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

  String get vendorId => FirebaseAuthSafe.currentUid;

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
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
    await db.collection('products').doc(id).set({
      'isActive': active,
      'isVisible': active,
      'isPublished': active,
      'showOnHome': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final doc = await db.collection('vendors').doc(vendorId).get();
    return doc.data() ?? {};
  }

  Future<void> _showProductDialog({
    String? id,
    Map<String, dynamic>? data,
  }) async {
    final vendor = await _vendorInfo();

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
      }
    } else {
      variants.add({
        'name': TextEditingController(text: _text(data?['unit'], 'Default')),
        'price': TextEditingController(text: _toDouble(data?['price']).toStringAsFixed(0)),
        'mrp': TextEditingController(text: _toDouble(data?['oldPrice']).toStringAsFixed(0)),
        'stock': TextEditingController(text: _toInt(data?['stock']).toString()),
      });
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
              if (mounted) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Variant name required')),
                );
                return;
              }

              if (variantNames.contains(n)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Duplicate variant: $n')),
                );
                return;
              }

              variantNames.add(n);
            }

            final variantList = variants.map((v) {
              final variantName = v['name']!.text.trim().isEmpty ? 'Default' : v['name']!.text.trim();
              return {
                'name': variantName,
                'price': _toDouble(v['price']!.text),
                'mrp': _toDouble(v['mrp']!.text),
                'stock': _toInt(v['stock']!.text),
              };
            }).toList();

            setDialogState(() => saving = true);

            try {
              final vendorName = _text(vendor['shopName'], 'Vendor');

              final payload = ProductService.buildProductPayload(
                name: productName,
                category: category!,
                generic: generic.text.trim(),
                manufacturer: manufacturer.text.trim(),
                type: type.text.trim(),
                strength: strength.text.trim(),
                overview: overview.text.trim(),
                image: imageUrl,
                images: images,
                isActive: id == null ? false : isActive,
                isMarketplace: true,
                vendorId: vendorId,
                vendorName: vendorName,
                approvalStatus: id == null ? 'pending' : _text(data?['approvalStatus'], 'pending'),
                variants: variantList,
                includeCreatedAt: id == null,
              );

              final approved = _text(payload['approvalStatus'], 'pending') == 'approved';
              final active = approved && payload['isActive'] == true;

              payload['isActive'] = active;
              payload['showOnHome'] = active;
              payload['isVisible'] = active;
              payload['isPublished'] = active;

              await ProductService.saveProduct(
                productId: id,
                payload: payload,
              );

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) {
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
                    Row(
                      children: [
                        GestureDetector(
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
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                              ),
                            )
                                : const Icon(Icons.add_a_photo_rounded, size: 36),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Wrap(
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
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Active Product'),
                                subtitle: dialogApprovalStatus == 'approved'
                                    ? null
                                    : const Text('Admin approval required before active'),
                                value: isActive,
                                onChanged: dialogApprovalStatus == 'approved'
                                    ? (v) => setDialogState(() => isActive = v)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
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
                          value: category,
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
                                      : () => setDialogState(() => variants.removeAt(i)),
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
    if (vendorId.isEmpty) {
      return const Scaffold(body: Center(child: Text('Vendor login required')));
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


