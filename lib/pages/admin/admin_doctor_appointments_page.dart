import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

class AdminDoctorAppointmentsPage extends StatefulWidget {
  const AdminDoctorAppointmentsPage({super.key});

  @override
  State<AdminDoctorAppointmentsPage> createState() => _AdminDoctorAppointmentsPageState();
}

class _AdminDoctorAppointmentsPageState extends State<AdminDoctorAppointmentsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  DateTime? selectedDate;
  String selectedDoctor = 'all';
  String selectedStatus = 'all';
  String searchText = '';

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _monthName(int m) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[m - 1];
  }

  String _dateString(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
  }

  String _todayString() => _dateString(DateTime.now());

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    await db.collection('doctor_appointments').doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _snack('Appointment marked as $status');
  }

  Future<void> _deleteAppointment(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel appointment?'),
        content: const Text('This appointment will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('doctor_appointments').doc(id).delete();
      _snack('Appointment cancelled');
    }
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty || clean == 'N/A') {
      _snack('Phone number not found');
      return;
    }

    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone, String name, String date, String time) async {
    String clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      _snack('Phone number not found');
      return;
    }

    if (clean.startsWith('0')) {
      clean = '88$clean';
    }

    final message = Uri.encodeComponent(
      'Hello $name, your doctor appointment is scheduled on $date at $time. - ChalakChar Mart',
    );

    final uri = Uri.parse('https://wa.me/$clean?text=$message');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<QueryDocumentSnapshot> _filterAppointments(List<QueryDocumentSnapshot> docs) {
    final search = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final isSelf = data['isForSelf'] == true;

      final patientName = isSelf ? _text(data['bookedByName']) : _text(data['patientName']);
      final patientPhone = isSelf ? _text(data['bookedByPhone']) : _text(data['patientPhone']);
      final bookedEmail = _text(data['bookedByEmail']);
      final doctorName = _text(data['doctorName'], 'Unknown Doctor');
      final status = _text(data['status'], 'pending');
      final appointmentDate = _text(data['appointmentDate']);

      if (selectedDate != null && appointmentDate != _dateString(selectedDate!)) return false;
      if (selectedDoctor != 'all' && doctorName != selectedDoctor) return false;
      if (selectedStatus != 'all' && status != selectedStatus) return false;

      if (search.isNotEmpty) {
        final id = doc.id.toLowerCase();

        return patientName.toLowerCase().contains(search) ||
            patientPhone.toLowerCase().contains(search) ||
            bookedEmail.toLowerCase().contains(search) ||
            doctorName.toLowerCase().contains(search) ||
            id.contains(search);
      }

      return true;
    }).toList();
  }

  Map<String, List<QueryDocumentSnapshot>> _groupByDoctor(List<QueryDocumentSnapshot> docs) {
    final result = <String, List<QueryDocumentSnapshot>>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final doctorName = _text(data['doctorName'], 'Unknown Doctor');
      result.putIfAbsent(doctorName, () => []);
      result[doctorName]!.add(doc);
    }

    return result;
  }

  Future<Map<String, dynamic>> _userInfo(String userId) async {
    if (userId.isEmpty) return {};
    final doc = await db.collection('users').doc(userId).get();
    return doc.data() ?? {};
  }

  Future<void> _generatePdf({
    required String doctorName,
    required List<QueryDocumentSnapshot> appointments,
  }) async {
    final pdf = pw.Document();
    final rows = <List<String>>[];
    final userCache = <String, Map<String, dynamic>>{};

    int serial = 1;

    for (final doc in appointments) {
      final data = doc.data() as Map<String, dynamic>;
      final isSelf = data['isForSelf'] == true;
      final userId = _text(data['userId']);

      final name = isSelf ? _text(data['bookedByName'], 'Unknown') : _text(data['patientName'], 'Unknown');
      final phone = isSelf ? _text(data['bookedByPhone'], 'N/A') : _text(data['patientPhone'], 'N/A');
      final email = _text(data['bookedByEmail'], 'N/A');

      Map<String, dynamic> user = {};
      if (userId.isNotEmpty) {
        if (!userCache.containsKey(userId)) {
          userCache[userId] = await _userInfo(userId);
        }
        user = userCache[userId] ?? {};
      }

      final address = _text(user['address'], 'N/A');
      final area = '${_text(user['division'], '-')} / ${_text(user['district'], '-')} / ${_text(user['upazila'], '-')}';

      rows.add([
        serial.toString(),
        name,
        phone,
        email.length > 24 ? email.replaceAll('@', '\n@') : email,
        address,
        area,
        _text(data['appointmentDate']),
        _text(data['appointmentTime']),
        _toDouble(data['fee']).toStringAsFixed(0),
        _text(data['status'], 'pending'),
      ]);

      serial++;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'Doctor Appointment Schedule',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('Doctor: $doctorName', style: const pw.TextStyle(fontSize: 12)),
          ),
          pw.Center(
            child: pw.Text(
              selectedDate == null ? 'All Dates' : 'Date: ${_dateString(selectedDate!)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'SL',
              'Patient',
              'Phone',
              'Email',
              'Address',
              'Area',
              'Date',
              'Time',
              'Fee',
              'Status',
            ],
            data: rows,
            border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey700),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.45),
              1: const pw.FlexColumnWidth(1.35),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(2.0),
              4: const pw.FlexColumnWidth(1.6),
              5: const pw.FlexColumnWidth(2.1),
              6: const pw.FlexColumnWidth(1.05),
              7: const pw.FlexColumnWidth(0.8),
              8: const pw.FlexColumnWidth(0.6),
              9: const pw.FlexColumnWidth(0.9),
            },
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Total appointments: ${rows.length}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeDoctor = doctorName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = 'Appointments_$safeDoctor.pdf';

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..style.display = 'none'
        ..download = fileName;
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
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
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    final today = _todayString();

    int todayCount = 0;
    int pending = 0;
    int confirmed = 0;
    int completed = 0;
    double revenue = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'pending');
      if (_text(data['appointmentDate']) == today) todayCount++;
      if (status == 'pending') pending++;
      if (status == 'confirmed') confirmed++;
      if (status == 'completed') {
        completed++;
        revenue += _toDouble(data['fee']);
      }
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 1000 ? 5 : c.maxWidth >= 650 ? 3 : 2;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 2 ? 1.7 : 2.0,
          children: [
            _summaryCard(title: 'Today', value: '$todayCount', icon: Icons.today_rounded, color: Colors.blue),
            _summaryCard(title: 'Pending', value: '$pending', icon: Icons.pending_actions_rounded, color: Colors.orange),
            _summaryCard(title: 'Confirmed', value: '$confirmed', icon: Icons.check_circle_rounded, color: Colors.green),
            _summaryCard(title: 'Completed', value: '$completed', icon: Icons.task_alt_rounded, color: Colors.purple),
            _summaryCard(title: 'Revenue', value: '৳${revenue.toStringAsFixed(0)}', icon: Icons.payments_rounded, color: Colors.teal),
          ],
        );
      },
    );
  }

  Widget _filters(List<QueryDocumentSnapshot> docs) {
    final doctors = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _text(data['doctorName'], 'Unknown Doctor');
    }).toSet().toList()
      ..sort();

    if (selectedDoctor != 'all' && !doctors.contains(selectedDoctor)) {
      selectedDoctor = 'all';
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
            final small = c.maxWidth < 800;

            final children = [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search patient, phone, email, doctor...',
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
                  initialValue: selectedDoctor,
                  decoration: const InputDecoration(
                    labelText: 'Doctor',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Doctors')),
                    ...doctors.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                  ],
                  onChanged: (v) => setState(() => selectedDoctor = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (v) => setState(() => selectedStatus = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2023),
                      lastDate: DateTime(2100),
                    );

                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(selectedDate == null ? 'All Dates' : _dateString(selectedDate!)),
                ),
              ),
              if (selectedDate != null || selectedDoctor != 'all' || selectedStatus != 'all' || searchText.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Clear filters',
                  onPressed: () {
                    setState(() {
                      selectedDate = null;
                      selectedDoctor = 'all';
                      selectedStatus = 'all';
                      searchText = '';
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, color: Colors.red),
                ),
              ],
            ];

            if (small) {
              return Column(
                children: [
                  children[0],
                  const SizedBox(height: 8),
                  children[2],
                  const SizedBox(height: 8),
                  children[4],
                  const SizedBox(height: 8),
                  children[6],
                  if (children.length > 8) children.last,
                ],
              );
            }

            return Row(children: children);
          },
        ),
      ),
    );
  }

  Widget _appointmentCard(QueryDocumentSnapshot doc, int serial) {
    final data = doc.data() as Map<String, dynamic>;
    final isSelf = data['isForSelf'] == true;

    final patientName = isSelf ? _text(data['bookedByName'], 'Unknown User') : _text(data['patientName'], 'Unknown Patient');
    final patientPhone = isSelf ? _text(data['bookedByPhone'], 'N/A') : _text(data['patientPhone'], 'N/A');
    final email = _text(data['bookedByEmail'], 'N/A');
    final status = _text(data['status'], 'pending');
    final userId = _text(data['userId']);

    return FutureBuilder<Map<String, dynamic>>(
      future: _userInfo(userId),
      builder: (context, userSnap) {
        final user = userSnap.data ?? {};
        final address = _text(user['address'], 'N/A');
        final area = '${_text(user['division'], '-')} / ${_text(user['district'], '-')} / ${_text(user['upazila'], '-')}';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF32A8C7),
                    child: Text(
                      '$serial',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      patientName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _info(Icons.call, patientPhone),
                  _info(Icons.email_outlined, email),
                  _info(Icons.family_restroom_rounded, isSelf ? 'Self' : _text(data['relation'], 'Family')),
                  if (_text(data['patientAge']).isNotEmpty) _info(Icons.cake_outlined, 'Age: ${_text(data['patientAge'])}'),
                  if (_text(data['patientGender']).isNotEmpty) _info(Icons.person_outline, 'Gender: ${_text(data['patientGender'])}'),
                  _info(Icons.calendar_month_rounded, _text(data['appointmentDate'])),
                  _info(Icons.access_time_rounded, _text(data['appointmentTime'])),
                  _info(Icons.payments_outlined, '৳${_toDouble(data['fee']).toStringAsFixed(0)}'),
                  _info(Icons.location_on_outlined, address),
                  _info(Icons.map_outlined, area),
                ],
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _button(
                    icon: Icons.check_circle_rounded,
                    label: 'Confirm',
                    color: Colors.green,
                    onTap: status == 'confirmed' || status == 'completed' ? null : () => _updateStatus(doc.id, 'confirmed'),
                  ),
                  _button(
                    icon: Icons.done_all_rounded,
                    label: 'Complete',
                    color: Colors.blue,
                    onTap: status == 'completed' ? null : () => _updateStatus(doc.id, 'completed'),
                  ),
                  _button(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: Colors.indigo,
                    onTap: () => _callPhone(patientPhone),
                  ),
                  _button(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: Colors.teal,
                    onTap: () => _openWhatsApp(
                      patientPhone,
                      patientName,
                      _text(data['appointmentDate']),
                      _text(data['appointmentTime']),
                    ),
                  ),
                  _button(
                    icon: Icons.cancel_rounded,
                    label: 'Cancel',
                    color: Colors.red,
                    onTap: () => _deleteAppointment(doc.id),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: onTap == null ? Colors.grey : color),
      label: Text(label, style: TextStyle(color: onTap == null ? Colors.grey : color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: (onTap == null ? Colors.grey : color).withOpacity(0.35)),
      ),
    );
  }

  Widget _doctorGroup(String doctorName, List<QueryDocumentSnapshot> docs) {
    docs.sort((a, b) {
      final ad = a.data() as Map<String, dynamic>;
      final bd = b.data() as Map<String, dynamic>;
      return _text(ad['appointmentTime']).compareTo(_text(bd['appointmentTime']));
    });

    final revenue = docs.fold<double>(0, (sum, doc) {
      final data = doc.data() as Map<String, dynamic>;
      return sum + _toDouble(data['fee']);
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          doctorName,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${docs.length} appointments • Total fee ৳${revenue.toStringAsFixed(0)}'),
        trailing: ElevatedButton.icon(
          onPressed: () => _generatePdf(doctorName: doctorName, appointments: docs),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
        ),
        children: List.generate(docs.length, (index) => _appointmentCard(docs[index], index + 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('doctor_appointments').orderBy('createdAt', descending: true).limit(500).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No appointments found'));
          }

          final allDocs = snap.data!.docs;
          final filtered = _filterAppointments(allDocs);
          final grouped = _groupByDoctor(filtered);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Doctor Appointments Pro',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: filtered.isEmpty
                        ? null
                        : () => _generatePdf(
                      doctorName: selectedDoctor == 'all' ? 'All Doctors' : selectedDoctor,
                      appointments: filtered,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Download Filtered PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _summaryGrid(allDocs),
              const SizedBox(height: 14),
              _filters(allDocs),
              const SizedBox(height: 14),

              if (filtered.isEmpty)
                const Card(
                  elevation: 0,
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('No matching appointments found')),
                  ),
                )
              else
                ...grouped.entries.map((entry) => _doctorGroup(entry.key, entry.value)),
            ],
          );
        },
      ),
    );
  }
}



