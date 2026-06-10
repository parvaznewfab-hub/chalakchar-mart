import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReferralService {
  static final db = FirebaseFirestore.instance;
  static final auth = FirebaseAuth.instance;

  static Stream<DocumentSnapshot> getUserData(String uid) {
    return db.collection('users').doc(uid).snapshots();
  }

  static Future<String> getOrCreateReferralCode(String uid) async {
    final doc = await db.collection('users').doc(uid).get();

    if (doc.exists && doc.data()!.containsKey('refCode')) {
      return doc.data()!['refCode'];
    }

    String newCode = uid.substring(0, 6).toUpperCase();

    await db.collection('users').doc(uid).set({
      'refCode': newCode,
    }, SetOptions(merge: true));

    return newCode;
  }

  static Future<String> applyReferral(String code) async {
    final currentUser = auth.currentUser;
    if (currentUser == null) return "User not logged in";

    final userRef = db.collection('users').doc(currentUser.uid);
    final userDoc = await userRef.get();

    if (userDoc.exists && userDoc.data()?.containsKey('referredBy') == true) {
      return "You have already applied a referral code.";
    }

    final refUserQuery = await db
        .collection('users')
        .where('refCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();

    if (refUserQuery.docs.isEmpty) {
      return "Invalid Referral Code";
    }

    final referrerDoc = refUserQuery.docs.first;

    if (referrerDoc.id == currentUser.uid) {
      return "You cannot use your own code.";
    }

    final appSettings =
    await db.collection('settings').doc('app').get();

    final settings = appSettings.data() ?? {};

    final num referrerReward =
        settings['referralReward'] ?? 25;

    final num refereeReward =
        settings['refereeReward'] ?? 25;

    final batch = db.batch();

    batch.update(db.collection('users').doc(referrerDoc.id), {
      'points': FieldValue.increment(referrerReward),
      'totalEarnings': FieldValue.increment(referrerReward),
      'referralCount': FieldValue.increment(1),
    });

    batch.update(userRef, {
      'points': FieldValue.increment(refereeReward),
      'referredBy': referrerDoc.id,
    });

    batch.set(db.collection('referrals').doc(), {
      'referrerId': referrerDoc.id,
      'refereeId': currentUser.uid,
      'referrerReward': referrerReward,
      'refereeReward': refereeReward,
      'status': 'Approved',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return "Success! Reward added to your balance.";
  }

  static Stream<QuerySnapshot> getReferralHistory(String uid) {
    return db
        .collection('referrals')
        .where('referrerId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Future<void> updateReferralSettings(
      int referrer,
      int referee,
      bool auto,
      String videoUrl,
      ) async {
    await db.collection('settings').doc('app').set({
      'referralReward': referrer,
      'refereeReward': referee,
      'referralYoutubeLink': videoUrl,
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot> getReferralSettings() {
    return db.collection('settings').doc('app').snapshots();
  }
}


