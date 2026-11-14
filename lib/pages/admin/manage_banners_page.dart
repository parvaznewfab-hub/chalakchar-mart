import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';

/// Professional banner manager for admin side.
///
/// Firestore collection: banners
///
/// Supported layoutType:
/// - normal
/// - amazon_grid
///
/// Main fields used by user/home side:
/// layoutType, title, subtitle, url, mobileUrl, desktopUrl, items,
/// categoryId, categoryName, isActive, priority, clickActionType, clickValue,
/// showOnMobile, showOnDesktop, startAt, endAt, createdAt, updatedAt.
class ManageBannersProPage extends StatefulWidget {
  const ManageBannersProPage({super.key});

  @override
  State<ManageBannersProPage> createState() => _ManageBannersProPageState();
}

class _ManageBannersProPageState extends State<ManageBannersProPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  final TextEditingController titleController = TextEditingController();
  final TextEditingController subtitleController = TextEditingController();
  final TextEditingController priorityController = TextEditingController();
  final TextEditingController clickValueController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  final List<TextEditingController> itemTitleControllers =
  List.generate(4, (_) => TextEditingController());
  final List<TextEditingController> itemClickValueControllers =
  List.generate(4, (_) => TextEditingController());

  String bannerType = 'normal';
  String clickActionType = 'category';
  String filterType = 'all';
  String searchText = '';

  bool _isUploading = false;
  bool loadingPermissions = true;
  bool canViewBanners = false;
  bool canEditBanners = false;
  bool canDeleteBanners = false;
  bool canChangeStatus = false;
  bool canChangePriority = false;

  bool isActive = true;
  bool showOnMobile = true;
  bool showOnDesktop = true;

  String? editingBannerId;
  Map<String, dynamic>? editingOldData;

  String? selectedCategoryId;
  String? selectedCategoryName;

  Timestamp? startAt;
  Timestamp? endAt;

  XFile? _normalImage;
  Uint8List? _normalWebImage;
  File? _normalFileImage;

  XFile? _mobileImage;
  Uint8List? _mobileWebImage;
  File? _mobileFileImage;

  XFile? _desktopImage;
  Uint8List? _desktopWebImage;
  File? _desktopFileImage;

  final List<XFile?> itemImages = List.generate(4, (_) => null);
  final List<Uint8List?> itemWebImages = List.generate(4, (_) => null);
  final List<File?> itemFileImages = List.generate(4, (_) => null);

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final results = await Future.wait<bool>([
        authService.hasPermission('banners.view'),
        authService.hasPermission('banners.edit'),
        authService.hasPermission('banners.delete'),
        authService.hasPermission('banners.status'),
        authService.hasPermission('banners.priority'),
      ]);

      if (!mounted) return;
      setState(() {
        canViewBanners = results[0];
        canEditBanners = results[1];
        canDeleteBanners = results[2];
        canChangeStatus = results[3];
        canChangePriority = results[4];
        loadingPermissions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loadingPermissions = false);
      _showSnack('Permission load failed: $e');
    }
  }

  bool _requirePermission(bool allowed, String message) {
    if (allowed) return true;
    _showSnack(message);
    return false;
  }

  @override
  void dispose() {
    titleController.dispose();
    subtitleController.dispose();
    priorityController.dispose();
    clickValueController.dispose();
    searchController.dispose();
    for (final c in itemTitleControllers) {
      c.dispose();
    }
    for (final c in itemClickValueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get isEditing => editingBannerId != null;

  String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _safePriority() {
    final text = priorityController.text.trim();
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
    return DateTime.now().millisecondsSinceEpoch;
  }

  Future<String> _uploadImage(XFile file) async {
    final String cleanName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final ref = FirebaseStorage.instance
        .ref()
        .child('banners/${DateTime.now().millisecondsSinceEpoch}_$cleanName');

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else {
      await ref.putFile(File(file.path));
    }

    return ref.getDownloadURL();
  }

  Future<void> _pickNormalImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    _normalImage = picked;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() => _normalWebImage = bytes);
    } else {
      setState(() => _normalFileImage = File(picked.path));
    }
  }

  Future<void> _pickMobileImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    _mobileImage = picked;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() => _mobileWebImage = bytes);
    } else {
      setState(() => _mobileFileImage = File(picked.path));
    }
  }

  Future<void> _pickDesktopImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    _desktopImage = picked;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() => _desktopWebImage = bytes);
    } else {
      setState(() => _desktopFileImage = File(picked.path));
    }
  }

  Future<void> _pickItemImage(int index) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    itemImages[index] = picked;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      setState(() => itemWebImages[index] = bytes);
    } else {
      setState(() => itemFileImages[index] = File(picked.path));
    }
  }

  Future<Timestamp?> _pickDateTime(Timestamp? initial) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = initial?.toDate() ?? now;

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (date == null || !mounted) return initial;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (time == null) return Timestamp.fromDate(date);

    return Timestamp.fromDate(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  String _dateText(Timestamp? value) {
    if (value == null) return 'Not set';
    final dt = value.toDate();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$min';
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveBanner() async {
    if (!_requirePermission(canEditBanners, 'You do not have permission to add or edit banners.')) return;
    if (!showOnMobile && !showOnDesktop) {
      _showSnack('Select at least mobile or desktop visibility');
      return;
    }

    if (selectedCategoryId == null && clickActionType == 'category') {
      _showSnack('Select category');
      return;
    }

    if ((clickActionType == 'url' || clickActionType == 'product') &&
        clickValueController.text.trim().isEmpty) {
      _showSnack('Enter click value');
      return;
    }

    if (startAt != null && endAt != null && startAt!.toDate().isAfter(endAt!.toDate())) {
      _showSnack('End date must be after start date');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final Map<String, dynamic> payload = {
        'layoutType': bannerType,
        'title': titleController.text.trim(),
        'subtitle': subtitleController.text.trim(),
        'categoryId': selectedCategoryId,
        'categoryName': selectedCategoryName,
        'isActive': isActive,
        'priority': _safePriority(),
        'clickActionType': clickActionType,
        'clickValue': clickActionType == 'category'
            ? selectedCategoryId
            : clickValueController.text.trim(),
        'showOnMobile': showOnMobile,
        'showOnDesktop': showOnDesktop,
        'startAt': startAt,
        'endAt': endAt,
        'updatedAt': Timestamp.now(),
      };

      if (!isEditing) {
        payload['createdAt'] = Timestamp.now();
      }

      if (bannerType == 'normal') {
        final String oldUrl = _safeString(editingOldData?['url']);
        final String oldMobileUrl = _safeString(editingOldData?['mobileUrl']);
        final String oldDesktopUrl = _safeString(editingOldData?['desktopUrl']);

        if (!isEditing && _normalImage == null && _mobileImage == null && _desktopImage == null) {
          _showSnack('Select at least one banner image');
          setState(() => _isUploading = false);
          return;
        }

        String url = oldUrl;
        String mobileUrl = oldMobileUrl;
        String desktopUrl = oldDesktopUrl;

        if (_normalImage != null) {
          url = await _uploadImage(_normalImage!);
        }
        if (_mobileImage != null) {
          mobileUrl = await _uploadImage(_mobileImage!);
        }
        if (_desktopImage != null) {
          desktopUrl = await _uploadImage(_desktopImage!);
        }

        // Backward compatibility: old home code reads `url`.
        // If admin uploads only mobile/desktop image, keep a common url too.
        if (url.isEmpty) {
          url = mobileUrl.isNotEmpty ? mobileUrl : desktopUrl;
        }

        payload.addAll({
          'url': url,
          'mobileUrl': mobileUrl,
          'desktopUrl': desktopUrl,
        });

        if (isEditing) {
          payload['items'] = FieldValue.delete();
        }
      } else {
        if (titleController.text.trim().isEmpty) {
          _showSnack('Enter Amazon grid title');
          setState(() => _isUploading = false);
          return;
        }

        final List oldItems = editingOldData?['items'] is List
            ? editingOldData!['items'] as List
            : [];

        final List<Map<String, dynamic>> items = [];

        for (int i = 0; i < 4; i++) {
          String imageUrl = '';
          if (i < oldItems.length && oldItems[i] is Map) {
            imageUrl = _safeString((oldItems[i] as Map)['imageUrl']);
          }

          if (itemImages[i] != null) {
            imageUrl = await _uploadImage(itemImages[i]!);
          }

          if (imageUrl.isEmpty) {
            _showSnack('Select item image ${i + 1}');
            setState(() => _isUploading = false);
            return;
          }

          items.add({
            'imageUrl': imageUrl,
            // Empty when not given: home hides the label instead of "Item N".
            'title': itemTitleControllers[i].text.trim(),
            'clickActionType': clickActionType,
            'clickValue': itemClickValueControllers[i].text.trim().isEmpty
                ? (clickActionType == 'category'
                ? selectedCategoryId
                : clickValueController.text.trim())
                : itemClickValueControllers[i].text.trim(),
          });
        }

        payload.addAll({
          'items': items,
        });

        if (isEditing) {
          payload['url'] = FieldValue.delete();
          payload['mobileUrl'] = FieldValue.delete();
          payload['desktopUrl'] = FieldValue.delete();
        }
      }

      if (isEditing) {
        await db.collection('banners').doc(editingBannerId).update(payload);
        _showSnack('Banner updated');
      } else {
        await db.collection('banners').add(payload);
        _showSnack('Banner uploaded');
      }

      _resetForm();
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _resetForm() {
    setState(() {
      editingBannerId = null;
      editingOldData = null;
      bannerType = 'normal';
      titleController.clear();
      subtitleController.clear();
      priorityController.clear();
      clickValueController.clear();

      clickActionType = 'category';
      selectedCategoryId = null;
      selectedCategoryName = null;
      isActive = true;
      showOnMobile = true;
      showOnDesktop = true;
      startAt = null;
      endAt = null;

      _normalImage = null;
      _normalWebImage = null;
      _normalFileImage = null;
      _mobileImage = null;
      _mobileWebImage = null;
      _mobileFileImage = null;
      _desktopImage = null;
      _desktopWebImage = null;
      _desktopFileImage = null;

      for (int i = 0; i < 4; i++) {
        itemImages[i] = null;
        itemWebImages[i] = null;
        itemFileImages[i] = null;
        itemTitleControllers[i].clear();
        itemClickValueControllers[i].clear();
      }
    });
  }

  void _editBanner(String id, Map<String, dynamic> data) {
    if (!_requirePermission(canEditBanners, 'You do not have permission to edit banners.')) return;
    setState(() {
      editingBannerId = id;
      editingOldData = Map<String, dynamic>.from(data);

      bannerType = _safeString(data['layoutType'], 'normal');
      titleController.text = _safeString(data['title']);
      subtitleController.text = _safeString(data['subtitle']);
      priorityController.text = _safeString(data['priority']);
      selectedCategoryId = _safeString(data['categoryId']).isEmpty ? null : _safeString(data['categoryId']);
      selectedCategoryName = _safeString(data['categoryName']).isEmpty ? null : _safeString(data['categoryName']);
      isActive = data['isActive'] == true;
      showOnMobile = data['showOnMobile'] != false;
      showOnDesktop = data['showOnDesktop'] != false;
      clickActionType = _safeString(data['clickActionType'], 'category');
      clickValueController.text = _safeString(data['clickValue']);
      startAt = data['startAt'] is Timestamp ? data['startAt'] as Timestamp : null;
      endAt = data['endAt'] is Timestamp ? data['endAt'] as Timestamp : null;

      _normalImage = null;
      _normalWebImage = null;
      _normalFileImage = null;
      _mobileImage = null;
      _mobileWebImage = null;
      _mobileFileImage = null;
      _desktopImage = null;
      _desktopWebImage = null;
      _desktopFileImage = null;

      final List items = data['items'] is List ? data['items'] as List : [];
      for (int i = 0; i < 4; i++) {
        itemImages[i] = null;
        itemWebImages[i] = null;
        itemFileImages[i] = null;
        if (i < items.length && items[i] is Map) {
          final item = items[i] as Map;
          final title = _safeString(item['title']);
          itemTitleControllers[i].text =
              RegExp(r'^Item \d+$').hasMatch(title) ? '' : title;
          itemClickValueControllers[i].text = _safeString(item['clickValue']);
        } else {
          itemTitleControllers[i].clear();
          itemClickValueControllers[i].clear();
        }
      }
    });

    _showSnack('Edit mode enabled');
  }

  Future<void> _deleteBanner(String id) async {
    if (!_requirePermission(canDeleteBanners, 'You do not have permission to delete banners.')) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Banner'),
        content: const Text('Are you sure you want to delete this banner?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await db.collection('banners').doc(id).delete();
      _showSnack('Banner deleted');
    }
  }

  Future<void> _toggleActive(String id, bool value) async {
    if (!_requirePermission(canChangeStatus, 'You do not have permission to change banner status.')) return;
    await db.collection('banners').doc(id).update({
      'isActive': value,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> _quickPriority(String id, int oldPriority, int change) async {
    if (!_requirePermission(canChangePriority, 'You do not have permission to change banner priority.')) return;
    await db.collection('banners').doc(id).update({
      'priority': oldPriority + change,
      'updatedAt': Timestamp.now(),
    });
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _imageBox({
    required VoidCallback onTap,
    Uint8List? webImage,
    File? fileImage,
    String? oldUrl,
    String text = 'Select Image',
    String hint = 'Tap to upload',
    double height = 170,
  }) {
    final bool hasNewImage = fileImage != null || webImage != null;
    final bool hasOldImage = oldUrl != null && oldUrl.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(
            color: (hasNewImage || hasOldImage) ? Colors.green.shade400 : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fileImage != null)
              Image.file(fileImage, fit: BoxFit.cover)
            else if (webImage != null)
              Image.memory(webImage, fit: BoxFit.cover)
            else if (hasOldImage)
                Image.network(
                  oldUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _emptyImageText(text, hint),
                )
              else
                _emptyImageText(text, hint),
            if (hasNewImage || hasOldImage)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Change', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyImageText(String text, String hint) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 38, color: Colors.grey.shade600),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      ],
    );
  }

  Widget _bannerTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: bannerType,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Banner Type',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'normal', child: Text('Normal Image Banner')),
        DropdownMenuItem(value: 'amazon_grid', child: Text('Amazon Grid Banner')),
      ],
      onChanged: (isEditing || !canEditBanners)
          ? null
          : (v) {
        setState(() => bannerType = v ?? 'normal');
      },
    );
  }

  Widget _categoryDropdown() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('categories').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final categories = snapshot.data!.docs;

        return DropdownButtonFormField<String>(
          initialValue: selectedCategoryId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Select Category',
            border: OutlineInputBorder(),
          ),
          items: categories.map((cat) {
            final data = cat.data() as Map<String, dynamic>;
            return DropdownMenuItem(
              value: cat.id,
              child: Text(
                data['name']?.toString() ?? 'Unnamed',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: canEditBanners ? (val) {
            if (val == null) return;
            final selectedDoc = categories.firstWhere((e) => e.id == val);
            final selectedData = selectedDoc.data() as Map<String, dynamic>;

            setState(() {
              selectedCategoryId = val;
              selectedCategoryName = selectedData['name']?.toString() ?? 'Unnamed';
              if (clickActionType == 'category') {
                clickValueController.text = val;
              }
            });
          } : null,
        );
      },
    );
  }

  Widget _clickActionFields(bool isDesktop) {
    final fields = <Widget>[
      DropdownButtonFormField<String>(
        initialValue: clickActionType,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Click Action',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'none', child: Text('No action')),
          DropdownMenuItem(value: 'category', child: Text('Open selected category')),
          DropdownMenuItem(value: 'product', child: Text('Open product ID')),
          DropdownMenuItem(value: 'url', child: Text('Open external URL')),
        ],
        onChanged: canEditBanners ? (value) {
          setState(() {
            clickActionType = value ?? 'category';
            if (clickActionType == 'category') {
              clickValueController.text = selectedCategoryId ?? '';
            } else if (clickActionType == 'none') {
              clickValueController.clear();
            }
          });
        } : null,
      ),
      if (clickActionType == 'product' || clickActionType == 'url')
        TextField(
          controller: clickValueController,
          decoration: InputDecoration(
            labelText: clickActionType == 'product' ? 'Product ID' : 'URL',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(clickActionType == 'product' ? Icons.inventory_2_outlined : Icons.link),
          ),
        ),
    ];

    if (isDesktop) {
      return Row(
        children: fields
            .map((w) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: w)))
            .toList(),
      );
    }

    return Column(
      children: fields
          .map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w))
          .toList(),
    );
  }

  Widget _dateAndVisibilityFields(bool isDesktop) {
    final children = [
      SwitchListTile(
        value: isActive,
        contentPadding: EdgeInsets.zero,
        title: const Text('Active'),
        subtitle: const Text('Show or hide without deleting'),
        onChanged: canEditBanners ? (v) => setState(() => isActive = v) : null,
      ),
      CheckboxListTile(
        value: showOnMobile,
        contentPadding: EdgeInsets.zero,
        title: const Text('Mobile'),
        onChanged: canEditBanners ? (v) => setState(() => showOnMobile = v ?? true) : null,
      ),
      CheckboxListTile(
        value: showOnDesktop,
        contentPadding: EdgeInsets.zero,
        title: const Text('Desktop'),
        onChanged: canEditBanners ? (v) => setState(() => showOnDesktop = v ?? true) : null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop)
          Row(children: children.map((e) => Expanded(child: e)).toList())
        else
          ...children,
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available),
              label: Text('Start: ${_dateText(startAt)}'),
              onPressed: canEditBanners ? () async {
                final picked = await _pickDateTime(startAt);
                setState(() => startAt = picked);
              } : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_busy),
              label: Text('End: ${_dateText(endAt)}'),
              onPressed: canEditBanners ? () async {
                final picked = await _pickDateTime(endAt);
                setState(() => endAt = picked);
              } : null,
            ),
            if (startAt != null || endAt != null)
              TextButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Clear schedule'),
                onPressed: canEditBanners ? () => setState(() {
                  startAt = null;
                  endAt = null;
                }) : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _normalBannerForm(bool isDesktop) {
    final oldUrl = _safeString(editingOldData?['url']);
    final oldMobileUrl = _safeString(editingOldData?['mobileUrl']);
    final oldDesktopUrl = _safeString(editingOldData?['desktopUrl']);

    if (isDesktop) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _imageBox(
                  onTap: _pickNormalImage,
                  webImage: _normalWebImage,
                  fileImage: _normalFileImage,
                  oldUrl: oldUrl,
                  text: 'Common Banner Image',
                  hint: 'Backward compatible image',
                  height: 230,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _imageBox(
                  onTap: _pickMobileImage,
                  webImage: _mobileWebImage,
                  fileImage: _mobileFileImage,
                  oldUrl: oldMobileUrl,
                  text: 'Mobile Banner Image',
                  hint: 'Recommended 800 x 1000',
                  height: 230,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _imageBox(
                  onTap: _pickDesktopImage,
                  webImage: _desktopWebImage,
                  fileImage: _desktopFileImage,
                  oldUrl: oldDesktopUrl,
                  text: 'Desktop Banner Image',
                  hint: 'Recommended 1600 x 500',
                  height: 230,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        _imageBox(
          onTap: _pickNormalImage,
          webImage: _normalWebImage,
          fileImage: _normalFileImage,
          oldUrl: oldUrl,
          text: 'Common Banner Image',
          hint: 'Tap to upload',
          height: 180,
        ),
        const SizedBox(height: 12),
        _imageBox(
          onTap: _pickMobileImage,
          webImage: _mobileWebImage,
          fileImage: _mobileFileImage,
          oldUrl: oldMobileUrl,
          text: 'Mobile Banner Image',
          hint: 'Optional',
          height: 180,
        ),
        const SizedBox(height: 12),
        _imageBox(
          onTap: _pickDesktopImage,
          webImage: _desktopWebImage,
          fileImage: _desktopFileImage,
          oldUrl: oldDesktopUrl,
          text: 'Desktop Banner Image',
          hint: 'Optional',
          height: 180,
        ),
      ],
    );
  }

  Widget _amazonGridForm(double maxWidth) {
    final bool isDesktop = maxWidth >= 900;
    final int crossAxisCount = isDesktop ? 4 : 2;
    final double cardHeight = isDesktop ? 285 : 260;
    final List oldItems = editingOldData?['items'] is List
        ? editingOldData!['items'] as List
        : [];

    return Column(
      children: [
        if (isDesktop)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title Example: Grocery',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle Example: Under SAR 49',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.subtitles_outlined),
                  ),
                ),
              ),
            ],
          )
        else ...[
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Title Example: Grocery',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subtitleController,
            decoration: const InputDecoration(
              labelText: 'Subtitle Example: Under SAR 49',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.subtitles_outlined),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Amazon Grid Items',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            String oldImage = '';
            if (index < oldItems.length && oldItems[index] is Map) {
              oldImage = _safeString((oldItems[index] as Map)['imageUrl']);
            }
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _imageBox(
                    onTap: () => _pickItemImage(index),
                    webImage: itemWebImages[index],
                    fileImage: itemFileImages[index],
                    oldUrl: oldImage,
                    text: 'Item Image ${index + 1}',
                    height: isDesktop ? 130 : 105,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: itemTitleControllers[index],
                    decoration: InputDecoration(
                      labelText: 'Item ${index + 1} title',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: itemClickValueControllers[index],
                    decoration: const InputDecoration(
                      labelText: 'Item link/value optional',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _previewBox() {
    final bool isAmazon = bannerType == 'amazon_grid';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: isAmazon
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleController.text.trim().isEmpty ? 'Amazon Grid Title' : titleController.text.trim(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            subtitleController.text.trim().isEmpty ? 'Subtitle preview' : subtitleController.text.trim(),
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 98,
            ),
            itemBuilder: (_, index) {
              return Container(
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  itemTitleControllers[index].text.trim().isEmpty
                      ? '(no name)'
                      : itemTitleControllers[index].text.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            },
          ),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Normal Banner Preview', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          _imageBox(
            onTap: () {},
            webImage: _normalWebImage ?? _mobileWebImage ?? _desktopWebImage,
            fileImage: _normalFileImage ?? _mobileFileImage ?? _desktopFileImage,
            oldUrl: _safeString(editingOldData?['url']).isNotEmpty
                ? _safeString(editingOldData?['url'])
                : (_safeString(editingOldData?['mobileUrl']).isNotEmpty
                ? _safeString(editingOldData?['mobileUrl'])
                : _safeString(editingOldData?['desktopUrl'])),
            text: 'Preview image',
            height: 160,
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return _sectionCard(
      child: LayoutBuilder(
        builder: (context, cardConstraints) {
          final bool isDesktop = cardConstraints.maxWidth >= 850;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Banner' : 'Create New Banner',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (isEditing)
                    TextButton.icon(
                      onPressed: canEditBanners ? _resetForm : null,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel edit'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (isDesktop)
                Row(
                  children: [
                    Expanded(child: _bannerTypeDropdown()),
                    const SizedBox(width: 12),
                    Expanded(child: _categoryDropdown()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: priorityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          hintText: 'Higher/lower as your home query uses',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.sort),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                _bannerTypeDropdown(),
                const SizedBox(height: 12),
                _categoryDropdown(),
                const SizedBox(height: 12),
                TextField(
                  controller: priorityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sort),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _clickActionFields(isDesktop),
              const SizedBox(height: 14),
              _dateAndVisibilityFields(isDesktop),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: Listenable.merge([
                  titleController,
                  subtitleController,
                  ...itemTitleControllers,
                ]),
                builder: (context, _) {
                  return bannerType == 'normal'
                      ? _normalBannerForm(isDesktop)
                      : _amazonGridForm(cardConstraints.maxWidth);
                },
              ),
              const SizedBox(height: 14),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Preview before upload'),
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      titleController,
                      subtitleController,
                      ...itemTitleControllers,
                    ]),
                    builder: (_, __) => _previewBox(),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isUploading || !canEditBanners) ? null : _saveBanner,
                  icon: _isUploading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(isEditing ? Icons.save_outlined : Icons.cloud_upload_outlined),
                  label: Text(
                    _isUploading
                        ? 'Saving...'
                        : (isEditing ? 'Update Banner' : 'Upload Banner'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _bannerMatchesFilter(Map<String, dynamic> data) {
    final String type = _safeString(data['layoutType'], 'normal');
    final bool active = data['isActive'] == true;
    final String title = _safeString(data['title']).toLowerCase();
    final String category = _safeString(data['categoryName']).toLowerCase();
    final String q = searchText.toLowerCase().trim();

    if (filterType == 'active' && !active) return false;
    if (filterType == 'inactive' && active) return false;
    if (filterType == 'normal' && type != 'normal') return false;
    if (filterType == 'amazon_grid' && type != 'amazon_grid') return false;

    if (q.isNotEmpty && !title.contains(q) && !category.contains(q) && !type.contains(q)) {
      return false;
    }

    return true;
  }

  Widget _existingBanners() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Existing Banners',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isDesktop = constraints.maxWidth >= 750;
              if (isDesktop) {
                return Row(
                  children: [
                    Expanded(child: _searchField()),
                    const SizedBox(width: 12),
                    SizedBox(width: 240, child: _filterDropdown()),
                  ],
                );
              }
              return Column(
                children: [
                  _searchField(),
                  const SizedBox(height: 10),
                  _filterDropdown(),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('banners').orderBy('priority', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final banners = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _bannerMatchesFilter(data);
              }).toList();

              if (banners.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No banners found'),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: banners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final banner = banners[index];
                  final data = banner.data() as Map<String, dynamic>;
                  return _bannerListTile(banner.id, data);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: searchController,
      onChanged: (v) => setState(() => searchText = v),
      decoration: const InputDecoration(
        labelText: 'Search banner',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.search),
      ),
    );
  }

  Widget _filterDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: filterType,
      decoration: const InputDecoration(
        labelText: 'Filter',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All banners')),
        DropdownMenuItem(value: 'active', child: Text('Active only')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactive only')),
        DropdownMenuItem(value: 'normal', child: Text('Normal only')),
        DropdownMenuItem(value: 'amazon_grid', child: Text('Amazon grid only')),
      ],
      onChanged: (v) => setState(() => filterType = v ?? 'all'),
    );
  }

  Widget _bannerListTile(String id, Map<String, dynamic> data) {
    final String layoutType = _safeString(data['layoutType'], 'normal');
    final String url = _safeString(data['url']).isNotEmpty
        ? _safeString(data['url'])
        : (_safeString(data['mobileUrl']).isNotEmpty
        ? _safeString(data['mobileUrl'])
        : _safeString(data['desktopUrl']));
    final String title = _safeString(data['title']);
    final String categoryName = _safeString(data['categoryName'], 'No category');
    final bool active = data['isActive'] == true;
    final int priority = data['priority'] is int
        ? data['priority'] as int
        : int.tryParse(_safeString(data['priority'])) ?? 0;

    String gridImage = '';
    if (layoutType == 'amazon_grid' && data['items'] is List && (data['items'] as List).isNotEmpty) {
      final first = (data['items'] as List).first;
      if (first is Map) gridImage = _safeString(first['imageUrl']);
    }

    final String previewImage = url.isNotEmpty ? url : gridImage;
    final String bannerName = layoutType == 'amazon_grid'
        ? 'Amazon Grid: ${title.isEmpty ? categoryName : title}'
        : categoryName;

    Widget preview({double size = 64}) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: previewImage.isNotEmpty
            ? Image.network(
          previewImage,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _bannerIcon(layoutType),
        )
            : _bannerIcon(layoutType),
      );
    }

    Widget chips() {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _chip(layoutType),
          _chip(active ? 'Active' : 'Inactive', color: active ? Colors.green : Colors.red),
          _chip('Priority: $priority'),
          if (data['showOnMobile'] != false) _chip('Mobile'),
          if (data['showOnDesktop'] != false) _chip('Desktop'),
        ],
      );
    }

    final List<Widget> actionButtons = [
      IconButton(
        tooltip: 'Move up',
        icon: const Icon(Icons.arrow_upward, size: 20),
        onPressed: canChangePriority ? () => _quickPriority(id, priority, 1) : null,
      ),
      IconButton(
        tooltip: 'Move down',
        icon: const Icon(Icons.arrow_downward, size: 20),
        onPressed: canChangePriority ? () => _quickPriority(id, priority, -1) : null,
      ),
      Switch(
        value: active,
        onChanged: canChangeStatus ? (v) => _toggleActive(id, v) : null,
      ),
      IconButton(
        tooltip: 'Edit',
        icon: const Icon(Icons.edit_outlined),
        onPressed: canEditBanners ? () => _editBanner(id, data) : null,
      ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: canDeleteBanners ? () => _deleteBanner(id) : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 520;

        return Container(
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isMobile
              ? Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview(size: 54),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bannerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          chips(),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 0,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionButtons,
                  ),
                ),
              ],
            ),
          )
              : ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading: preview(),
            title: Text(
              bannerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: chips(),
            trailing: Wrap(
              spacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actionButtons,
            ),
          ),
        );
      },
    );
  }

  Widget _bannerIcon(String type) {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey.shade100,
      child: Icon(
        type == 'amazon_grid' ? Icons.dashboard_customize : Icons.image,
        color: Colors.grey.shade700,
      ),
    );
  }

  Widget _chip(String text, {Color? color}) {
    final Color c = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _readOnlyNotice() {
    return _sectionCard(
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Read-only mode: you can view banners, but cannot add or edit them.',
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loadingPermissions) {
      return const Scaffold(
        backgroundColor: Color(0xfff7f2f8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewBanners) {
      return const Scaffold(
        backgroundColor: Color(0xfff7f2f8),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You do not have permission to view banners.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xfff7f2f8),
      appBar: AppBar(
        title: const Text('Pro Banner Manager'),
        backgroundColor: const Color(0xfff7f2f8),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _resetForm,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double contentWidth = constraints.maxWidth > 1180 ? 1180.0 : constraints.maxWidth;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canEditBanners) _formCard() else _readOnlyNotice(),
                      _existingBanners(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
