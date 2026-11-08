// -----------------------------------------------------------------------------
// Confident, non-fuzzy matching between an existing (Firestore) variant and a
// list of freshly-fetched AliExpress variants. Used by the variant-image
// backfill. Never fuzzy/substring/partial-name matches, never matches by
// array index — only exact equality on identity fields, tried in priority
// order, stopping (not falling through) the moment a higher-priority field
// is present but inconclusive, so a weaker signal never papers over a real
// mismatch.
// -----------------------------------------------------------------------------

const MATCH_PRIORITY_FIELDS = ["sourceSkuId", "skuId", "variantId", "id"];

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function cleanVariantNameForMatch(name) {
  return textValue(name).toLowerCase();
}

/**
 * @param {object} existingVariant one entry from the Firestore product's variants[]
 * @param {object[]} freshVariants freshly-fetched AliExpress variants
 * @returns {{ matched: object|null, matchField: string|null, ambiguous: boolean }}
 */
function matchAliExpressVariant(existingVariant, freshVariants) {
  const existing = mapValue(existingVariant);
  const fresh = (Array.isArray(freshVariants) ? freshVariants : []).map(mapValue);

  for (const field of MATCH_PRIORITY_FIELDS) {
    const value = textValue(existing[field]);
    if (!value) continue; // identifier absent on the existing variant — try the next one

    const found = fresh.filter((f) => textValue(f[field]) === value);
    if (found.length === 1) return { matched: found[0], matchField: field, ambiguous: false };
    if (found.length > 1) return { matched: null, matchField: field, ambiguous: true };
    // Present on `existing` but zero matches in fresh data: stop here rather
    // than falling through to a weaker identifier that could mask a real
    // change (e.g. AliExpress genuinely removed/replaced that SKU).
    return { matched: null, matchField: field, ambiguous: false };
  }

  // Final fallback: exact cleaned name, only when unambiguous.
  const existingName = cleanVariantNameForMatch(existing.name || existing.unit || existing.variantName);
  if (existingName) {
    const found = fresh.filter((f) => cleanVariantNameForMatch(f.name) === existingName);
    if (found.length === 1) return { matched: found[0], matchField: "name", ambiguous: false };
    if (found.length > 1) return { matched: null, matchField: "name", ambiguous: true };
  }

  return { matched: null, matchField: null, ambiguous: false };
}

module.exports = { matchAliExpressVariant, cleanVariantNameForMatch, MATCH_PRIORITY_FIELDS };
