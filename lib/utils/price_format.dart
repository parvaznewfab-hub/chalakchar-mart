import 'package:intl/intl.dart';

final NumberFormat _wholeTaka = NumberFormat('#,##0', 'en_US');

/// Display-only Taka amount: "৳" + thousands separators, whole taka.
///
///   16603    -> ৳16,603
///   2851.49  -> ৳2,851
///   1850.5   -> ৳1,851
///   -40      -> -৳40
///   -0.004   -> ৳0      (never "৳-0.00")
///
/// Shop rule (audit item 16): prices are whole taka, rounded to the nearest
/// taka (.5 up) — the same rule imports/sync use (importSettings.roundingMode
/// "round") and the admin edit form saves. Never use this for stored or
/// machine-read values (SEO schema, invoices, payloads).
String formatTaka(num value) {
  final taka = value.isFinite ? value.round() : 0;
  final sign = taka < 0 ? '-' : '';
  return '$sign৳${_wholeTaka.format(taka.abs())}';
}

/// Whole-number discount percentage of [price] against [mrp], or 0 when
/// there is no discount worth showing (no MRP, MRP not above price, or a
/// discount that rounds to 0%).
int discountPercent(num price, num mrp) {
  if (mrp <= 0 || price < 0 || mrp <= price) return 0;
  return ((mrp - price) / mrp * 100).round();
}
