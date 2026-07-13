
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/image_upload_service.dart';

class ManageDoctorsPage extends StatefulWidget {
  const ManageDoctorsPage({super.key});

  @override
  State<ManageDoctorsPage> createState() => _ManageDoctorsPageState();
}

class _ManageDoctorsPageState extends State<ManageDoctorsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final degreeController = TextEditingController();
  final titleController = TextEditingController();
  final hospitalController = TextEditingController();
  final chamberAddressController = TextEditingController();
  final regNumberController = TextEditingController();
  final experienceController = TextEditingController();
  final newPatientFeeController = TextEditingController();
  final followupFeeController = TextEditingController();
  final dateController = TextEditingController();
  final timeController = TextEditingController();
  final unavailableDateController = TextEditingController();
  final aboutController = TextEditingController();
  final priorityController = TextEditingController(text: '0');

  String? selectedDepartmentId;
  String? selectedDepartmentName;

  String searchText = '';
  String filterDepartment = 'all';
  String filterStatus = 'all';

  bool isUploading = false;
  bool isActive = true;
  bool isFeatured = false;
  bool allowOnlineConsultation = false;
  bool allowChamberConsultation = true;

  File? imageFile;
  Uint8List? webImage;

  final Map<String, bool> weeklyDays = {
    'Sat': false,
    'Sun': false,
    'Mon': false,
    'Tue': false,
    'Wed': false,
    'Thu': false,
    'Fri': false,
  };

  @override
  void dispose() {
    nameController.dispose();
    degreeController.dispose();
    titleController.dispose();
    hospitalController.dispose();
    chamberAddressController.dispose();
    regNumberController.dispose();
    experienceController.dispose();
    newPatientFeeController.dispose();
    followupFeeController.dispose();
    dateController.dispose();
    timeController.dispose();
    unavailableDateController.dispose();
    aboutController.dispose();
    priorityController.dispose();
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

  bool _isValidDateFormat(String date) {
    final regex = RegExp(
      r'^(0[1-9]|[12][0-9]|3[01]) (January|February|March|April|May|June|July|August|September|October|November|December) \d{4}$',
    );
    return regex.hasMatch(date.trim());
  }

  bool _validateDates(String text, {bool allowEmpty = true}) {
    final clean = text.trim();
    if (clean.isEmpty) return allowEmpty;

    final dates = clean
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final d in dates) {
      if (!_isValidDateFormat(d)) return false;
    }

    return true;
  }

  List<String> _splitList(String text) {
    return text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  String? _numberRequired(String? value) {
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

  Future<String> _uploadDoctorImage(File? file, Uint8List? bytes) async {
    if (file == null && bytes == null) return '';
    return ImageUploadService.upload(file, webImage: bytes);
  }

  void _clearForm() {
    nameController.clear();
    degreeController.clear();
    titleController.clear();
    hospitalController.clear();
    chamberAddressController.clear();
    regNumberController.clear();
    experienceController.clear();
    newPatientFeeController.clear();
    followupFeeController.clear();
    dateController.clear();
    timeController.clear();
    unavailableDateController.clear();
    aboutController.clear();
    priorityController.text = '0';

    setState(() {
      selectedDepartmentId = null;
      selectedDepartmentName = null;
      imageFile = null;
      webImage = null;
      isActive = true;
      isFeatured = false;
      allowOnlineConsultation = false;
      allowChamberConsultation = true;
      for (final key in weeklyDays.keys) {
        weeklyDays[key] = false;
      }
    });
  }

  Future<void> _addDoctor() async {
    if (!formKey.currentState!.validate()) return;

    if (selectedDepartmentId == null || selectedDepartmentName == null) {
      _snack('Please select department');
      return;
    }

    if (!_validateDates(dateController.text)) {
      _snack('Available date format wrong. Use: 24 April 2026, 01 May 2026');
      return;
    }

    if (!_validateDates(unavailableDateController.text)) {
      _snack('Unavailable date format wrong. Use: 24 April 2026, 01 May 2026');
      return;
    }

    final fee = _toInt(newPatientFeeController.text);
    final experience = _toInt(experienceController.text);

    if (fee <= 0 || experience <= 0) {
      _snack('Experience and fee must be greater than 0');
      return;
    }

    setState(() => isUploading = true);

    try {
      final imageUrl = await _uploadDoctorImage(imageFile, webImage);
      final availableDates = _splitList(dateController.text);
      final unavailableDates = _splitList(unavailableDateController.text);
      final availableTimes = _splitList(timeController.text);
      final weeklySchedule = weeklyDays.entries.where((e) => e.value).map((e) => e.key).toList();

      await db.collection('doctors').add({
        'departmentId': selectedDepartmentId,
        'departmentName': selectedDepartmentName,
        'name': nameController.text.trim(),
        'degree': degreeController.text.trim(),
        'title': titleController.text.trim(),
        'hospital': hospitalController.text.trim(),
        'chamberAddress': chamberAddressController.text.trim(),
        'regNumber': regNumberController.text.trim(),
        'experience': experience,
        'fee': fee,
        'newPatientFee': fee,
        'followupFee': _toInt(followupFeeController.text),
        'about': aboutController.text.trim(),
        'imageUrl': imageUrl,
        'availableDates': availableDates,
        'availableTimes': availableTimes,
        'unavailableDates': unavailableDates,
        'weeklySchedule': weeklySchedule,
        'consultationsDone': 0,
        'priority': _toInt(priorityController.text),
        'isActive': isActive,
        'isFeatured': isFeatured,
        'allowOnlineConsultation': allowOnlineConsultation,
        'allowChamberConsultation': allowChamberConsultation,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _clearForm();
      _snack('Doctor added successfully');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> data) async {
    File? newImageFile;
    Uint8List? newWebImage;

    final name = TextEditingController(text: _text(data['name']));
    final degree = TextEditingController(text: _text(data['degree']));
    final title = TextEditingController(text: _text(data['title']));
    final hospital = TextEditingController(text: _text(data['hospital']));
    final chamber = TextEditingController(text: _text(data['chamberAddress']));
    final reg = TextEditingController(text: _text(data['regNumber']));
    final exp = TextEditingController(text: _toInt(data['experience']).toString());
    final newFee = TextEditingController(text: _toInt(data['newPatientFee'] ?? data['fee']).toString());
    final followFee = TextEditingController(text: _toInt(data['followupFee']).toString());
    final about = TextEditingController(text: _text(data['about']));
    final dates = TextEditingController(text: List<String>.from(data['availableDates'] ?? []).join(', '));
    final times = TextEditingController(text: List<String>.from(data['availableTimes'] ?? []).join(', '));
    final unavailableDates = TextEditingController(text: List<String>.from(data['unavailableDates'] ?? []).join(', '));
    final consultations = TextEditingController(text: _toInt(data['consultationsDone']).toString());
    final priority = TextEditingController(text: _toInt(data['priority']).toString());

    String? deptId = _text(data['departmentId']).isEmpty ? null : _text(data['departmentId']);
    String? deptName = _text(data['departmentName']).isEmpty ? null : _text(data['departmentName']);
    bool active = data['isActive'] != false;
    bool featured = data['isFeatured'] == true;
    bool online = data['allowOnlineConsultation'] == true;
    bool chamberConsult = data['allowChamberConsultation'] != false;

    final editWeekly = <String, bool>{
      'Sat': false,
      'Sun': false,
      'Mon': false,
      'Tue': false,
      'Wed': false,
      'Thu': false,
      'Fri': false,
    };

    final rawWeekly = List<String>.from(data['weeklySchedule'] ?? []);
    for (final d in rawWeekly) {
      if (editWeekly.containsKey(d)) editWeekly[d] = true;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickEditImage() async {
            await _pickImage(
              onFile: (file) => setDialogState(() => newImageFile = file),
              onWeb: (bytes) => setDialogState(() => newWebImage = bytes),
            );
          }

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
                  SizedBox(height: 4),
                  Text('Tap to upload'),
                ],
              );
            }

            return InkWell(
              onTap: pickEditImage,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 130,
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
            if (name.text.trim().isEmpty || deptId == null || newFee.text.trim().isEmpty) {
              _snack('Department, doctor name and fee required');
              return;
            }

            if (!_validateDates(dates.text)) {
              _snack('Available date format wrong. Use: 24 April 2026, 01 May 2026');
              return;
            }

            if (!_validateDates(unavailableDates.text)) {
              _snack('Unavailable date format wrong. Use: 24 April 2026, 01 May 2026');
              return;
            }

            String imageUrl = _text(data['imageUrl']);

            if (newImageFile != null || newWebImage != null) {
              imageUrl = await _uploadDoctorImage(newImageFile, newWebImage);
            }

            await db.collection('doctors').doc(id).update({
              'departmentId': deptId,
              'departmentName': deptName,
              'name': name.text.trim(),
              'degree': degree.text.trim(),
              'title': title.text.trim(),
              'hospital': hospital.text.trim(),
              'chamberAddress': chamber.text.trim(),
              'regNumber': reg.text.trim(),
              'experience': _toInt(exp.text),
              'fee': _toInt(newFee.text),
              'newPatientFee': _toInt(newFee.text),
              'followupFee': _toInt(followFee.text),
              'consultationsDone': _toInt(consultations.text),
              'priority': _toInt(priority.text),
              'about': about.text.trim(),
              'imageUrl': imageUrl,
              'availableDates': _splitList(dates.text),
              'availableTimes': _splitList(times.text),
              'unavailableDates': _splitList(unavailableDates.text),
              'weeklySchedule': editWeekly.entries.where((e) => e.value).map((e) => e.key).toList(),
              'isActive': active,
              'isFeatured': featured,
              'allowOnlineConsultation': online,
              'allowChamberConsultation': chamberConsult,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            if (context.mounted) Navigator.pop(context);
            _snack('Doctor updated');
          }

          return AlertDialog(
            title: const Text('Edit Doctor'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    imageBox(),
                    const SizedBox(height: 14),
                    StreamBuilder<QuerySnapshot>(
                      stream: db.collection('doctor_departments').where('isActive', isEqualTo: true).snapshots(),
                      builder: (context, snap) {
                        final deps = snap.data?.docs ?? [];

                        return DropdownButtonFormField<String>(
                          initialValue: deptId,
                          decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
                          items: deps.map((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text(_text(d['name'])),
                              onTap: () => deptName = _text(d['name']),
                            );
                          }).toList(),
                          onChanged: (v) => setDialogState(() => deptId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _dialogGrid([
                      _dialogField('Doctor Name', name),
                      _dialogField('Degree', degree),
                      _dialogField('Title/Specialist', title),
                      _dialogField('Hospital/Chamber', hospital),
                      _dialogField('Chamber Address', chamber),
                      _dialogField('BMDC/Reg Number', reg),
                      _dialogField('Experience Years', exp, number: true),
                      _dialogField('New Patient Fee', newFee, number: true),
                      _dialogField('Follow-up Fee', followFee, number: true),
                      _dialogField('Consultations Done', consultations, number: true),
                      _dialogField('Priority', priority, number: true),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dates,
                      decoration: const InputDecoration(
                        labelText: 'Available Dates',
                        hintText: '24 April 2026, 01 May 2026',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: times,
                      decoration: const InputDecoration(
                        labelText: 'Available Times',
                        hintText: '7:40 PM, 8:00 PM, 8:20 PM',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unavailableDates,
                      decoration: const InputDecoration(
                        labelText: 'Unavailable Dates',
                        hintText: 'Optional',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: about,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'About Doctor', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    _weeklySelector(editWeekly, setDialogState),
                    SwitchListTile(
                      value: active,
                      title: const Text('Active'),
                      onChanged: (v) => setDialogState(() => active = v),
                    ),
                    SwitchListTile(
                      value: featured,
                      title: const Text('Featured Doctor'),
                      onChanged: (v) => setDialogState(() => featured = v),
                    ),
                    SwitchListTile(
                      value: online,
                      title: const Text('Allow Online Consultation'),
                      onChanged: (v) => setDialogState(() => online = v),
                    ),
                    SwitchListTile(
                      value: chamberConsult,
                      title: const Text('Allow Chamber Consultation'),
                      onChanged: (v) => setDialogState(() => chamberConsult = v),
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

  Widget _dialogField(String label, TextEditingController controller, {bool number = false}) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  Widget _dialogGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth > 650 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: count == 1 ? 6 : 5,
          ),
          itemBuilder: (_, i) => children[i],
        );
      },
    );
  }

  Future<void> _deleteDoctor(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Doctor?'),
        content: const Text('This doctor will be permanently deleted.'),
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
      await db.collection('doctors').doc(id).delete();
      _snack('Doctor deleted');
    }
  }

  Future<void> _toggleDoctor(String id, bool value) async {
    await db.collection('doctors').doc(id).update({
      'isActive': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _toggleFeatured(String id, bool value) async {
    await db.collection('doctors').doc(id).update({
      'isFeatured': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<QueryDocumentSnapshot> _filterDoctors(List<QueryDocumentSnapshot> docs) {
    final search = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final active = data['isActive'] != false;
      final departmentName = _text(data['departmentName']);
      final name = _text(data['name']).toLowerCase();
      final title = _text(data['title']).toLowerCase();
      final degree = _text(data['degree']).toLowerCase();
      final reg = _text(data['regNumber']).toLowerCase();

      if (filterStatus == 'active' && !active) return false;
      if (filterStatus == 'inactive' && active) return false;
      if (filterDepartment != 'all' && departmentName != filterDepartment) return false;

      if (search.isNotEmpty &&
          !name.contains(search) &&
          !title.contains(search) &&
          !degree.contains(search) &&
          !reg.contains(search)) {
        return false;
      }

      return true;
    }).toList();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _weeklySelector(Map<String, bool> source, void Function(void Function()) setter) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: source.keys.map((day) {
          return FilterChip(
            label: Text(day),
            selected: source[day] == true,
            onSelected: (v) => setter(() => source[day] = v),
          );
        }).toList(),
      ),
    );
  }

  Widget _formCard() {
    Widget imageBox() {
      Widget child;

      if (webImage != null) {
        child = Image.memory(webImage!, fit: BoxFit.cover);
      } else if (imageFile != null) {
        child = Image.file(imageFile!, fit: BoxFit.cover);
      } else {
        child = const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded, size: 44),
            SizedBox(height: 6),
            Text('Upload Doctor Image'),
          ],
        );
      }

      return InkWell(
        onTap: _pickImage,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 160,
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
              const Text('Add New Doctor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              imageBox(),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: db.collection('doctor_departments').where('isActive', isEqualTo: true).snapshots(),
                builder: (context, snapshot) {
                  final departments = snapshot.data?.docs ?? [];

                  return DropdownButtonFormField<String>(
                    initialValue: selectedDepartmentId,
                    decoration: InputDecoration(
                      labelText: 'Select Department',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: departments.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(_text(data['name'])),
                        onTap: () => selectedDepartmentName = _text(data['name']),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => selectedDepartmentId = value),
                    validator: (value) => value == null ? 'Required' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final count = c.maxWidth > 850 ? 3 : c.maxWidth > 550 ? 2 : 1;
                  final fields = [
                    _field(label: 'Doctor Name', controller: nameController, icon: Icons.person, validator: _required),
                    _field(label: 'Degree / Qualification', controller: degreeController, hint: 'MBBS, FCPS', icon: Icons.school_outlined),
                    _field(label: 'Doctor Title', controller: titleController, hint: 'Eye Specialist', icon: Icons.medical_services_outlined),
                    _field(label: 'Hospital / Chamber', controller: hospitalController, icon: Icons.local_hospital_outlined),
                    _field(label: 'Chamber Address', controller: chamberAddressController, icon: Icons.location_on_outlined),
                    _field(label: 'BMDC / Reg Number', controller: regNumberController, icon: Icons.verified_user_outlined),
                    _field(label: 'Experience Years', controller: experienceController, number: true, icon: Icons.work_history_outlined, validator: _numberRequired),
                    _field(label: 'New Patient Fee', controller: newPatientFeeController, number: true, icon: Icons.payments_outlined, validator: _numberRequired),
                    _field(label: 'Follow-up Fee', controller: followupFeeController, number: true, icon: Icons.price_check_outlined),
                    _field(label: 'Priority', controller: priorityController, number: true, icon: Icons.sort_rounded),
                  ];

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: fields.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: count == 1 ? 5.8 : 4.3,
                    ),
                    itemBuilder: (_, i) => fields[i],
                  );
                },
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Available Dates',
                controller: dateController,
                hint: '24 April 2026, 01 May 2026',
                icon: Icons.calendar_month_outlined,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Available Times',
                controller: timeController,
                hint: '7:40 PM, 8:00 PM, 8:20 PM',
                icon: Icons.access_time_outlined,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Unavailable Dates',
                controller: unavailableDateController,
                hint: 'Optional: 25 April 2026',
                icon: Icons.event_busy_outlined,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'About Doctor',
                controller: aboutController,
                maxLines: 4,
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 14),
              const Text('Weekly Schedule', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _weeklySelector(weeklyDays, setState),
              const SizedBox(height: 12),
              SwitchListTile(
                value: isActive,
                title: const Text('Active Doctor'),
                onChanged: (v) => setState(() => isActive = v),
              ),
              SwitchListTile(
                value: isFeatured,
                title: const Text('Featured Doctor'),
                onChanged: (v) => setState(() => isFeatured = v),
              ),
              SwitchListTile(
                value: allowOnlineConsultation,
                title: const Text('Allow Online Consultation'),
                onChanged: (v) => setState(() => allowOnlineConsultation = v),
              ),
              SwitchListTile(
                value: allowChamberConsultation,
                title: const Text('Allow Chamber Consultation'),
                onChanged: (v) => setState(() => allowChamberConsultation = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: isUploading ? null : _addDoctor,
                  icon: isUploading
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.add_rounded),
                  label: Text(isUploading ? 'Adding...' : 'Add Doctor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(List<QueryDocumentSnapshot> doctors) {
    final departments = doctors
        .map((doc) => _text((doc.data() as Map<String, dynamic>)['departmentName']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (filterDepartment != 'all' && !departments.contains(filterDepartment)) {
      filterDepartment = 'all';
    }

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
              decoration: const InputDecoration(
                hintText: 'Search doctor, title, degree, reg number...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final dept = DropdownButtonFormField<String>(
              initialValue: filterDepartment,
              decoration: const InputDecoration(
                labelText: 'Department',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All Departments')),
                ...departments.map((d) => DropdownMenuItem(value: d, child: Text(d))),
              ],
              onChanged: (v) => setState(() => filterDepartment = v ?? 'all'),
            );

            final status = DropdownButtonFormField<String>(
              initialValue: filterStatus,
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
              onChanged: (v) => setState(() => filterStatus = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  dept,
                  const SizedBox(height: 8),
                  status,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: dept),
                const SizedBox(width: 8),
                Expanded(child: status),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _doctorCard(String id, Map<String, dynamic> data) {
    final active = data['isActive'] != false;
    final featured = data['isFeatured'] == true;
    final imageUrl = _text(data['imageUrl']);

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFEAF6FA),
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty ? const Icon(Icons.person, size: 34, color: Color(0xFF1592B3)) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(data['name'], 'Unnamed Doctor'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _text(data['title']),
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_text(data['departmentName'])} • ${_text(data['degree'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(active ? 'Active' : 'Inactive', active ? Colors.green : Colors.red),
                      if (featured) _chip('Featured', Colors.deepPurple),
                      _chip('New ৳${_toInt(data['newPatientFee'] ?? data['fee'])}', Colors.blue),
                      _chip('Old ৳${_toInt(data['followupFee'])}', Colors.teal),
                      _chip('${_toInt(data['experience'])} yrs', Colors.orange),
                      if (_text(data['regNumber']).isNotEmpty) _chip('Reg: ${_text(data['regNumber'])}', Colors.indigo),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dates: ${List<String>.from(data['availableDates'] ?? []).take(3).join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_rounded, color: Colors.orange),
                  onPressed: () => _showEditDialog(id, data),
                ),
                Switch(
                  value: active,
                  onChanged: (v) => _toggleDoctor(id, v),
                ),
                IconButton(
                  tooltip: featured ? 'Remove featured' : 'Make featured',
                  icon: Icon(
                    featured ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.deepPurple,
                  ),
                  onPressed: () => _toggleFeatured(id, !featured),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  onPressed: () => _deleteDoctor(id),
                ),
              ],
            ),
          ],
        ),
      ),
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

  Widget _doctorList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('doctors').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }

        final allDoctors = snapshot.data!.docs;
        final doctors = _filterDoctors(allDoctors);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filters(allDoctors),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'All Doctors (${doctors.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (doctors.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching doctors')),
                ),
              )
            else
              ...doctors.map((doc) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _doctorCard(doc.id, doc.data() as Map<String, dynamic>),
              )),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1150;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Manage Doctors Pro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _formCard()),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: _doctorList()),
              ],
            )
          else ...[
            _formCard(),
            const SizedBox(height: 16),
            _doctorList(),
          ],
        ],
      ),
    );
  }
}



