import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/referral_service.dart';

class ChalakCharCashWalletPage extends StatefulWidget {
  const ChalakCharCashWalletPage({super.key});

  static const Color primary = Color(0xFF32A8C7);

  @override
  State<ChalakCharCashWalletPage> createState() =>
      _ChalakCharCashWalletPageState();
}

class _ChalakCharCashWalletPageState extends State<ChalakCharCashWalletPage> {
  final TextEditingController _referralController = TextEditingController();

  bool _applyingReferral = false;

  static const Color primary = ChalakCharCashWalletPage.primary;

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _date(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      final day = d.day.toString().padLeft(2, '0');
      final month = d.month.toString().padLeft(2, '0');
      return '$day/$month/${d.year}';
    }
    return '';
  }

  bool _isPositiveTransaction(Map<String, dynamic> data) {
    final direction = _text(data['direction']).toLowerCase();
    final type = _text(data['type']).toLowerCase();

    if (direction == 'credit') return true;
    if (direction == 'debit') return false;

    return type == 'credit' ||
        type.contains('reward') ||
        type.contains('cashback') ||
        type.contains('bonus');
  }

  String _transactionTitle(Map<String, dynamic> data) {
    final title = _text(data['title']);
    if (title.isNotEmpty) return title;

    final note = _text(data['note']);
    if (note.isNotEmpty) return note;

    final type = _text(data['type']);
    if (type.isNotEmpty) {
      return type
          .replaceAll('_', ' ')
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    return 'Cash Transaction';
  }

  Future<void> _shareReferral(String uid) async {
    try {
      final code = await ReferralService.getOrCreateReferralCode(uid);
      await Share.share(
        'Join ChalakChar Mart and use my referral code $code to get rewards!',
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share referral code now.')),
      );
    }
  }

  Future<void> _copyCode(String code) async {
    final cleanCode = ReferralService.normalizeCode(code);

    if (cleanCode.isEmpty || cleanCode == 'TAPSHARETOCREATE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral code is not ready yet.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: cleanCode));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied.')),
    );
  }

  Future<void> _applyReferral() async {
    if (_applyingReferral) return;

    final code = ReferralService.normalizeCode(_referralController.text);

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a referral code.')),
      );
      return;
    }

    setState(() => _applyingReferral = true);

    try {
      final message = await ReferralService.applyReferral(code);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      final lower = message.toLowerCase();
      if (lower.contains('success') || lower.contains('already')) {
        _referralController.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _applyingReferral = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login first')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('ChalakChar Cash Wallet'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data?.data() ?? {};
          final balance = _toDouble(data['points']);
          final totalEarnings = _toDouble(data['totalEarnings']);
          final referralCount = data['referralCount'] ?? 0;
          final refCode = _text(data['refCode'], 'Tap share to create');
          final alreadyApplied = _text(data['referredByUid']).isNotEmpty ||
              _text(data['referredByCode']).isNotEmpty ||
              _text(data['referredBy']).isNotEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _balanceCard(balance, totalEarnings, referralCount),
              const SizedBox(height: 14),
              _referralCard(
                uid: user.uid,
                code: refCode,
                alreadyApplied: alreadyApplied,
              ),
              const SizedBox(height: 14),
              _howItWorks(),
              const SizedBox(height: 18),
              const Text(
                'Cash History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _history(user.uid),
            ],
          );
        },
      ),
    );
  }

  Widget _balanceCard(
      double balance,
      double totalEarnings,
      dynamic referralCount,
      ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primary, Color(0xFF137B96)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ChalakChar Cash',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '৳${balance.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _smallStat('Total Earned', totalEarnings)),
              Expanded(child: _smallStat('Referrals', referralCount)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String title, dynamic value) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            value is num ? value.toStringAsFixed(0) : value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referralCard({
    required String uid,
    required String code,
    required bool alreadyApplied,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Referral Reward',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share your code with friends, or apply a friend code once to get reward.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Code: $code',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: () => _copyCode(code),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (alreadyApplied)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Referral code already applied for this account.',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _referralController,
              enabled: !_applyingReferral,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Enter friend referral code',
                hintText: 'Example: ABC123',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.card_giftcard_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _applyingReferral ? null : _applyReferral,
                icon: _applyingReferral
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.redeem_rounded),
                label: Text(
                  _applyingReferral
                      ? 'Applying...'
                      : 'Apply Referral Code',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _shareReferral(uid),
              icon: const Icon(Icons.share),
              label: const Text('Share Referral Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Step(icon: Icons.shopping_bag, text: 'Order'),
          Icon(Icons.arrow_forward, color: primary),
          _Step(icon: Icons.wallet_giftcard, text: 'Earn'),
          Icon(Icons.arrow_forward, color: primary),
          _Step(icon: Icons.payments, text: 'Use Cash'),
        ],
      ),
    );
  }

  Widget _history(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('wallet_logs')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        if (snap.connectionState == ConnectionState.waiting && docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: _box(),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: _box(),
            child: const Text('No cash history found'),
          );
        }

        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final amount = _toDouble(d['amount']);
            final title = _transactionTitle(d);
            final isCredit = _isPositiveTransaction(d);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isCredit
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                    child: Icon(
                      isCredit ? Icons.add : Icons.remove,
                      color: isCredit ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$title\n${_date(d['createdAt'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${isCredit ? '+' : '-'}৳${amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: isCredit ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Step({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: ChalakCharCashWalletPage.primary, size: 30),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
