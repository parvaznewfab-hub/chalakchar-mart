/// ChalakChar Cash rules for the cart (14b step G). Must match
/// functions/cash/cashCheck.js: the onOrderCreatedCash function takes the
/// points only when the claimed Cash passes the same limits, otherwise it
/// takes nothing and flags the order for the admin.
library;

const double defaultMaxCashPerOrder = 100;

double _num(dynamic v, double fallback) {
  if (v is num) return v.toDouble();
  final parsed = double.tryParse('${v ?? ''}'.trim());
  return parsed ?? fallback;
}

/// settings/app -> (enabled, maxPerOrder). enableChalakCharCash wins over
/// the older enableAbdCash key, like AppSettingsService.
({bool enabled, double maxPerOrder}) cashSettingsFrom(Map<String, dynamic> data) {
  final flag = data.containsKey('enableChalakCharCash') ? data['enableChalakCharCash'] : data['enableAbdCash'];
  final enabled = flag != false;
  final max = data.containsKey('maxAbdCashRedeem') ? _num(data['maxAbdCashRedeem'], defaultMaxCashPerOrder) : defaultMaxCashPerOrder;
  return (enabled: enabled, maxPerOrder: max < 0 ? 0 : max);
}

/// The most Cash this order may use: points, the per-order limit and
/// (subtotal - coupon), whichever is smallest; 0 when Cash is off.
double usableCash({
  required double points,
  required double subtotal,
  required double couponDiscount,
  required bool enabled,
  required double maxPerOrder,
}) {
  if (!enabled) return 0;
  var limit = subtotal - couponDiscount;
  if (maxPerOrder < limit) limit = maxPerOrder;
  if (points < limit) limit = points;
  return limit < 0 ? 0 : limit;
}
