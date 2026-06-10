import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:http/http.dart' as http;

import '../../services/notification_service.dart';
import 'admin_edit_order_page.dart';

class AdminListsPage extends StatefulWidget {
  const AdminListsPage({super.key});

  @override
  State<AdminListsPage> createState() => _AdminListsPageState();
}

class _AdminListsPageState extends State<AdminListsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String searchText = '';
  String statusFilter = 'all';

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Accepted':
        return Colors.green;
      case 'Rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    }
    return 'N/A';
  }

  Future<Map<String, dynamic>> _userInfo(String userId) async {
    if (userId.isEmpty) return {};
    final doc = await db.collection('users').doc(userId).get();
    return doc.data() ?? {};
  }

  Future<String?> _findOrderIdBylist(String listId) async {
    final snap = await db
        .collection('orders')
        .where('listId', isEqualTo: listId)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> _updateStatus(String id, String status, Map<String, dynamic> presData) async {
    try {
      final userId = _text(presData['userId']);

      if (status == 'Accepted') {
        final existingOrderId = await _findOrderIdBylist(id);

        if (existingOrderId != null) {
          final orderDoc = await db.collection('orders').doc(existingOrderId).get();
          final order = orderDoc.data() ?? {};

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminEditOrderPage(orderId: existingOrderId),
              ),
            );
          }

          if (order['isEdited'] == true && order['isDraft'] != true) {
            _snack('Order already created and confirmed');
          }

          return;
        }
      }

      await db.collection('lists').doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (status == 'Accepted') {
        await NotificationService.sendNotification(
          userId: userId,
          title: 'List Accepted ✅',
          body: 'Your list has been reviewed. Please check and confirm the order details.',
          type: 'list',
          data: {'listId': id},
        );

        final userDoc = await db.collection('users').doc(userId).get();
        final userData = userDoc.data() ?? {};

        final address = {
          'name': _text(userData['name']),
          'phone': _text(userData['phone']),
          'address': _text(userData['address']),
          'division': _text(userData['division']),
          'district': _text(userData['district']),
          'upazila': _text(userData['upazila']),
          'label': 'List',
        };

        final docRef = await db.collection('orders').add({
          'userId': userId,
          'userName': _text(userData['name'], 'User'),
          'userEmail': _text(userData['email']),
          'phone': _text(userData['phone']),
          'status': 'draft',
          'isDraft': true,
          'isEdited': false,
          'total': 0,
          'totalMrp': 0,
          'discount': 0,
          'deliveryCharge': 0,
          'grandTotal': 0,
          'items': [],
          'address': address,
          'source': 'list',
          'listId': id,
          'listImageUrl': _text(presData['imageUrl']),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await db.collection('lists').doc(id).update({
          'orderCreated': true,
          'orderId': docRef.id,
        });

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminEditOrderPage(orderId: docRef.id),
            ),
          );
        }
      } else if (status == 'Rejected') {
        await NotificationService.sendNotification(
          userId: userId,
          title: 'List Rejected ❌',
          body: 'Your list was not accepted. Please upload a clearer image or contact support.',
          type: 'list',
          data: {'listId': id},
        );
      }

      _snack('List $status successfully');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _showFullImage(String url) async {
    if (url.isEmpty) {
      _snack('Image not found');
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadImage(String url, String listId) async {
    if (url.isEmpty) {
      _snack('Image not found');
      return;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception('Download failed');

      final bytes = response.bodyBytes;
      final fileName = 'list_${listId.substring(0, 8)}.jpg';

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'image/jpeg');
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: blobUrl)
          ..download = fileName
          ..click();
        html.Url.revokeObjectUrl(blobUrl);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      _snack('Download failed: $e');
    }
  }

  Future<void> _openOrder(String listId) async {
    final orderId = await _findOrderIdBylist(listId);

    if (orderId == null) {
      _snack('Order not created yet');
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEditOrderPage(orderId: orderId),
      ),
    );
  }

  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty || phone == 'No Phone') {
      _snack('Phone number not found');
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsAppCustomer(String phone, String name) async {
    String clean = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (clean.isEmpty) {
      _snack('Phone number not found');
      return;
    }

    if (clean.startsWith('0')) {
      clean = '88$clean';
    }

    final msg = Uri.encodeComponent(
      'Hello $name, we received your list. ChalakChar Mart team will review it shortly.',
    );

    final uri = Uri.parse('https://wa.me/$clean?text=$msg');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs, Map<String, Map<String, dynamic>> userMap) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'pending');
      final userId = _text(data['userId']);
      final user = userMap[userId] ?? {};

      if (statusFilter != 'all' && status != statusFilter) return false;

      if (s.isEmpty) return true;

      final name = _text(user['name']).toLowerCase();
      final phone = _text(user['phone']).toLowerCase();
      final email = _text(user['email']).toLowerCase();
      final id = doc.id.toLowerCase();

      return name.contains(s) || phone.contains(s) || email.contains(s) || id.contains(s);
    }).toList();
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int pending = 0;
    int accepted = 0;
    int rejected = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'pending');

      if (status == 'Accepted') {
        accepted++;
      } else if (status == 'Rejected') {
        rejected++;
      } else {
        pending++;
      }
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
          childAspectRatio: count == 1 ? 4.5 : 2.1,
          children: [
            _summaryCard('Total', '${docs.length}', Icons.assignment_rounded, Colors.blue),
            _summaryCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.orange),
            _summaryCard('Accepted', '$accepted', Icons.check_circle_rounded, Colors.green),
            _summaryCard('Rejected', '$rejected', Icons.cancel_rounded, Colors.red),
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
            final small = c.maxWidth < 760;

            final search = TextField(
              decoration: const InputDecoration(
                hintText: 'Search customer, phone, email, list id...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final status = DropdownButtonFormField<String>(
              initialValue: statusFilter,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Accepted', child: Text('Accepted')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  status,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: status),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: onTap == null ? Colors.grey : color),
      label: Text(label, style: TextStyle(color: onTap == null ? Colors.grey : color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: (onTap == null ? Colors.grey : color).withValues(alpha: 0.35)),
      ),
    );
  }

  Widget _listImage(String url, String id) {
    if (url.isEmpty) {
      return Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 40)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Image.network(
            url,
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 240,
              color: Colors.grey.shade100,
              child: const Center(child: Icon(Icons.broken_image)),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                _imageAction(Icons.fullscreen_rounded, () => _showFullImage(url)),
                const SizedBox(width: 8),
                _imageAction(Icons.download_rounded, () => _downloadImage(url, id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageAction(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _listCard({
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> user,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final id = doc.id;
    final status = _text(data['status'], 'pending');
    final imageUrl = _text(data['imageUrl']);

    final name = _text(user['name'], 'Unknown User');
    final phone = _text(user['phone'], 'No Phone');
    final email = _text(user['email']);
    final address = _text(user['address'], '-');
    final area = '${_text(user['division'], '-')} → ${_text(user['district'], '-')} → ${_text(user['upazila'], '-')}';

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;

            final header = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFF1592B3),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    _statusChip(status),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _info(Icons.call, phone),
                    if (email.isNotEmpty) _info(Icons.email_outlined, email),
                    _info(Icons.location_on_outlined, address),
                    _info(Icons.map_outlined, area),
                    _info(Icons.calendar_today_rounded, 'Uploaded: ${_dateText(data['createdAt'])}'),
                    if (data['updatedAt'] != null) _info(Icons.update_rounded, 'Updated: ${_dateText(data['updatedAt'])}'),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _button(
                      icon: Icons.call_rounded,
                      label: 'Call',
                      color: Colors.indigo,
                      onTap: () => _callCustomer(phone),
                    ),
                    _button(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      color: Colors.teal,
                      onTap: () => _whatsAppCustomer(phone, name),
                    ),
                    _button(
                      icon: Icons.open_in_new_rounded,
                      label: 'Open Order',
                      color: Colors.blue,
                      onTap: status == 'Accepted' ? () => _openOrder(id) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (status == 'pending')
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _updateStatus(id, 'Accepted', data),
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Accept & Create Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _updateStatus(id, 'Rejected', data),
                          icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                          label: const Text('Reject', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Processed: ${_dateText(data['updatedAt'])}',
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            );

            final image = _listImage(imageUrl, id);

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: image),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: header),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 12),
                image,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersForLists(List<QueryDocumentSnapshot> docs) async {
    final userIds = docs
        .map((doc) => _text((doc.data() as Map<String, dynamic>)['userId']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final result = <String, Map<String, dynamic>>{};

    for (final id in userIds) {
      result[id] = await _userInfo(id);
    }

    return result;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('lists').orderBy('createdAt', descending: true).limit(300).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading lists'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No lists found'));
          }

          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _loadUsersForLists(docs),
            builder: (context, userSnap) {
              final userMap = userSnap.data ?? {};
              final filtered = _filterDocs(docs, userMap);

              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'List Verification Pro',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  _summaryGrid(docs),
                  const SizedBox(height: 14),
                  _filters(),
                  const SizedBox(height: 14),
                  if (!userSnap.hasData)
                    const LinearProgressIndicator(),
                  if (filtered.isEmpty)
                    const Card(
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('No matching lists')),
                      ),
                    )
                  else
                    ...filtered.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final userId = _text(data['userId']);
                      return _listCard(
                        doc: doc,
                        user: userMap[userId] ?? {},
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
