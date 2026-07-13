import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_page.dart';

class MyAddressPage extends StatefulWidget {
  const MyAddressPage({super.key});

  @override
  State<MyAddressPage> createState() => _MyAddressPageState();
}

class _MyAddressPageState extends State<MyAddressPage> {
  final user = FirebaseAuth.instance.currentUser;
  String? selectedAddressId;

  bool _hasValue(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "My Address",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF32A8C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showAddressDialog(),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "ADD ADDRESS",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.touch_app, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: RadioGroup<String>(
              groupValue: selectedAddressId,
              onChanged: (String? v) {
                setState(() {
                  selectedAddressId = v;
                });
              },
              child: ListView(
                children: [
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;

                        final profileAddress = (data['address'] ?? '').toString().trim();
                        final profilePhone = (data['phone'] ?? '').toString().trim();
                        final profileDivision = (data['division'] ?? '').toString().trim();
                        final profileDistrict = (data['district'] ?? '').toString().trim();
                        final profileUpazila = (data['upazila'] ?? '').toString().trim();

                        final isProfileAddressComplete = profileAddress.isNotEmpty &&
                            profilePhone.isNotEmpty &&
                            profileDivision.isNotEmpty &&
                            profileDistrict.isNotEmpty &&
                            profileUpazila.isNotEmpty;

                        return InkWell(
                          onTap: isProfileAddressComplete
                              ? null
                              : () async {
                            final updated = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EditProfilePage()),
                            );

                            if (updated == true && mounted) {
                              setState(() {});
                            }
                          },
                          child: RadioListTile<String>(
                            value: "profile_default",
                            activeColor: const Color(0xFF32A8C7),
                            title: Text(
                              "Default (from Profile)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isProfileAddressComplete ? Colors.black : Colors.grey,
                              ),
                            ),
                            subtitle: Text(
                              isProfileAddressComplete
                                  ? "$profileAddress\n$profilePhone\n$profileDivision, $profileDistrict, $profileUpazila"
                                  : "Profile address incomplete. Tap here to complete profile.",
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                  const Divider(),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user?.uid)
                        .collection('addresses')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();

                      final docs = snapshot.data!.docs;

                      return Column(
                        children: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;

                          final addressComplete = _hasValue(data['address']) &&
                              _hasValue(data['phone']) &&
                              _hasValue(data['division']) &&
                              _hasValue(data['district']) &&
                              _hasValue(data['upazila']);

                          return RadioListTile<String>(
                            value: doc.id,
                            activeColor: const Color(0xFF32A8C7),
                            title: Row(
                              children: [
                                Text(
                                  data['label'] ?? 'Home',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _showAddressDialog(id: doc.id, data: data),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _deleteAddress(doc.id),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              addressComplete
                                  ? "${data['address']}\n${data['phone']}\n${data['division']}, ${data['district']}, ${data['upazila']}"
                                  : "Address incomplete. Please edit and complete it.",
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: selectedAddressId == null
                ? null
                : () => Navigator.pop(context, selectedAddressId),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF32A8C7),
              disabledBackgroundColor: Colors.grey.shade300,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              "APPLY",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddressDialog({String? id, Map<String, dynamic>? data}) {
    final label = TextEditingController(text: data?['label'] ?? '');
    final addr = TextEditingController(text: data?['address'] ?? '');
    final phone = TextEditingController(text: data?['phone'] ?? '');
    final div = TextEditingController(text: data?['division'] ?? '');
    final dist = TextEditingController(text: data?['district'] ?? '');
    final upa = TextEditingController(text: data?['upazila'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF3EDF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          id == null ? "Add Address" : "Edit Address",
          style: const TextStyle(fontSize: 24),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(label, "Label (Home/Work)"),
              _buildField(addr, "Full Address"),
              _buildField(phone, "Phone Number", keyboardType: TextInputType.phone),
              _buildField(div, "Division"),
              _buildField(dist, "District"),
              _buildField(upa, "Upazila"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Color(0xFF6750A4))),
          ),
          ElevatedButton(
            onPressed: () async {
              if (addr.text.trim().isEmpty ||
                  phone.text.trim().isEmpty ||
                  div.text.trim().isEmpty ||
                  dist.text.trim().isEmpty ||
                  upa.text.trim().isEmpty) {
                _showSnack("Please fill address, phone, division, district and upazila");
                return;
              }

              final map = {
                'label': label.text.trim().isEmpty ? 'Home' : label.text.trim(),
                'address': addr.text.trim(),
                'phone': phone.text.trim(),
                'division': div.text.trim(),
                'district': dist.text.trim(),
                'upazila': upa.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (id == null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .collection('addresses')
                    .add(map);
              } else {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .collection('addresses')
                    .doc(id)
                    .update(map);
              }

              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF6750A4),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
      TextEditingController c,
      String l, {
        TextInputType? keyboardType,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: l,
          labelStyle: const TextStyle(color: Color(0xFF49454F)),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  void _deleteAddress(String id) {
    FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('addresses')
        .doc(id)
        .delete();

    if (selectedAddressId == id) {
      setState(() => selectedAddressId = null);
    }
  }
}