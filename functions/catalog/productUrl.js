"use strict";
// The one place public product links are built: /product/{urlSlug}, or
// /product/{doc id} for a product that has no slug yet (productSeo answers
// that one with a 301 to the slug once it has one).

const admin = require("firebase-admin");

const SITE_URL = "https://chalakcharmart.com";

function text(value) {
  return value == null ? "" : String(value).trim();
}

/** "/product/<slug or id>" for a product's data ([product.id] or [id]). */
function productPath(product, id = "") {
  const slug = text(product?.urlSlug);
  const key = slug || text(id || product?.id || product?.productId);
  return `/product/${encodeURIComponent(key)}`;
}

/** Full public URL for a product's data. */
function productUrlFor(product, id = "") {
  return `${SITE_URL}${productPath(product, id)}`;
}

/** Full public URL for a product id (reads its urlSlug). */
async function productPublicUrl(productId, db = admin.firestore()) {
  const id = text(productId);
  if (!id) return `${SITE_URL}/`;
  try {
    const snap = await db.collection("products").doc(id).get();
    return productUrlFor(snap.exists ? snap.data() : {}, id);
  } catch (_) {
    return productUrlFor({}, id);
  }
}

module.exports = { SITE_URL, productPath, productUrlFor, productPublicUrl };
