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

// -----------------------------------------------------------------------------
// Seller boilerplate in imported descriptions: marketplace rules aimed at
// the seller's own buyers ("do not open a dispute", "leave a bad review",
// "please contact us", "Tips: please check the appearance…"), plus broken
// characters (U+FFFD "��") and HTML entities left as text ("don&#x27;t").
// Removed sentence by sentence at display time; Firestore is not changed.
// -----------------------------------------------------------------------------
const SELLER_SENTENCE = new RegExp([
  // Marketplace rules aimed at the seller's own buyers.
  /\bdisputes?\b|\b(?:bad|negative|neutral|poor)\s+(?:reviews?|feedbacks?|ratings?)\b/,
  /|\bcontact\s+(?:us|me)\b|\bcustomer\s+service\b|\bdear\s+(?:buyers?|customers?|friends?)\b|^\s*tips?\s*[:：]/,
  // The seller speaking as themselves ("send them to me", "our store",
  // "we will handle your issue"): ChalakChar Mart's own policies apply.
  /|\b(?:to|contact|message|tell|ask|inform)\s+me\b|\bme\s+(?:immediately|first|directly)\b|\b(?:my|our)\s+(?:store|shop)\b/,
  /|\bwe\s+will\s+(?:handle|solve|resolve|refund|replace|reship|resend)\b/,
  // Delivery-time claims: imported items follow the delivery date on the
  // product page, not the seller's promise.
  /|\b(?:deliver\w*|ship\w*|dispatch\w*|send\w*|arriv\w*)\b[^.]*?\b\d+(?:\s*(?:-|–|~|to)\s*\d+)?\s*(?:working\s+|business\s+)?(?:days?|hours?|hrs?|weeks?)\b/,
  /|\bafter\s+(?:payment|you\s+pay)\b|\bshipping\s+method\b/,
  // "about 15-45 working days", "7 business days": a span of days is a
  // delivery claim even without a ship word before it.
  /|\b\d+\s*(?:-|–|~|to)\s*\d+\s*(?:working\s+|business\s+)?days?\b|\b\d+\s*(?:working|business)\s+days?\b/,
].map((r) => r.source).join(""), "i");
const BARE_LIST_NUMBER = /^\d{1,2}\.$/;
// Broken characters and emoji bullets mark where a new sentence starts.
const SENTENCE_MARK = /�+|[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]️?/gu;
const LINE_SENTENCE_END = /(?<=[!?।])\s+|(?<=\.)(?!\d)\s*|\u0000+\s*|(?=\btips?\s*[:：])/i;

function decodeEntities(text) {
  return text
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}

function isDroppedSentence(sentence) {
  return SELLER_SENTENCE.test(sentence) || mentionsSupplier(sentence);
}

function lineNeedsCleaning(line) {
  SENTENCE_MARK.lastIndex = 0;
  return SENTENCE_MARK.test(line) || isDroppedSentence(line) || /\btips?\s*[:：]/i.test(line);
}

/**
 * Brackets left half-open by a removed sentence: a ")" with no "(" before
 * it, and empty "( )" pairs, go (with the space in front of them).
 */
function tidyBrackets(text) {
  let depth = 0;
  let out = "";
  for (const ch of text) {
    if (ch === "(") depth++;
    if (ch === ")") {
      if (depth === 0) {
        out = out.replace(/\s+$/, "");
        continue;
      }
      depth--;
    }
    out += ch;
  }
  return out.replace(/\s*\(\s*\)/g, "").replace(/\s{2,}/g, " ").trim();
}

function cleanLine(line) {
  if (!lineNeedsCleaning(line)) return line;
  const parts = line
    .replace(SENTENCE_MARK, "\u0000")
    .split(LINE_SENTENCE_END)
    .map((part) => (part || "").trim())
    .filter(Boolean);
  const dropped = parts.map(isDroppedSentence);
  // A list number ("3.") whose sentence was removed goes with it.
  const kept = parts.filter((part, i) =>
    !dropped[i] && !(BARE_LIST_NUMBER.test(part) && (i + 1 >= parts.length || dropped[i + 1])));
  return tidyBrackets(kept.join(" "));
}

/**
 * Text shoppers may see: seller boilerplate, supplier/origin sentences,
 * broken characters dropped; HTML entities decoded. Lines with nothing to
 * remove stay exactly as they were (spec lists keep their shape).
 */
function cleanCustomerText(text) {
  const lines = decodeEntities(String(text ?? "")).split("\n");
  const out = [];
  for (const line of lines) {
    const cleaned = cleanLine(line);
    if (cleaned || !line.trim()) out.push(cleaned);
  }
  // A removed line leaves no extra gap: at most one blank line in a row.
  return out.join("\n").replace(/\n\s*\n(\s*\n)+/g, "\n\n").trim();
}

/** [cleanCustomerText] for each text run of an HTML description; tags stay. */
function cleanCustomerHtml(html) {
  const wrapped = `>${String(html ?? "")}<`;
  const cleaned = wrapped.replace(/>([^<>]+)</g, (whole, text) => {
    const lines = text.split("\n").map(cleanLine);
    const joined = lines.join("\n");
    return joined === text ? whole : `>${joined.trim()}<`;
  });
  return cleaned.slice(1, -1);
}

module.exports = {
  mentionsSupplier,
  isHiddenSpecification,
  stripSupplierSentences,
  withoutSupplierKeywords,
  cleanCustomerText,
  cleanCustomerHtml,
};
