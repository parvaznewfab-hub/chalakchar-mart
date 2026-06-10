import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> init() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground notification: ${message.notification?.title}');
    });
  }

  static Future<void> saveToken(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    await _db.collection('users').doc(userId).set({
      'fcmToken': token,
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastTokenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    await _db.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> sendToVendor({
    required String vendorId,
    required String title,
    required String body,
    String type = 'vendor',
    Map<String, dynamic>? data,
  }) async {
    await _db.collection('vendor_notifications').add({
      'vendorId': vendorId,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> sendToAdmins({
    required String title,
    required String body,
    String type = 'admin',
    Map<String, dynamic>? data,
  }) async {
    final admins = await _db.collection('users').where('role', whereIn: ['admin', 'superAdmin']).get();
    final batch = _db.batch();
    for (final admin in admins.docs) {
      batch.set(_db.collection('notifications').doc(), {
        'userId': admin.id,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Future<void> sendToAll({required String title, required String body}) async {
    final users = await _db.collection('users').get();
    final batch = _db.batch();
    for (final user in users.docs) {
      batch.set(_db.collection('notifications').doc(), {
        'userId': user.id,
        'title': title,
        'body': body,
        'type': 'broadcast',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Future<void> createOrderNotifications({
    required String orderId,
    required String userId,
    required List items,
  }) async {
    await sendNotification(
      userId: userId,
      title: 'Order placed',
      body: 'Your order #${orderId.substring(0, 8)} has been placed.',
      type: 'order',
      data: {'orderId': orderId},
    );
    await sendToAdmins(
      title: 'New order received',
      body: 'Order #${orderId.substring(0, 8)} is waiting for review.',
      type: 'admin_order',
      data: {'orderId': orderId},
    );

    final vendorIds = items
        .map((e) => e is Map ? e['vendorId']?.toString() : null)
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toSet();
    for (final vendorId in vendorIds) {
      await sendToVendor(
        vendorId: vendorId,
        title: 'New vendor order',
        body: 'You have new items in order #${orderId.substring(0, 8)}.',
        type: 'vendor_order',
        data: {'orderId': orderId},
      );
    }
  }
}



