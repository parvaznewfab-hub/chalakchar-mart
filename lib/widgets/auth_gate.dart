import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../pages/admin/admin_dashboard_page.dart';
import '../pages/main_navigation_page.dart';
import '../services/notification_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {

        // 🌐 WEB → always home (no login required)
        if (kIsWeb) {
          return const MainNavigation(role: 'user');
        }

        // 📱 MOBILE APP → login required
        if (authSnap.hasData) {
          NotificationService.saveToken(authSnap.data!.uid);

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(authSnap.data!.uid)
                .get(),
            builder: (context, roleSnap) {
              if (roleSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator(color: Color(0xFF32A8C7))),
                );
              }
              
              if (roleSnap.hasData && roleSnap.data!.exists) {
                final role = (roleSnap.data!.data() as Map<String, dynamic>?)?['role'] ?? 'user';

                if (role == 'admin') return const AdminDashboard();
              }
              return const MainNavigation(role: 'user'); // logged in user
            },
          );
        }

        // ❌ Not logged in → mobile app e login page
        return const MainNavigation(role: 'user');
      },
    );
  }
}



