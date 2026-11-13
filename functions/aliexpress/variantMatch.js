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

/**
 * Saved (Firestore) variants carry the AliExpress SKU as `sourceSkuId`
 * (set by normalizeMarketplaceVariants at import), while freshly-fetched
 * variants from normalizeAliExpressProduct carry it as `skuId`. Because
 * matchAliExpressVariant stops at the first identifier present on the saved
 * variant, fresh variants must expose the same SKU as `sourceSkuId` or no
 * saved variant ever matches. Returns copies; never mutates the input.
 *
 * @param {object[]} freshVariants
 * @returns {object[]}
 */
function withSourceSkuIds(freshVariants) {
  return (Array.isArray(freshVariants) ? freshVariants : []).map((variant) => {
    const item = mapValue(variant);
    const skuId = textValue(item.skuId);
    return skuId && !textValue(item.sourceSkuId) ? { ...item, sourceSkuId: skuId } : item;
  });
}

function savedVariantName(variant) {
  const item = mapValue(variant);
  return cleanVariantNameForMatch(item.name || item.unit || item.variantName).replace(/\s+/g, " ");
}

function freshVariantName(variant) {
  return cleanVariantNameForMatch(mapValue(variant).name).replace(/\s+/g, " ");
}

/**
 * Picks the fresh AliExpress variant for one saved variant, requiring the
 * SKU and the customer-visible name to AGREE.
 *
 * Why: some n8n imports saved variants whose sourceSkuId belongs to a
 * DIFFERENT AliExpress variant (seen live 2026-11-13: 14 of 17 saved
 * variants on one product, e.g. saved "16 128g No Face" carrying the SKU of
 * "16 Pro 128g No Face"). A SKU-only match would put that other variant's
 * price/stock/image on what the customer sees and picks by name.
 *
 * Outcomes (`how`):
 *   "sku"                - SKU matches and names agree: safe.
 *   "name_sku_mismatch"  - SKU points at a differently-named variant, but
 *                          exactly one fresh variant has the saved name: use it.
 *   "name_sku_changed"   - SKU not on AliExpress any more, exactly one fresh
 *                          variant has the saved name: use it.
 *   "sku_name_mismatch"  - SKU matches a differently-named variant and no
 *                          unique name match: do NOT use (leave untouched).
 *   "ambiguous"          - several candidates: do NOT use.
 *   "not_on_aliexpress"  - neither SKU nor name found: the variant is gone.
 *
 * @param {object} savedVariant
 * @param {object[]} freshVariants (raw; skuId is enough)
 * @returns {{ fresh: object|null, how: string }}
 */
function pickFreshVariantForSaved(savedVariant, freshVariants) {
  const saved = mapValue(savedVariant);
  const fresh = withSourceSkuIds(freshVariants);
  const sku = textValue(saved.sourceSkuId || saved.skuId);
  const name = savedVariantName(saved);

  const skuHits = sku ? fresh.filter((f) => textValue(f.sourceSkuId) === sku) : [];
  const nameHits = name ? fresh.filter((f) => freshVariantName(f) === name) : [];

  if (skuHits.length === 1 && (!name || freshVariantName(skuHits[0]) === name)) {
    return { fresh: skuHits[0], how: "sku" };
  }
  if (skuHits.length > 1) return { fresh: null, how: "ambiguous" };
  if (nameHits.length === 1) {
    return { fresh: nameHits[0], how: skuHits.length ? "name_sku_mismatch" : "name_sku_changed" };
  }
  if (nameHits.length > 1) return { fresh: null, how: "ambiguous" };
  if (skuHits.length === 1) return { fresh: null, how: "sku_name_mismatch" };
  return { fresh: null, how: "not_on_aliexpress" };
}

module.exports = {
  matchAliExpressVariant,
  cleanVariantNameForMatch,
  withSourceSkuIds,
  pickFreshVariantForSaved,
  MATCH_PRIORITY_FIELDS,
};
