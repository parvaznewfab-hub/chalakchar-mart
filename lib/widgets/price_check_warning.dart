import 'package:flutter/material.dart';

/// ledger-1: orders/{id}.priceCheck is written only by the
/// onOrderCreatedLedger Cloud Function (prices checked again from products/).
/// Returns what to warn about, or null: no priceCheck (older orders) or ok.
class PriceCheckIssue {
  const PriceCheckIssue({
    required this.clientTotal,
    required this.serverTotal,
    required this.mismatchedItems,
  });

  final double clientTotal;
  final double serverTotal;
  final int mismatchedItems;
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

PriceCheckIssue? priceCheckIssue(dynamic raw) {
  if (raw is! Map) return null;
  if (raw['ok'] != false) return null;
  final items = raw['mismatchedItems'];
  return PriceCheckIssue(
    clientTotal: _num(raw['clientTotal']),
    serverTotal: _num(raw['serverTotal']),
    mismatchedItems: items is List ? items.length : 0,
  );
}

/// Red box for the admin order card; nothing when the check passed or is
/// missing.
class PriceCheckWarning extends StatelessWidget {
  const PriceCheckWarning({super.key, required this.priceCheck});

  final dynamic priceCheck;

  @override
  Widget build(BuildContext context) {
    final issue = priceCheckIssue(priceCheck);
    if (issue == null) return const SizedBox.shrink();
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
              'Price check failed: customer total ৳${issue.clientTotal.toStringAsFixed(2)}, '
              'server total ৳${issue.serverTotal.toStringAsFixed(2)}'
              '${issue.mismatchedItems > 0 ? ' (${issue.mismatchedItems} item(s) differ)' : ''}. '
              'Check before confirming.',
              style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
