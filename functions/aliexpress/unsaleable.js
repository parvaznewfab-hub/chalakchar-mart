// -----------------------------------------------------------------------------
// "All SKU Unsaleable" handling for the AliExpress price/stock sync.
//
// aliexpress.ds.product.get answers rsp_code 604 / rsp_msg "All SKU
// Unsaleable" when no variant of a product can currently be bought (verified
// live 2026-11-13). Before this, the sync counted that as a plain failure and
// left the product's stock untouched, so 24 live products kept showing stock
// customers could order but ChalakChar Mart could not buy.
//
// Now:
//   - unsaleable: stock 0 on the product AND on every variant (the app reads
//     the selected variant's own stock), needsReview:true,
//     aliexpressUnsaleable:true. Price and isActive are left alone (AliExpress
//     returned no data to replace them with).
//   - saleable again (only when aliexpressUnsaleable was true): variant stock
//     restored from AliExpress by exact SKU match; unmatched variants stay 0.
//     needsReview stays true and isActive is never touched, so the product
//     stays hidden until an admin publishes it.
//
// Everything here is pure: callers pass the timestamp value to write (e.g.
// FieldValue.serverTimestamp()) so it is unit-testable without Firestore.
// -----------------------------------------------------------------------------

const { pickFreshVariantForSaved, withSourceSkuIds } = require("./variantMatch");

const UNSALEABLE_RSP_CODE = "604";
const UNSALEABLE_MESSAGE_PATTERN = /all\s*sku\s*unsaleable/i;
const MAX_IDS_IN_NOTE = 40;

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function toStock(value) {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/**
 * True only for AliExpress's "All SKU Unsaleable" answer. Requires the
 * message; when AliExpress also sent an rsp_code it must be 604, so a
 * different error that happens to mention the phrase is never treated as one.
 */
function isAliExpressUnsaleableError(error) {
  if (!error) return false;
  const api = error.api && typeof error.api === "object" ? error.api : {};
  const message = `${textValue(error.message)} ${textValue(api.rsp_msg)}`;
  if (!UNSALEABLE_MESSAGE_PATTERN.test(message)) return false;
  const rspCode = textValue(api.rsp_code);
  return !rspCode || rspCode === UNSALEABLE_RSP_CODE;
}

function zeroVariantStock(variants) {
  if (!Array.isArray(variants)) return undefined;
  return variants.map((variant) => (
    variant && typeof variant === "object" ? { ...variant, stock: 0 } : variant
  ));
}

/**
 * Firestore update for a product AliExpress reports as unsaleable.
 *
 * @param {object} productData current product doc data
 * @param {*} now value to write for first-detection time (serverTimestamp)
 * @returns {{ update: object, newlyUnsaleable: boolean }}
 */
function buildUnsaleableUpdate(productData, now) {
  const data = productData || {};
  const newlyUnsaleable = data.aliexpressUnsaleable !== true;
  const update = {
    stock: 0,
    inStock: false,
    needsReview: true,
    aliexpressUnsaleable: true,
  };
  const variants = zeroVariantStock(data.variants);
  if (variants) update.variants = variants;
  if (newlyUnsaleable || !data.aliexpressUnsaleableSince) update.aliexpressUnsaleableSince = now;
  return { update, newlyUnsaleable };
}

/**
 * Restores each saved variant's stock from the fresh AliExpress variants.
 * Saved variants carry `sourceSkuId`; fresh ones carry `skuId` — the fresh
 * side is given a matching `sourceSkuId` so matchAliExpressVariant (which
 * stops at the first identifier present on the saved variant) can match.
 * Only `stock` is changed on each variant; every other field (hand-edited
 * names, prices, images) is preserved.
 *
 * @returns {{ variants: object[], matched: number, unmatched: number }}
 */
function restoreVariantStock(savedVariants, freshVariants) {
  const fresh = withSourceSkuIds(freshVariants);

  let matched = 0;
  let unmatched = 0;
  const variants = (Array.isArray(savedVariants) ? savedVariants : []).map((variant) => {
    if (!variant || typeof variant !== "object") return variant;
    // SKU and name must agree (some imports saved another variant's SKU).
    const pick = pickFreshVariantForSaved(variant, fresh);
    if (pick.fresh) {
      matched += 1;
      return { ...variant, stock: toStock(pick.fresh.stock) };
    }
    unmatched += 1;
    return { ...variant, stock: 0 };
  });
  return { variants, matched, unmatched };
}

/**
 * Extra fields for a successful sync of a product previously marked
 * unsaleable. Returns null when the product wasn't flagged (normal sync).
 * Product-level stock is set to the sum of the restored variants so it never
 * claims more stock than customers can actually pick.
 *
 * @returns {{ update: object, matched: number, unmatched: number } | null}
 */
function buildSaleableAgainUpdate(productData, freshVariants, now) {
  const data = productData || {};
  if (data.aliexpressUnsaleable !== true) return null;

  const update = {
    aliexpressUnsaleable: false,
    aliexpressSaleableAgainAt: now,
    needsReview: true,
  };

  if (Array.isArray(data.variants) && data.variants.length) {
    const restored = restoreVariantStock(data.variants, freshVariants);
    const total = restored.variants.reduce((sum, v) => sum + toStock(v?.stock), 0);
    update.variants = restored.variants;
    update.stock = total;
    update.inStock = total > 0;
    return { update, matched: restored.matched, unmatched: restored.unmatched };
  }

  return { update, matched: 0, unmatched: 0 };
}

function formatNames(items, max) {
  const names = items.slice(0, max).map((p) => `${textValue(p.name, p.productId).slice(0, 50)} (${p.sourceProductId})`);
  const more = items.length > max ? `, +${items.length - max} more` : "";
  return names.join("; ") + more;
}

/**
 * One admin note per sync run, only when something changed state.
 *
 * @param {{ productId: string, sourceProductId: string, name: string }[]} newlyUnsaleable
 * @param {{ productId: string, sourceProductId: string, name: string }[]} saleableAgain
 * @returns {{ kind: string, title: string, body: string, data: object } | null}
 */
function buildUnsaleableChangeNote(newlyUnsaleable, saleableAgain, maxNames = 10) {
  const down = Array.isArray(newlyUnsaleable) ? newlyUnsaleable : [];
  const up = Array.isArray(saleableAgain) ? saleableAgain : [];
  if (!down.length && !up.length) return null;

  const parts = [];
  if (down.length) {
    parts.push(`${down.length} product${down.length === 1 ? "" : "s"} became unsaleable on AliExpress — stock set to 0, marked for review: ${formatNames(down, maxNames)}.`);
  }
  if (up.length) {
    parts.push(`${up.length} product${up.length === 1 ? " is" : "s are"} saleable again — stock restored, publish status unchanged, still marked for review: ${formatNames(up, maxNames)}.`);
  }

  return {
    kind: "unsaleable_changes",
    title: "AliExpress availability changed 📦",
    body: parts.join(" "),
    data: {
      newlyUnsaleableCount: down.length,
      saleableAgainCount: up.length,
      // Capped: these also ride along as FCM data (4KB payload limit).
      newlyUnsaleableIds: down.slice(0, MAX_IDS_IN_NOTE).map((p) => p.productId).join(","),
      saleableAgainIds: up.slice(0, MAX_IDS_IN_NOTE).map((p) => p.productId).join(","),
    },
  };
}

module.exports = {
  UNSALEABLE_RSP_CODE,
  isAliExpressUnsaleableError,
  buildUnsaleableUpdate,
  restoreVariantStock,
  buildSaleableAgainUpdate,
  buildUnsaleableChangeNote,
};
