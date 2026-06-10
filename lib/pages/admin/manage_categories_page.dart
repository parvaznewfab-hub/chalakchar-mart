import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';

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

  Future<String> _uploadImage(File? file, Uint8List? bytes) async {
    if (file == null && bytes == null) return '';

    final ref = FirebaseStorage.instance
        .ref()
        .child('categories/${DateTime.now().millisecondsSinceEpoch}.jpg');

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
      final duplicate = await db
          .collection('categories')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (duplicate.docs.isNotEmpty) {
        _snack('Category already exists');
        return;
      }

      final imageUrl = await _uploadImage(imageFile, webImage);

      await db.collection('categories').add({
        'name': name,
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

      _clearForm();
      _snack('Category added successfully');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<int> _productCount(String categoryName) async {
    final snap = await db
        .collection('products')
        .where('category', isEqualTo: categoryName)
        .limit(100)
        .get();

    return snap.docs.length;
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> data) async {
    if (!_requirePermission(canEditCategories, 'You do not have permission to edit categories.')) {
      return;
    }

    final name = TextEditingController(text: _text(data['name']));
    final priority = TextEditingController(text: _toInt(data['priority']).toString());
    final description = TextEditingController(text: _text(data['description']));

    bool active = data['isActive'] != false;
    bool featured = data['isFeatured'] == true;
    bool home = data['showOnHome'] != false;

    File? newImageFile;
    Uint8List? newWebImage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
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

            String imageUrl = _text(data['imageUrl'] ?? data['image']);

            if (newImageFile != null || newWebImage != null) {
              imageUrl = await _uploadImage(newImageFile, newWebImage);
            }

            await db.collection('categories').doc(id).update({
              'name': newName,
              'priority': _toInt(priority.text),
              'description': description.text.trim(),
              'image': imageUrl,
              'imageUrl': imageUrl,
              'isActive': active,
              'isFeatured': featured,
              'showOnHome': home,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            if (context.mounted) Navigator.pop(context);
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

    final count = await _productCount(_text(data['name']));

    if (count > 0) {
      _snack('Cannot delete. $count products are using this category.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete category?'),
        content: const Text('This category will be permanently deleted.'),
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
      await db.collection('categories').doc(id).delete();
      _snack('Category deleted');
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
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
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
              value: statusFilter,
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _categoryCard(String id, Map<String, dynamic> data) {
    final active = data['isActive'] != false;
    final featured = data['isFeatured'] == true;
    final home = data['showOnHome'] != false;
    final categoryName = _text(data['name']);

    return FutureBuilder<int>(
      future: _productCount(categoryName),
      builder: (context, countSnap) {
        final count = countSnap.data ?? 0;

        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _categoryImage(data),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName.isEmpty ? 'Unnamed Category' : categoryName,
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
                          _chip('$count Products', Colors.teal),
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
          ),
        );
      },
    );
  }

  Widget _categoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('categories').orderBy('priority').limit(300).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
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
                  child: _categoryCard(doc.id, doc.data() as Map<String, dynamic>),
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
                  backgroundColor: Colors.orange.withOpacity(0.12),
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



