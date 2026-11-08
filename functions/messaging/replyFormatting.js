// Formats product-search chat replies using the same caption-template
// substitution as lib/services/marketing_queue_service.dart's _applyTemplate
// (ported to Node), so a chat reply about a product reads consistently with
// marketing broadcasts about the same product, per the spec.

function text(value, fallback = "") {
  const t = String(value ?? "").trim();
  return t.length ? t : fallback;
}

/** Same fallback chain as marketing_queue_service.dart's _price(). */
function priceOf(product) {
  const variants = product.variants;
  if (Array.isArray(variants) && variants.length > 0 && variants[0] && typeof variants[0] === "object") {
    const p = Number(variants[0].price ?? variants[0].piecePrice ?? 0);
    if (p > 0) return String(Math.round(p));
  }
  const direct = Number(product.price ?? product.piecePrice ?? 0);
  return direct > 0 ? String(Math.round(direct)) : "";
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

/**
 * Builds the chat reply for a product-search hit: the caption template for a
 * single match (direct link), or a short numbered list for 2-5 matches, per
 * the spec's §3 reply logic. Returns { replyText, productLinks }.
 */
function formatProductReply(products, captionTemplate) {
  const list = (products || []).slice(0, 5);

  if (list.length === 1) {
    const product = list[0];
    return {
      replyText: applyCaptionTemplate(captionTemplate, product),
      productLinks: [productUrl(product.id)],
    };
  }

  const lines = list.map((product, index) => {
    const name = text(product.name ?? product.title, "Product");
    const price = priceOf(product);
    const priceSuffix = price ? ` - ৳${price}` : "";
    return `${index + 1}. ${name}${priceSuffix}\n${productUrl(product.id)}`;
  });

  return {
    replyText: `এই প্রোডাক্টগুলো পাওয়া যাচ্ছে:\n\n${lines.join("\n\n")}`,
    productLinks: list.map((product) => productUrl(product.id)),
  };
}

module.exports = { priceOf, productUrl, applyCaptionTemplate, formatProductReply };
