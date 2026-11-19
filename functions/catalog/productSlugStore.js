"use strict";
// Unique urlSlug per product: product_slugs/{slug} -> { productId } is the
// reservation (Firestore has no unique index). A reservation is never
// deleted, also not when the product is, so an old link never starts
// pointing at a different product.

const admin = require("firebase-admin");
const { slugCandidates } = require("./productSlug");

const PRODUCT_SLUGS = "product_slugs";
// Stamped by every slug write, so onProductStockUpdated sends nothing for it.
const SLUG_ASSIGNED_FIELD = "urlSlugAssignedAt";
const SLUG_WRITE_SOURCE = "slug_assign";

function slugRef(db, slug) {
  return db.collection(PRODUCT_SLUGS).doc(slug);
}

/**
 * Inside a transaction (reads only): the first candidate slug that is free or
 * already this product's. [product]: { name, strength }.
 */
async function pickSlugInTransaction(tx, db, product, productId) {
  // Same exact title as another product: start from the size, never the
  // bare name (also when the earlier ones got size slugs and left it free).
  const name = String(product?.name || "").trim();
  let titleTaken = false;
  if (name) {
    const same = await tx.get(db.collection("products").where("name", "==", name).limit(3));
    titleTaken = same.docs.some((d) => d.id !== productId);
  }
  for (const slug of slugCandidates(product, productId, { titleTaken })) {
    const snap = await tx.get(slugRef(db, slug));
    if (!snap.exists || snap.data()?.productId === productId) return slug;
  }
  const error = new Error(`No free slug for product ${productId}`);
  error.code = "SLUG_UNAVAILABLE";
  throw error;
}

/** Inside a transaction (write): reserve [slug] for [productId]. */
function reserveSlugInTransaction(tx, db, slug, productId) {
  tx.set(slugRef(db, slug), {
    productId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

/** The public fields a slug write sets on the product. */
function slugFields(slug) {
  return {
    urlSlug: slug,
    [SLUG_ASSIGNED_FIELD]: admin.firestore.FieldValue.serverTimestamp(),
    lastWriteSource: SLUG_WRITE_SOURCE,
  };
}

/**
 * Gives a product a slug if it has none (new products from the admin/vendor
 * app; imports get theirs while saving). Never changes an existing urlSlug.
 * Returns the product's slug, or "" when the product is gone.
 */
async function assignProductSlug(db, productRef) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(productRef);
    if (!snap.exists) return "";
    const product = snap.data() || {};
    const existing = String(product.urlSlug || "").trim();
    if (existing) return existing;
    const slug = await pickSlugInTransaction(tx, db, product, productRef.id);
    reserveSlugInTransaction(tx, db, slug, productRef.id);
    tx.update(productRef, slugFields(slug));
    return slug;
  });
}

function stampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** True for the write that only gave the product its slug. */
function isSlugAssignWrite(before, after) {
  const afterMs = stampMs(after?.[SLUG_ASSIGNED_FIELD]);
  return afterMs > 0 && afterMs !== stampMs(before?.[SLUG_ASSIGNED_FIELD]);
}

module.exports = {
  PRODUCT_SLUGS,
  SLUG_ASSIGNED_FIELD,
  SLUG_WRITE_SOURCE,
  pickSlugInTransaction,
  reserveSlugInTransaction,
  slugFields,
  assignProductSlug,
  isSlugAssignWrite,
};
