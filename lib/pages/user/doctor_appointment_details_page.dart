import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile/edit_profile_page.dart';
import '../auth/login_page.dart';

class DoctorAppointmentDetailsPage extends StatefulWidget {
  final String doctorId;
  final Map<String, dynamic> doctor;

  const DoctorAppointmentDetailsPage({
    super.key,
    required this.doctorId,
    required this.doctor,
  });

  @override
  State<DoctorAppointmentDetailsPage> createState() =>
      _DoctorAppointmentDetailsPageState();
}

class _DoctorAppointmentDetailsPageState
    extends State<DoctorAppointmentDetailsPage> {
  String? selectedDate;
  String? selectedTime;
  bool loading = false;
  bool showAbout = false;

  bool isForSelf = true;
  final patientNameController = TextEditingController();
  final patientPhoneController = TextEditingController();
  final patientAgeController = TextEditingController();
  String patientGender = "Male";
  String patientRelation = "Father";

  @override
  void dispose() {
    patientNameController.dispose();
    patientPhoneController.dispose();
    patientAgeController.dispose();
    super.dispose();
  }

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  Future<bool> _isProfileComplete(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection("users").doc(uid).get();

    if (!doc.exists) return false;

    final data = doc.data();

    return _hasValue(data?['name']) &&
        _hasValue(data?['age']) &&
        _hasValue(data?['address']) &&
        _hasValue(data?['phone']);
  }

  void _showProfileWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Complete Profile"),
        content:
            const Text("Please complete your profile to use this feature."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfilePage()),
              );
            },
            child: const Text("Go to Profile"),
          ),
        ],
      ),
    );
  }

  String _monthToNumber(String month) {
    const months = {
      "January": "01",
      "February": "02",
      "March": "03",
      "April": "04",
      "May": "05",
      "June": "06",
      "July": "07",
      "August": "08",
      "September": "09",
      "October": "10",
      "November": "11",
      "December": "12",
    };
    return months[month] ?? "01";
  }

  DateTime? _parseDoctorDate(String date) {
    try {
      final parts = date.trim().split(' ');
      if (parts.length != 3) return null;

      final day = parts[0].padLeft(2, '0');
      final month = _monthToNumber(parts[1]);
      final year = parts[2];

      return DateTime.parse("$year-$month-$day");
    } catch (e) {
      return null;
    }
  }

  Future<void> bookAppointment() async {
    if (selectedDate == null || selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select date and time")),
      );
      return;
    }

    if (!isForSelf &&
        (patientNameController.text.trim().isEmpty ||
            patientPhoneController.text.trim().isEmpty ||
            patientAgeController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill patient information"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => const LoginPage(isPopup: true),
        );
      }
      return;
    }

    final profileComplete = await _isProfileComplete(user.uid);

    if (!profileComplete) {
      if (mounted) {
        _showProfileWarning();
      }
      return;
    }

    setState(() => loading = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};

      final duplicateCheck = await FirebaseFirestore.instance
          .collection('doctor_appointments')
          .where('userId', isEqualTo: user.uid)
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('appointmentDate', isEqualTo: selectedDate)
          .where('status', whereIn: ['pending', 'confirmed', 'PENDING', 'CONFIRMED'])
          .limit(1)
          .get();

      if (duplicateCheck.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => loading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "You already have an appointment with this doctor on this date"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final patientName = isForSelf
          ? (userData['name'] ?? user.displayName ?? 'User')
          : patientNameController.text.trim();

      final patientPhone = isForSelf
          ? (userData['phone'] ?? user.phoneNumber ?? '')
          : patientPhoneController.text.trim();

      await FirebaseFirestore.instance.collection('doctor_appointments').add({
        'userId': user.uid,
        'isForSelf': isForSelf,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'patientEmail': user.email ?? userData['email'] ?? '',
        'patientAge': isForSelf ? '' : patientAgeController.text.trim(),
        'patientGender': isForSelf ? '' : patientGender,
        'relation': isForSelf ? 'Self' : patientRelation,
        'bookedByUserId': user.uid,
        'bookedByName': userData['name'] ?? user.displayName ?? 'User',
        'bookedByPhone': userData['phone'] ?? user.phoneNumber ?? '',
        'bookedByEmail': user.email ?? userData['email'] ?? '',
        'doctorId': widget.doctorId,
        'doctorName': widget.doctor['name'],
        'doctorImage': widget.doctor['imageUrl'],
        'departmentId': widget.doctor['departmentId'],
        'fee': widget.doctor['newPatientFee'] ?? widget.doctor['fee'] ?? 0,
        'newPatientFee': widget.doctor['newPatientFee'] ?? widget.doctor['fee'] ?? 0,
        'followupFee': widget.doctor['followupFee'] ?? 0,
        'consultationType': 'new_patient',
        'appointmentDate': selectedDate,
        'appointmentTime': selectedTime,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Appointment booked successfully")),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctor = widget.doctor;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final dates = List<String>.from(doctor['availableDates'] ?? []).where((d) {
      final parsedDate = _parseDoctorDate(d);
      if (parsedDate == null) return false;

      final appointmentDate = DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
      );

      return appointmentDate.isAfter(today);
    }).toList();

    final times = List<String>.from(doctor['availableTimes'] ?? []);
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("Appointment"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 55,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : bookAppointment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2CB1DE),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                "Book Consultation",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = MediaQuery.of(context).size.width >= 1024;

                if (!isDesktop) {
                  // 🔹 MOBILE SAME (no change)
                  return Column(
                    children: [
                      _doctorHeader(doctor),
                      const SizedBox(height: 20),
                      _buildTabs(),
                      _buildContent(doctor, dates, times),
                    ],
                  );
                }

                // 🔥 DESKTOP LAYOUT
                return Column(
                  children: [
                    _doctorHeader(doctor),
                    const SizedBox(height: 20),
                    _buildTabs(),
                    const SizedBox(height: 20),
                    if (!showAbout)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT SIDE
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _buildPatientSection(),
                                const SizedBox(height: 20),
                                _buildDateSection(dates),
                              ],
                            ),
                          ),

                          const SizedBox(width: 20),

                          // RIGHT SIDE
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                _buildTimeSection(times),
                                const SizedBox(height: 20),
                                _buildDesktopButton(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      _buildAbout(doctor),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => showAbout = false),
                child: Text(
                  "Book",
                  style: TextStyle(
                    color: !showAbout ? const Color(0xFF2CB1DE) : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => showAbout = true),
                child: Text(
                  "About",
                  style: TextStyle(
                    color: showAbout ? const Color(0xFF2CB1DE) : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: showAbout ? 1 : 0.5,
          color: const Color(0xFF2CB1DE),
          backgroundColor: Colors.grey,
        ),
      ],
    );
  }

  Widget _buildContent(
      Map<String, dynamic> doctor, List<String> dates, List<String> times) {
    if (showAbout) {
      return _buildAbout(doctor);
    } else {
      return Column(
        children: [
          const SizedBox(height: 12),
          _buildPatientSection(),
          const SizedBox(height: 20),
          _buildDateSection(dates),
          const SizedBox(height: 28),
          _buildTimeSection(times),
        ],
      );
    }
  }

  Widget _buildAbout(Map<String, dynamic> doctor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        doctor['about'] ?? 'No about information available.',
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
    );
  }

  Widget _buildPatientSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Appointment For",
              style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  value: true,
                  groupValue: isForSelf,
                  onChanged: (v) => setState(() => isForSelf = v!),
                  title: const Text("Myself"),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  value: false,
                  groupValue: isForSelf,
                  onChanged: (v) => setState(() => isForSelf = v!),
                  title: const Text("Family"),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (!isForSelf) ...[
            const SizedBox(height: 10),
            TextField(
                controller: patientNameController,
                decoration: const InputDecoration(
                    labelText: "Patient Name", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: patientPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: "Patient Phone", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: patientAgeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: "Age", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: patientGender,
              items: ["Male", "Female"]
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => patientGender = v!),
              decoration: const InputDecoration(
                  labelText: "Gender", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: patientRelation,
              items: [
                "Father",
                "Mother",
                "Brother",
                "Sister",
                "Child",
                "Wife",
                "Husband",
                "Other"
              ]
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => patientRelation = v!),
              decoration: const InputDecoration(
                  labelText: "Relation", border: OutlineInputBorder()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateSection(List<String> dates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Appointment Date",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          itemCount: dates.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.4,
          ),
          itemBuilder: (context, index) {
            final date = dates[index];
            final active = selectedDate == date;

            return GestureDetector(
              onTap: () => setState(() {
                selectedDate = date;
                selectedTime = null;
              }),
              child: Container(
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFA8E98E)
                      : const Color(0xFFD1ECF1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    date,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimeSection(List<String> times) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Appointment Time",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),

        if (selectedDate == null)
          const Text("Please select appointment date first")
        else
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('doctor_appointments')
                .where('appointmentDate', isEqualTo: selectedDate)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snap.hasError) {
                return Text(
                  "Slot loading error: ${snap.error}",
                  style: const TextStyle(color: Colors.red),
                );
              }

              final bookedTimes = <String>{};

              if (snap.hasData) {
                for (final doc in snap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;

                  final status = (data['status'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  final time = (data['appointmentTime'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  final apptDoctorId = (data['doctorId'] ?? '')
                      .toString()
                      .trim();

                  final apptDoctorName = (data['doctorName'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  final currentDoctorName = (widget.doctor['name'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  final sameDoctor =
                      apptDoctorId == widget.doctorId ||
                          apptDoctorName == currentDoctorName;

                  if (!sameDoctor) continue;

                  if ((status == 'pending' ||
                      status == 'confirmed' ||
                      status == 'completed' ||
                      status == 'done') &&
                      time.isNotEmpty) {
                    bookedTimes.add(time);
                  }
                }
              }

              final availableTimes = times.where((t) {
                final normalized = t.toString().trim().toLowerCase();
                return !bookedTimes.contains(normalized);
              }).toList();

              if (availableTimes.isEmpty) {
                return const Text(
                  "No time slot available for this date",
                  style: TextStyle(color: Colors.red),
                );
              }

              return GridView.builder(
                itemCount: availableTimes.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.8,
                ),
                itemBuilder: (context, index) {
                  final time = availableTimes[index];
                  final active = selectedTime == time;

                  return GestureDetector(
                    onTap: () => setState(() => selectedTime = time),
                    child: Container(
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFA8E98E)
                            : const Color(0xFFD1ECF1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          time,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildDesktopButton() {
    return SizedBox(
      height: 55,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : bookAppointment,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2CB1DE),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                "Book Consultation",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _doctorHeader(Map<String, dynamic> doctor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: doctor['imageUrl'] != null &&
                        doctor['imageUrl'].toString().isNotEmpty
                    ? NetworkImage(doctor['imageUrl'])
                    : null,
                child: doctor['imageUrl'] == null ||
                        doctor['imageUrl'].toString().isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(doctor['degree'] ?? ''),
                    Text(doctor['hospital'] ?? ''),
                    const SizedBox(height: 6),
                    Text(
                      "${doctor['consultationsDone'] ?? 0} Consultations Done",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 25),
          Row(
            children: [
              Expanded(
                child: Text(
                  "৳ New Patient\n${doctor['newPatientFee'] ?? doctor['fee'] ?? 0}\n"
                      "৳ Follow-up\n${doctor['followupFee'] ?? 0}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  "🕘\nExperience\n${doctor['experience'] ?? 0} yrs",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



