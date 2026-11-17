import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/user/customer_order_tracking_page.dart';
import '../pages/user/notifications_page.dart';
import '../utils/customer_notification_view.dart';

const Color _accent = Color(0xFF007185);
const Color _unreadDot = Color(0xFFFF9900);

/// Unread notifications of the signed-in user (badge count).
Stream<int> unreadNotificationCount(String uid) {
  return FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: uid)
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);
}

class NotificationActions {
  NotificationActions._();

  /// Product the shopper may open from a notification: it exists and is
  /// live (same rules as the storefront lists).
  static bool isProductAvailable(Map<String, dynamic>? p) {
    if (p == null) return false;
    if (p['isActive'] == false) return false;
    if (p['isVisible'] == false) return false;
    if (p['isPublished'] == false) return false;
    if ((p['hiddenReason'] ?? '').toString().trim().isNotEmpty) return false;
    final approval = (p['approvalStatus'] ?? '').toString().trim();
    if (approval.isNotEmpty && approval != 'approved') return false;
    return true;
  }

  static Future<void> markRead(DocumentReference ref) async {
    try {
      await ref.set({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Notification mark read failed: $e');
    }
  }

  /// Tap: mark it read (badge drops), then open its product or order.
  /// [context] must stay mounted after a popup that held the item closes.
  static Future<void> open(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? const <String, dynamic>{};
    if (data['isRead'] != true) {
      // Not awaited: the badge updates from the stream, navigation needn't wait.
      markRead(doc.reference);
    }

    final view = CustomerNotificationView.fromDoc(data);
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (view.productId.isNotEmpty) {
      Map<String, dynamic>? product;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('products')
            .doc(view.productId)
            .get();
        product = snap.exists ? snap.data() : null;
      } catch (e) {
        debugPrint('Notification product read failed: $e');
      }

      if (!isProductAvailable(product)) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('পণ্যটি এখন পাওয়া যাচ্ছে না')),
        );
        return;
      }
      navigator.pushNamed('/product/${view.productId}');
      return;
    }

    if (view.orderId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CustomerOrderTrackingPage(orderId: view.orderId),
        ),
      );
    }
  }
}

IconData notificationIcon(NotificationCategory c) {
  switch (c) {
    case NotificationCategory.order:
      return Icons.shopping_bag_rounded;
    case NotificationCategory.newProduct:
      return Icons.new_releases_rounded;
    case NotificationCategory.offer:
      return Icons.local_offer_rounded;
    case NotificationCategory.general:
      return Icons.notifications_rounded;
  }
}

Color notificationColor(NotificationCategory c) {
  switch (c) {
    case NotificationCategory.order:
      return Colors.blue;
    case NotificationCategory.newProduct:
      return Colors.green;
    case NotificationCategory.offer:
      return Colors.deepOrange;
    case NotificationCategory.general:
      return Colors.blueGrey;
  }
}

/// One notification row. Unread: tinted background, bold text, orange dot.
class NotificationListItem extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;
  final bool compact;
  final Widget? trailing;

  const NotificationListItem({
    super.key,
    required this.doc,
    required this.onTap,
    this.compact = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? const <String, dynamic>{};
    final view = CustomerNotificationView.fromDoc(data);
    final unread = data['isRead'] != true;
    final color = notificationColor(view.category);
    final created = data['createdAt'];
    final when = CustomerNotificationView.timeAgo(created is Timestamp ? created.toDate() : null);

    return Material(
      color: unread ? const Color(0xFFFFF7E8) : Colors.white,
      borderRadius: BorderRadius.circular(compact ? 10 : 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 12, compact ? 8 : 12, compact ? 4 : 6, compact ? 8 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: compact ? 16 : 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(notificationIcon(view.category), color: color, size: compact ? 17 : 21),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13.5 : 15,
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                        color: unread ? Colors.black : Colors.black87,
                      ),
                    ),
                    if (view.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        view.body,
                        maxLines: compact ? 2 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 12.5 : 13.5,
                          height: 1.35,
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          color: unread ? Colors.black87 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          view.label,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                        ),
                        if (when.isNotEmpty)
                          Text(when, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: compact ? 4 : 6, left: 6, right: 4),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: unread ? _unreadDot : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bell with unread badge for the mobile header. Signed-in users only.
class NotificationBellButton extends StatelessWidget {
  final Color iconColor;

  const NotificationBellButton({super.key, this.iconColor = Colors.black87});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) return const SizedBox.shrink();

        return StreamBuilder<int>(
          stream: unreadNotificationCount(user.uid),
          builder: (context, snap) {
            final count = snap.data ?? 0;
            return Semantics(
              button: true,
              label: count > 0 ? 'Notifications, $count unread' : 'Notifications',
              child: IconButton(
                tooltip: 'Notifications',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                ),
                icon: NotificationBadgeIcon(count: count, color: iconColor),
              ),
            );
          },
        );
      },
    );
  }
}

class NotificationBadgeIcon extends StatelessWidget {
  final int count;
  final Color color;

  const NotificationBadgeIcon({super.key, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_none_rounded, color: color, size: 25),
        if (count > 0)
          Positioned(
            right: -6,
            top: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }
}

/// Accent used by notification screens.
const Color notificationAccent = _accent;
