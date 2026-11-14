// -----------------------------------------------------------------------------
// Should a product write send the wishlist "discount" message?
//
// The product-level price moved from variants[0] to the display variant
// (cheapest in stock — catalog/displayPrice.js), and backfillDisplayPrice.js
// rewrites it for existing products (Netac SSD: ৳47,546 -> ৳2,851). Neither
// is a real price drop, so:
//   - before AND after are both computed with the same display-price helper
//     from each side's own variants — never from the stored top-level price;
//   - a write stamped by the backfill (a new priceBackfillAt) sends nothing
//     at all (onProductStockUpdated returns early, see isPriceBackfillWrite).
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

const { productDisplayPrice, productDisplayMrp } = require("../catalog/displayPrice");

const PRICE_BACKFILL_FIELD = "priceBackfillAt";
const PRICE_BACKFILL_SOURCE = "price_backfill";
const MIN_DISCOUNT_TO_ANNOUNCE = 5;

function timestampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** Whole-number discount of the display price against its own MRP (0 if none). */
function displayDiscountPercent(product) {
  const price = productDisplayPrice(product);
  const mrp = productDisplayMrp(product);
  if (price <= 0 || mrp <= price) return 0;
  return Math.round(((mrp - price) / mrp) * 100);
}

/**
 * True when THIS write is a price backfill: it sets a new priceBackfillAt
 * stamp. Later writes (sync, admin) leave the stamp unchanged, so they are
 * never mistaken for a backfill.
 */
function isPriceBackfillWrite(before, after) {
  const afterMs = timestampMs(after?.[PRICE_BACKFILL_FIELD]);
  return afterMs > 0 && afterMs !== timestampMs(before?.[PRICE_BACKFILL_FIELD]);
}

/**
 * @returns {{ notify: boolean, beforeDiscount: number, afterDiscount: number, reason: string }}
 */
function wishlistDiscountDecision(before, after) {
  if (isPriceBackfillWrite(before, after)) {
    return { notify: false, beforeDiscount: 0, afterDiscount: 0, reason: "price_backfill" };
  }
  const beforeDiscount = displayDiscountPercent(before);
  const afterDiscount = displayDiscountPercent(after);
  const notify = afterDiscount >= MIN_DISCOUNT_TO_ANNOUNCE && afterDiscount > beforeDiscount;
  return { notify, beforeDiscount, afterDiscount, reason: notify ? "discount_increased" : "no_new_discount" };
}

module.exports = {
  PRICE_BACKFILL_FIELD,
  PRICE_BACKFILL_SOURCE,
  displayDiscountPercent,
  isPriceBackfillWrite,
  wishlistDiscountDecision,
};
