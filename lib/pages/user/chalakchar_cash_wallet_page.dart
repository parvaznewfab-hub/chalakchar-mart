import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/referral_service.dart';

class ChalakCharCashWalletPage extends StatelessWidget {
  const ChalakCharCashWalletPage({super.key});

  static const Color primary = Color(0xFF32A8C7);

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
      return '${d.day}/${d.month}/${d.year}';
    }
    return '';
  }

  Future<void> _shareReferral(BuildContext context, String uid) async {
    final code = await ReferralService.getOrCreateReferralCode(uid);
    await Share.share(
      'Join ChalakChar Mart and use my referral code $code to get rewards!',
    );
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
          final data = snap.data?.data() ?? {};
          final balance = _toDouble(data['points']);
          final totalEarnings = _toDouble(data['totalEarnings']);
          final referralCount = data['referralCount'] ?? 0;
          final refCode = _text(data['refCode'], 'Tap share to create');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _balanceCard(balance, totalEarnings, referralCount),
              const SizedBox(height: 14),
              _referralCard(context, user.uid, refCode),
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

  Widget _balanceCard(double balance, double totalEarnings, dynamic referralCount) {
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

  Widget _referralCard(BuildContext context, String uid, String code) {
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
          Text('Your Code: $code'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareReferral(context, uid),
              icon: const Icon(Icons.share),
              label: const Text('Share Referral Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
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
          .collection('cashTransactions')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

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
            final type = _text(d['type']);
            final title = _text(d['title'], type);
            final isCredit = type == 'credit';

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