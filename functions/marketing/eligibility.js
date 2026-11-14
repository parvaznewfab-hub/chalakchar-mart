// -----------------------------------------------------------------------------
// May this product be marketed (push, in-app, social posts, WhatsApp)?
//
// The one rule every marketing path uses: product create/update triggers,
// wishlist discount/back-in-stock messages, and — last line of defence — the
// marketing_outbox dispatcher, which re-reads the product before anything
// goes out (so a queue item written by any client or older code path is
// still stopped).
//
// Incident 2026-11-14: a chat search-miss imported 5 unrelated costume
// products live (needsReview: true) and the create trigger marketed them on
// 8 channels, because the old check ignored needsReview.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

function text(value) {
  return String(value ?? "").trim().toLowerCase();
}

/**
 * Why [product] must not be marketed, or null when it may be.
 * A missing approvalStatus counts as approved (legacy hand-made products).
 */
function marketingBlockReason(product) {
  if (!product || typeof product !== "object") return "product_missing";
  if (product.needsReview === true) return "needs_review";
  const approval = text(product.approvalStatus) || "approved";
  if (approval !== "approved") return "not_approved";
  if (product.isActive === false || product.isVisible === false || product.isPublished === false) {
    return "not_live";
  }
  return null;
}

/** Explicit marketing (an admin's queue item): only the product's state matters. */
function isMarketingEligible(product) {
  return marketingBlockReason(product) === null;
}

/**
 * Automatic marketing (create/update triggers): also honours the product's
 * autoMarketingDisabled switch, which every import sets — imported products
 * are only ever marketed by an admin, after review.
 */
function autoMarketingBlockReason(product) {
  const reason = marketingBlockReason(product);
  if (reason) return reason;
  if (product.autoMarketingDisabled === true) return "auto_marketing_disabled";
  return null;
}

function shouldAutoMarketProduct(product) {
  return autoMarketingBlockReason(product) === null;
}

module.exports = {
  marketingBlockReason,
  isMarketingEligible,
  autoMarketingBlockReason,
  shouldAutoMarketProduct,
};
