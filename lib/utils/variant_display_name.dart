/// Presentation-only cleanup for a variant's display name.
///
/// The underlying stored variant name (used for matching/lookup — dropdown
/// `value:`, `onTap` handlers, price/stock/image lookups) is never touched;
/// this only affects what customers visually see. Some AliExpress-imported
/// variant names combine the real spec with a shipping-origin/warehouse
/// property joined by AliExpress itself (e.g. "11 64g No Face ID |
/// China Mainland", "Blue 128GB / Spain") — ChalakChar Mart's storefront
/// should not surface that origin/location to customers.
///
/// This never matches against a specific location name/value (no hardcoded
/// "China Mainland" or country list) — it's a purely structural rule: keep
/// only the text before the first recognized separator. Deliberately does
/// NOT split on a bare `/` (no surrounding spaces), since that's plausible
/// inside a legitimate spec (e.g. "S/M/L"); only "|" and " / " (this
/// project's own join format for combined AliExpress properties) are
/// treated as separators.
const _variantDisplayNameSeparators = ['|', ' / '];

String cleanVariantDisplayName(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return text;

  for (final separator in _variantDisplayNameSeparators) {
    final index = text.indexOf(separator);
    if (index > 0) {
      final head = text.substring(0, index).trim();
      if (head.isNotEmpty) return head;
    }
  }

  return text;
}
