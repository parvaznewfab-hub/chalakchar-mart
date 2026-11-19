"use strict";
// Firestore side of catalog/productSource.js: merged reads, split writes,
// the list of supplier-sourced products, and import dedupe/doc ids.

const admin = require("firebase-admin");
const {
  PRODUCT_SOURCES,
  PRODUCT_IMPORT_KEYS,
  splitProductWrite,
  mergeProductWithSource,
  importKeyId,
} = require("./productSource");

function sourceRefFor(db, productId) {
  return db.collection(PRODUCT_SOURCES).doc(productId);
}

/**
 * A snapshot-like object whose data() is the merged view, so code written for
 * product snapshots keeps working: { id, ref, exists, data() }.
 */
function mergedSnapshot(productSnap, sourceSnap) {
  const merged = mergeProductWithSource(productSnap.data() || {}, sourceSnap?.exists ? sourceSnap.data() : {});
  return { id: productSnap.id, ref: productSnap.ref, exists: productSnap.exists, data: () => merged };
}

/** One product with its source record merged in ([tx] optional). */
async function loadMergedProduct(db, productId, tx = null) {
  const ref = db.collection("products").doc(productId);
  const sref = sourceRefFor(db, productId);
  const [snap, ssnap] = tx ? await Promise.all([tx.get(ref), tx.get(sref)]) : await Promise.all([ref.get(), sref.get()]);
  return mergedSnapshot(snap, ssnap);
}

/**
 * Writes [data] to a product, the private part into product_sources.
 * mode "update": product must exist (like ref.update). mode "set": merge set.
 * [writer]: a Transaction or WriteBatch, or null to write directly.
 */
async function writeProduct(db, productRef, data, { writer = null, mode = "update" } = {}) {
  const { publicData, privateData } = splitProductWrite(data);
  const sref = sourceRefFor(db, productRef.id);
  const hasPublic = Object.keys(publicData).length > 0;
  const hasPrivate = Object.keys(privateData).length > 0;
  const sourceDoc = hasPrivate ? {
    ...privateData,
    productId: productRef.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  } : null;

  if (writer) {
    if (hasPublic) {
      if (mode === "set") writer.set(productRef, publicData, { merge: true });
      else writer.update(productRef, publicData);
    }
    if (sourceDoc) writer.set(sref, sourceDoc, { merge: true });
    return;
  }
  const batch = db.batch();
  if (hasPublic) {
    if (mode === "set") batch.set(productRef, publicData, { merge: true });
    else batch.update(productRef, publicData);
  }
  if (sourceDoc) batch.set(sref, sourceDoc, { merge: true });
  if (hasPublic || sourceDoc) await batch.commit();
}

/**
 * Supplier-sourced products as merged snapshots. Reads product_sources and,
 * until the migration has run, also products that still carry the fields.
 * Options: source ("aliexpress"), requireSyncEnabled, sourceProductId, limit.
 */
async function listSourcedProducts(db, { source = "aliexpress", requireSyncEnabled = false, sourceProductId = "", limit = 0 } = {}) {
  let sq = db.collection(PRODUCT_SOURCES).where("source", "==", source);
  let lq = db.collection("products").where("source", "==", source);
  if (sourceProductId) {
    sq = sq.where("sourceProductId", "==", sourceProductId);
    lq = lq.where("sourceProductId", "==", sourceProductId);
  }
  const [sourceSnaps, legacySnaps] = await Promise.all([sq.get(), lq.get()]);

  const sourceById = new Map(sourceSnaps.docs.map((d) => [d.id, d]));
  const ids = [...new Set([...sourceSnaps.docs.map((d) => d.id), ...legacySnaps.docs.map((d) => d.id)])].sort();
  const legacyById = new Map(legacySnaps.docs.map((d) => [d.id, d]));
  const missing = ids.filter((id) => !legacyById.has(id));
  const fetched = missing.length
    ? await db.getAll(...missing.map((id) => db.collection("products").doc(id)))
    : [];
  const productById = new Map([...legacySnaps.docs, ...fetched].map((d) => [d.id, d]));
  const legacyOnly = ids.filter((id) => !sourceById.has(id));
  const legacySources = legacyOnly.length ? await db.getAll(...legacyOnly.map((id) => sourceRefFor(db, id))) : [];
  for (const s of legacySources) sourceById.set(s.id, s);

  let out = ids
    .map((id) => productById.get(id))
    .filter((snap) => snap && snap.exists)
    .map((snap) => mergedSnapshot(snap, sourceById.get(snap.id)));
  if (requireSyncEnabled) out = out.filter((s) => s.data().syncEnabled === true);
  if (limit > 0) out = out.slice(0, limit);
  return out;
}

/**
 * Inside a transaction: which product an import of (source, sourceProductId)
 * writes to. Order: the dedupe key, then the pre-2026-11 doc id, else a new
 * neutral id. Returns { productId, keyRef, keyExists }. All reads, no writes.
 */
async function resolveImportTarget(tx, db, source, sourceProductId, legacyId) {
  const keyRef = db.collection(PRODUCT_IMPORT_KEYS).doc(importKeyId(source, sourceProductId));
  const keySnap = await tx.get(keyRef);
  const keyed = keySnap.exists ? String(keySnap.data()?.productId || "") : "";
  if (keyed) return { productId: keyed, keyRef, keyExists: true };
  const legacySnap = await tx.get(db.collection("products").doc(legacyId));
  if (legacySnap.exists) return { productId: legacyId, keyRef, keyExists: false };
  return { productId: db.collection("products").doc().id, keyRef, keyExists: false };
}

/** Outside a transaction: the product already imported for this listing, or "". */
async function findImportedProductId(db, source, sourceProductId, legacyId) {
  const keySnap = await db.collection(PRODUCT_IMPORT_KEYS).doc(importKeyId(source, sourceProductId)).get();
  const keyed = keySnap.exists ? String(keySnap.data()?.productId || "") : "";
  if (keyed) return keyed;
  const legacySnap = await db.collection("products").doc(legacyId).get();
  return legacySnap.exists ? legacyId : "";
}

module.exports = {
  sourceRefFor,
  mergedSnapshot,
  loadMergedProduct,
  writeProduct,
  listSourcedProducts,
  resolveImportTarget,
  findImportedProductId,
};
