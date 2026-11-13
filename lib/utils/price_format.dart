import 'package:intl/intl.dart';

final NumberFormat _wholeTaka = NumberFormat('#,##0', 'en_US');
final NumberFormat _fractionTaka = NumberFormat('#,##0.00', 'en_US');

/// Display-only Taka amount: "৳" + thousands separators, no decimals for
/// whole amounts, two decimals only when there is a real fraction.
///
///   16603    -> ৳16,603
///   16603.00 -> ৳16,603
///   1850.5   -> ৳1,850.50
///   -40      -> -৳40
///
/// Rounds to the paisa first, so float noise (16602.999999) still shows as
/// a whole number. Never use this for stored or machine-read values (SEO
/// schema, invoices, payloads); it only formats what the shopper sees.
String formatTaka(num value) {
  final paisa = (value * 100).round();
  final sign = paisa < 0 ? '-' : '';
  final absPaisa = paisa.abs();
  final body = absPaisa % 100 == 0
      ? _wholeTaka.format(absPaisa ~/ 100)
      : _fractionTaka.format(absPaisa / 100);
  return '$sign৳$body';
}

/// Whole-number discount percentage of [price] against [mrp], or 0 when
/// there is no discount worth showing (no MRP, MRP not above price, or a
/// discount that rounds to 0%).
int discountPercent(num price, num mrp) {
  if (mrp <= 0 || price < 0 || mrp <= price) return 0;
  return ((mrp - price) / mrp * 100).round();
}
