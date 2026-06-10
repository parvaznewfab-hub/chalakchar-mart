import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final user = FirebaseAuth.instance.currentUser;
  final name = TextEditingController();
  final age = TextEditingController();
  final address = TextEditingController();
  final phone = TextEditingController();
  final division = TextEditingController();
  final district = TextEditingController();
  final upazila = TextEditingController();

  String gender = "Male";
  final List<String> genderOptions = ["Male", "Female"];
  bool isPhoneEditable = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    // 🔥 Firebase Auth থেকে ফোন নাম্বার চেক করা
    if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
      phone.text = user!.phoneNumber!;
      isPhoneEditable = false; // ফোন দিয়ে লগইন করলে এডিট করা যাবে না
    }

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user!.uid)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data();
      name.text = data?['name'] ?? '';
      age.text = data?['age'] ?? '';
      address.text = data?['address'] ?? '';
      division.text = data?['division'] ?? '';
      district.text = data?['district'] ?? '';
      upazila.text = data?['upazila'] ?? '';
      
      // যদি Firestore-এ ফোন নাম্বার থাকে এবং Auth-এ না থাকে (যেমন ইমেইল লগইন)
      if (phone.text.isEmpty && data?['phone'] != null) {
        phone.text = data?['phone'];
      }
      
      String? loadedGender = data?['gender'];
      if (loadedGender != null && genderOptions.contains(loadedGender)) {
        gender = loadedGender;
      }
      setState(() {});
    }
  }

  Future<void> save() async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login required")),
      );
      return;
    }

    if (name.text.trim().isEmpty ||
        age.text.trim().isEmpty ||
        phone.text.trim().isEmpty ||
        division.text.trim().isEmpty ||
        district.text.trim().isEmpty ||
        upazila.text.trim().isEmpty ||
        address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all profile fields")),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
        "uid": user!.uid,
        "email": user!.email ?? "",
        "name": name.text.trim(),
        "age": age.text.trim(),
        "gender": gender,
        "address": address.text.trim(),
        "phone": phone.text.trim(),
        "division": division.text.trim(),
        "district": district.text.trim(),
        "upazila": upazila.text.trim(),
        "profileCompleted": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved successfully")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Profile save failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"), 
        backgroundColor: const Color(0xFF32A8C7),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildTextField(name, "User Name", Icons.person),
            const SizedBox(height: 15),
            _buildTextField(phone, "Phone Number", Icons.phone, 
                keyboardType: TextInputType.phone, 
                enabled: isPhoneEditable),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildTextField(age, "Age", Icons.cake, keyboardType: TextInputType.number)),
                const SizedBox(width: 15),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: gender,
                    items: genderOptions
                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) => setState(() => gender = val!),
                    decoration: InputDecoration(
                      labelText: "Gender",
                      prefixIcon: const Icon(Icons.people),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildTextField(division, "Division", Icons.map),
            const SizedBox(height: 15),
            _buildTextField(district, "District", Icons.location_city),
            const SizedBox(height: 15),
            _buildTextField(upazila, "Upazila", Icons.explore),
            const SizedBox(height: 15),
            _buildTextField(address, "Detailed Address (Village/Road/House)", Icons.location_on, maxLines: 2),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF32A8C7),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text("Save Changes", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, 
      {TextInputType keyboardType = TextInputType.text, bool enabled = true, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: !enabled,
        fillColor: enabled ? null : Colors.grey[100],
      ),
    );
  }
}



