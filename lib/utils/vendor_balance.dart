/// ledger-1: one place for a vendor's money. Every number comes from
/// vendor_private/{vendorId}, written by the commission ledger functions
/// (functions/ledger) and the admin payout step. Nothing is worked out from
/// orders on the device any more.
library;

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

class VendorBalance {
  const VendorBalance({
    required this.withdrawable,
    required this.pendingOrders,
    required this.totalSales,
    required this.totalCommission,
    required this.totalPaidOut,
    required this.requested,
  });

  /// Money from delivered orders, minus payouts. Negative = the vendor owes
  /// (an order was returned after the money was paid out).
  final double withdrawable;

  /// Money from orders not delivered yet (not withdrawable).
  final double pendingOrders;
  final double totalSales;
  final double totalCommission;
  final double totalPaidOut;

  /// Withdraw requests still waiting for the admin.
  final double requested;

  bool get inDebt => withdrawable < 0;

  /// What a new request may ask for: withdrawable minus what is already
  /// requested. Never below 0.
  double get available {
    final a = withdrawable - requested;
    return a > 0 ? a : 0;
  }

  /// A request (or a payout) is allowed only while withdrawable > 0.
  bool get canWithdraw => withdrawable > 0 && available > 0;

  static VendorBalance from(Map<String, dynamic>? vendorPrivate, {double requested = 0}) {
    final v = vendorPrivate ?? const <String, dynamic>{};
    return VendorBalance(
      withdrawable: _num(v['withdrawableBalance']),
      pendingOrders: _num(v['pendingBalance']),
      totalSales: _num(v['totalSales']),
      totalCommission: _num(v['totalCommission']),
      totalPaidOut: _num(v['totalPaidOut']),
      requested: requested,
    );
  }
}

/// Sum of the vendor's withdraw requests still marked pending.
double pendingRequestTotal(Iterable<Map<String, dynamic>> requests) {
  double total = 0;
  for (final r in requests) {
    if ('${r['status'] ?? ''}'.toLowerCase() == 'pending') total += _num(r['amount']);
  }
  return total;
}

/// The admin payout check: withdrawable must be > 0 and cover the amount.
/// Returns an error text, or null when the payout may go ahead.
String? payoutBlockedReason({required double withdrawable, required double amount}) {
  if (amount <= 0) return 'Invalid payout amount.';
  if (withdrawable <= 0) {
    return withdrawable < 0
        ? 'Vendor owes ৳${(-withdrawable).toStringAsFixed(2)} (returned order). No payout until it is cleared.'
        : 'Vendor has no withdrawable balance.';
  }
  if (amount > withdrawable + 0.005) {
    return 'Amount ৳${amount.toStringAsFixed(2)} is more than the withdrawable ৳${withdrawable.toStringAsFixed(2)}.';
  }
  return null;
}
