import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/customer_notifications.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  Future<void> _markRead(String id, bool read) async {
    await db.collection('notifications').doc(id).set({
      'isRead': read,
      'readAt': read ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final batch = db.batch();

    for (final doc in docs) {
      batch.set(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('সব নোটিফিকেশন পড়া হয়েছে')),
    );
  }

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final isRead = doc.data()['isRead'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead ? const Color(0xFFE5E7EB) : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: NotificationListItem(
        doc: doc,
        onTap: () => NotificationActions.open(context, doc),
        trailing: IconButton(
          tooltip: isRead ? 'না-পড়া করুন' : 'পড়া হয়েছে',
          onPressed: () => _markRead(doc.id, !isRead),
          icon: Icon(
            isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded,
            color: notificationAccent,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view notifications')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('নোটিফিকেশন'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('notifications')
                .where('userId', isEqualTo: user.uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snap) {
              final unreadDocs = snap.data?.docs ?? [];

              final onPressed = unreadDocs.isEmpty ? null : () => _markAllRead(unreadDocs);
              // Phones: icon only, so the title keeps its room.
              if (MediaQuery.of(context).size.width < 480) {
                return IconButton(
                  tooltip: 'সব পড়া হয়েছে',
                  onPressed: onPressed,
                  icon: const Icon(Icons.done_all_rounded),
                );
              }
              return TextButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('সব পড়া হয়েছে'),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('নোটিফিকেশন লোড করা যায়নি। পরে আবার চেষ্টা করুন।'));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = [...snap.data!.docs];

          docs.sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];

            if (ta is! Timestamp || tb is! Timestamp) return 0;

            return tb.compareTo(ta);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'এখনও কোনো নোটিফিকেশন নেই',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: docs.map(_card).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}