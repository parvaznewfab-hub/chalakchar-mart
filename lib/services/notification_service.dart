import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Outcome of asking the visitor for notification permission.
enum NotificationPermissionResult { granted, denied, unsupported }

class NotificationService {
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // getToken() talks to FCM over the network; never let it hang a caller.
  static const Duration _tokenTimeout = Duration(seconds: 10);

  /// Startup hook. Call it after the first frame, never await it before
  /// runApp(), and it never throws.
  ///
  /// On web it only registers listeners and never asks for permission: the
  /// browser prompt is shown only after a user action (login, placing an
  /// order, the "জানিয়ে দিন" button), via [requestPermission].
  /// On Android/iOS it keeps the old ask-at-startup flow, without awaiting
  /// the system dialog.
  static Future<void> init() async {
    try {
      if (!await _messaging.isSupported()) return;
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground notification: ${message.notification?.title}');
      });
      if (!kIsWeb) unawaited(requestPermission());
    } catch (e) {
      debugPrint('Notification init skipped: $e');
    }
  }

  /// Shows the permission prompt. On web, call only from a user action.
  /// The returned future may stay pending while the prompt is open, so
  /// callers must not block navigation or rendering on it. Never throws.
  static Future<NotificationPermissionResult> requestPermission() async {
    try {
      // false on browsers without push support, e.g. iOS Safari outside an
      // installed PWA.
      if (!await _messaging.isSupported()) {
        return NotificationPermissionResult.unsupported;
      }
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final status = settings.authorizationStatus;
      return status == AuthorizationStatus.authorized ||
              status == AuthorizationStatus.provisional
          ? NotificationPermissionResult.granted
          : NotificationPermissionResult.denied;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return NotificationPermissionResult.unsupported;
    }
  }

  /// Asks for permission after a user action and, if granted and signed in,
  /// saves the FCM token. Safe to call without awaiting. Never throws.
  static Future<NotificationPermissionResult> requestAndSaveToken(String? userId) async {
    final result = await requestPermission();
    if (result == NotificationPermissionResult.granted && userId != null && userId.isNotEmpty) {
      await saveToken(userId);
    }
    return result;
  }

  /// Saves this device's FCM token for [userId]. Never shows a prompt: on
  /// web, getToken() would show one by itself, so it is only called once
  /// permission is already granted. Never throws.
  static Future<void> saveToken(String userId) async {
    try {
      if (!await _messaging.isSupported()) return;
      if (kIsWeb) {
        final settings = await _messaging.getNotificationSettings();
        if (settings.authorizationStatus != AuthorizationStatus.authorized) return;
      }
      final token = await _messaging.getToken().timeout(_tokenTimeout);
      if (token == null) return;
      await _db.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'lastTokenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FCM token save skipped: $e');
    }
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



