import 'package:flutter/material.dart';

/// Step G: orders/{id}.cashCheck is written only by the onOrderCreatedCash
/// Cloud Function. It checks the ChalakChar Cash claimed on the order
/// against the customer's points and settings, and the order total against
/// the server's own sum. Messages for the admin order card; empty when the
/// check passed or is missing (older orders).
class CashCheckIssues {
  const CashCheckIssues({this.totalMessage, this.cashMessage});

  final String? totalMessage;
  final String? cashMessage;

  bool get isEmpty => totalMessage == null && cashMessage == null;
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

String _taka(double v) {
  final whole = v == v.roundToDouble();
  return '৳${v.toStringAsFixed(whole ? 0 : 2)}';
}

String _cashReason(String reason, Map raw) {
  switch (reason) {
    case 'not_enough_points':
      return 'customer-এর কাছে আছে ${_taka(_num(raw['available']))}';
    case 'over_limit':
      return 'এক অর্ডারে সর্বোচ্চ ${_taka(_num(raw['maxPerOrder']))}';
    case 'cash_disabled':
      return 'Cash এখন বন্ধ';
    case 'over_order_value':
      return 'পণ্যের দামের চেয়ে বেশি';
    case 'claim_mismatch':
      return 'অর্ডারের দুই জায়গায় Cash-এর অঙ্ক আলাদা';
    default:
      return 'অঙ্কটা ঠিক নয়';
  }
}

CashCheckIssues cashCheckIssues(dynamic raw) {
  if (raw is! Map) return const CashCheckIssues();
  String? total;
  String? cash;
  if (raw['totalOk'] == false) {
    final client = raw['clientGrandTotal'];
    total = 'মোট দাম মেলে না: customer ${client == null ? '—' : _taka(_num(client))}, '
        'হিসাবে ${_taka(_num(raw['serverGrandTotal']))}। rider পাঠানোর আগে দেখুন।';
  }
  if (raw['ok'] == false) {
    cash = 'ChalakChar Cash কাটা হয়নি: customer চেয়েছে ${_taka(_num(raw['claimed']))}, '
        '${_cashReason('${raw['reason'] ?? ''}', raw)}। confirm করার আগে দেখুন।';
  }
  return CashCheckIssues(totalMessage: total, cashMessage: cash);
}

/// Red boxes for the admin order card, next to the price check warning.
class CashCheckWarning extends StatelessWidget {
  const CashCheckWarning({super.key, required this.cashCheck});

  final dynamic cashCheck;

  @override
  Widget build(BuildContext context) {
    final issues = cashCheckIssues(cashCheck);
    if (issues.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issues.totalMessage != null) _box(issues.totalMessage!),
        if (issues.cashMessage != null) _box(issues.cashMessage!),
      ],
    );
  }

  Widget _box(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
