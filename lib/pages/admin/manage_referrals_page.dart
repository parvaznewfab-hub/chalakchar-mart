import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/referral_service.dart';

class ManageReferralsPage extends StatefulWidget {
  const ManageReferralsPage({super.key});

  @override
  State<ManageReferralsPage> createState() => _ManageReferralsPageState();
}

class _ManageReferralsPageState extends State<ManageReferralsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final formKey = GlobalKey<FormState>();

  final referrerRewardController = TextEditingController();
  final refereeRewardController = TextEditingController();
  final videoUrlController = TextEditingController();
  final maxRewardPerUserController = TextEditingController(text: '0');
  final searchController = TextEditingController();

  bool autoApprove = true;
  bool referralEnabled = true;
  bool loading = true;
  bool saving = false;

  String statusFilter = 'all';
  String searchText = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    referrerRewardController.dispose();
    refereeRewardController.dispose();
    videoUrlController.dispose();
    maxRewardPerUserController.dispose();
    searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final t = value.toString().trim();
    return t.isEmpty ? fallback : t;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _short(dynamic value) {
    final id = _text(value);
    return id.length > 8 ? '${id.substring(0, 8)}...' : id;
  }

  String _date(dynamic value) {
    if (value is! Timestamp) return 'N/A';
    final d = value.toDate();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await db.collection('settings').doc('referral').get();
      final data = doc.data() ?? {};

      referrerRewardController.text = _toInt(data['referrerReward'], 50).toString();
      refereeRewardController.text = _toInt(data['refereeReward'], 20).toString();
      videoUrlController.text = _text(data['videoUrl']);
      maxRewardPerUserController.text = _toInt(data['maxRewardPerUser'], 0).toString();
      autoApprove = data['autoApprove'] != false;
      referralEnabled = data['referralEnabled'] != false;
    } catch (e) {
      _snack('Settings load failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _number(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Required';
    if (int.tryParse(text) == null) return 'Enter valid number';
    return null;
  }

  Future<void> _saveSettings() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);
    try {
      final referrer = _toInt(referrerRewardController.text, 50);
      final referee = _toInt(refereeRewardController.text, 20);
      final videoUrl = videoUrlController.text.trim();

      await ReferralService.updateReferralSettings(
        referrer,
        referee,
        autoApprove,
        videoUrl,
      );

      await db.collection('settings').doc('referral').set({
        'referrerReward': referrer,
        'refereeReward': referee,
        'videoUrl': videoUrl,
        'autoApprove': autoApprove,
        'referralEnabled': referralEnabled,
        'maxRewardPerUser': _toInt(maxRewardPerUserController.text),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('Referral settings updated');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<Map<String, dynamic>> _userInfo(String uid) async {
    if (uid.isEmpty) return {};
    final doc = await db.collection('users').doc(uid).get();
    return doc.data() ?? {};
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _approveReferral(String docId, Map<String, dynamic> data) async {
    if (data['status'] == 'Approved') {
      _snack('Already approved');
      return;
    }

    final ok = await _confirm(
      title: 'Approve Referral?',
      message: 'Reward will be added to referrer and referee accounts.',
      confirmText: 'Approve',
    );
    if (ok != true) return;

    try {
      final referrerId = _text(data['referrerId']);
      final refereeId = _text(data['refereeId']);
      final referrerReward = _toInt(data['referrerReward']);
      final refereeReward = _toInt(data['refereeReward']);

      if (referrerId.isEmpty || refereeId.isEmpty) {
        _snack('Invalid referral user ids');
        return;
      }

      final batch = db.batch();

      batch.update(db.collection('users').doc(referrerId), {
        'points': FieldValue.increment(referrerReward),
        'totalEarnings': FieldValue.increment(referrerReward),
        'referralCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(db.collection('users').doc(refereeId), {
        'points': FieldValue.increment(refereeReward),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(db.collection('referrals').doc(docId), {
        'status': 'Approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      _snack('Referral approved');
    } catch (e) {
      _snack('Approve failed: $e');
    }
  }

  Future<void> _rejectReferral(String docId) async {
    final ok = await _confirm(
      title: 'Reject Referral?',
      message: 'This referral will be marked as rejected.',
      confirmText: 'Reject',
      danger: true,
    );
    if (ok != true) return;

    try {
      await db.collection('referrals').doc(docId).update({
        'status': 'Rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _snack('Referral rejected');
    } catch (e) {
      _snack('Reject failed: $e');
    }
  }

  List<QueryDocumentSnapshot> _filterReferrals(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'Pending');
      if (statusFilter != 'all' && status != statusFilter) return false;
      if (s.isEmpty) return true;

      return doc.id.toLowerCase().contains(s) ||
          _text(data['referrerId']).toLowerCase().contains(s) ||
          _text(data['refereeId']).toLowerCase().contains(s);
    }).toList();
  }

  Widget _settingsTab() {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Referral Settings Pro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reward Configuration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, c) {
                      final count = c.maxWidth >= 900 ? 3 : c.maxWidth >= 600 ? 2 : 1;
                      final fields = [
                        _field('Referrer Reward (৳)', referrerRewardController, Icons.person_add_alt_1_rounded),
                        _field('Referee Reward (৳)', refereeRewardController, Icons.redeem_rounded),
                        _field('Max Reward/User (0 = unlimited)', maxRewardPerUserController, Icons.lock_clock_rounded),
                      ];
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: fields.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: count == 1 ? 5.6 : 4.2,
                        ),
                        itemBuilder: (_, i) => fields[i],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: videoUrlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Instruction Video URL',
                      hintText: 'https://youtube.com/...',
                      prefixIcon: const Icon(Icons.play_circle_outline_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _switchTile(
                    title: 'Referral Enabled',
                    subtitle: 'Turn referral system on or off for users.',
                    value: referralEnabled,
                    icon: Icons.share_rounded,
                    onChanged: (v) => setState(() => referralEnabled = v),
                  ),
                  _switchTile(
                    title: 'Auto Approve Rewards',
                    subtitle: 'If disabled, rewards must be approved manually.',
                    value: autoApprove,
                    icon: Icons.verified_user_rounded,
                    onChanged: (v) => setState(() => autoApprove = v),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : _saveSettings,
                      icon: saving
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_rounded),
                      label: Text(saving ? 'Saving...' : 'Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, IconData icon) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      validator: _number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: const Color(0xFF1592B3)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _referralsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('referrals').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allDocs = snapshot.data!.docs;
        final docs = _filterReferrals(allDocs);

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('Referral Approvals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            _summaryGrid(allDocs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Text('Referrals (${docs.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching referrals')),
                ),
              )
            else
              ...docs.map((doc) => _referralCard(doc.id, doc.data() as Map<String, dynamic>)),
          ],
        );
      },
    );
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int pending = 0;
    int approved = 0;
    int rejected = 0;
    int rewardPaid = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'Pending');
      if (status == 'Approved') {
        approved++;
        rewardPaid += _toInt(data['referrerReward']) + _toInt(data['refereeReward']);
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
          childAspectRatio: count == 1 ? 4.5 : 2.15,
          children: [
            _summaryCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.orange),
            _summaryCard('Approved', '$approved', Icons.verified_rounded, Colors.green),
            _summaryCard('Rejected', '$rejected', Icons.cancel_rounded, Colors.red),
            _summaryCard('Reward Paid', '৳$rewardPaid', Icons.payments_rounded, Colors.blue),
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
          BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
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
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search referral, referrer id, referee id...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );
            final status = DropdownButtonFormField<String>(
              value: statusFilter,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            );
            if (small) {
              return Column(children: [search, const SizedBox(height: 8), status]);
            }
            return Row(children: [Expanded(flex: 2, child: search), const SizedBox(width: 8), Expanded(child: status)]);
          },
        ),
      ),
    );
  }

  Widget _referralCard(String id, Map<String, dynamic> data) {
    final status = _text(data['status'], 'Pending');
    final referrerId = _text(data['referrerId']);
    final refereeId = _text(data['refereeId']);
    final color = status == 'Approved' ? Colors.green : status == 'Rejected' ? Colors.red : Colors.orange;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait([_userInfo(referrerId), _userInfo(refereeId)]),
      builder: (context, snap) {
        final referrer = snap.data != null && snap.data!.isNotEmpty ? snap.data![0] : <String, dynamic>{};
        final referee = snap.data != null && snap.data!.length > 1 ? snap.data![1] : <String, dynamic>{};

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
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(Icons.share_rounded, color: color)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Referral #${_short(id)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                    _chip(status, color),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final referrerBox = _userBox('Referrer', referrerId, referrer, _toInt(data['referrerReward']), Icons.person_add_alt_1_rounded);
                    final refereeBox = _userBox('Referee', refereeId, referee, _toInt(data['refereeReward']), Icons.person_rounded);
                    if (c.maxWidth < 700) {
                      return Column(children: [referrerBox, const SizedBox(height: 8), refereeBox]);
                    }
                    return Row(children: [Expanded(child: referrerBox), const SizedBox(width: 8), Expanded(child: refereeBox)]);
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Created ${_date(data['createdAt'])}', Colors.blueGrey),
                    _chip('Total ৳${_toInt(data['referrerReward']) + _toInt(data['refereeReward'])}', Colors.blue),
                  ],
                ),
                if (status == 'Pending') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approveReferral(id, data),
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _rejectReferral(id),
                          icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                          label: const Text('Reject', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _userBox(String title, String id, Map<String, dynamic> user, int reward, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1592B3)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(_text(user['name'], _short(id)), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_text(user['phone']).isNotEmpty)
                  Text(_text(user['phone']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text('৳$reward', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(30)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text('Manage Referrals Pro'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Color(0xFF1592B3),
            unselectedLabelColor: Colors.black54,
            indicatorColor: Color(0xFF1592B3),
            tabs: [
              Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
              Tab(icon: Icon(Icons.verified_rounded), text: 'Approvals'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _settingsTab(),
            _referralsTab(),
          ],
        ),
      ),
    );
  }
}



