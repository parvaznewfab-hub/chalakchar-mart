import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      final h = d.hour > 12 ? d.hour - 12 : d.hour;
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
          '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
    }
    return '';
  }

  Color _typeColor(String type) {
    if (type.contains('order')) return Colors.blue;
    if (type.contains('broadcast')) return Colors.green;
    if (type.contains('vendor')) return Colors.orange;
    return Colors.blueGrey;
  }

  IconData _typeIcon(String type) {
    if (type.contains('order')) return Icons.shopping_bag_rounded;
    if (type.contains('broadcast')) return Icons.campaign_rounded;
    if (type.contains('vendor')) return Icons.storefront_rounded;
    return Icons.notifications_rounded;
  }

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
      const SnackBar(content: Text('All notifications marked as read')),
    );
  }

  Future<void> _deleteNotification(String id) async {
    await db.collection('notifications').doc(id).delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification deleted')),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _card(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = _text(data['title'], 'Notification');
    final body = _text(data['body']);
    final type = _text(data['type'], 'general');
    final isRead = data['isRead'] == true;
    final color = _typeColor(type);

    return Card(
      elevation: 0,
      color: isRead ? Colors.white : const Color(0xFFFFFBEB),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRead ? const Color(0xFFE5E7EB) : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_typeIcon(type), color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (body.isNotEmpty)
                Text(
                  body,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(type, color),
                  if (_dateText(data['createdAt']).isNotEmpty)
                    _chip(_dateText(data['createdAt']), Colors.blueGrey),
                  _chip(isRead ? 'Read' : 'Unread', isRead ? Colors.green : Colors.orange),
                ],
              ),
            ],
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: isRead ? 'Mark unread' : 'Mark read',
              onPressed: () => _markRead(doc.id, !isRead),
              icon: Icon(
                isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded,
                color: const Color(0xFF007185),
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _deleteNotification(doc.id),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            ),
          ],
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
        title: const Text('My Notifications'),
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

              return TextButton.icon(
                onPressed: unreadDocs.isEmpty ? null : () => _markAllRead(unreadDocs),
                icon: const Icon(Icons.mark_email_read_rounded),
                label: const Text('Mark all read'),
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
            return Center(child: Text('Notifications load failed: ${snap.error}'));
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
                'No notifications found',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(14),
            children: docs.map(_card).toList(),
          );
        },
      ),
    );
  }
}