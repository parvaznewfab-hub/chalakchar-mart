import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/image_upload_service.dart';
import '../../services/product_service.dart';
import '../../services/ai_product_optimizer_service.dart';
import '../../widgets/ai_product_preview_dialog.dart';

class ManageProductsPage extends StatefulWidget {
  const ManageProductsPage({super.key});

  @override
  State<ManageProductsPage> createState() => _ManageProductsPageState();
}

class _ManageProductsPageState extends State<ManageProductsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();


  String searchText = '';
  String stockFilter = 'all';
  String statusFilter = 'all';
  String? selectedCategoryFilter;

  bool bulkWorking = false;
  bool permissionLoading = true;
  bool canViewProducts = false;
  bool canEditProducts = false;
  bool canDeleteProducts = false;
  bool canBulkProducts = false;
  bool canChangeProductStatus = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final results = await Future.wait<bool>([
        authService.hasPermission('products.view'),
        authService.hasPermission('products.edit'),
        authService.hasPermission('products.delete'),
        authService.hasPermission('products.bulk'),
        authService.hasPermission('products.status'),
      ]);

      if (!mounted) return;

      setState(() {
        canViewProducts = results[0] || results[1];
        canEditProducts = results[1];
        canDeleteProducts = results[2] || results[1];
        canBulkProducts = results[3] || results[1];
        canChangeProductStatus = results[4] || results[1];
        permissionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e', isError: true);
    }
  }

  bool _denyIf(bool denied, String message) {
    if (!denied) return false;
    _snack(message, isError: true);
    return true;
  }


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
    final t = (value ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Future<String> _uploadPickedImage(XFile file) async {
    try {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('Selected image is empty');
        }
        return ImageUploadService.upload(null, webImage: bytes, folder: 'products');
      }

      if (file.path.isEmpty) {
        throw Exception('Image file path is empty');
      }

      return ImageUploadService.upload(File(file.path), folder: 'products');
    } catch (e, s) {
      debugPrint('PRODUCT IMAGE UPLOAD ERROR: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }

  Future<void> _pickCSVFile() async {
    if (_denyIf(!canBulkProducts, 'You do not have products.bulk permission.')) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return;

      setState(() => bulkWorking = true);

      String csvContent;

      if (kIsWeb) {
        csvContent = utf8.decode(result.files.first.bytes ?? []);
      } else {
        csvContent = await File(result.files.first.path!).readAsString();
      }

      final rows = const CsvToListConverter().convert(csvContent);

      if (rows.length <= 1) {
        _snack('CSV file is empty', isError: true);
        return;
      }

      int added = 0;
      int updated = 0;
      int skipped = 0;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.isEmpty || _text(row[0]).isEmpty) {
          skipped++;
          continue;
        }

        final name = _text(row[0]);
        final strength = row.length > 1 ? _text(row[1]) : '';
        final type = row.length > 2 ? _text(row[2]) : 'Tablet';
        final price = row.length > 3 ? _toDouble(row[3]) : 0;
        final oldPrice = row.length > 4 ? _toDouble(row[4]) : price;
        final generic = row.length > 5 ? _text(row[5]) : '';
        final manufacturer = row.length > 6 ? _text(row[6]) : '';
        final variantName = row.length > 7 && _text(row[7]).isNotEmpty ? _text(row[7]) : 'Default';
        final stock = row.length > 8 ? _toInt(row[8]) : 0;
        final category = row.length > 9 && _text(row[9]).isNotEmpty ? _text(row[9]) : 'Other';
        final overview = row.length > 10 ? _text(row[10]) : '';

        final existing = await db
            .collection('products')
            .where('name', isEqualTo: name)
            .where('strength', isEqualTo: strength)
            .limit(1)
            .get();

        final newVariant = {
          'name': variantName,
          'price': price,
          'mrp': oldPrice,
          'stock': stock,
        };

        if (existing.docs.isNotEmpty) {
          final doc = existing.docs.first;
          final data = doc.data();
          final variants = List<Map<String, dynamic>>.from(
            (data['variants'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
          );

          final exists = variants.any(
                (v) => _text(v['name']).toLowerCase() == variantName.toLowerCase(),
          );

          if (exists) {
            skipped++;
            continue;
          }

          variants.add(newVariant);

          final payload = ProductService.buildProductPayload(
            name: _text(data['name']),
            category: _text(data['category']).isEmpty ? category : _text(data['category']),
            generic: _text(data['generic']),
            manufacturer: _text(data['manufacturer']),
            type: _text(data['type']).isEmpty ? type : _text(data['type']),
            strength: _text(data['strength']).isEmpty ? strength : _text(data['strength']),
            overview: _text(data['overview']).isEmpty ? overview : _text(data['overview']),
            image: _text(data['image']),
            images: List<String>.from(data['images'] ?? []),
            videoUrl: _text(data['videoUrl']),
            isActive: data['isActive'] != false,
            isMarketplace: data['isMarketplace'] == true,
            vendorId: _text(data['vendorId']).isEmpty ? 'super_admin' : _text(data['vendorId']),
            vendorName: _text(data['vendorName']).isEmpty ? 'ChalakChar Mart' : _text(data['vendorName']),
            approvalStatus: _text(data['approvalStatus']).isEmpty ? 'approved' : _text(data['approvalStatus']),
            variants: variants,
          );

          await ProductService.saveProduct(
            productId: doc.id,
            payload: payload,
          );

          updated++;
        } else {
          final payload = ProductService.buildProductPayload(
            name: name,
            category: category,
            generic: generic,
            manufacturer: manufacturer,
            type: type,
            strength: strength,
            overview: overview,

            isActive: true,
            isMarketplace: false,
            vendorId: 'super_admin',
            vendorName: 'ChalakChar Mart',
            approvalStatus: 'approved',

            variants: [newVariant],
            includeCreatedAt: true,
          );

          await ProductService.saveProduct(payload: payload);

          added++;
        }
      }

      _snack('CSV done: $added added, $updated updated, $skipped skipped');
    } catch (e) {
      _snack('CSV error: $e', isError: true);
    } finally {
      if (mounted) setState(() => bulkWorking = false);
    }
  }

  Future<void> _showJsonBulkDialog() async {
    if (_denyIf(!canBulkProducts, 'You do not have products.bulk permission.')) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Paste JSON Products'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[{"name":"Ace","price":2,"stock":100,"category":"Product"}]',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final raw = jsonDecode(controller.text);
                if (raw is! List) throw Exception('JSON must be a list');

                int count = 0;

                for (final item in raw) {
                  if (item is! Map) continue;

                  final price = _toDouble(item['price']);
                  final oldPrice = _toDouble(item['oldPrice'] ?? item['mrp'] ?? price);
                  final stock = _toInt(item['stock']);
                  final variantName = _text(item['variantName']).isEmpty ? 'Default' : _text(item['variantName']);

                  final payload = ProductService.buildProductPayload(
                    name: _text(item['name']),
                    category: _text(item['category']).isEmpty ? 'Other' : _text(item['category']),
                    generic: _text(item['generic']),
                    manufacturer: _text(item['manufacturer']),
                    type: _text(item['type']).isEmpty ? 'Tablet' : _text(item['type']),
                    strength: _text(item['strength']),
                    overview: _text(item['overview']),
                    image: _text(item['image']),
                    images: List<String>.from(item['images'] ?? []),
                    videoUrl: _text(item['videoUrl']),

                    isActive: true,
                    isMarketplace: false,
                    vendorId: 'super_admin',
                    vendorName: 'ChalakChar Mart',
                    approvalStatus: 'approved',

                    variants: [
                      {
                        'name': variantName,
                        'price': price,
                        'mrp': oldPrice,
                        'stock': stock,
                      }
                    ],
                    includeCreatedAt: true,
                  );

                  await ProductService.saveProduct(payload: payload);

                  count++;
                }

                if (context.mounted) Navigator.pop(context);
                _snack('$count products uploaded from JSON');
              } catch (e) {
                _snack('JSON error: $e', isError: true);
              }
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDialog({
    String? id,
    Map<String, dynamic>? data,
  }) async {
    if (_denyIf(!canEditProducts, 'You do not have products.edit permission.')) return;

    final name = TextEditingController(text: _text(data?['name']));
    final generic = TextEditingController(text: _text(data?['generic']));
    final manufacturer = TextEditingController(text: _text(data?['manufacturer']));
    final type = TextEditingController(text: _text(data?['type']));
    final strength = TextEditingController(text: _text(data?['strength']));
    final overview = TextEditingController(text: _text(data?['overview']));
    final videoUrl = TextEditingController(text: _text(data?['videoUrl']));

    String? category = _text(data?['category']).isEmpty ? null : _text(data?['category']);
    String imageUrl = _text(data?['image']);
    List<String> images = List<String>.from(data?['images'] ?? []);
    bool isActive = data?['isActive'] != false;
    bool saving = false;
    bool uploading = false;
    bool aiLoading = false;

    String banglaTitle = _text(data?['banglaTitle']);
    List<String> seoTags = List<String>.from(data?['seoTags'] ?? []);

    List<Map<String, TextEditingController>> variantControllers = [];

    final oldVariants = data?['variants'] is List ? data!['variants'] as List : [];

    if (oldVariants.isNotEmpty) {
      for (final v in oldVariants) {
        if (v is! Map) continue;
        variantControllers.add({
          'name': TextEditingController(text: _text(v['name'])),
          'price': TextEditingController(text: _toDouble(v['price']).toStringAsFixed(0)),
          'mrp': TextEditingController(text: _toDouble(v['mrp'] ?? v['oldPrice']).toStringAsFixed(0)),
          'stock': TextEditingController(text: _toInt(v['stock']).toString()),
        });
      }
    } else {
      variantControllers.add({
        'name': TextEditingController(text: _text(data?['unit']).isEmpty ? 'Default' : _text(data?['unit'])),
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
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );

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
              _snack('Image upload failed: $e', isError: true);
            } finally {
              setDialogState(() => uploading = false);
            }
          }

          void addVariant() {
            setDialogState(() {
              variantControllers.add({
                'name': TextEditingController(text: 'Default'),
                'price': TextEditingController(text: '0'),
                'mrp': TextEditingController(text: '0'),
                'stock': TextEditingController(text: '0'),
              });
            });
          }

          Future<void> optimizeWithAI() async {
            final productName = name.text.trim();

            if (productName.isEmpty) {
              _snack('Product name required before AI optimize', isError: true);
              return;
            }

            if (aiLoading || saving) return;

            setDialogState(() => aiLoading = true);

            try {
              final result = await AIProductOptimizerService.optimize(
                title: productName,
                description: overview.text.trim(),
                category: category ?? '',
              );

              if (!mounted) return;

              if (result == null) {
                _snack('AI optimize failed. Please try again.', isError: true);
                return;
              }

              await showDialog(
                context: this.context,
                builder: (_) => AIProductPreviewDialog(
                  title: result.title,
                  banglaTitle: result.banglaTitle,
                  description: result.description,
                  seoTags: result.seoTags,
                  onApply: () {
                    if (!mounted) return;

                    name.text = result.title;
                    overview.text = result.description;

                    setDialogState(() {
                      banglaTitle = result.banglaTitle;
                      seoTags = result.seoTags;
                    });
                  },
                ),
              );
            } catch (e, s) {
              debugPrint('AI dialog error: $e');
              debugPrintStack(stackTrace: s);

              if (mounted) {
                // If it's a 401, give a clearer message
                String message = e.toString().contains('401')
                    ? 'AI Config Error: Invalid API Key. Please contact admin.'
                    : 'AI error: $e';
                _snack(message, isError: true);
              }
            } finally {
              if (mounted) {
                setDialogState(() {
                  aiLoading = false;
                });
              }
            }
          }

          Future<void> saveProduct() async {
            final user = FirebaseAuth.instance.currentUser;

            debugPrint('========== PRODUCT SAVE DEBUG ==========');
            debugPrint('UID: ${user?.uid}');
            debugPrint('EMAIL: ${user?.email}');

            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user!.uid)
                .get();

            debugPrint('USER DOC: ${userDoc.data()}');
            final productName = name.text.trim();

            if (productName.isEmpty) {
              _snack('Product name required', isError: true);
              return;
            }

            if (category == null || category!.isEmpty) {
              _snack('Category required', isError: true);
              return;
            }

            final variants = variantControllers.map((v) {
              final vName = v['name']!.text.trim().isEmpty ? 'Default' : v['name']!.text.trim();
              return {
                'name': vName,
                'price': _toDouble(v['price']!.text),
                'mrp': _toDouble(v['mrp']!.text),
                'stock': _toInt(v['stock']!.text),
              };
            }).toList();

            setDialogState(() => saving = true);

            try {
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
                videoUrl: videoUrl.text.trim(),
                isActive: isActive,
                isMarketplace: false,
                vendorId: 'super_admin',
                vendorName: 'ChalakChar Mart',
                approvalStatus: 'approved',
                variants: variants,
                includeCreatedAt: id == null,
              );

              payload.addAll({
                'banglaTitle': banglaTitle,
                'seoTags': seoTags,
                'aiOptimized': banglaTitle.isNotEmpty || seoTags.isNotEmpty,
                'aiOptimizedAt': banglaTitle.isNotEmpty || seoTags.isNotEmpty
                    ? FieldValue.serverTimestamp()
                    : null,
              });

              await ProductService.saveProduct(
                productId: id,
                payload: payload,
              );

              _snack(id == null ? 'Product added' : 'Product updated');

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              _snack('Save failed: $e', isError: true);
            } finally {
              setDialogState(() => saving = false);
            }
          }

          return AlertDialog(
            title: Text(id == null ? 'Add Product' : 'Edit Product'),
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
                                subtitle: canChangeProductStatus
                                    ? null
                                    : const Text('products.status permission required'),
                                value: isActive,
                                onChanged: canChangeProductStatus
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
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
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
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: aiLoading || saving ? null : optimizeWithAI,
                        icon: aiLoading
                            ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.auto_awesome),
                        label: Text(aiLoading ? 'Optimizing...' : 'AI Optimize'),
                      ),
                    ),

                    if (banglaTitle.isNotEmpty || seoTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurple.withOpacity(0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (banglaTitle.isNotEmpty) ...[
                              const Text(
                                'Bangla Title',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(banglaTitle),
                            ],
                            if (seoTags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'SEO Tags',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: seoTags
                                    .map((tag) => Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: generic,
                            decoration: const InputDecoration(
                              labelText: 'Generic',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: manufacturer,
                            decoration: const InputDecoration(
                              labelText: 'Manufacturer',
                              border: OutlineInputBorder(),
                            ),
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
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: strength,
                            decoration: const InputDecoration(
                              labelText: 'Strength',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseService.getCategories(onlyActive: true),
                      builder: (context, snap) {
                        final cats = snap.data?.docs
                            .map((e) => (e.data() as Map<String, dynamic>)['name']?.toString() ?? '')
                            .where((e) => e.isNotEmpty)
                            .toList() ??
                            [];

                        if (category != null && category!.isNotEmpty && !cats.contains(category)) {
                          cats.insert(0, category!);
                        }

                        return DropdownButtonFormField<String>(
                          value: category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                          ),
                          items: cats.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setDialogState(() => category = v),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: overview,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Overview',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: videoUrl,
                      decoration: const InputDecoration(
                        labelText: 'Video URL',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Variants',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: addVariant,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Variant'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    ...List.generate(variantControllers.length, (index) {
                      final v = variantControllers[index];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: v['name'],
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v['price'],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Price',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v['mrp'],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'MRP',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v['stock'],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: variantControllers.length == 1
                                  ? null
                                  : () => setDialogState(() => variantControllers.removeAt(index)),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
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
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : saveProduct,
                icon: saving
                    ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save_rounded),
                label: Text(id == null ? 'Add Product' : 'Update Product'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteProduct(String id) async {
    if (_denyIf(!canDeleteProducts, 'You do not have products.delete permission.')) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product?'),
        content: const Text('This product will be permanently deleted.'),
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
      _snack('Product deleted');
    }
  }

  Future<void> _toggleStatus(String id, bool active) async {
    if (_denyIf(!canChangeProductStatus, 'You do not have products.status permission.')) return;

    await db.collection('products').doc(id).set({
      'isActive': active,
      'isVisible': active,
      'isPublished': active,
      'showOnHome': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<QueryDocumentSnapshot> _filterProducts(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = _text(data['name']).toLowerCase();
      final generic = _text(data['generic']).toLowerCase();
      final manufacturer = _text(data['manufacturer']).toLowerCase();
      final category = _text(data['category']);
      final approvalStatus = _text(data['approvalStatus'], 'approved');
      final isVendorProduct = data['isMarketplace'] == true ||
          _text(data['vendorId'], 'super_admin') != 'super_admin';
      final active = data['isActive'] == true;
      final displayActive = isVendorProduct && approvalStatus != 'approved'
          ? false
          : active;
      final stock = _toInt(data['stock']);

      final search = searchText.toLowerCase().trim();

      if (search.isNotEmpty &&
          !name.contains(search) &&
          !generic.contains(search) &&
          !manufacturer.contains(search)) {
        return false;
      }

      if (selectedCategoryFilter != null &&
          selectedCategoryFilter!.isNotEmpty &&
          category != selectedCategoryFilter) {
        return false;
      }

      if (statusFilter == 'active' && !displayActive) return false;
      if (statusFilter == 'inactive' && displayActive) return false;

      if (stockFilter == 'low' && stock > 5) return false;
      if (stockFilter == 'out' && stock > 0) return false;
      if (stockFilter == 'available' && stock <= 0) return false;

      return true;
    }).toList();
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade800 : null,
      ),
    );
  }

  Widget _productImage(String url) {
    if (url.isEmpty) {
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 58,
          height: 58,
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  Widget _statusChip(bool active) {
    return Chip(
      label: Text(active ? 'Active' : 'Inactive'),
      backgroundColor: active ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
      labelStyle: TextStyle(
        color: active ? Colors.green.shade800 : Colors.red.shade800,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _approvalChip(String status) {
    Color color = Colors.orange;
    final clean = status.trim().isEmpty ? 'pending' : status.trim().toLowerCase();

    if (clean == 'approved') {
      color = Colors.green;
    } else if (clean == 'rejected') {
      color = Colors.red;
    }

    return Chip(
      label: Text(clean.toUpperCase()),
      backgroundColor: color.withOpacity(0.12),
      labelStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _stockChip(int stock) {
    Color color = Colors.green;
    String label = 'Stock: $stock';

    if (stock <= 0) {
      color = Colors.red;
      label = 'Out';
    } else if (stock <= 5) {
      color = Colors.orange;
      label = 'Low: $stock';
    }

    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewProducts) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  'Products access denied',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'You need products.view permission to open Product Manager.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Product Manager Pro',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (canBulkProducts) ...[
                      OutlinedButton.icon(
                        onPressed: bulkWorking ? null : _pickCSVFile,
                        icon: bulkWorking
                            ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.table_chart_rounded),
                        label: const Text('CSV Upload'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: bulkWorking ? null : _showJsonBulkDialog,
                        icon: const Icon(Icons.data_object_rounded),
                        label: const Text('JSON'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (canEditProducts)
                      ElevatedButton.icon(
                        onPressed: () => _showProductDialog(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Product'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    final isSmall = c.maxWidth < 850;

                    final filters = [
                      Expanded(
                        flex: isSmall ? 1 : 2,
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search product, generic, manufacturer...',
                            prefixIcon: Icon(Icons.search_rounded),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => searchText = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: stockFilter,
                          decoration: const InputDecoration(
                            labelText: 'Stock',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(value: 'available', child: Text('Available')),
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(value: 'out', child: Text('Out')),
                          ],
                          onChanged: (v) => setState(() => stockFilter = v ?? 'all'),
                        ),
                      ),
                    ];

                    if (isSmall) {
                      return Column(
                        children: [
                          filters[0],
                          const SizedBox(height: 8),
                          Row(children: filters.sublist(2)),
                        ],
                      );
                    }

                    return Row(children: filters);
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db.collection('products').orderBy('createdAt', descending: true).limit(300).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('No products found'));
                }

                final products = _filterProducts(snap.data!.docs);

                if (products.isEmpty) {
                  return const Center(child: Text('No matching products'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = products[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final active = data['isActive'] == true;
                    final approvalStatus = _text(data['approvalStatus'], 'approved');
                    final isVendorProduct = data['isMarketplace'] == true ||
                        _text(data['vendorId'], 'super_admin') != 'super_admin';
                    final isPendingVendorProduct =
                        isVendorProduct && approvalStatus != 'approved';
                    final displayActive = isPendingVendorProduct ? false : active;
                    final stock = _toInt(data['stock']);
                    final variants = data['variants'] is List ? data['variants'] as List : [];

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _productImage(_text(data['image'])),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _text(data['name']).isEmpty ? 'Unnamed Product' : _text(data['name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_text(data['category'])} • ${_text(data['strength'])} • ${_text(data['manufacturer'])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      _statusChip(displayActive),
                                      if (isPendingVendorProduct)
                                        _approvalChip(approvalStatus),
                                      _stockChip(stock),
                                      Chip(label: Text('৳${_toDouble(data['price']).toStringAsFixed(0)}')),
                                      Chip(label: Text('${variants.length} variants')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: displayActive,
                              onChanged: canChangeProductStatus && !isPendingVendorProduct
                                  ? (v) => _toggleStatus(doc.id, v)
                                  : null,
                            ),
                            if (canEditProducts)
                              IconButton(
                                tooltip: 'Edit',
                                onPressed: () => _showProductDialog(id: doc.id, data: data),
                                icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                              ),
                            if (canDeleteProducts)
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _deleteProduct(doc.id),
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
