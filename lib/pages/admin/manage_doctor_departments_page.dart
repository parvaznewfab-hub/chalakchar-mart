import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ManageDoctorDepartmentsPage extends StatefulWidget {
  const ManageDoctorDepartmentsPage({super.key});

  @override
  State<ManageDoctorDepartmentsPage> createState() => _ManageDoctorDepartmentsPageState();
}

class _ManageDoctorDepartmentsPageState extends State<ManageDoctorDepartmentsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final banglaController = TextEditingController();
  final descriptionController = TextEditingController();
  final priorityController = TextEditingController(text: '0');
  final searchController = TextEditingController();

  String searchText = '';
  String statusFilter = 'all';

  bool isActive = true;
  bool isFeatured = false;
  bool saving = false;

  File? imageFile;
  Uint8List? webImage;

  @override
  void dispose() {
    nameController.dispose();
    banglaController.dispose();
    descriptionController.dispose();
    priorityController.dispose();
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
        .child('doctor_departments/${DateTime.now().millisecondsSinceEpoch}.jpg');

    if (kIsWeb && bytes != null) {
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else if (file != null) {
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    }

    return ref.getDownloadURL();
  }

  void _clearForm() {
    nameController.clear();
    banglaController.clear();
    descriptionController.clear();
    priorityController.text = '0';

    setState(() {
      imageFile = null;
      webImage = null;
      isActive = true;
      isFeatured = false;
    });
  }

  Future<void> _addDepartment() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final imageUrl = await _uploadImage(imageFile, webImage);

      await db.collection('doctor_departments').add({
        'name': nameController.text.trim(),
        'bangla': banglaController.text.trim(),
        'description': descriptionController.text.trim(),
        'imageUrl': imageUrl,
        'priority': _toInt(priorityController.text),
        'isActive': isActive,
        'isFeatured': isFeatured,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _clearForm();
      _snack('Department added successfully');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> data) async {
    final name = TextEditingController(text: _text(data['name']));
    final bangla = TextEditingController(text: _text(data['bangla']));
    final description = TextEditingController(text: _text(data['description']));
    final priority = TextEditingController(text: _toInt(data['priority']).toString());

    bool active = data['isActive'] != false;
    bool featured = data['isFeatured'] == true;

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
            } else if (_text(data['imageUrl']).isNotEmpty) {
              child = Image.network(
                _text(data['imageUrl']),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              );
            } else {
              child = const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_rounded, size: 38),
                  SizedBox(height: 5),
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
                height: 140,
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
            if (name.text.trim().isEmpty) {
              _snack('Department name required');
              return;
            }

            String imageUrl = _text(data['imageUrl']);

            if (newImageFile != null || newWebImage != null) {
              imageUrl = await _uploadImage(newImageFile, newWebImage);
            }

            await db.collection('doctor_departments').doc(id).update({
              'name': name.text.trim(),
              'bangla': bangla.text.trim(),
              'description': description.text.trim(),
              'priority': _toInt(priority.text),
              'imageUrl': imageUrl,
              'isActive': active,
              'isFeatured': featured,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            if (context.mounted) Navigator.pop(context);
            _snack('Department updated');
          }

          return AlertDialog(
            title: const Text('Edit Department'),
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
                        labelText: 'English Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bangla,
                      decoration: const InputDecoration(
                        labelText: 'Bangla Name',
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

  Future<void> _deleteDepartment(String id, Map<String, dynamic> data) async {
    final doctorCount = await _countDoctorsByDepartment(id, _text(data['name']));

    if (doctorCount > 0) {
      _snack('Cannot delete. $doctorCount doctors are using this department.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete department?'),
        content: const Text('This department will be permanently deleted.'),
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
      await db.collection('doctor_departments').doc(id).delete();
      _snack('Department deleted');
    }
  }

  Future<void> _toggleDepartment(String id, bool value) async {
    await db.collection('doctor_departments').doc(id).update({
      'isActive': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleFeatured(String id, bool value) async {
    await db.collection('doctor_departments').doc(id).update({
      'isFeatured': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> _countDoctorsByDepartment(String departmentId, String departmentName) async {
    final byId = await db
        .collection('doctors')
        .where('departmentId', isEqualTo: departmentId)
        .limit(50)
        .get();

    if (byId.docs.isNotEmpty) return byId.docs.length;

    final byName = await db
        .collection('doctors')
        .where('departmentName', isEqualTo: departmentName)
        .limit(50)
        .get();

    return byName.docs.length;
  }

  Future<int> _countAppointmentsByDepartment(String departmentName) async {
    final snap = await db
        .collection('doctor_appointments')
        .where('departmentName', isEqualTo: departmentName)
        .limit(100)
        .get();

    return snap.docs.length;
  }

  List<QueryDocumentSnapshot> _filterDepartments(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final active = data['isActive'] != false;
      final name = _text(data['name']).toLowerCase();
      final bangla = _text(data['bangla']).toLowerCase();

      if (statusFilter == 'active' && !active) return false;
      if (statusFilter == 'inactive' && active) return false;
      if (statusFilter == 'featured' && data['isFeatured'] != true) return false;

      if (s.isNotEmpty && !name.contains(s) && !bangla.contains(s)) return false;

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
          Text('Upload Department Image/Icon'),
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
  }) {
    return TextFormField(
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
              const Text('Add Doctor Department', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _imageBox(),
              const SizedBox(height: 14),
              _field(
                label: 'English Name',
                controller: nameController,
                icon: Icons.medical_information_outlined,
                validator: _required,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Bangla Name',
                controller: banglaController,
                icon: Icons.translate_rounded,
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
                title: const Text('Active Department'),
                onChanged: (v) => setState(() => isActive = v),
              ),
              SwitchListTile(
                value: isFeatured,
                title: const Text('Featured Department'),
                onChanged: (v) => setState(() => isFeatured = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : _addDepartment,
                  icon: saving
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.add_rounded),
                  label: Text(saving ? 'Saving...' : 'Add Department'),
                ),
              ),
            ],
          ),
        ),
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
            final small = c.maxWidth < 700;

            final search = TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search department...',
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

  Widget _departmentImage(Map<String, dynamic> data) {
    final url = _text(data['imageUrl']);

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

  Widget _departmentCard(String id, Map<String, dynamic> data) {
    final active = data['isActive'] != false;
    final featured = data['isFeatured'] == true;
    final departmentName = _text(data['name']);

    return FutureBuilder<List<int>>(
      future: Future.wait([
        _countDoctorsByDepartment(id, departmentName),
        _countAppointmentsByDepartment(departmentName),
      ]),
      builder: (context, countsSnap) {
        final doctorCount = countsSnap.data?[0] ?? 0;
        final appointmentCount = countsSnap.data?[1] ?? 0;

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
                _departmentImage(data),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        departmentName.isEmpty ? 'Unnamed Department' : departmentName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      if (_text(data['bangla']).isNotEmpty)
                        Text(
                          _text(data['bangla']),
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
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
                          _chip('Priority ${_toInt(data['priority'])}', Colors.blue),
                          _chip('$doctorCount Doctors', Colors.teal),
                          _chip('$appointmentCount Appointments', Colors.orange),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _showEditDialog(id, data),
                      icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                    ),
                    Switch(
                      value: active,
                      onChanged: (v) => _toggleDepartment(id, v),
                    ),
                    IconButton(
                      tooltip: featured ? 'Remove featured' : 'Make featured',
                      onPressed: () => _toggleFeatured(id, !featured),
                      icon: Icon(
                        featured ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.deepPurple,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _deleteDepartment(id, data),
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

  Widget _departmentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('doctor_departments').orderBy('priority').limit(200).snapshots(),
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
        final docs = _filterDepartments(allDocs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filters(),
            const SizedBox(height: 12),
            Text(
              'All Departments (${docs.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching departments')),
                ),
              )
            else
              ...docs.map((doc) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _departmentCard(doc.id, doc.data() as Map<String, dynamic>),
                );
              }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Doctor Departments Pro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: _formCard()),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: _departmentList()),
              ],
            )
          else ...[
            _formCard(),
            const SizedBox(height: 16),
            _departmentList(),
          ],
        ],
      ),
    );
  }
}



