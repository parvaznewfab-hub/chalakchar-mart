import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of resolving a product's delivery estimate for display.
class ProductDeliveryEstimate {
  final bool hasEstimate;
  final DateTime? date;
  final String? displayText;
  final int? days;

  /// True when [displayText] is a day-count-derived range (from
  /// deliveryMinDays/deliveryMaxDays, recalculated from today on every
  /// render) rather than an AliExpress-confirmed exact date — callers should
  /// label it clearly as an estimate, e.g. "Estimated delivery: ...".
  final bool isEstimateRange;

  const ProductDeliveryEstimate({
    required this.hasEstimate,
    this.date,
    this.displayText,
    this.days,
    this.isEstimateRange = false,
  });

  static const ProductDeliveryEstimate none =
      ProductDeliveryEstimate(hasEstimate: false);
}

/// Single shared source of truth for "when will this arrive", so every
/// screen (product overview tab, sticky mobile action bar, desktop sidebar,
/// and any future cart/checkout delivery display) agrees on the same date
/// instead of each computing its own with `DateTime.now() + deliveryDays`.
///
/// Display priority (per product doc field):
///   A. estimatedDeliveryDate — an AliExpress-confirmed exact calendar date
///      (not currently populated by any integration, but kept for when one
///      is confirmed; see functions/aliexpress/deliveryEstimate.js)
///   B. deliveryMinDays / deliveryMaxDays — AliExpress's freight-quoted day
///      range (e.g. "10-20day"), recalculated from today on every render
///      since it's a rolling estimate, not a fixed date. Labeled as an
///      estimate via [ProductDeliveryEstimate.isEstimateRange].
///   C. estimatedDeliveryMaxDate (shown as a range with min, if min differs)
///   D. estimatedDeliveryMinDate
///   E. estimatedDeliveryText (AliExpress's own free-text estimate, verbatim)
///   F. deliveryDays fallback (today + N days) — also covers non-AliExpress
///      products and older AliExpress rows that only ever had deliveryDays.
///
/// Firestore values may be a [Timestamp], an ISO-8601 string, or an epoch
/// int (seconds or milliseconds) — all three are handled safely.
class ProductDeliveryResolver {
  ProductDeliveryResolver._();

  static int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static DateTime? _toDateTimeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      final ms = value > 20000000000 ? value.toInt() : (value.toInt() * 1000);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final numeric = num.tryParse(text);
    if (numeric != null) {
      final ms =
          numeric > 20000000000 ? numeric.toInt() : (numeric.toInt() * 1000);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    return DateTime.tryParse(text);
  }

  static bool _isSameCalendarDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Formats a delivery date consistently across the app, e.g. "12 Aug 2026".
  static String formatShortDate(DateTime date) {
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  static String _formatDayMonth(DateTime date) =>
      '${date.day} ${_months[date.month - 1]}';

  /// Resolves the delivery estimate to display for a product's raw Firestore
  /// data map, following the priority order documented above.
  static ProductDeliveryEstimate resolve(Map<String, dynamic> data) {
    final exact = _toDateTimeValue(data['estimatedDeliveryDate']);
    if (exact != null) {
      return ProductDeliveryEstimate(
          hasEstimate: true, date: exact, displayText: formatShortDate(exact));
    }

    final minDaysRaw = data['deliveryMinDays'];
    final maxDaysRaw = data['deliveryMaxDays'];
    final hasDayRange = minDaysRaw != null &&
        maxDaysRaw != null &&
        _toInt(maxDaysRaw, -1) >= 0;
    if (hasDayRange) {
      final minDays = _toInt(minDaysRaw);
      final maxDays = _toInt(maxDaysRaw);
      final now = DateTime.now();
      final rangeMinDate = now.add(Duration(days: minDays));
      final rangeMaxDate = now.add(Duration(days: maxDays));
      final label = _isSameCalendarDate(rangeMinDate, rangeMaxDate)
          ? formatShortDate(rangeMaxDate)
          : '${_formatDayMonth(rangeMinDate)}–${formatShortDate(rangeMaxDate)}';
      return ProductDeliveryEstimate(
        hasEstimate: true,
        date: rangeMaxDate,
        displayText: label,
        days: maxDays,
        isEstimateRange: true,
      );
    }

    final maxDate = _toDateTimeValue(data['estimatedDeliveryMaxDate']);
    if (maxDate != null) {
      final minDate = _toDateTimeValue(data['estimatedDeliveryMinDate']);
      final label = (minDate != null && !_isSameCalendarDate(minDate, maxDate))
          ? '${_formatDayMonth(minDate)}–${formatShortDate(maxDate)}'
          : formatShortDate(maxDate);
      return ProductDeliveryEstimate(
          hasEstimate: true, date: maxDate, displayText: label);
    }

    final minDate = _toDateTimeValue(data['estimatedDeliveryMinDate']);
    if (minDate != null) {
      return ProductDeliveryEstimate(
          hasEstimate: true,
          date: minDate,
          displayText: formatShortDate(minDate));
    }

    final text = (data['estimatedDeliveryText'] ?? '').toString().trim();
    if (text.isNotEmpty) {
      return ProductDeliveryEstimate(hasEstimate: true, displayText: text);
    }

    final daysRaw = data['deliveryDays'];
    final hasDays = daysRaw != null && _toInt(daysRaw, -1) >= 0;
    if (hasDays) {
      final days = _toInt(daysRaw);
      final fallbackDate = DateTime.now().add(Duration(days: days));
      return ProductDeliveryEstimate(
        hasEstimate: true,
        date: fallbackDate,
        displayText: formatShortDate(fallbackDate),
        days: days,
      );
    }

    return ProductDeliveryEstimate.none;
  }
}
