// -----------------------------------------------------------------------------
// Per-variant price/stock refresh for the AliExpress sync.
//
// Before this, the sync refreshed only product-level fields, and got them
// from AliExpress's view of the product rather than the variants the store
// actually sells:
//   - price/oldPrice came from AliExpress's FIRST SKU, which may not be one of
//     the saved variants (seen live: product ৳29,691 while every saved
//     variant sold for ৳5,214–7,033);
//   - stock was the sum of ALL AliExpress SKUs, not just the saved ones;
//   - variants[].price/stock were never refreshed after import, even though
//     the app charges and stock-checks the selected variant.
//
// Now, unless the product opts out with variantSyncEnabled:false:
//   - each saved variant is matched to AliExpress by SKU AND name agreeing
//     (pickFreshVariantForSaved — some imports saved the wrong SKU on a
//     variant), and gets fresh stock and
//     price/piecePrice/mrp/oldPrice computed with the SAME price rule the
//     import used (caller passes priceFor);
//   - a saved variant AliExpress no longer returns gets stock 0 (price kept);
//   - a saved variant that can't be identified safely (SKU and name point at
//     different AliExpress variants, or ambiguous) is left exactly as is and
//     reported as "unresolved";
//   - every other variant field (name, image, order, ...) is preserved;
//   - product stock = sum of saved variants, product price/oldPrice = the
//     first saved variant's.
//
// Pure: no Firestore, no AliExpress calls.
// -----------------------------------------------------------------------------

const { pickFreshVariantForSaved, withSourceSkuIds } = require("./variantMatch");

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function toStock(value) {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

/** Default true: only an explicit false opts a product out. */
function isVariantSyncEnabled(productData) {
  return productData?.variantSyncEnabled !== false;
}

function variantMrp(variant) {
  return num(variant?.mrp ?? variant?.oldPrice);
}

/**
 * @param {object[]} savedVariants product.variants from Firestore
 * @param {object[]} freshVariants normalizeAliExpressProduct(...).variants
 * @param {(fresh: object) => { price: number, mrp: number }} priceFor BDT prices
 *   for one fresh variant, using the import's price rule
 * @returns {{ variants: object[], changes: object[], matched: number,
 *             unmatched: number, missing: object[], firstFresh: object|null }}
 */
function refreshSavedVariants(savedVariants, freshVariants, priceFor) {
  const fresh = withSourceSkuIds(freshVariants);
  const changes = [];
  const missing = [];
  const unresolved = [];
  const matchedBy = {};
  let matched = 0;
  let unmatched = 0;
  let firstFresh = null;

  const variants = (Array.isArray(savedVariants) ? savedVariants : []).map((variant, index) => {
    if (!isObject(variant)) return variant;
    const name = textValue(variant.name || variant.unit || variant.variantName, `Variant ${index + 1}`);
    const sourceSkuId = textValue(variant.sourceSkuId || variant.skuId);
    // SKU and name must agree — see pickFreshVariantForSaved for why.
    const pick = pickFreshVariantForSaved(variant, fresh);

    let next;
    const isMatched = Boolean(pick.fresh);
    if (isMatched) {
      matched += 1;
      matchedBy[pick.how] = (matchedBy[pick.how] || 0) + 1;
      if (index === 0) firstFresh = pick.fresh;
      const priced = priceFor(pick.fresh) || {};
      const price = num(priced.price);
      next = { ...variant, stock: toStock(pick.fresh.stock) };
      // A zero/invalid price from AliExpress never overwrites a real one.
      if (price > 0) {
        const mrp = Math.max(price, num(priced.mrp));
        Object.assign(next, { price, piecePrice: price, mrp, oldPrice: mrp });
      }
    } else if (pick.how === "not_on_aliexpress") {
      // Neither the SKU nor the name exists on AliExpress: the variant is gone.
      unmatched += 1;
      missing.push({ index, name, sourceSkuId, reason: pick.how });
      next = { ...variant, stock: 0 };
    } else {
      // SKU/name disagree with no safe alternative, or ambiguous: we can't
      // tell which AliExpress variant this is, so leave it exactly as is.
      unmatched += 1;
      unresolved.push({ index, name, sourceSkuId, reason: pick.how });
      next = variant;
    }

    const oldPrice = num(variant.price);
    const newPrice = num(next.price);
    const oldMrp = variantMrp(variant);
    const newMrp = variantMrp(next);
    const oldStock = toStock(variant.stock);
    const newStock = toStock(next.stock);
    if (oldPrice !== newPrice || oldMrp !== newMrp || oldStock !== newStock) {
      changes.push({ index, name, sourceSkuId, oldPrice, newPrice, oldMrp, newMrp, oldStock, newStock, matched: isMatched });
    }
    return next;
  });

  return { variants, changes, matched, unmatched, missing, unresolved, matchedBy, firstFresh };
}

/**
 * Product-level fields from the (refreshed) saved variants: stock = sum,
 * price/oldPrice = first saved variant.
 */
function deriveProductFromVariants(variants) {
  const list = (Array.isArray(variants) ? variants : []).filter(isObject);
  if (!list.length) return null;
  const stock = list.reduce((sum, v) => sum + toStock(v.stock), 0);
  const fields = { stock, inStock: stock > 0 };
  const price = num(list[0].price);
  if (price > 0) {
    fields.price = price;
    fields.oldPrice = Math.max(price, variantMrp(list[0]));
  }
  return fields;
}

/**
 * Everything the sync merges into its product update for the variant
 * refresh. Returns null when the product opted out or has no saved variants
 * (the sync then behaves exactly as before for that product).
 *
 * originalPrice/originalMrp (the USD inputs) follow the AliExpress SKU behind
 * the first saved variant; if that SKU is gone they are omitted so the old
 * values are kept rather than replaced by an unrelated SKU's price.
 */
function buildVariantRefreshUpdate(productData, freshVariants, priceFor) {
  const data = productData || {};
  if (!isVariantSyncEnabled(data)) return null;
  if (!Array.isArray(data.variants) || !data.variants.some(isObject)) return null;

  const refreshed = refreshSavedVariants(data.variants, freshVariants, priceFor);
  const update = { variants: refreshed.variants, ...deriveProductFromVariants(refreshed.variants) };
  const omit = [];
  if (refreshed.firstFresh) {
    update.originalPrice = num(refreshed.firstFresh.price);
    update.originalMrp = num(refreshed.firstFresh.mrp ?? refreshed.firstFresh.price);
  } else {
    omit.push("originalPrice", "originalMrp");
  }

  return {
    update,
    omit,
    changes: refreshed.changes,
    matched: refreshed.matched,
    unmatched: refreshed.unmatched,
    missing: refreshed.missing,
    unresolved: refreshed.unresolved,
    matchedBy: refreshed.matchedBy,
  };
}

// ---- one-shot wishlist-discount suppression ---------------------------------

const SYNC_MARKETING_SUPPRESSED_FIELD = "syncDiscountMarketingSuppressedAt";

function timestampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/**
 * True when THIS write (before -> after) is a sync write that asked for
 * discount marketing to be suppressed: the sync stamps
 * syncDiscountMarketingSuppressedAt with a fresh server timestamp on each
 * suppressed write, so a later admin edit (which leaves the stamp unchanged)
 * is never suppressed.
 */
function isSyncDiscountMarketingSuppressed(before, after) {
  const afterMs = timestampMs(after?.[SYNC_MARKETING_SUPPRESSED_FIELD]);
  return afterMs > 0 && afterMs !== timestampMs(before?.[SYNC_MARKETING_SUPPRESSED_FIELD]);
}

module.exports = {
  SYNC_MARKETING_SUPPRESSED_FIELD,
  isVariantSyncEnabled,
  refreshSavedVariants,
  deriveProductFromVariants,
  buildVariantRefreshUpdate,
  isSyncDiscountMarketingSuppressed,
};
