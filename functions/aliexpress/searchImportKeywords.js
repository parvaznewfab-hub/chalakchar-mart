// -----------------------------------------------------------------------------
// AliExpress keywords for a shopper's search-box query.
//
// AliExpress only understands English: any Bangla text returned unrelated
// junk (medieval costumes) that the relevance filter then had to drop. A
// query with Bangla script is turned into English product words with the
// chat's normalizeChatQuery ("১২৮ জিবি এসএসডির দাম কত?" -> "128gb ssd");
// Bangla words it can't translate are dropped. If no English word with a
// letter is left ("ভালো জুতা"), there is nothing worth sending: null.
// English queries are returned unchanged (existing behaviour).
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

const { normalizeChatQuery } = require("../messaging/queryNormalize");

const BANGLA_RE = /[ঀ-৿]/;
const LATIN_LETTER_RE = /[a-z]/i;

/** @returns {string|null} keywords to send to AliExpress, or null to skip the import. */
function searchImportKeywords(query) {
  const q = String(query ?? "").trim();
  if (!q) return null;
  if (!BANGLA_RE.test(q)) return q;
  const terms = normalizeChatQuery(q).filter((t) => !BANGLA_RE.test(t));
  if (!terms.some((t) => LATIN_LETTER_RE.test(t))) return null;
  return terms.join(" ");
}

module.exports = { searchImportKeywords };
