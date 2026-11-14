// -----------------------------------------------------------------------------
// Which variant a product's top-level price/mrp/unit describe.
//
// variants[] keeps AliExpress's SKU order, which is arbitrary (seen live: a
// 4TB SSD first, so the card said ৳47,546 while the 128GB default sold for
// ৳2,851). The product-level price is what cards, search, price sort,
// sitemap/SEO and the chat bot show, so it must be the "from" price: the
// cheapest variant that is in stock, or the cheapest priced variant when
// nothing is in stock. variants[] itself (and its order) is never changed,
// and the cart always charges the selected variant's own price.
//
// Mirrored in Dart: ProductService.displayVariant (lib/services/product_service.dart).
// Pure: no Firestore.
// -----------------------------------------------------------------------------

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function variantPrice(variant) {
  return num(variant?.price ?? variant?.piecePrice);
}

function variantMrp(variant) {
  return num(variant?.mrp ?? variant?.oldPrice);
}

/**
 * Index of the display variant in [variants], or -1 when no variant has a
 * price. Ties keep the earlier variant.
 */
function pickDisplayVariantIndex(variants) {
  const list = Array.isArray(variants) ? variants : [];
  let best = -1;
  let bestInStock = false;
  list.forEach((variant, index) => {
    if (!isObject(variant)) return;
    const price = variantPrice(variant);
    if (price <= 0) return;
    const inStock = num(variant.stock) > 0;
    if (best === -1) {
      best = index;
      bestInStock = inStock;
      return;
    }
    if (inStock && !bestInStock) {
      best = index;
      bestInStock = true;
      return;
    }
    if (inStock === bestInStock && price < variantPrice(list[best])) best = index;
  });
  return best;
}

function pickDisplayVariant(variants) {
  const index = pickDisplayVariantIndex(variants);
  return index >= 0 ? variants[index] : null;
}

/** True when the priced variants don't all cost the same ("৳X থেকে"). */
function hasPriceRange(variants) {
  const prices = new Set(
    (Array.isArray(variants) ? variants : [])
      .filter(isObject)
      .map(variantPrice)
      .filter((p) => p > 0)
  );
  return prices.size > 1;
}

/**
 * Product-level price fields for [variants]; null when no variant is priced
 * (callers then keep whatever they had). mrp is never below price.
 */
function displayPriceFields(variants) {
  const variant = pickDisplayVariant(variants);
  if (!variant) return null;
  const price = variantPrice(variant);
  const mrp = Math.max(price, variantMrp(variant));
  const fields = { price, piecePrice: price, oldPrice: mrp, mrp };
  const unit = String(variant.name ?? variant.unit ?? "").trim();
  if (unit) fields.unit = unit;
  return fields;
}

/** Display price of a product doc: its variants' rule, else the stored price. */
function productDisplayPrice(product) {
  const variant = pickDisplayVariant(product?.variants);
  if (variant) return variantPrice(variant);
  return num(product?.price || product?.piecePrice);
}

/** MRP that belongs to productDisplayPrice (never below it). */
function productDisplayMrp(product) {
  const variant = pickDisplayVariant(product?.variants);
  if (variant) return Math.max(variantPrice(variant), variantMrp(variant));
  return num(product?.oldPrice || product?.mrp);
}

module.exports = {
  pickDisplayVariantIndex,
  pickDisplayVariant,
  hasPriceRange,
  displayPriceFields,
  productDisplayPrice,
  productDisplayMrp,
};
