// Product search-intent matching for the omnichannel messaging pipeline.
// Scoring weights follow lib/pages/user/search_page.dart's _searchScore so a
// chat customer gets roughly the ranking a shopper sees on the search page.
//
// Unlike the search box, a chat message is a sentence ("Netac SSD 128GB
// price?", "১২৮ জিবি এসএসডির দাম কত?"), so it is first reduced to search
// terms by queryNormalize.js (Bangla digits/words -> English, question words
// dropped). Every remaining term must then match the product: as the start
// of one of its words ("128" matches "128GB"), or anywhere for terms of 4+
// characters. Short words like "hi" must be a whole word, so chit-chat
// doesn't match half the catalog.

const { normalizeChatQuery } = require("./queryNormalize");

function text(value, fallback = "") {
  const t = String(value ?? "").trim();
  return t.length ? t : fallback;
}

function listText(value) {
  return Array.isArray(value) ? value.map((v) => text(v)).join(" ") : text(value);
}

function haystackOf(product) {
  return [
    product.name,
    product.banglaTitle,
    product.generic,
    product.manufacturer,
    product.brand,
    product.category,
    product.subcategory,
    product.type,
    product.strength,
    product.vendorName,
    product.shopName,
    listText(product.searchKeywords),
    listText(product.seoTags),
    product.overview,
  ]
    .filter((v) => v !== null && v !== undefined)
    .join(" ")
    .toLowerCase();
}

function wordsOf(haystack) {
  return haystack.split(/[^\p{L}\p{M}\p{N}.]+/u).filter(Boolean);
}

function termMatches(term, haystack, words) {
  // 1-2 letter words ("hi", "ok") must be a whole word; numbers may prefix ("12" -> "12pro").
  if (term.length <= 2 && !/^\d/.test(term)) return words.includes(term);
  if (words.some((w) => w.startsWith(term))) return true;
  return term.length >= 4 && haystack.includes(term);
}

/**
 * Weighted relevance (same weights as SearchPage._searchScore), computed on
 * the normalized query. 0 for a blank query or no signal in common.
 */
function scoreProductMatch(product, query) {
  const terms = normalizeChatQuery(query);
  const q = terms.join(" ");
  if (!q) return 0;

  const name = text(product.name).toLowerCase();
  const generic = text(product.generic).toLowerCase();
  const manufacturer = text(product.manufacturer).toLowerCase();
  const brand = text(product.brand).toLowerCase();
  const category = text(product.category).toLowerCase();
  const type = text(product.type).toLowerCase();
  const strength = text(product.strength).toLowerCase();
  const vendorName = text(product.vendorName ?? product.shopName).toLowerCase();

  let score = 0;
  if (name === q) score += 100;
  if (name.startsWith(q)) score += 60;
  if (name.includes(q)) score += 40;
  if (generic.includes(q)) score += 30;
  if (manufacturer.includes(q)) score += 20;
  if (brand.includes(q)) score += 20;
  if (category.includes(q)) score += 15;
  if (type.includes(q)) score += 10;
  if (strength.includes(q)) score += 10;
  if (vendorName.includes(q)) score += 8;

  const haystack = [name, generic, manufacturer, brand, category, type, strength, vendorName].join(" ");
  const words = wordsOf(haystack);
  for (const term of terms) {
    if (termMatches(term, haystack, words)) score += 5;
    // A term in the product's own name counts more than one in its category.
    if (wordsOf(name).some((w) => w.startsWith(term))) score += 5;
  }

  return score;
}

/** Every normalized query term must match the product somewhere. */
function matchesQuery(product, query) {
  const terms = normalizeChatQuery(query);
  if (!terms.length) return true;
  const haystack = haystackOf(product);
  const words = wordsOf(haystack);
  return terms.every((term) => termMatches(term, haystack, words));
}

/** Only what a shopper could actually open and buy. */
function isSellable(product) {
  if (!product || product.isActive === false) return false;
  if (product.isVisible === false || product.isPublished === false) return false;
  const status = text(product.approvalStatus);
  return !status || status === "approved";
}

/**
 * Ranks `products` (plain data objects, e.g. Firestore docs mapped to
 * { id, ...data() }) against `query`: sellable products that match with a
 * nonzero score, highest first, capped at `limit`.
 */
function rankProducts(products, query, limit = 5) {
  return (products || [])
    .filter((p) => isSellable(p) && matchesQuery(p, query))
    .map((p) => ({ product: p, score: scoreProductMatch(p, query) }))
    .filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(0, limit))
    .map(({ product }) => product);
}

/** How many of [terms] match [text], and whether a word (not just a number) did. */
function termCoverage(terms, text) {
  const haystack = String(text ?? "").toLowerCase();
  const words = wordsOf(haystack);
  let matched = 0;
  let wordMatched = false;
  for (const term of terms) {
    if (termMatches(term, haystack, words)) {
      matched += 1;
      if (!/^\d+(?:\.\d+)?$/.test(term)) wordMatched = true;
    }
  }
  return { matched, total: terms.length, wordMatched };
}

const RELEVANT_SHARE = 0.6;
const PARTIAL_SHARE = 0.5;

/**
 * Is an AliExpress search result titled [title] about [query]? At least 60%
 * of the query's product terms must match the title, one of them a word.
 * ("Netac SSD 128GB" vs "Medieval PU Leather Belt..." -> 0/3 -> no.)
 */
function isRelevantTitle(query, title) {
  const terms = normalizeChatQuery(query);
  if (!terms.length) return false;
  const { matched, total, wordMatched } = termCoverage(terms, title);
  return wordMatched && matched / total >= RELEVANT_SHARE;
}

/**
 * True when the catalog already has something close to [query] (half its
 * terms, one of them a word) even if nothing matched fully. The AliExpress
 * search-miss import must not run then: the shop sells that kind of thing.
 */
function hasPartialCatalogMatch(products, query) {
  const terms = normalizeChatQuery(query);
  if (!terms.length) return false;
  return (products || []).some((p) => {
    if (!isSellable(p)) return false;
    const { matched, total, wordMatched } = termCoverage(terms, haystackOf(p));
    return wordMatched && matched / total >= PARTIAL_SHARE;
  });
}

module.exports = {
  scoreProductMatch,
  matchesQuery,
  rankProducts,
  isSellable,
  isRelevantTitle,
  hasPartialCatalogMatch,
};
