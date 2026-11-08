// -----------------------------------------------------------------------------
// Pure category/subcategory name normalization and unique-slug generation.
// No Firestore dependency — fully unit-testable in isolation. Reused
// identically by the category and subcategory resolvers (and any future
// product-type resolver), so the dedup/slug rules never drift between tiers.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

/**
 * Normalizes a name into a stable dedup key: Unicode NFKC-normalize (catches
 * visually-identical but differently-encoded characters — cheap insurance
 * given this store's mixed English/Bangla input), collapse internal
 * whitespace, trim, lowercase. Used ONLY as a lookup key — never displayed.
 *
 * "Electronics", "electronics", " Electronics ", "Electronics  ", "ELECTRONICS"
 * all normalize to the same key.
 */
function normalizeCategoryKey(rawName) {
  const text = textValue(rawName);
  if (!text) return "";
  return text
    .normalize("NFKC")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

/**
 * Converts a name into a URL-safe kebab-case slug base. Does not guarantee
 * uniqueness — see generateUniqueSlug for that.
 */
function slugifyCategoryName(rawName) {
  const text = textValue(rawName);
  if (!text) return "";
  return text
    .normalize("NFKC")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
}

/**
 * Generates a slug guaranteed unique according to `checkTaken(candidate)`
 * (an async function returning true if that slug is already in use). Tries
 * the base slug first, then "-2", "-3", ... up to `maxAttempts`, so
 * "mobile-parts" -> "mobile-parts-2" -> "mobile-parts-3" on collision.
 *
 * Callers running this inside a Firestore transaction should have
 * checkTaken perform `transaction.get(...)` so the whole sequence
 * participates in the transaction's conflict detection/retry.
 */
async function generateUniqueSlug(rawName, checkTaken, options = {}) {
  const maxAttempts = options.maxAttempts || 50;
  const base = slugifyCategoryName(rawName) || "category";

  let candidate = base;
  let suffix = 1;
  while (suffix <= maxAttempts) {
    const taken = await checkTaken(candidate);
    if (!taken) return candidate;
    suffix += 1;
    candidate = `${base}-${suffix}`;
  }
  throw new Error(`generateUniqueSlug: exhausted ${maxAttempts} attempts for base "${base}"`);
}

module.exports = { normalizeCategoryKey, slugifyCategoryName, generateUniqueSlug };
