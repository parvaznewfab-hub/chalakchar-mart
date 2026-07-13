import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ReferralService {
  static final db = FirebaseFirestore.instance;
  static final auth = FirebaseAuth.instance;

  static const String _applyReferralRewardUrl =
      'https://asia-south1-chalakchar-mart.cloudfunctions.net/applyReferralReward';

  static Stream<DocumentSnapshot> getUserData(String uid) {
    return db.collection('users').doc(uid).snapshots();
  }

  static Future<String> getOrCreateReferralCode(String uid) async {
    final doc = await db.collection('users').doc(uid).get();
    final data = doc.data();

    final existingCode = (data?['refCode'] ?? '').toString().trim();

    if (doc.exists && existingCode.isNotEmpty) {
      return existingCode;
    }

    final cleanUid =
    uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

    final newCode = cleanUid.length >= 6
        ? cleanUid.substring(0, 6)
        : cleanUid.padRight(6, 'X');

    await db.collection('users').doc(uid).set({
      'refCode': newCode,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return newCode;
  }

  static String normalizeCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static Future<String> applyReferral(String code) async {
    final currentUser = auth.currentUser;
    if (currentUser == null) return 'User not logged in';

    final cleanCode = normalizeCode(code);
    if (cleanCode.isEmpty) return 'Please enter a referral code.';

    try {
      final idToken = await currentUser.getIdToken(true);

      final response = await http
          .post(
        Uri.parse(_applyReferralRewardUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'code': cleanCode}),
      )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> payload = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {
        payload = {};
      }

      final message = (payload['message'] ?? '').toString().trim();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return message.isNotEmpty
            ? message
            : 'Referral applied successfully.';
      }

      return message.isNotEmpty
          ? message
          : 'Referral could not be applied now.';
    } catch (e) {
      return 'Referral could not be applied now.';
    }
  }

  static Stream<QuerySnapshot> getReferralHistory(String uid) {
    return db
        .collection('referrals')
        .where('referrerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> updateReferralSettings(
      int referrer,
      int referee,
      bool auto,
      String videoUrl,
      ) async {
    await db.collection('settings').doc('referral').set({
      'referralEnabled': true,
      'referrerReward': referrer,
      'refereeReward': referee,
      'autoApprove': auto,
      'referralYoutubeLink': videoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot> getReferralSettings() {
    return db.collection('settings').doc('referral').snapshots();
  }
}
