// -----------------------------------------------------------------------------
// Keeps supplier / origin wording out of customer-facing text (SEO pages,
// keywords, imported product fields). JS mirror of lib/utils/customer_text.dart
// — change both together.
//
// Imported products carry the marketplace seller's text ("we mainly ship via
// AliExpress standard shipping", "items cannot be tracked after they leave
// China") and an "Origin: Mainland China" spec; ChalakChar Mart never names
// its supplier or the origin country to shoppers.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

const SUPPLIER_WORDS = /ali\s*express|\bchina\b|\bchinese\b|cainiao|\btaobao\b|\b1688\b|চীন/i;
const ORIGIN_SPEC_NAMES = /^\s*(origin|place\s+of\s+origin|country\s+of\s+origin|ships?\s+from|ship\s+from|origin\s+country)\s*$/i;
// Sentence ends: . ! ? । and line breaks (keeps "2.5" intact).
const SENTENCE_END = /(?<=[!?।])\s+|(?<=\.)(?!\d)\s*|\n+/;

function mentionsSupplier(text) {
  return SUPPLIER_WORDS.test(String(text ?? ""));
}

function isHiddenSpecification(name, value) {
  return ORIGIN_SPEC_NAMES.test(String(name ?? "")) || mentionsSupplier(name) || mentionsSupplier(value);
}

/** Drops every sentence that mentions the supplier or origin country. */
function stripSupplierSentences(text) {
  const s = String(text ?? "");
  if (!mentionsSupplier(s)) return s;
  return s
    .split(SENTENCE_END)
    .map((part) => (part || "").trim())
    .filter((part) => part && !mentionsSupplier(part))
    .join(" ")
    .trim();
}

/** Keyword lists without supplier names ("aliexpress", "china"). */
function withoutSupplierKeywords(list) {
  return (Array.isArray(list) ? list : []).filter((k) => !mentionsSupplier(k));
}

module.exports = { mentionsSupplier, isHiddenSpecification, stripSupplierSentences, withoutSupplierKeywords };
