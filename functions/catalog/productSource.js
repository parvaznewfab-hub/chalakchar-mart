"use strict";
// -----------------------------------------------------------------------------
// Supplier/cost data lives in an admin-only record, never on the public
// product.
//
// products/{id} is readable by anyone (the shop reads it straight from
// Firestore). Everything that names or prices the supplier — AliExpress ids
// and links, the original price/currency, exchange rate, markup, freight,
// import/sync bookkeeping, each variant's sourceSkuId — is kept in
// product_sources/{id} instead (firestore.rules: admin only; Cloud Functions
// bypass rules).
//
// Server code works on a merged view (product + source record, variants with
// their sourceSkuId put back) and writes through splitProductWrite(), so the
// sync/unsaleable/variant-refresh logic itself did not change.
//
// Imports: product_import_keys/{sha256(source:sourceProductId)} -> productId
// is the dedupe key. New imports get a neutral random doc id; the 107 older
// imp_aliexpress_* ids are kept (carts, orders, reviews and marketing point
// at them) and get their key from scripts/migrateProductSources.js.
//
// Orders: order_sources/{orderId} holds each item's sourcing, written by
// onNewOrderCreated. The customer's own order no longer carries it.
// -----------------------------------------------------------------------------

const crypto = require("crypto");

const PRODUCT_SOURCES = "product_sources";
const PRODUCT_IMPORT_KEYS = "product_import_keys";
const ORDER_SOURCES = "order_sources";

// Top-level product fields that are supplier, cost or import/sync internals.
// firestore.rules (privateSourceFields) keeps the same list.
const PRIVATE_SOURCE_FIELDS = Object.freeze([
  "source",
  "sourceProductId",
  "sourceUrl",
  "sourceStoreId",
  "sourceStoreName",
  "sourceSkuCount",
  "syncEnabled",
  "importType",
  "importedBy",
  "importedAt",
  "importRevision",
  "importAiEnabled",
  "importSeoEnabled",
  "importMarketingEnabled",
  "originalCurrency",
  "originalPrice",
  "originalMrp",
  "exchangeRate",
  "markupPercent",
  "shippingCostOriginal",
  "shippingCostCurrency",
  "shippingCostBDT",
  "deliveryFreightAmount",
  "deliveryFreightCurrency",
  "deliveryServiceName",
  "deliverySource",
  "deliverySourceField",
  "deliverySyncStatus",
  "deliveryLastSyncedAt",
  "deliveryTrackingAvailable",
  "lastSyncedAt",
  "lastPriceSyncAt",
  "lastStockSyncAt",
  "aliexpressUnsaleable",
  "aliexpressUnsaleableSince",
  "categoryResolutionMethod",
  "cleanupNote",
  "variantSkuRepairedAt",
  "variantAttributeBackfilledAt",
]);
const PRIVATE_SET = new Set(PRIVATE_SOURCE_FIELDS);

// Per-variant fields kept in product_sources.variantSkus[variantKey].
const PRIVATE_VARIANT_FIELDS = Object.freeze(["sourceSkuId"]);

// Order item fields that name the supplier (older app builds wrote them).
const PRIVATE_ORDER_ITEM_FIELDS = Object.freeze(["source", "sourceProductId", "aliExpressLink", "sourceSkuId", "sourceUrl"]);

function text(value) {
  return value == null ? "" : String(value).trim();
}

function isPlainObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

/** The key a variant's private fields are stored under. */
function variantKey(variant, index) {
  return text(variant?.variantId || variant?.id) || `idx_${index}`;
}

/**
 * Splits a product write into what may go on the public product and what goes
 * into product_sources. [data] may be a full product or a partial update
 * (dotted paths are left public unless their root is private).
 * Returns { publicData, privateData } — privateData is {} when nothing private.
 * variants: each sourceSkuId moves to privateData.variantSkus; the map is only
 * written when at least one variant carried one (an admin save of variants
 * without SKUs never wipes them).
 */
function splitProductWrite(data) {
  const publicData = {};
  const privateData = {};
  for (const [key, value] of Object.entries(data || {})) {
    const root = key.split(".")[0];
    if (PRIVATE_SET.has(root)) privateData[key] = value;
    else publicData[key] = value;
  }

  if (Array.isArray(publicData.variants)) {
    const skus = {};
    publicData.variants = publicData.variants.map((variant, index) => {
      if (!isPlainObject(variant)) return variant;
      const copy = { ...variant };
      const hidden = {};
      for (const field of PRIVATE_VARIANT_FIELDS) {
        if (field in copy) {
          if (text(copy[field])) hidden[field] = copy[field];
          delete copy[field];
        }
      }
      if (Object.keys(hidden).length) skus[variantKey(variant, index)] = hidden;
      return copy;
    });
    if (Object.keys(skus).length) privateData.variantSkus = skus;
  }
  return { publicData, privateData };
}

/**
 * The server's view of a product: public fields + its source record, with
 * each variant's sourceSkuId put back. Works before the migration too (the
 * private fields are then still on the product; the source record wins).
 */
function mergeProductWithSource(productData, sourceData) {
  const product = { ...(productData || {}) };
  const source = { ...(sourceData || {}) };
  const variantSkus = isPlainObject(source.variantSkus) ? source.variantSkus : {};
  delete source.variantSkus;
  delete source.productId;
  delete source.migratedAt;
  delete source.updatedAt;
  const merged = { ...product, ...source };
  if (Array.isArray(product.variants)) {
    merged.variants = product.variants.map((variant, index) => {
      if (!isPlainObject(variant)) return variant;
      const hidden = variantSkus[variantKey(variant, index)];
      if (!isPlainObject(hidden)) return variant;
      const out = { ...variant };
      for (const field of PRIVATE_VARIANT_FIELDS) {
        if (!text(out[field]) && text(hidden[field])) out[field] = hidden[field];
      }
      return out;
    });
  }
  return merged;
}

/** Field names of [productData] that must not be public (for checks/migration). */
function privateFieldsOn(productData) {
  const found = Object.keys(productData || {}).filter((k) => PRIVATE_SET.has(k));
  const variants = Array.isArray(productData?.variants) ? productData.variants : [];
  if (variants.some((v) => isPlainObject(v) && PRIVATE_VARIANT_FIELDS.some((f) => f in v))) found.push("variants[].sourceSkuId");
  return found;
}

/** Dedupe key doc id for an imported product: same digest the old doc ids used. */
function importKeyId(source, sourceProductId) {
  return crypto.createHash("sha256").update(`${source}:${sourceProductId}`).digest("hex").slice(0, 32);
}

/** The AliExpress listing link, for the admin panel only. */
function aliExpressLink(source, sourceProductId) {
  const id = text(sourceProductId);
  return text(source).toLowerCase() === "aliexpress" && id ? `https://www.aliexpress.com/item/${id}.html` : "";
}

/**
 * Admin-only sourcing for an order: one entry per item that came from a
 * supplier. [items] = order items; [sourcesById] = productId -> merged source.
 */
function orderSourceEntries(items, sourcesById) {
  const out = [];
  (Array.isArray(items) ? items : []).forEach((item, index) => {
    const productId = text(item?.productId);
    const src = sourcesById.get(productId) || {};
    const source = text(src.source || item?.source);
    const sourceProductId = text(src.sourceProductId || item?.sourceProductId);
    if (!source && !sourceProductId && !text(item?.aliExpressLink)) return;
    const variantId = text(item?.variantId);
    const skus = isPlainObject(src.variantSkus) ? src.variantSkus : {};
    const sourceSkuId = text(item?.sourceSkuId || skus[variantId]?.sourceSkuId);
    out.push({
      index,
      productId,
      variantId,
      source,
      sourceProductId,
      ...(sourceSkuId ? { sourceSkuId } : {}),
      aliExpressLink: text(item?.aliExpressLink) || aliExpressLink(source, sourceProductId),
    });
  });
  return out;
}

/** An order item without its supplier fields. */
function stripOrderItem(item) {
  if (!isPlainObject(item)) return item;
  const copy = { ...item };
  for (const field of PRIVATE_ORDER_ITEM_FIELDS) delete copy[field];
  return copy;
}

module.exports = {
  PRODUCT_SOURCES,
  PRODUCT_IMPORT_KEYS,
  ORDER_SOURCES,
  PRIVATE_SOURCE_FIELDS,
  PRIVATE_VARIANT_FIELDS,
  PRIVATE_ORDER_ITEM_FIELDS,
  splitProductWrite,
  mergeProductWithSource,
  privateFieldsOn,
  variantKey,
  importKeyId,
  aliExpressLink,
  orderSourceEntries,
  stripOrderItem,
};
