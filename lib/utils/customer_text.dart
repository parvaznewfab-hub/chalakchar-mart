/// Keeps supplier / origin wording out of what shoppers see.
///
/// Imported products carry the marketplace seller's own text: shipping
/// boilerplate ("we mainly ship via AliExpress standard shipping", "items
/// cannot be tracked after they leave China") and an "Origin: Mainland China"
/// specification. ChalakChar Mart never names its supplier or the origin
/// country to customers, so these are removed at display time; the stored
/// data is untouched (admins still see it).
library;

final RegExp _supplierWords = RegExp(
  r'ali\s*express|\bchina\b|\bchinese\b|cainiao|\btaobao\b|\b1688\b|চীন',
  caseSensitive: false,
);

/// Specification names that only describe where the item ships from.
final RegExp _originSpecNames = RegExp(
  r'^\s*(origin|place\s+of\s+origin|country\s+of\s+origin|ships?\s+from|ship\s+from|origin\s+country)\s*$',
  caseSensitive: false,
);

/// True when a text mentions the supplier or origin country.
bool mentionsSupplier(String text) => _supplierWords.hasMatch(text);

/// True when a specification row must not be shown to shoppers.
bool isHiddenSpecification(String name, String value) =>
    _originSpecNames.hasMatch(name) || mentionsSupplier(name) || mentionsSupplier(value);

/// Sentence ends: . ! ? । and line breaks (keeps "2.5" and "v1.2" intact).
final RegExp _sentenceEnd = RegExp(r'(?<=[!?।])\s+|(?<=\.)(?!\d)\s*|\n+');

/// Drops every sentence that mentions the supplier or origin country.
String stripSupplierSentences(String text) {
  if (!mentionsSupplier(text)) return text;
  final kept = text
      .split(_sentenceEnd)
      .where((s) => s.trim().isNotEmpty && !mentionsSupplier(s))
      .map((s) => s.trim())
      .toList();
  return kept.join(' ').trim();
}

final RegExp _htmlTextNode = RegExp(r'>([^<>]+)<');

/// [stripSupplierSentences] for each text run of an HTML description; tags,
/// images and tables stay as they are.
String stripSupplierSentencesHtml(String html) {
  if (!mentionsSupplier(html)) return html;
  final wrapped = '>$html<';
  final cleaned = wrapped.replaceAllMapped(_htmlTextNode, (m) {
    final text = m[1]!;
    if (!mentionsSupplier(text)) return m[0]!;
    return '>${stripSupplierSentences(text)}<';
  });
  return cleaned.substring(1, cleaned.length - 1);
}
