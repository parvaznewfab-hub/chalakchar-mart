// -----------------------------------------------------------------------------
// Safety net for importAliExpressProduct (the n8n webhook).
//
// The n8n workflow paired AliExpress SKU ids and variant names BY POSITION
// from two differently-ordered lists, so 6 products were saved with variants
// carrying another variant's SKU (40 variants; seen live 2026-11-13). Every
// later SKU-based step (sync, image backfill) then had to work around it.
//
// Before saving, each incoming variant's SKU id is checked against the name
// AliExpress itself gives that SKU:
//   - SKU and name agree               -> kept as sent
//   - they disagree, but exactly one AliExpress SKU has the incoming name
//                                      -> repaired: skuId, price, mrp, stock
//                                         taken from THAT SKU (the n8n values
//                                         were paired with the wrong SKU too)
//   - no unique same-name SKU          -> rejected (the import is refused,
//                                         never saved with a guessed SKU)
//   - no SKU id sent                   -> can't verify; kept and listed
//
// Matched variants (kept or repaired) also get AliExpress's
// sourceAttributeName for that SKU when n8n didn't send one — n8n bodies
// don't carry it, and it's only stored for reference (never displayed).
//
// Pure: the caller fetches the fresh AliExpress variants.
// -----------------------------------------------------------------------------

const { pickFreshVariantForSaved } = require("./variantMatch");

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

// Same field precedence the importer (normalizeMarketplaceVariants) reads.
function incomingSkuId(variant) {
  return textValue(variant.skuId || variant.sku_id || variant.sourceSkuId);
}

function incomingName(variant) {
  return textValue(variant.name || variant.unit || variant.variantName || variant.skuName);
}

// Fields the importer would read INSTEAD of price/mrp/stock if present; they
// came from the wrongly-paired n8n data, so a repair removes them.
const SUPERSEDED_ON_REPAIR = ["sku_id", "sourceSkuId", "salePrice", "piecePrice", "oldPrice", "originalPrice", "quantity", "availableStock"];

function withSourceAttributeName(variant, freshVariant) {
  const name = textValue(freshVariant && freshVariant.sourceAttributeName);
  if (!name || textValue(variant.sourceAttributeName)) return variant;
  return { ...variant, sourceAttributeName: name };
}

/**
 * @param {object[]} incomingVariants product.variants from the n8n body
 * @param {object[]} freshVariants normalizeAliExpressProduct(...).variants
 * @returns {{ variants: object[], verified: number, repaired: object[],
 *             rejected: object[], unverified: object[] }}
 */
function verifyIncomingVariants(incomingVariants, freshVariants) {
  const repaired = [];
  const rejected = [];
  const unverified = [];
  let verified = 0;
  const fresh = Array.isArray(freshVariants) ? freshVariants : [];

  const variants = (Array.isArray(incomingVariants) ? incomingVariants : []).map((raw, index) => {
    if (!isObject(raw)) return raw;
    const skuId = incomingSkuId(raw);
    const name = incomingName(raw);
    if (!skuId) {
      unverified.push({ index, name });
      return raw;
    }

    const pick = pickFreshVariantForSaved({ sourceSkuId: skuId, name }, fresh);
    if (pick.how === "sku") {
      verified += 1;
      return withSourceAttributeName(raw, pick.fresh);
    }
    if (pick.fresh) {
      const owner = fresh.find((f) => textValue(f.skuId) === skuId);
      repaired.push({ index, name, fromSkuId: skuId, toSkuId: textValue(pick.fresh.skuId), skuBelongsTo: owner ? textValue(owner.name) : null });
      const next = { ...raw };
      for (const key of SUPERSEDED_ON_REPAIR) delete next[key];
      return withSourceAttributeName({
        ...next,
        skuId: textValue(pick.fresh.skuId),
        price: pick.fresh.price,
        mrp: pick.fresh.mrp ?? pick.fresh.price,
        stock: pick.fresh.stock,
      }, pick.fresh);
    }
    rejected.push({ index, name, skuId, reason: pick.how });
    return raw;
  });

  return { variants, verified, repaired, rejected, unverified };
}

/**
 * True for an n8n body that only identifies an AliExpress product (id or
 * link) and carries no product data — the backend then fetches everything
 * itself, so names and SKU ids always come from the same AliExpress SKU.
 */
function isAliExpressIdOnlyImport(body) {
  const b = isObject(body) ? body : {};
  const data = isObject(b.product) ? b.product : isObject(b.data) ? b.data : b;
  const source = textValue(b.source || data.source, "aliexpress").toLowerCase();
  if (source !== "aliexpress") return false;
  if (textValue(data.name || data.title)) return false;
  return Boolean(textValue(
    b.productId || b.productUrl || b.url || b.sourceProductId ||
    data.productId || data.productUrl || data.url || data.sourceProductId
  ));
}

module.exports = { verifyIncomingVariants, isAliExpressIdOnlyImport };
