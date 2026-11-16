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

// ---------------------------------------------------------------------------
// Seller boilerplate in imported descriptions: marketplace rules aimed at the
// seller's own buyers ("do not open a dispute", "leave a bad review", "please
// contact us", "Tips: please check the appearance…"), plus broken characters
// (U+FFFD "��") and HTML entities left as text ("don&#x27;t"). Removed
// sentence by sentence at display time; Firestore is not changed.
// Mirror: functions/catalog/customerText.js (cleanCustomerText /
// cleanCustomerHtml), fixture test/fixtures/seller_text_cases.json.
// ---------------------------------------------------------------------------

final RegExp _sellerSentence = RegExp(
  r'\bdisputes?\b|\b(?:bad|negative|neutral|poor)\s+(?:reviews?|feedbacks?|ratings?)\b|\bcontact\s+(?:us|me)\b|\bcustomer\s+service\b|\bdear\s+(?:buyers?|customers?|friends?)\b|^\s*tips?\s*[:：]',
  caseSensitive: false,
);

/// Broken characters and emoji bullets mark where a new sentence starts.
final RegExp _sentenceMark = RegExp(r'�+|[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]️?', unicode: true);
final RegExp _tipsLabel = RegExp(r'\btips?\s*[:：]', caseSensitive: false);
final RegExp _lineSentenceEnd = RegExp(
  r'(?<=[!?।])\s+|(?<=\.)(?!\d)\s*|\u0000+\s*|(?=\btips?\s*[:：])',
  caseSensitive: false,
);

String _decodeEntities(String text) => text
    .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

bool _isDroppedSentence(String sentence) =>
    _sellerSentence.hasMatch(sentence) || mentionsSupplier(sentence);

String _cleanLine(String line) {
  final needs = _sentenceMark.hasMatch(line) || _isDroppedSentence(line) || _tipsLabel.hasMatch(line);
  if (!needs) return line;
  return line
      .replaceAll(_sentenceMark, '\u0000')
      .split(_lineSentenceEnd)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && !_isDroppedSentence(part))
      .join(' ')
      .trim();
}

/// Text shoppers may see: seller boilerplate, supplier/origin sentences and
/// broken characters dropped; HTML entities decoded. Lines with nothing to
/// remove stay exactly as they were (spec lists keep their shape).
String cleanCustomerText(String? text) {
  final out = <String>[];
  for (final line in _decodeEntities(text ?? '').split('\n')) {
    final cleaned = _cleanLine(line);
    if (cleaned.isNotEmpty || line.trim().isEmpty) out.add(cleaned);
  }
  return out.join('\n').trim();
}

/// [cleanCustomerText] for each text run of an HTML description; tags,
/// images and tables stay as they are.
String cleanCustomerHtml(String? html) {
  final wrapped = '>${html ?? ''}<';
  final cleaned = wrapped.replaceAllMapped(_htmlTextNode, (m) {
    final text = m[1]!;
    final joined = text.split('\n').map(_cleanLine).join('\n');
    return joined == text ? m[0]! : '>${joined.trim()}<';
  });
  return cleaned.substring(1, cleaned.length - 1);
}
