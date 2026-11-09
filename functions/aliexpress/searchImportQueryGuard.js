// -----------------------------------------------------------------------------
// Server-side validation for aliexpressSearchImport queries. This is defense
// in depth: the client (search_page.dart) already filters before it calls the
// endpoint, but the endpoint is public, and the messaging bot calls it
// server-to-server too.
//
// Rejects strings that are never real product searches but used to reach
// AliExpress anyway:
//   - partial keystrokes ("ht", "htm") — too short
//   - pasted item IDs and their prefixes ("1005", "10050093") — digits only
//   - pasted links and item IDs ("https://www.aliexpress.com/item/...html",
//     "aliexpress/item/1005009353445701")
//   - HTML/code fragments ("html_and_usb", "<div>", "a=1;")
//
// Pure and dependency-free so it can be unit tested directly.
// -----------------------------------------------------------------------------

const MIN_QUERY_LENGTH = 3;
// Shoppers sometimes paste a whole AliExpress title (130-160 chars seen in
// searchImportLog), so this is looser than search_logs' 100-char limit.
const MAX_QUERY_LENGTH = 200;

const URL_RE = /(https?:\/\/|\bwww\.|\b[a-z0-9-]+\.(com|net|org|io|bd|html?|php|aspx?)\b)/i;
// AliExpress item IDs are 12+ digits; no real product search contains one.
const ITEM_ID_RE = /\d{12,}/;
const CODE_CHARS_RE = /[<>{}[\]`$\\|;=]/;
const CODE_WORDS_RE = /\b(https?|www|html?|php|aspx?|javascript|script|onclick|onerror)\b/i;
const HAS_LETTER_RE = /\p{L}/u;

/**
 * Collapses whitespace and trims. Case is preserved because AliExpress gets
 * the query as typed. The searchImportLog dedupe key is lowercased separately
 * by importSafeId in index.js.
 */
function normalizeSearchImportQuery(raw) {
  return String(raw ?? "").replace(/\s+/g, " ").trim();
}

/**
 * @param {unknown} raw
 * @returns {{ ok: true, query: string } | { ok: false, reason: string, query: string }}
 *   reason is one of: TOO_SHORT, TOO_LONG, DIGITS_ONLY, URL, CODE_LIKE, NO_LETTERS
 */
function validateSearchImportQuery(raw) {
  const query = normalizeSearchImportQuery(raw);
  const fail = (reason) => ({ ok: false, reason, query });

  if (query.length < MIN_QUERY_LENGTH) return fail("TOO_SHORT");
  if (query.length > MAX_QUERY_LENGTH) return fail("TOO_LONG");
  if (/^[\d\s.,_-]+$/.test(query)) return fail("DIGITS_ONLY");
  if (URL_RE.test(query) || ITEM_ID_RE.test(query)) return fail("URL");
  // "_" is a regex word character, so swap it for a space before the
  // word-boundary check; otherwise "html_and_usb" would slip through.
  if (CODE_CHARS_RE.test(query) || CODE_WORDS_RE.test(query.replace(/_/g, " "))) return fail("CODE_LIKE");
  if (!HAS_LETTER_RE.test(query)) return fail("NO_LETTERS");

  return { ok: true, query };
}

module.exports = {
  MIN_QUERY_LENGTH,
  MAX_QUERY_LENGTH,
  normalizeSearchImportQuery,
  validateSearchImportQuery,
};
