
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class AdminMarketingPage extends StatefulWidget {
  const AdminMarketingPage({super.key});

  @override
  State<AdminMarketingPage> createState() => _AdminMarketingPageState();
}

class _AdminMarketingPageState extends State<AdminMarketingPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  String channelFilter = 'all';
  String statusFilter = 'all';

  String _text(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _date(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
    }
    return 'N/A';
  }

  int _countEnabled(Map<String, dynamic> channels) {
    int total = 0;
    for (final value in channels.values) {
      if (value == true) total++;
    }
    return total;
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('failed')) return Colors.red;
    if (s.contains('pending')) return Colors.orange;
    if (s.contains('sent') || s.contains('completed')) return Colors.green;
    return Colors.blueGrey;
  }

  Future<Map<String, dynamic>> _loadOverview() async {
    final results = await Future.wait([
      db.collection('marketing_outbox').limit(1000).get(),
      db.collection('marketing_logs').limit(1000).get(),
      db.collection('product_marketing_scores').limit(1000).get(),
      db.collection('user_marketing_profiles').limit(1000).get(),
    ]);

    final outbox = results[0].docs;
    final logs = results[1].docs;
    final scores = results[2].docs;
    final profiles = results[3].docs;

    int failed = 0;
    int pendingSocial = 0;
    int fcmReady = 0;
    for (final doc in outbox) {
      final data = doc.data();
      final status = _text(data['status']).toLowerCase();
      if (status.contains('failed')) failed++;
      if (status.contains('not_connected') || status.contains('pending')) pendingSocial++;
      final channels = data['channels'];
      if (channels is Map && channels['fcm'] == true) fcmReady++;
    }

    int totalScore = 0;
    for (final doc in scores) {
      final score = doc.data()['score'];
      if (score is num) totalScore += score.toInt();
    }

    return {
      'outbox': outbox.length,
      'logs': logs.length,
      'scores': scores.length,
      'profiles': profiles.length,
      'failed': failed,
      'pendingSocial': pendingSocial,
      'fcmReady': fcmReady,
      'totalScore': totalScore,
    };
  }

  Widget _stat(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadOverview(),
      builder: (context, snap) {
        final data = snap.data ?? {};
        return LayoutBuilder(
          builder: (context, c) {
            final count = c.maxWidth > 1150 ? 4 : c.maxWidth > 720 ? 3 : 2;
            return GridView.count(
              crossAxisCount: count,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: c.maxWidth < 600 ? 1.45 : 2.1,
              children: [
                _stat('Marketing Queue', '${data['outbox'] ?? 0}', Icons.campaign_rounded, Colors.pink),
                _stat('Automation Logs', '${data['logs'] ?? 0}', Icons.history_rounded, Colors.indigo),
                _stat('Pending Social', '${data['pendingSocial'] ?? 0}', Icons.schedule_send_rounded, Colors.orange),
                _stat('Failed Queue', '${data['failed'] ?? 0}', Icons.error_outline_rounded, Colors.red),
                _stat('Product Scores', '${data['scores'] ?? 0}', Icons.trending_up_rounded, Colors.green),
                _stat('User Profiles', '${data['profiles'] ?? 0}', Icons.group_rounded, Colors.deepPurple),
                _stat('FCM Ready', '${data['fcmReady'] ?? 0}', Icons.notifications_active_rounded, Colors.teal),
                _stat('Total Score', '${data['totalScore'] ?? 0}', Icons.bolt_rounded, Colors.amber),
              ],
            );
          },
        );
      },
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: statusFilter,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All status')),
                DropdownMenuItem(value: 'sent', child: Text('Sent / Completed')),
                DropdownMenuItem(value: 'pending', child: Text('Pending / Not connected')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: channelFilter,
              decoration: const InputDecoration(labelText: 'Channel', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All channels')),
                DropdownMenuItem(value: 'fcm', child: Text('FCM')),
                DropdownMenuItem(value: 'facebook', child: Text('Facebook')),
                DropdownMenuItem(value: 'instagram', child: Text('Instagram')),
                DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                DropdownMenuItem(value: 'messenger', child: Text('Messenger')),
                DropdownMenuItem(value: 'tiktok', child: Text('TikTok')),
              ],
              onChanged: (v) => setState(() => channelFilter = v ?? 'all'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  bool _matches(Map<String, dynamic> data) {
    final status = _text(data['status']).toLowerCase();
    if (statusFilter == 'failed' && !status.contains('failed')) return false;
    if (statusFilter == 'pending' && !(status.contains('pending') || status.contains('not_connected'))) return false;
    if (statusFilter == 'sent' && !(status.contains('sent') || status.contains('completed'))) return false;

    final channelsRaw = data['channels'];
    final channels = channelsRaw is Map ? Map<String, dynamic>.from(channelsRaw) : <String, dynamic>{};
    if (channelFilter != 'all' && channels[channelFilter] != true) return false;
    return true;
  }

  Widget _queueList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('marketing_outbox').orderBy('updatedAt', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Marketing queue failed: ${snap.error}'));
        if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));

        final docs = snap.data!.docs.where((doc) => _matches(doc.data())).toList();
        if (docs.isEmpty) {
          return const Card(
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No marketing queue item found')),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Marketing Queue (${docs.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            ...docs.map((doc) => _queueCard(doc.id, doc.data())),
          ],
        );
      },
    );
  }

  Widget _queueCard(String id, Map<String, dynamic> data) {
    final productName = _text(data['productName'], 'Product / Campaign');
    final status = _text(data['status'], 'pending');
    final reason = _text(data['reason'], _text(data['type'], 'new_product'));
    final imageUrl = _text(data['imageUrl']);
    final productUrl = _text(data['productUrl']);
    final channelsRaw = data['channels'];
    final channels = channelsRaw is Map ? Map<String, dynamic>.from(channelsRaw) : <String, dynamic>{};
    final captionsRaw = data['captions'];
    final captions = captionsRaw is Map ? Map<String, dynamic>.from(captionsRaw) : <String, dynamic>{};

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 800;
            final thumb = ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isEmpty
                  ? Container(width: 70, height: 70, color: const Color(0xFFF3F4F6), child: const Icon(Icons.image_rounded, color: Colors.grey))
                  : Image.network(imageUrl, width: 70, height: 70, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 70, height: 70, color: const Color(0xFFF3F4F6), child: const Icon(Icons.broken_image_rounded))),
            );

            final info = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                      _chip(status, _statusColor(status)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text('ID: $id • Reason: $reason • Channels: ${_countEnabled(channels)}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in channels.entries)
                        _chip('${e.key}: ${e.value == true ? 'on' : 'off'}', e.value == true ? Colors.green : Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_text(captions['facebook']).isNotEmpty)
                    Text('FB: ${_text(captions['facebook'])}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade800)),
                  if (productUrl.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(productUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF32A8C7), fontSize: 12)),
                  ],
                  const SizedBox(height: 5),
                  Text('Updated: ${_date(data['updatedAt'] ?? data['createdAt'])}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            );

            final retry = OutlinedButton.icon(
              onPressed: () => _markRetry(id),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [thumb, const SizedBox(width: 12), info]),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: retry),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [thumb, const SizedBox(width: 12), info, const SizedBox(width: 12), retry],
            );
          },
        ),
      ),
    );
  }

  Future<void> _markRetry(String id) async {
    await db.collection('marketing_outbox').doc(id).set({
      'status': 'retry_requested',
      'retryRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retry requested. Dispatcher function can process this when social API is connected.')),
    );
  }

  Widget _topProducts() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('product_marketing_scores').orderBy('score', descending: true).limit(12).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5E7EB))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trending Product Scores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                ...docs.map((doc) {
                  final data = doc.data();
                  final score = data['score'] ?? 0;
                  final reason = _text(data['lastReason'], 'signal');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.12), child: const Icon(Icons.trending_up_rounded, color: Colors.green)),
                    title: Text('Product: ${_text(data['productId'], doc.id)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Last signal: $reason'),
                    trailing: Text('$score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Marketing Center', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text('AI marketing automation queue, wishlist campaigns, social-ready captions and product scores.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _overview(),
            const SizedBox(height: 16),
            _filters(),
            const SizedBox(height: 14),
            _queueList(),
            const SizedBox(height: 16),
            _topProducts(),
          ],
        ),
      ),
    );
  }
}
