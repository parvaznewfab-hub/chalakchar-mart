import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'doctors_list_page.dart';

class DoctorDepartmentsPage extends StatelessWidget {
  const DoctorDepartmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    const Color primaryColor = Color(0xFF32A8C7);
    double screenWidth = MediaQuery.of(context).size.width;
    bool isDesktop = screenWidth >= 1024;

    return Scaffold(
      backgroundColor: const Color(0xffF4F7F8),
      appBar: AppBar(
        title: const Text(
          "Select a Department",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('doctor_departments')
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: primaryColor));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        "No departments available",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              final departments = snapshot.data!.docs;

              return GridView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 60 : 16, 
                  vertical: 30
                ),
                itemCount: departments.length,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220, // ডেক্সটপে কার্ডের সর্বোচ্চ প্রস্থ নির্ধারণ
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, index) {
                  final doc = departments[index];
                  final data = doc.data() as Map<String, dynamic>;

                  return _buildDepartmentCard(
                    context,
                    id: doc.id,
                    name: data['name'] ?? '',
                    banglaName: data['bangla'] ?? '',
                    imageUrl: data['imageUrl'] ?? '',
                    primaryColor: primaryColor,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentCard(
    BuildContext context, {
    required String id,
    required String name,
        required String banglaName,
        required String imageUrl,
        required Color primaryColor,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DoctorsListPage(
              departmentId: id,
              departmentName: name,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: primaryColor.withValues(alpha: 0.08),
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? Icon(
                Icons.medical_services_rounded,
                color: primaryColor,
                size: 30,
              )
                  : null,
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            if (banglaName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(
                  banglaName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



