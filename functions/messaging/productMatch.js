// Product search-intent matching for the omnichannel messaging pipeline.
// Deliberately mirrors lib/pages/user/search_page.dart's _searchScore/_matches
// field-by-field (same weights, same field list) so a chat customer gets the
// same relevance ranking a shopper sees on the in-app search page — this is
// the "reuse existing product search logic" the spec calls for, ported to
// Node since there is no server-side search endpoint to call into directly
// (search_page.dart runs its scoring entirely client-side over a Firestore
// snapshot).

function text(value, fallback = "") {
  const t = String(value ?? "").trim();
  return t.length ? t : fallback;
}

/**
 * Same weighted scoring as SearchPage._searchScore. Returns 0 for a blank
 * query or a product with no signal in common with it.
 */
function scoreProductMatch(product, query) {
  const q = text(query).toLowerCase();
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

  const terms = q.split(/\s+/).filter(Boolean);
  const haystack = [name, generic, manufacturer, brand, category, type, strength, vendorName].join(" ");
  for (const term of terms) {
    if (haystack.includes(term)) score += 5;
  }

  return score;
}

/** Same field list as SearchPage._matches — every query term must appear somewhere. */
function matchesQuery(product, query) {
  const q = text(query).toLowerCase();
  if (!q) return true;

  const terms = q.split(/\s+/).filter(Boolean);
  const haystack = [
    product.name,
    product.generic,
    product.manufacturer,
    product.brand,
    product.category,
    product.type,
    product.strength,
    product.vendorName,
    product.shopName,
    product.overview,
  ]
    .filter((v) => v !== null && v !== undefined)
    .join(" ")
    .toLowerCase();

  return terms.every((term) => haystack.includes(term));
}

/**
 * Ranks `products` (plain data objects, e.g. from Firestore docs already
 * mapped to { id, ...data() }) against `query`, filtering to isActive
 * products with a nonzero score, highest first, capped at `limit`.
 */
function rankProducts(products, query, limit = 5) {
  return (products || [])
    .filter((p) => p && p.isActive !== false && matchesQuery(p, query))
    .map((p) => ({ product: p, score: scoreProductMatch(p, query) }))
    .filter(({ score }) => score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(0, limit))
    .map(({ product }) => product);
}

module.exports = { scoreProductMatch, matchesQuery, rankProducts };
