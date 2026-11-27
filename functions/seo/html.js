// -----------------------------------------------------------------------------
// HTML text helpers for the server-rendered SEO pages (functions/seo/*).
//
// Firestore text can already hold HTML entities (imported titles such as
// `6.6&quot; LCD` or `A &amp; B`). Every helper here decodes first and then
// escapes exactly once, so the page never shows "&amp;quot;" and never shows
// a raw entity either.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

function decodeEntities(value) {
  return String(value ?? "")
    .replace(/&#x([0-9a-f]+);/gi, (m, h) => safeCodePoint(parseInt(h, 16), m))
    .replace(/&#(\d+);/g, (m, d) => safeCodePoint(Number(d), m))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function safeCodePoint(n, fallback) {
  try {
    return String.fromCodePoint(n);
  } catch (_) {
    return fallback;
  }
}

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function compactWhitespace(value) {
  return cleanText(value).replace(/\s+/g, " ").trim();
}

/** Plain text of [value]: entities decoded, tags removed, spaces collapsed. */
function plainText(value) {
  return compactWhitespace(decodeEntities(String(value ?? "").replace(/<[^>]*>/g, " ")));
}

// Same rule as lib/services/seo_titles.dart SeoTitles.limitText
// (test/seo_titles_parity_test.dart reads these lines).
function limitText(value, max) {
  const text = compactWhitespace(value);
  if (text.length <= max) return text;
  return `${text.slice(0, Math.max(0, max - 3)).trim()}...`;
}

/** Text content (between tags): decoded, then & < > escaped once. */
function escText(value) {
  return decodeEntities(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Attribute value inside double quotes: decoded, then escaped once. */
function escAttr(value) {
  return escText(value)
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** JSON-LD body safe inside <script>. Values are plain (decoded) text. */
function jsonLd(obj) {
  return JSON.stringify(obj)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026");
}

/** Category URL slug: same rule as the app (CategoryService.slugOf). */
function seoSlug(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/** "৳1,250" (whole taka, as the app shows prices). */
function taka(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n) || n <= 0) return "";
  return `৳${Math.round(n).toLocaleString("en-US")}`;
}

module.exports = {
  decodeEntities,
  cleanText,
  compactWhitespace,
  plainText,
  limitText,
  escText,
  escAttr,
  jsonLd,
  seoSlug,
  taka,
};
