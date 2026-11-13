import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import 'admin_edit_order_page.dart';
import 'admin_lists_page.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  static const List<String> adminNotificationPermissions = [
    'notifications.view',
    'notifications.send',
    'notifications.manage',
    'notifications.delete',
    'notifications.read',
    'notifications.open_related',
  ];
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  bool permissionLoading = true;
  bool canView = false;
  bool canSend = false;
  bool canManage = false;
  bool canDelete = false;
  bool canOpenRelated = false;


  final searchController = TextEditingController();
  final titleController = TextEditingController();
  final bodyController = TextEditingController();

  String searchText = '';
  String typeFilter = 'all';
  String readFilter = 'all';

  bool sending = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<bool> _hasAnyPermission(List<String> permissions) async {
    for (final permission in permissions) {
      if (await authService.hasPermission(permission)) return true;
    }
    return false;
  }

  Future<void> _loadPermissions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => permissionLoading = false);
        return;
      }

      final userRef = db.collection('users').doc(user.uid);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? {};

      final role = _text(userData['role']);
      final roles = userData['roles'] is List
          ? List<String>.from((userData['roles'] as List).map((e) => e.toString()))
          : <String>[];

      final isSuperAdmin = role == 'superAdmin' || roles.contains('superAdmin');
      final isAdmin = role == 'admin' || roles.contains('admin');

      if (isSuperAdmin || isAdmin) {
        await userRef.set({
          'permissions': FieldValue.arrayUnion(adminNotificationPermissions),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        setState(() {
          canView = true;
          canSend = true;
          canManage = true;
          canDelete = true;
          canOpenRelated = true;
          permissionLoading = false;
        });
        return;
      }

      final view = await _hasAnyPermission(['notifications.view', 'notifications.send']);
      final send = await _hasAnyPermission(['notifications.send']);
      final manage = await _hasAnyPermission([
        'notifications.manage',
        'notifications.read',
        'notifications.send',
      ]);
      final delete = await _hasAnyPermission(['notifications.delete', 'notifications.manage']);
      final openRelated = await _hasAnyPermission([
        'notifications.open_related',
        'orders.view',
        'orders.edit',
        'lists.edit',
      ]);

      if (!mounted) return;
      setState(() {
        canView = view;
        canSend = send;
        canManage = manage;
        canDelete = delete;
        canOpenRelated = openRelated;
        permissionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e');
    }
  }

  bool _denyUnless(bool allowed, String message) {
    if (allowed) return false;
    _snack(message);
    return true;
  }

  @override
  void dispose() {
    searchController.dispose();
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      final h = d.hour > 12 ? d.hour - 12 : d.hour;
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} '
          '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
    }
    return 'N/A';
  }

  Color _typeColor(String type) {
    if (type.contains('order')) return Colors.blue;
    if (type.contains('list')) return Colors.redAccent;
    if (type.contains('vendor')) return Colors.orange;
    if (type.contains('broadcast')) return Colors.green;
    if (type.contains('admin')) return Colors.deepPurple;
    return Colors.blueGrey;
  }

  IconData _typeIcon(String type) {
    if (type.contains('order')) return Icons.shopping_bag_rounded;
    if (type.contains('list')) return Icons.medical_information_rounded;
    if (type.contains('vendor')) return Icons.storefront_rounded;
    if (type.contains('broadcast')) return Icons.campaign_rounded;
    if (type.contains('admin')) return Icons.admin_panel_settings_rounded;
    return Icons.notifications_rounded;
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final title = _text(data['title']).toLowerCase();
      final body = _text(data['body']).toLowerCase();
      final type = _text(data['type'], 'general');
      final isRead = data['isRead'] == true;

      if (typeFilter != 'all' && type != typeFilter) return false;
      if (readFilter == 'read' && !isRead) return false;
      if (readFilter == 'unread' && isRead) return false;

      if (s.isNotEmpty && !title.contains(s) && !body.contains(s) && !doc.id.toLowerCase().contains(s)) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _markRead(String id, bool read) async {
    if (_denyUnless(canManage, 'You do not have permission to update notifications.')) return;
    await db.collection('notifications').doc(id).set({
      'isRead': read,
      'readAt': read ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot> docs) async {
    if (_denyUnless(canManage, 'You do not have permission to update notifications.')) return;
    final batch = db.batch();

    for (final doc in docs) {
      batch.set(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    _snack('All visible notifications marked as read');
  }

  Future<void> _deleteNotification(String id) async {
    if (_denyUnless(canDelete, 'You do not have permission to delete notifications.')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete notification?'),
        content: const Text('This notification will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('notifications').doc(id).delete();
      _snack('Notification deleted');
    }
  }

  Future<void> _deleteAllRead() async {
    if (_denyUnless(canDelete, 'You do not have permission to delete notifications.')) return;
    final snap = await db.collection('notifications').where('isRead', isEqualTo: true).limit(300).get();

    if (snap.docs.isEmpty) {
      _snack('No read notifications found');
      return;
    }

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all read notifications?'),
        content: Text('${snap.docs.length} read notifications will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final batch = db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    _snack('Read notifications deleted');
  }

  Future<void> _sendBroadcastDialog() async {
    if (_denyUnless(canSend, 'You do not have permission to send broadcast notifications.')) return;
    titleController.clear();
    bodyController.clear();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> send() async {
            final title = titleController.text.trim();
            final body = bodyController.text.trim();

            if (title.isEmpty || body.isEmpty) {
              _snack('Title and message required');
              return;
            }

            setDialogState(() => sending = true);

            try {
              await NotificationService.sendToAll(title: title, body: body);
              if (!context.mounted) return;
              Navigator.pop(context);
              _snack('Broadcast notification created for all users');
            } catch (e) {
              _snack('Send failed: $e');
            } finally {
              setDialogState(() => sending = false);
            }
          }

          return AlertDialog(
            title: const Text('Send Broadcast Notification'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: sending ? null : send,
                icon: sending
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text(sending ? 'Sending...' : 'Send'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRelated(Map<String, dynamic> data) async {
    if (_denyUnless(canOpenRelated, 'You do not have permission to open related admin pages.')) return;
    final type = _text(data['type']);
    final payload = data['data'] is Map ? Map<String, dynamic>.from(data['data']) : <String, dynamic>{};

    final orderId = _text(payload['orderId'] ?? data['orderId']);
    final listId = _text(payload['listId'] ?? data['listId']);

    if (orderId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdminEditOrderPage(orderId: orderId)),
      );
      return;
    }

    if (listId.isNotEmpty || type.contains('list')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminListsPage()),
      );
      return;
    }

    _snack('No related page found');
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int unread = 0;
    int orders = 0; int lists = 0;
    int vendors = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final type = _text(data['type']);

      if (data['isRead'] != true) unread++;
      if (type.contains('order')) orders++;
      if (type.contains('list')) lists++;
      if (type.contains('vendor')) vendors++;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 2 : 1;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 1 ? 4.6 : 2.15,
          children: [
            _summaryCard('Unread', '$unread', Icons.mark_email_unread_rounded, Colors.red),
            _summaryCard('Orders', '$orders', Icons.shopping_bag_rounded, Colors.blue),
            _summaryCard('Lists', '$lists', Icons.medical_information_rounded, Colors.green),
            _summaryCard('Vendors', '$vendors', Icons.storefront_rounded, Colors.orange),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final small = c.maxWidth < 900;

            final search = TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search notification title, message, id...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final type = DropdownButtonFormField<String>(
              initialValue: typeFilter,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'admin_order', child: Text('Admin Order')),
                DropdownMenuItem(value: 'order', child: Text('Order')),
                DropdownMenuItem(value: 'list', child: Text('List')),
                DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                DropdownMenuItem(value: 'broadcast', child: Text('Broadcast')),
                DropdownMenuItem(value: 'admin_system_alert', child: Text('System Alert')),
                DropdownMenuItem(value: 'general', child: Text('General')),
              ],
              onChanged: (v) => setState(() => typeFilter = v ?? 'all'),
            );

            final read = DropdownButtonFormField<String>(
              initialValue: readFilter,
              decoration: const InputDecoration(
                labelText: 'Read',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'unread', child: Text('Unread')),
                DropdownMenuItem(value: 'read', child: Text('Read')),
              ],
              onChanged: (v) => setState(() => readFilter = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: type),
                      const SizedBox(width: 8),
                      Expanded(child: read),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: type),
                const SizedBox(width: 8),
                Expanded(child: read),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _notificationCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final title = _text(data['title'], 'Untitled Notification');
    final body = _text(data['body']);
    final type = _text(data['type'], 'general');
    final isRead = data['isRead'] == true;
    final color = _typeColor(type);

    return Card(
      elevation: 0,
      color: isRead ? Colors.white : const Color(0xFFFFFBEB),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isRead ? const Color(0xFFE5E7EB) : Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 850;

            final icon = CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(_typeIcon(type), color: color),
            );

            final info = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (!isRead) _chip('NEW', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(type, color),
                      _chip(_dateText(data['createdAt']), Colors.blueGrey),
                      _chip(isRead ? 'Read' : 'Unread', isRead ? Colors.green : Colors.orange),
                    ],
                  ),
                ],
              ),
            );

            final actions = Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: canOpenRelated ? () => _openRelated(data) : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  onPressed: canManage ? () => _markRead(doc.id, !isRead) : null,
                  icon: Icon(isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded, size: 18),
                  label: Text(isRead ? 'Unread' : 'Read'),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: canDelete ? () => _deleteNotification(doc.id) : null,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [icon, const SizedBox(width: 12), info]),
                  const Divider(height: 22),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(width: 12),
                info,
                const SizedBox(width: 12),
                SizedBox(width: 310, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _notificationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('notifications').orderBy('createdAt', descending: true).limit(500).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Notifications load failed: ${snap.error}'));
        }

        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final allDocs = snap.data!.docs;
        final docs = _filterDocs(allDocs);

        if (allDocs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('No notifications found'),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryGrid(allDocs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Notifications (${docs.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: canManage && docs.isNotEmpty ? () => _markAllRead(docs) : null,
                  icon: const Icon(Icons.mark_email_read_rounded),
                  label: const Text('Mark visible read'),
                ),
                TextButton.icon(
                  onPressed: canDelete ? _deleteAllRead : null,
                  icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                  label: const Text('Delete read', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching notifications')),
                ),
              )
            else
              ...docs.map(_notificationCard),
          ],
        );
      },
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }


  Widget _permissionDenied() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
        child: Container(
          width: 430,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 46, color: Colors.red),
              SizedBox(height: 12),
              Text(
                'Notification access denied',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'You need notifications.view or notifications.send permission to open this page.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canView) return _permissionDenied();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Admin Notifications Pro',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Open Marketing Center from Admin sidebar')),
                  );
                },
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('Marketing Center'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: canSend ? _sendBroadcastDialog : null,
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('Send Broadcast'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!canManage || !canDelete || !canSend)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
              ),
              child: Text(
                'Limited access: some notification actions are disabled based on your permissions.',
                style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 6),
          _notificationList(),
        ],
      ),
    );
  }
}
