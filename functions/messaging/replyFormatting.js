// Formats product-search chat replies: for every matched product its price,
// delivery estimate and link. Customer-facing text never names the supplier
// or origin country; imported items say "বিদেশ থেকে আমদানি" instead.
//
// applyCaptionTemplate keeps the marketing caption substitution of
// lib/services/marketing_queue_service.dart's _applyTemplate (ported to Node).

const { pickDisplayVariant, hasPriceRange } = require("../catalog/displayPrice");
const { cleanVariantDisplayName } = require("../catalog/variantLabel");
const { normalizeChatQuery } = require("./queryNormalize");

const BANGLA_DIGITS = ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯"];

function text(value, fallback = "") {
  const t = String(value ?? "").trim();
  return t.length ? t : fallback;
}

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function banglaNumber(value) {
  return String(value).replace(/[0-9]/g, (d) => BANGLA_DIGITS[Number(d)]);
}

function taka(value) {
  return `৳${Math.round(num(value)).toLocaleString("en-US")}`;
}

/**
 * The shown "from" price as whole taka ("2851"), or "" when the product has
 * no price: cheapest in-stock variant (catalog/displayPrice.js), else the
 * top-level price.
 */
function priceOf(product) {
  const variant = pickDisplayVariant(product?.variants);
  const p = variant ? num(variant.price ?? variant.piecePrice) : num(product?.price || product?.piecePrice);
  return p > 0 ? String(Math.round(p)) : "";
}

function productUrl(productId) {
  return `https://chalakcharmart.com/product/${encodeURIComponent(productId)}`;
}

/** Same placeholder substitution as marketing_queue_service.dart's _applyTemplate. */
function applyCaptionTemplate(template, product) {
  const name = text(product.name ?? product.title, "Product");
  const price = priceOf(product);
  const category = text(product.category);
  const url = productUrl(product.id);

  return String(template || "")
    .replaceAll("{productName}", name)
    .replaceAll("{name}", name)
    .replaceAll("{price}", price)
    .replaceAll("{category}", category)
    .replaceAll("{productUrl}", url);
}

const SIZE_TERM = /^\d+(?:\.\d+)?(?:gb|tb|mb|mah|w|hz|inch|mm|cm|v)$/;

/**
 * The variant the customer asked about: one whose name contains every size
 * term of the query ("128gb"), preferring one in stock; null when the query
 * names no size or no variant has it.
 */
function variantForQuery(product, query) {
  const sizes = normalizeChatQuery(query).filter((t) => SIZE_TERM.test(t));
  if (!sizes.length || !Array.isArray(product?.variants)) return null;
  const hits = product.variants.filter((v) => {
    if (!v || typeof v !== "object" || num(v.price ?? v.piecePrice) <= 0) return false;
    const compact = text(v.name ?? v.unit).toLowerCase().replace(/\s+/g, "");
    return sizes.every((s) => compact.includes(s));
  });
  return hits.find((v) => num(v.stock) > 0) || hits[0] || null;
}

/** "💰 দাম: ৳2,851 (128GB Black)" / "💰 দাম: ৳2,851 থেকে" / "" when unpriced. */
function priceLine(product, query) {
  const asked = variantForQuery(product, query);
  if (asked) {
    const label = cleanVariantDisplayName(text(asked.name ?? asked.unit));
    const soldOut = num(asked.stock) <= 0 ? " — এই মুহূর্তে স্টকে নেই" : "";
    return `💰 দাম: ${taka(asked.price ?? asked.piecePrice)}${label ? ` (${label})` : ""}${soldOut}`;
  }
  const price = priceOf(product);
  if (!price) return "";
  const from = hasPriceRange(product.variants) ? " থেকে" : "";
  return `💰 দাম: ${taka(price)}${from}`;
}

/** "🚚 বিদেশ থেকে আমদানি, আনুমানিক ডেলিভারি ৯–২৭ দিন" or "" when unknown. */
function deliveryLine(product) {
  const min = Math.round(num(product?.deliveryMinDays));
  const max = Math.round(num(product?.deliveryMaxDays));
  const days = Math.round(num(product?.deliveryDays));
  let range = "";
  if (min > 0 && max > min) range = `${banglaNumber(min)}–${banglaNumber(max)} দিন`;
  else if (max > 0 || min > 0) range = `${banglaNumber(Math.max(min, max))} দিন`;
  else if (days > 0) range = `${banglaNumber(days)} দিন`;

  const imported = text(product?.source).toLowerCase() === "aliexpress";
  if (imported) {
    return range ? `🚚 বিদেশ থেকে আমদানি, আনুমানিক ডেলিভারি ${range}` : "🚚 বিদেশ থেকে আমদানি করা পণ্য";
  }
  return range ? `🚚 আনুমানিক ডেলিভারি ${range}` : "";
}

function productBlock(product, query) {
  const name = text(product.name ?? product.title, "Product");
  const shortName = name.length > 90 ? `${name.slice(0, 87).trim()}...` : name;
  return [shortName, priceLine(product, query), deliveryLine(product), `🔗 ${productUrl(product.id)}`]
    .filter(Boolean)
    .join("\n");
}

/**
 * Chat reply for a product-search hit (up to 5 products), each with price,
 * delivery estimate and link. [query] is the customer's message, used to
 * quote the variant they named (e.g. 128GB). Returns { replyText, productLinks }.
 * [captionTemplate] is accepted for call compatibility and no longer used:
 * marketing captions carry no delivery time.
 */
function formatProductReply(products, _captionTemplate, query = "") {
  const list = (products || []).slice(0, 5);

  if (list.length === 1) {
    return {
      replyText: `এই প্রোডাক্টটি পাওয়া যাচ্ছে:\n\n${productBlock(list[0], query)}`,
      productLinks: [productUrl(list[0].id)],
    };
  }

  const blocks = list.map((product, index) => `${index + 1}. ${productBlock(product, query)}`);
  return {
    replyText: `এই প্রোডাক্টগুলো পাওয়া যাচ্ছে:\n\n${blocks.join("\n\n")}`,
    productLinks: list.map((product) => productUrl(product.id)),
  };
}

module.exports = { priceOf, productUrl, applyCaptionTemplate, formatProductReply, variantForQuery, deliveryLine };
