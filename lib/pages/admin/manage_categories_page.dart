import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../utils/category_lookup.dart';
import '../../utils/category_normalize.dart';

class ManageCategoriesPage extends StatefulWidget {
  const ManageCategoriesPage({super.key});

  @override
  State<ManageCategoriesPage> createState() => _ManageCategoriesPageState();
}

class _ManageCategoriesPageState extends State<ManageCategoriesPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final priorityController = TextEditingController(text: '0');
  final descriptionController = TextEditingController();
  final searchController = TextEditingController();

  String searchText = '';
  String statusFilter = 'all';

  bool isActive = true;
  bool isFeatured = false;
  bool showOnHome = true;
  bool saving = false;
  bool permissionLoading = true;

  bool canViewCategories = false;
  bool canEditCategories = false;
  bool canDeleteCategories = false;
  bool canChangeCategoryStatus = false;

  File? imageFile;
  Uint8List? webImage;

  /// Category ids whose subcategory list is expanded in the card.
  final Set<String> expandedCategoryIds = {};

  /// Product count per category name for the card chip; refreshed when the
  /// categories stream emits (see _categoryListBody).
  final Map<String, Future<_ProductCounts>> _productCountCache = {};
  QuerySnapshot? _lastCategorySnapshot;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final canAccessAdmin = await authService.canAccessAdminPanel();

      final canView = await authService.hasPermission('categories.view');
      final canEdit = await authService.hasPermission('categories.edit');
      final canDelete = await authService.hasPermission('categories.delete');
      final canStatus = await authService.hasPermission('categories.status');

      if (!mounted) return;

      setState(() {
        canViewCategories = canAccessAdmin && (canView || canEdit);
        canEditCategories = canAccessAdmin && canEdit;
        canDeleteCategories = canAccessAdmin && (canDelete || canEdit);
        canChangeCategoryStatus = canAccessAdmin && (canStatus || canEdit);
        permissionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        canViewCategories = false;
        canEditCategories = false;
        canDeleteCategories = false;
        canChangeCategoryStatus = false;
        permissionLoading = false;
      });
    }
  }

  bool _requirePermission(bool allowed, String message) {
    if (allowed) return true;
    _snack(message);
    return false;
  }

  @override
  void dispose() {
    nameController.dispose();
    priorityController.dispose();
    descriptionController.dispose();
    searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  String? _number(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Required';
    if (int.tryParse(text) == null) return 'Enter valid number';
    return null;
  }

  Future<void> _pickImage({
    void Function(File?)? onFile,
    void Function(Uint8List?)? onWeb,
  }) async {
    if (!_requirePermission(canEditCategories, 'You do not have permission to upload category images.')) {
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked == null) return;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      if (onWeb != null) {
        onWeb(bytes);
      } else {
        setState(() => webImage = bytes);
      }
    } else {
      final file = File(picked.path);
      if (onFile != null) {
        onFile(file);
      } else {
        setState(() => imageFile = file);
      }
    }
  }

  /// Uploads into the flat `categories/` folder (the only category path
  /// storage.rules allows). [prefix] keeps subcategory images
  /// distinguishable there without needing a new storage rule.
  Future<String> _uploadImage(File? file, Uint8List? bytes, {String prefix = ''}) async {
    if (file == null && bytes == null) return '';

    final ref = FirebaseStorage.instance
        .ref()
        .child('categories/$prefix${DateTime.now().millisecondsSinceEpoch}.jpg');

    if (kIsWeb && bytes != null) {
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else if (file != null) {
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    }

    return ref.getDownloadURL();
  }

  void _clearForm() {
    nameController.clear();
    priorityController.text = '0';
    descriptionController.clear();

    setState(() {
      imageFile = null;
      webImage = null;
      isActive = true;
      isFeatured = false;
      showOnHome = true;
    });
  }

  Future<void> _addCategory() async {
    if (!_requirePermission(canEditCategories, 'You do not have permission to add categories.')) {
      return;
    }

    if (!formKey.currentState!.validate()) return;

    final name = nameController.text.trim();

    setState(() => saving = true);

    try {
      final duplicate = await _categoryNameClash(name);
      if (duplicate != null) {
        _snack('Category "$duplicate" already exists');
        return;
      }

      final imageUrl = await _uploadImage(imageFile, webImage);

      await db.collection('categories').add({
        'name': name,
        // Same key ensureCategoryExists (functions) looks up, so a later
        // import of this name reuses this doc instead of duplicating it.
        'normalizedName': normalizeCategoryKey(name),
        'source': 'admin',
        'autoCreated': false,
        'priority': _toInt(priorityController.text),
        'description': descriptionController.text.trim(),
        'image': imageUrl,
        'imageUrl': imageUrl,
        'isActive': isActive,
        'isFeatured': isFeatured,
        'showOnHome': showOnHome,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _clearForm();
      _snack('Category added successfully');
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Name of an existing live category whose normalized key equals [name]'s
  /// (other than [excludeId]); null when the name is free. Compares keys
  /// computed from every doc's name rather than querying `normalizedName`,
  /// because older docs created here never stored that field.
  Future<String?> _categoryNameClash(String name, {String? excludeId}) async {
    final snap = await db.collection('categories').get();
    return findCategoryNameClash(
      snap.docs.map((d) => (id: d.id, data: d.data())),
      name,
      excludeId: excludeId,
    );
  }

  /// Total and live (isActive + approved — what customers see) products
  /// in a category, plus live counts per subcategoryId, from one read.
  Future<_ProductCounts> _productCount(String categoryName) async {
    final snap = await db
        .collection('products')
        .where('category', isEqualTo: categoryName)
        .limit(2000)
        .get();

    var live = 0;
    final liveBySub = <String, int>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isActive'] != true || data['approvalStatus'] != 'approved') continue;
      live++;
      final subId = _text(data['subcategoryId']);
      if (subId.isNotEmpty) liveBySub[subId] = (liveBySub[subId] ?? 0) + 1;
    }
    return (total: snap.docs.length, live: live, liveBySub: liveBySub);
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> data) async {
    if (!_requirePermission(canEditCategories, 'You do not have permission to edit categories.')) {
      return;
    }

    final name = TextEditingController(text: _text(data['name']));
    final priority = TextEditingController(text: _toInt(data['priority']).toString());
    final description = TextEditingController(text: _text(data['description']));
    final variantLabel = TextEditingController(text: _text(data['variantLabel']));

    bool active = data['isActive'] != false;
    bool featured = data['isFeatured'] == true;
    bool home = data['showOnHome'] != false;

    File? newImageFile;
    Uint8List? newWebImage;

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget imageBox() {
            Widget child;

            if (newWebImage != null) {
              child = Image.memory(newWebImage!, fit: BoxFit.cover);
            } else if (newImageFile != null) {
              child = Image.file(newImageFile!, fit: BoxFit.cover);
            } else if (_text(data['imageUrl'] ?? data['image']).isNotEmpty) {
              child = Image.network(
                _text(data['imageUrl'] ?? data['image']),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              );
            } else {
              child = const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, size: 38),
                  SizedBox(height: 6),
                  Text('Tap to upload image'),
                ],
              );
            }

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                await _pickImage(
                  onFile: (file) => setDialogState(() => newImageFile = file),
                  onWeb: (bytes) => setDialogState(() => newWebImage = bytes),
                );
              },
              child: Container(
                height: 150,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: child,
              ),
            );
          }

          Future<void> saveEdit() async {
            final newName = name.text.trim();

            if (newName.isEmpty) {
              _snack('Category name required');
              return;
            }

            final duplicate = await _categoryNameClash(newName, excludeId: id);
            if (duplicate != null) {
              _snack('Category "$duplicate" already exists');
              return;
            }

            String imageUrl = _text(data['imageUrl'] ?? data['image']);

            if (newImageFile != null || newWebImage != null) {
              imageUrl = await _uploadImage(newImageFile, newWebImage);
            }

            await db.collection('categories').doc(id).update({
              'name': newName,
              // A merged-away doc keeps no key (categoryMerge.js removes it)
              // so the backend resolver never matches it again.
              if (!isMergedCategory(data)) 'normalizedName': normalizeCategoryKey(newName),
              'priority': _toInt(priority.text),
              'description': description.text.trim(),
              // Empty = automatic: remove the field rather than store "".
              'variantLabel': variantLabel.text.trim().isEmpty
                  ? FieldValue.delete()
                  : variantLabel.text.trim(),
              'image': imageUrl,
              'imageUrl': imageUrl,
              'isActive': active,
              'isFeatured': featured,
              'showOnHome': home,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            // Subcategories carry a denormalized copy of the parent name.
            if (newName != _text(data['name'])) {
              await _syncSubcategoryParentName(id, newName);
            }

            if (!context.mounted) return;
            Navigator.pop(context);
            _snack('Category updated');
          }

          return AlertDialog(
            title: const Text('Edit Category'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    imageBox(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Category Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priority,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('category-variant-label'),
                      controller: variantLabel,
                      decoration: const InputDecoration(
                        labelText: 'Variant label',
                        hintText: 'e.g. Model, Type, Capacity',
                        helperText: 'Default label before product variants ("Model: 12 Pro"). Empty = automatic.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: active,
                      title: const Text('Active'),
                      onChanged: (v) => setDialogState(() => active = v),
                    ),
                    SwitchListTile(
                      value: featured,
                      title: const Text('Featured'),
                      onChanged: (v) => setDialogState(() => featured = v),
                    ),
                    SwitchListTile(
                      value: home,
                      title: const Text('Show on Homepage'),
                      onChanged: (v) => setDialogState(() => home = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: saveEdit,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCategory(String id, Map<String, dynamic> data) async {
    if (!_requirePermission(canDeleteCategories, 'You do not have permission to delete categories.')) {
      return;
    }

    final categoryName = _text(data['name']);

    try {
      // Fresh read (not the stream) so the safety check sees every child.
      final subSnap = await db
          .collection('subcategories')
          .where('categoryId', isEqualTo: id)
          .get();
      final subDocs = subSnap.docs;

      // A product can point at this category three different ways; all
      // three must be zero before anything is deleted.
      final byName = categoryName.isEmpty
          ? 0
          : await _countProducts(
              db.collection('products').where('category', isEqualTo: categoryName));
      final byId = await _countProducts(
          db.collection('products').where('categoryId', isEqualTo: id));
      final bySubcategory = await _countProductsInSubcategories(
          subDocs.map((d) => d.id).toList());

      if (!mounted) return;

      if (byName > 0 || byId > 0 || bySubcategory > 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cannot delete category'),
            content: Text(
              'Products are still linked to "$categoryName":\n\n'
              '• by category name: $byName\n'
              '• by category id: $byId\n'
              '• through its subcategories: $bySubcategory\n\n'
              'Move or delete those products first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final subNames = subDocs
          .map((d) => _text(d.data()['name'], 'Unnamed'))
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete category?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"$categoryName" will be permanently deleted.'),
                if (subNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This category has ${subNames.length} '
                            '${subNames.length == 1 ? 'subcategory' : 'subcategories'}. '
                            'They will be deleted too:',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      thumbVisibility: subNames.length > 8,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final n in subNames)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $n'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(subNames.isEmpty
                  ? 'Delete'
                  : 'Delete category + ${subNames.length}'),
            ),
          ],
        ),
      );

      if (ok != true) return;

      // Children first, parent in the last batch, so a partial failure
      // never leaves subcategories pointing at a missing parent.
      final refs = [
        ...subDocs.map((d) => d.reference),
        db.collection('categories').doc(id),
      ];
      for (var i = 0; i < refs.length; i += _batchLimit) {
        final batch = db.batch();
        for (final ref in refs.skip(i).take(_batchLimit)) {
          batch.delete(ref);
        }
        await batch.commit();
      }

      expandedCategoryIds.remove(id);
      _snack(subNames.isEmpty
          ? 'Category deleted'
          : 'Category and ${subNames.length} subcategories deleted');
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  static const int _batchLimit = 450;

  Future<int> _countProducts(Query query) async {
    final agg = await query.count().get();
    return agg.count ?? 0;
  }

  /// Products whose subcategoryId is any of [subIds]. `whereIn` takes at
  /// most 30 values per query, so ids are chunked.
  Future<int> _countProductsInSubcategories(List<String> subIds) async {
    var total = 0;
    for (var i = 0; i < subIds.length; i += 30) {
      final chunk = subIds.skip(i).take(30).toList();
      total += await _countProducts(
        db.collection('products').where('subcategoryId', whereIn: chunk),
      );
    }
    return total;
  }

  Future<void> _syncSubcategoryParentName(String categoryId, String newName) async {
    final snap = await db
        .collection('subcategories')
        .where('categoryId', isEqualTo: categoryId)
        .get();
    for (var i = 0; i < snap.docs.length; i += _batchLimit) {
      final batch = db.batch();
      for (final doc in snap.docs.skip(i).take(_batchLimit)) {
        batch.update(doc.reference, {
          'categoryName': newName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  // ---------------------------------------------------------------------------
  // Subcategories
  //
  // Schema is the one functions/category/ensureSubcategoryExists.js writes:
  // top-level `subcategories` collection, parent link in `categoryId`, dedup
  // on (categoryId, normalizedName), slug unique per parent. Products link
  // through `subcategoryId` only.
  // ---------------------------------------------------------------------------

  /// Another subcategory under [categoryId] already using [normalizedName],
  /// ignoring [excludeId] (the doc being edited). Case- and
  /// whitespace-insensitive via normalizeCategoryKey.
  Future<String?> _duplicateSubcategoryName(
    String categoryId,
    String normalizedName, {
    String? excludeId,
  }) async {
    final snap = await db
        .collection('subcategories')
        .where('categoryId', isEqualTo: categoryId)
        .where('normalizedName', isEqualTo: normalizedName)
        .limit(2)
        .get();
    for (final doc in snap.docs) {
      if (doc.id != excludeId) return _text(doc.data()['name'], normalizedName);
    }
    return null;
  }

  /// Same algorithm as generateUniqueSlug in categoryNormalize.js: base slug,
  /// then "-2", "-3", ... scoped to the parent category.
  Future<String> _uniqueSubcategorySlug(
    String categoryId,
    String name, {
    String? excludeId,
  }) async {
    final base = slugifyCategoryName(name).isEmpty ? 'category' : slugifyCategoryName(name);
    var candidate = base;
    for (var suffix = 2; suffix <= 51; suffix++) {
      final snap = await db
          .collection('subcategories')
          .where('categoryId', isEqualTo: categoryId)
          .where('slug', isEqualTo: candidate)
          .limit(2)
          .get();
      if (snap.docs.every((d) => d.id == excludeId)) return candidate;
      candidate = '$base-$suffix';
    }
    throw StateError('Could not find a free slug for "$base"');
  }

  Future<void> _showSubcategoryDialog({
    required List<QueryDocumentSnapshot> categories,
    required String parentId,
    String? subId,
    Map<String, dynamic>? data,
  }) async {
    if (!_requirePermission(canEditCategories, 'You do not have permission to edit subcategories.')) {
      return;
    }

    final editing = subId != null;
    final original = data ?? const <String, dynamic>{};
    final originalParentId = _text(original['categoryId'], parentId);

    final name = TextEditingController(text: _text(original['name']));
    final priority = TextEditingController(text: _toInt(original['priority']).toString());
    final description = TextEditingController(text: _text(original['description']));
    final variantLabel = TextEditingController(text: _text(original['variantLabel']));
    final existingImage = _text(original['imageUrl'] ?? original['image']);

    var selectedParentId = originalParentId;
    var active = editing ? original['isActive'] != false : true;
    var saving = false;
    String? error;
    File? newImageFile;
    Uint8List? newWebImage;

    final parentOptions = categories
        .map((d) => MapEntry(d.id, _text((d.data() as Map<String, dynamic>)['name'], 'Unnamed')))
        .toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final trimmedName = name.text.trim();
            final normalized = normalizeCategoryKey(trimmedName);
            if (normalized.isEmpty) {
              setDialogState(() => error = 'Subcategory name required');
              return;
            }
            if (int.tryParse(priority.text.trim()) == null) {
              setDialogState(() => error = 'Priority must be a whole number');
              return;
            }
            final parentEntry = parentOptions.where((e) => e.key == selectedParentId);
            if (parentEntry.isEmpty) {
              setDialogState(() => error = 'Select a parent category');
              return;
            }
            final parentName = parentEntry.first.value;

            setDialogState(() {
              saving = true;
              error = null;
            });

            try {
              final parentChanged = editing && selectedParentId != originalParentId;

              // Products carry categoryId alongside subcategoryId; moving a
              // subcategory that has products would split them from their
              // parent, so that move is refused.
              if (parentChanged) {
                final linked = await _countProducts(
                  db.collection('products').where('subcategoryId', isEqualTo: subId),
                );
                if (linked > 0) {
                  setDialogState(() {
                    saving = false;
                    error = 'Cannot move to another category: $linked products use this subcategory.';
                  });
                  return;
                }
              }

              final duplicate = await _duplicateSubcategoryName(
                selectedParentId,
                normalized,
                excludeId: subId,
              );
              if (duplicate != null) {
                setDialogState(() {
                  saving = false;
                  error = '"$duplicate" already exists in $parentName.';
                });
                return;
              }

              final nameChanged = normalized != _text(original['normalizedName']);
              final slug = (!editing || parentChanged || nameChanged || _text(original['slug']).isEmpty)
                  ? await _uniqueSubcategorySlug(selectedParentId, trimmedName, excludeId: subId)
                  : _text(original['slug']);

              var imageUrl = existingImage;
              if (newImageFile != null || newWebImage != null) {
                imageUrl = await _uploadImage(newImageFile, newWebImage, prefix: 'sub_');
              }

              final previousStatus = _text(original['status']);
              final payload = <String, dynamic>{
                'categoryId': selectedParentId,
                'categoryName': parentName,
                'name': trimmedName,
                'normalizedName': normalized,
                'slug': slug,
                'priority': _toInt(priority.text),
                'description': description.text.trim(),
                'image': imageUrl,
                'imageUrl': imageUrl,
                'isActive': active,
                'status': active
                    ? 'active'
                    : (previousStatus == 'pending' ? 'pending' : 'inactive'),
                'updatedAt': FieldValue.serverTimestamp(),
              };

              // Empty = automatic: removed on edit, omitted on create.
              final label = variantLabel.text.trim();
              if (label.isNotEmpty) {
                payload['variantLabel'] = label;
              } else if (editing) {
                payload['variantLabel'] = FieldValue.delete();
              }

              if (editing) {
                await db.collection('subcategories').doc(subId).update(payload);
              } else {
                await db.collection('subcategories').add({
                  ...payload,
                  'isFeatured': false,
                  'showOnHome': false,
                  'autoCreated': false,
                  'source': 'admin',
                  'createdAt': FieldValue.serverTimestamp(),
                });
              }

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (mounted) setState(() => expandedCategoryIds.add(selectedParentId));
              _snack(editing ? 'Subcategory updated' : 'Subcategory added');
            } catch (e) {
              setDialogState(() {
                saving = false;
                error = 'Save failed: $e';
              });
            }
          }

          Widget imageBox() {
            Widget child;
            if (newWebImage != null) {
              child = Image.memory(newWebImage!, fit: BoxFit.cover);
            } else if (newImageFile != null) {
              child = Image.file(newImageFile!, fit: BoxFit.cover);
            } else if (existingImage.isNotEmpty) {
              child = Image.network(
                existingImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              );
            } else {
              child = const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, size: 30),
                  SizedBox(height: 4),
                  Text('Image (optional)'),
                ],
              );
            }
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: saving
                  ? null
                  : () => _pickImage(
                        onFile: (f) => setDialogState(() => newImageFile = f),
                        onWeb: (b) => setDialogState(() => newWebImage = b),
                      ),
              child: Container(
                height: 110,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: child,
              ),
            );
          }

          return AlertDialog(
            title: Text(editing ? 'Edit Subcategory' : 'Add Subcategory'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: !editing,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Subcategory Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedParentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Parent Category',
                        border: OutlineInputBorder(),
                      ),
                      items: parentOptions
                          .map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setDialogState(() => selectedParentId = v ?? selectedParentId),
                    ),
                    const SizedBox(height: 10),
                    imageBox(),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priority,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('subcategory-variant-label'),
                      controller: variantLabel,
                      decoration: const InputDecoration(
                        labelText: 'Variant label',
                        hintText: 'e.g. Model, Type, Capacity',
                        helperText: 'Default label before product variants ("Model: 12 Pro"). Empty = automatic.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      title: const Text('Active'),
                      onChanged: saving ? null : (v) => setDialogState(() => active = v),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(editing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
    // Controllers are left to GC, like the category edit dialog: disposing
    // here races the dialog's exit animation, which still reads them.
  }

  Future<void> _toggleSubcategory(String id, Map<String, dynamic> data, bool value) async {
    if (!_requirePermission(canChangeCategoryStatus, 'You do not have permission to change subcategory status.')) {
      return;
    }
    final previousStatus = _text(data['status']);
    try {
      await db.collection('subcategories').doc(id).update({
        'isActive': value,
        'status': value ? 'active' : (previousStatus == 'pending' ? 'pending' : 'inactive'),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _snack('Status change failed: $e');
    }
  }

  Future<void> _deleteSubcategory(String id, Map<String, dynamic> data) async {
    if (!_requirePermission(canDeleteCategories, 'You do not have permission to delete subcategories.')) {
      return;
    }
    final subName = _text(data['name'], 'this subcategory');

    try {
      final count = await _countProducts(
        db.collection('products').where('subcategoryId', isEqualTo: id),
      );
      if (!mounted) return;

      if (count > 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cannot delete subcategory'),
            content: Text(
              '$count ${count == 1 ? 'product uses' : 'products use'} "$subName". '
              'Move those products to another subcategory first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete subcategory?'),
          content: Text('"$subName" will be permanently deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      await db.collection('subcategories').doc(id).delete();
      _snack('Subcategory deleted');
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  Future<void> _toggleCategory(String id, bool value) async {
    if (!_requirePermission(canChangeCategoryStatus, 'You do not have permission to change category status.')) {
      return;
    }

    await db.collection('categories').doc(id).update({
      'isActive': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleFeatured(String id, bool value) async {
    if (!_requirePermission(canChangeCategoryStatus, 'You do not have permission to change featured category status.')) {
      return;
    }

    await db.collection('categories').doc(id).update({
      'isFeatured': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<QueryDocumentSnapshot> _filterCategories(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final active = data['isActive'] != false;
      final featured = data['isFeatured'] == true;
      final home = data['showOnHome'] != false;
      final name = _text(data['name']).toLowerCase();

      if (statusFilter == 'active' && !active) return false;
      if (statusFilter == 'inactive' && active) return false;
      if (statusFilter == 'featured' && !featured) return false;
      if (statusFilter == 'home' && !home) return false;

      if (s.isNotEmpty && !name.contains(s)) return false;

      return true;
    }).toList();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _imageBox() {
    Widget child;

    if (webImage != null) {
      child = Image.memory(webImage!, fit: BoxFit.cover);
    } else if (imageFile != null) {
      child = Image.file(imageFile!, fit: BoxFit.cover);
    } else {
      child = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_rounded, size: 42),
          SizedBox(height: 6),
          Text('Upload Category Image'),
        ],
      );
    }

    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 150,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: child,
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool number = false,
    int maxLines = 1,
    String? Function(String?)? validator,
    IconData? icon,
    bool enabled = true,
  }) {
    return TextFormField(
      enabled: enabled,
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _formCard() {
    if (!canEditCategories) {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 34, color: Colors.orange),
              SizedBox(height: 10),
              Text(
                'Category editing is locked',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'You can view categories, but add/edit/delete/status controls require categories.edit, categories.delete, or categories.status permission.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Category', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _imageBox(),
              const SizedBox(height: 14),
              _field(
                label: 'Category Name',
                controller: nameController,
                icon: Icons.category_outlined,
                validator: _required,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Priority',
                controller: priorityController,
                number: true,
                icon: Icons.sort_rounded,
                validator: _number,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Description',
                controller: descriptionController,
                icon: Icons.info_outline_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: isActive,
                title: const Text('Active Category'),
                onChanged: (v) => setState(() => isActive = v),
              ),
              SwitchListTile(
                value: isFeatured,
                title: const Text('Featured Category'),
                onChanged: (v) => setState(() => isFeatured = v),
              ),
              SwitchListTile(
                value: showOnHome,
                title: const Text('Show on Homepage'),
                onChanged: (v) => setState(() => showOnHome = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : _addCategory,
                  icon: saving
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.add_rounded),
                  label: Text(saving ? 'Saving...' : 'Add Category'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int active = 0;
    int inactive = 0;
    int featured = 0;
    int home = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['isActive'] != false) {
        active++;
      } else {
        inactive++;
      }

      if (data['isFeatured'] == true) featured++;
      if (data['showOnHome'] != false) home++;
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
            _summaryCard('Active', '$active', Icons.verified_rounded, Colors.green),
            _summaryCard('Inactive', '$inactive', Icons.toggle_off_rounded, Colors.red),
            _summaryCard('Featured', '$featured', Icons.star_rounded, Colors.deepPurple),
            _summaryCard('Home', '$home', Icons.home_rounded, Colors.blue),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
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

  Widget _filters() {
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
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search category...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final status = DropdownButtonFormField<String>(
              initialValue: statusFilter,
              decoration: const InputDecoration(
                labelText: 'Filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'featured', child: Text('Featured')),
                DropdownMenuItem(value: 'home', child: Text('Homepage')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  status,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: status),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _categoryImage(Map<String, dynamic> data) {
    final url = _text(data['imageUrl'] ?? data['image']);

    if (url.isEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: const Color(0xFFEAF6FA),
        child: Text(
          _text(data['name'], '?').substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF1592B3),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 32,
      backgroundImage: NetworkImage(url),
      backgroundColor: const Color(0xFFEAF6FA),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _subcategoryAvatar(Map<String, dynamic> data) {
    final url = _text(data['imageUrl'] ?? data['image']);
    final initial = _text(data['name'], '?').characters.first.toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFEAF6FA),
      backgroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty
          ? Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF1592B3),
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget _subcategoryTile(
    QueryDocumentSnapshot doc,
    List<QueryDocumentSnapshot> categories,
    String parentId,
    bool parentActive,
    int liveCount,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final name = _text(data['name'], 'Unnamed');
    final active = data['isActive'] != false;
    final pending = _text(data['status']) == 'pending';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF8FAFC) : const Color(0xFFFFF7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          _subcategoryAvatar(data),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: name,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _chip(active ? 'Active' : 'Inactive', active ? Colors.green : Colors.red),
                    if (pending) _chip('Pending review', Colors.orange),
                    if (active && !parentActive) _chip('Hidden: parent inactive', Colors.grey),
                    _chip('P ${_toInt(data['priority'])}', Colors.blueGrey),
                    _chip('$liveCount live', Colors.teal),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: canChangeCategoryStatus ? (v) => _toggleSubcategory(doc.id, data, v) : null,
          ),
          if (canEditCategories)
            IconButton(
              tooltip: 'Edit subcategory',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showSubcategoryDialog(
                categories: categories,
                parentId: parentId,
                subId: doc.id,
                data: data,
              ),
              icon: const Icon(Icons.edit_rounded, size: 20, color: Colors.orange),
            ),
          if (canDeleteCategories)
            IconButton(
              tooltip: 'Delete subcategory',
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteSubcategory(doc.id, data),
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
            ),
        ],
      ),
    );
  }

  Widget _subcategorySection(
    String categoryId,
    bool parentActive,
    List<QueryDocumentSnapshot> subs,
    List<QueryDocumentSnapshot> categories,
    Map<String, int> liveBySub,
  ) {
    final expanded = expandedCategoryIds.contains(categoryId);

    final footer = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: subs.isEmpty
              ? null
              : () => setState(() {
                    if (!expandedCategoryIds.remove(categoryId)) {
                      expandedCategoryIds.add(categoryId);
                    }
                  }),
          icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          label: Text(subs.isEmpty
              ? 'No subcategories yet'
              : expanded
                  ? 'Hide subcategories'
                  : 'Show subcategories (${subs.length})'),
        ),
        if (canEditCategories)
          OutlinedButton.icon(
            onPressed: () => _showSubcategoryDialog(
              categories: categories,
              parentId: categoryId,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Subcategory যোগ করুন'),
          ),
      ],
    );

    if (!expanded || subs.isEmpty) return footer;

    final tiles = [
      for (final s in subs)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _subcategoryTile(s, categories, categoryId, parentActive, liveBySub[s.id] ?? 0),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        footer,
        const SizedBox(height: 6),
        if (!parentActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Parent category is inactive, so none of these show in the customer app.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ),
        // Long lists scroll inside the card instead of stretching the page.
        if (subs.length > 8)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView(
                primary: false,
                shrinkWrap: true,
                padding: const EdgeInsets.only(right: 8),
                children: tiles,
              ),
            ),
          )
        else
          ...tiles,
      ],
    );
  }

  Widget _categoryCard(
    String id,
    Map<String, dynamic> data,
    List<QueryDocumentSnapshot> subs,
    List<QueryDocumentSnapshot> categories,
  ) {
    final active = data['isActive'] != false;
    final featured = data['isFeatured'] == true;
    final home = data['showOnHome'] != false;
    final categoryName = _text(data['name']);

    return FutureBuilder<_ProductCounts>(
      // Cached per name: expanding a card calls setState, and an uncached
      // future would re-run this query for every card on every click.
      future: _productCountCache.putIfAbsent(categoryName, () => _productCount(categoryName)),
      builder: (context, countSnap) {
        final counts = countSnap.data;

        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                _categoryImage(data),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName.isEmpty ? 'Unnamed Category' : categoryName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      if (_text(data['description']).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _text(data['description']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(active ? 'Active' : 'Inactive', active ? Colors.green : Colors.red),
                          if (featured) _chip('Featured', Colors.deepPurple),
                          if (home) _chip('Home', Colors.blue),
                          _chip('Priority ${_toInt(data['priority'])}', Colors.orange),
                          _chip(
                            counts == null ? '… Products' : '${counts.live} live · ${counts.total} total',
                            Colors.teal,
                          ),
                          _chip(
                            '${subs.length} ${subs.length == 1 ? 'Subcategory' : 'Subcategories'}',
                            Colors.indigo,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (canEditCategories)
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _showEditDialog(id, data),
                        icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                      ),
                    Switch(
                      value: active,
                      onChanged: canChangeCategoryStatus ? (v) => _toggleCategory(id, v) : null,
                    ),
                    IconButton(
                      tooltip: featured ? 'Remove featured' : 'Make featured',
                      onPressed: canChangeCategoryStatus ? () => _toggleFeatured(id, !featured) : null,
                      icon: Icon(
                        featured ? Icons.star_rounded : Icons.star_border_rounded,
                        color: canChangeCategoryStatus ? Colors.deepPurple : Colors.grey,
                      ),
                    ),
                    if (canDeleteCategories)
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteCategory(id, data),
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      ),
                  ],
                ),
              ],
            ),
                const Divider(height: 18),
                _subcategorySection(id, active, subs, categories, counts?.liveBySub ?? const {}),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One stream for every subcategory, grouped by parent client-side, so
  /// the page costs one listener instead of one per category card and
  /// needs no extra composite index.
  late final Stream<QuerySnapshot> _subcategoryStream =
      db.collection('subcategories').limit(2000).snapshots();

  // Held once (it used to be rebuilt inline) so expanding a card, which
  // calls setState, doesn't resubscribe and flash the loading spinner.
  late final Stream<QuerySnapshot> _categoryStream =
      db.collection('categories').orderBy('priority').limit(300).snapshots();

  Map<String, List<QueryDocumentSnapshot>> _groupSubcategories(List<QueryDocumentSnapshot> docs) {
    final grouped = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final parent = _text((doc.data() as Map<String, dynamic>)['categoryId']);
      if (parent.isEmpty) continue;
      grouped.putIfAbsent(parent, () => []).add(doc);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final dbb = b.data() as Map<String, dynamic>;
        final byPriority = _toInt(da['priority']).compareTo(_toInt(dbb['priority']));
        if (byPriority != 0) return byPriority;
        return _text(da['name']).toLowerCase().compareTo(_text(dbb['name']).toLowerCase());
      });
    }
    return grouped;
  }

  Widget _categoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _subcategoryStream,
      builder: (context, subSnap) {
        final subsByCategory = _groupSubcategories(subSnap.data?.docs ?? const []);
        return _categoryListBody(subsByCategory);
      },
    );
  }

  Widget _categoryListBody(Map<String, List<QueryDocumentSnapshot>> subsByCategory) {
    return StreamBuilder<QuerySnapshot>(
      stream: _categoryStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        // New category data (add/edit/delete/toggle) → recount, matching
        // the old behaviour where counts refreshed on every stream event.
        if (!identical(snap.data, _lastCategorySnapshot)) {
          _lastCategorySnapshot = snap.data;
          _productCountCache.clear();
        }

        final allDocs = snap.data!.docs;
        final docs = _filterCategories(allDocs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryGrid(allDocs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Text(
              'All Categories (${docs.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching categories')),
                ),
              )
            else
              ...docs.map((doc) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _categoryCard(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                    subsByCategory[doc.id] ?? const [],
                    allDocs,
                  ),
                );
              }),
          ],
        );
      },
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

    if (!canViewCategories) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Access denied. You need categories.view permission to view Category Manager.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Category Manager Pro',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              if (!canEditCategories)
                Chip(
                  avatar: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Read Only'),
                  backgroundColor: Colors.orange.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: _formCard()),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: _categoryList()),
              ],
            )
          else ...[
            _formCard(),
            const SizedBox(height: 16),
            _categoryList(),
          ],
        ],
      ),
    );
  }
}

typedef _ProductCounts = ({int total, int live, Map<String, int> liveBySub});
