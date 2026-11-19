#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time migration: supplier data off the public product, plus URL slugs.
//
// 1. products: every supplier/cost/import field (catalog/productSource.js
//    PRIVATE_SOURCE_FIELDS) and each variant's sourceSkuId is copied to
//    product_sources/{id} and DELETED from products/{id}. A value already in
//    product_sources (written by new code since deploy) is newer and kept.
//    Imported products get the public isImported:true (chat says "imported
//    from abroad", naming no supplier).
// 2. product_import_keys/{sha256(source:sourceProductId)} -> productId, the
//    import dedupe key (doc ids stay as they are; new imports get neutral ids).
// 3. urlSlug for every product without one (catalog/productSlug.js
//    planSlugs), reserved in product_slugs/{slug}.
// 4. orders: items that carry source/sourceProductId/aliExpressLink/
//    sourceSkuId (customers, vendors and riders can read orders) get them
//    moved to order_sources/{orderId} and removed from the item.
// 5. cart/{uid}/items: the same fields removed.
//
// Product writes stamp urlSlugAssignedAt + lastWriteSource "source_migration",
// on which onProductStockUpdated sends nothing. Order writes don't change
// status, so onOrderStatusUpdated does nothing.
//
// DRY RUN BY DEFAULT: prints the plan and writes a report to tools/backfill/
// (git-ignored). --apply first writes a JSON backup of every value it will
// change or delete, then applies (one transaction per product/order, which
// re-reads the doc). Running it again is safe: it only touches what is left.
//
// Credentials: application-default credentials, or FIRESTORE_EMULATOR_HOST.
// Usage (from functions/):
//   node scripts/migrateProductSources.js [--apply] [--products=id,id] [--skip-orders] [--skip-carts]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const {
  PRODUCT_SOURCES,
  PRODUCT_IMPORT_KEYS,
  ORDER_SOURCES,
  PRIVATE_SOURCE_FIELDS,
  PRIVATE_VARIANT_FIELDS,
  PRIVATE_ORDER_ITEM_FIELDS,
  splitProductWrite,
  privateFieldsOn,
  importKeyId,
  orderSourceEntries,
  stripOrderItem,
} = require("../catalog/productSource");
const { planSlugs } = require("../catalog/productSlug");
const { PRODUCT_SLUGS, SLUG_ASSIGNED_FIELD } = require("../catalog/productSlugStore");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const WRITE_SOURCE = "source_migration";

function parseArgs(argv) {
  const args = { apply: false, products: [], skipOrders: false, skipCarts: false };
  for (const arg of argv) {
    if (arg === "--apply") args.apply = true;
    else if (arg === "--skip-orders") args.skipOrders = true;
    else if (arg === "--skip-carts") args.skipCarts = true;
    else if (arg.startsWith("--products=")) args.products = arg.slice(11).split(",").map((s) => s.trim()).filter(Boolean);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

function text(v) {
  return v == null ? "" : String(v).trim();
}

function jsonSafe(value) {
  return JSON.parse(JSON.stringify(value, (_k, v) => {
    if (v && typeof v.toDate === "function") return { __timestamp: v.toDate().toISOString() };
    return v;
  }));
}

/** What the migration does to one product (pure; used for the plan and the write). */
function productChanges(id, product, sourceRecord, slug) {
  const fields = privateFieldsOn(product);
  const { privateData } = splitProductWrite(product);
  const existing = sourceRecord || {};
  const toSource = {};
  for (const [k, v] of Object.entries(privateData)) {
    if (k === "variantSkus") continue;
    if (!(k in existing)) toSource[k] = v;
  }
  if (privateData.variantSkus) {
    const have = existing.variantSkus || {};
    const add = {};
    for (const [vk, v] of Object.entries(privateData.variantSkus)) if (!have[vk]) add[vk] = v;
    if (Object.keys(add).length) toSource.variantSkus = add;
  }
  const source = text(existing.source || product.source).toLowerCase();
  const sourceProductId = text(existing.sourceProductId || product.sourceProductId);
  const strippedVariants = Array.isArray(product.variants) && fields.includes("variants[].sourceSkuId")
    ? product.variants.map((v) => {
      if (!v || typeof v !== "object") return v;
      const copy = { ...v };
      for (const f of PRIVATE_VARIANT_FIELDS) delete copy[f];
      return copy;
    })
    : null;
  return {
    id,
    deleteFields: fields.filter((f) => f !== "variants[].sourceSkuId"),
    stripVariantSkus: Boolean(strippedVariants),
    strippedVariants,
    toSource,
    setImported: Boolean(source) && product.isImported !== true,
    slug: text(product.urlSlug) ? "" : slug,
    importKey: source && sourceProductId ? { id: importKeyId(source, sourceProductId), source, sourceProductId } : null,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const target = process.env.FIRESTORE_EMULATOR_HOST ? `EMULATOR ${process.env.FIRESTORE_EMULATOR_HOST}` : "LIVE";
  console.log(`Target: ${target}  Mode: ${args.apply ? "APPLY" : "dry run"}`);

  const [productsSnap, sourcesSnap, slugsSnap, keysSnap] = await Promise.all([
    db.collection("products").get(),
    db.collection(PRODUCT_SOURCES).get(),
    db.collection(PRODUCT_SLUGS).get(),
    db.collection(PRODUCT_IMPORT_KEYS).get(),
  ]);
  const sourceById = new Map(sourcesSnap.docs.map((d) => [d.id, d.data()]));
  const slugOwner = new Map(slugsSnap.docs.map((d) => [d.id, d.data()?.productId]));
  const keyOwner = new Map(keysSnap.docs.map((d) => [d.id, d.data()?.productId]));
  const only = args.products.length ? new Set(args.products) : null;
  const productDocs = productsSnap.docs.filter((d) => !only || only.has(d.id));

  // Slugs are planned over ALL products (uniqueness is global).
  const taken = new Set([...slugOwner.keys(), ...productsSnap.docs.map((d) => text(d.data().urlSlug)).filter(Boolean)]);
  const plan = planSlugs(
    productsSnap.docs.filter((d) => !text(d.data().urlSlug)).map((d) => ({ id: d.id, name: d.data().name || "", strength: d.data().strength || "" })),
    taken
  );

  const changes = productDocs.map((d) => productChanges(d.id, d.data(), sourceById.get(d.id), plan.get(d.id)?.slug || ""));
  const productWork = changes.filter((c) => c.deleteFields.length || c.stripVariantSkus || c.setImported || c.slug ||
    (c.importKey && keyOwner.get(c.importKey.id) !== c.id));
  const keyConflicts = changes.filter((c) => c.importKey && keyOwner.has(c.importKey.id) && keyOwner.get(c.importKey.id) !== c.id);

  // Orders and carts that carry supplier fields.
  const mergedSourceById = new Map(productsSnap.docs.map((d) => {
    const p = d.data();
    const s = sourceById.get(d.id) || {};
    const { privateData } = splitProductWrite(p);
    return [d.id, { ...privateData, ...s, variantSkus: { ...(privateData.variantSkus || {}), ...(s.variantSkus || {}) } }];
  }));
  const hasLeak = (o) => o && typeof o === "object" && PRIVATE_ORDER_ITEM_FIELDS.some((f) => f in o);
  let orderWork = [];
  if (!args.skipOrders) {
    const ordersSnap = await db.collection("orders").get();
    orderWork = ordersSnap.docs
      .filter((d) => (Array.isArray(d.data().items) ? d.data().items : []).some(hasLeak))
      .map((d) => ({ id: d.id, items: d.data().items, entries: orderSourceEntries(d.data().items, mergedSourceById) }));
  }
  let cartWork = [];
  if (!args.skipCarts) {
    const itemsSnap = await db.collectionGroup("items").get();
    cartWork = itemsSnap.docs
      .filter((d) => d.ref.parent.parent && d.ref.parent.parent.parent.id === "cart" && hasLeak(d.data()))
      .map((d) => ({ path: d.ref.path, fields: PRIVATE_ORDER_ITEM_FIELDS.filter((f) => f in d.data()), values: jsonSafe(d.data()) }));
  }

  // ---- report -------------------------------------------------------------
  const count = (fn) => productWork.filter(fn).length;
  console.log(`Products: ${productDocs.length} scanned, ${productWork.length} to change`);
  console.log(`  private fields to move+delete: ${count((c) => c.deleteFields.length)} products`);
  console.log(`  variant sourceSkuId to move:   ${count((c) => c.stripVariantSkus)} products`);
  console.log(`  isImported to set:             ${count((c) => c.setImported)}`);
  console.log(`  urlSlug to assign:             ${count((c) => c.slug)}`);
  console.log(`  import keys to create:         ${changes.filter((c) => c.importKey && !keyOwner.has(c.importKey.id)).length}`);
  console.log(`  import key conflicts:          ${keyConflicts.length}`);
  console.log(`Orders with supplier fields in items: ${orderWork.length} (${orderWork.reduce((n, o) => n + o.items.filter(hasLeak).length, 0)} items)`);
  console.log(`Cart items with supplier fields: ${cartWork.length}`);
  const fieldsSeen = {};
  for (const c of productWork) for (const f of c.deleteFields) fieldsSeen[f] = (fieldsSeen[f] || 0) + 1;
  console.log("Fields removed from products:", fieldsSeen);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const tag = process.env.FIRESTORE_EMULATOR_HOST ? "emulator" : "live";
  const reportPath = path.join(OUT_DIR, `product-sources-${tag}-${stamp}-${args.apply ? "apply" : "dryrun"}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(jsonSafe({
    target, apply: args.apply,
    products: productWork.map((c) => ({ id: c.id, deleteFields: c.deleteFields, stripVariantSkus: c.stripVariantSkus, setImported: c.setImported, slug: c.slug, importKey: c.importKey })),
    keyConflicts: keyConflicts.map((c) => ({ id: c.id, key: c.importKey, owner: keyOwner.get(c.importKey.id) })),
    orders: orderWork.map((o) => ({ id: o.id, entries: o.entries })),
    carts: cartWork.map((c) => ({ path: c.path, fields: c.fields })),
  }), null, 1));
  console.log(`Report: ${reportPath}`);
  if (!args.apply) return;

  // ---- backup (before any write) ------------------------------------------
  const productById = new Map(productsSnap.docs.map((d) => [d.id, d.data()]));
  const backupPath = path.join(OUT_DIR, `product-sources-${tag}-${stamp}-BACKUP.json`);
  fs.writeFileSync(backupPath, JSON.stringify(jsonSafe({
    target,
    products: productWork.map((c) => {
      const p = productById.get(c.id) || {};
      const old = {};
      for (const f of [...PRIVATE_SOURCE_FIELDS, "variants", "isImported", "urlSlug", SLUG_ASSIGNED_FIELD, "lastWriteSource"]) if (f in p) old[f] = p[f];
      return { id: c.id, fields: old, productSourceBefore: sourceById.get(c.id) || null };
    }),
    orders: orderWork.map((o) => ({ id: o.id, items: o.items })),
    carts: cartWork.map((c) => ({ path: c.path, data: c.values })),
  }), null, 1));
  console.log(`Backup: ${backupPath}`);

  // ---- apply --------------------------------------------------------------
  const FieldValue = admin.firestore.FieldValue;
  let done = 0;
  const failures = [];
  for (const c of productWork) {
    try {
      await db.runTransaction(async (tx) => {
        const ref = db.collection("products").doc(c.id);
        const sref = db.collection(PRODUCT_SOURCES).doc(c.id);
        const slugRef = c.slug ? db.collection(PRODUCT_SLUGS).doc(c.slug) : null;
        const keyRef = c.importKey ? db.collection(PRODUCT_IMPORT_KEYS).doc(c.importKey.id) : null;
        const [snap, ssnap, slugSnap, keySnap] = await Promise.all([
          tx.get(ref), tx.get(sref), slugRef ? tx.get(slugRef) : null, keyRef ? tx.get(keyRef) : null,
        ]);
        if (!snap.exists) return;
        // Recompute from the doc as it is now (a sync may have run since the plan).
        const fresh = productChanges(c.id, snap.data(), ssnap.exists ? ssnap.data() : null, c.slug);
        if (fresh.slug && slugSnap?.exists && slugSnap.data()?.productId !== c.id) {
          throw new Error(`slug ${fresh.slug} already reserved by ${slugSnap.data()?.productId}`);
        }
        if (Object.keys(fresh.toSource).length) {
          tx.set(sref, { ...fresh.toSource, productId: c.id, migratedAt: FieldValue.serverTimestamp() }, { merge: true });
        }
        const update = {
          [SLUG_ASSIGNED_FIELD]: FieldValue.serverTimestamp(),
          lastWriteSource: WRITE_SOURCE,
        };
        for (const f of fresh.deleteFields) update[f] = FieldValue.delete();
        if (fresh.strippedVariants) update.variants = fresh.strippedVariants;
        if (fresh.setImported) update.isImported = true;
        if (fresh.slug) {
          update.urlSlug = fresh.slug;
          tx.set(slugRef, { productId: c.id, createdAt: FieldValue.serverTimestamp() }, { merge: true });
        }
        if (keyRef && !keySnap?.exists) {
          tx.set(keyRef, {
            source: fresh.importKey.source,
            sourceProductId: fresh.importKey.sourceProductId,
            productId: c.id,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
        tx.update(ref, update);
      });
      done++;
    } catch (error) {
      failures.push({ id: c.id, message: error.message });
    }
  }
  console.log(`Products written: ${done}/${productWork.length}`);

  let ordersDone = 0;
  for (const o of orderWork) {
    try {
      await db.runTransaction(async (tx) => {
        const ref = db.collection("orders").doc(o.id);
        const snap = await tx.get(ref);
        if (!snap.exists) return;
        const items = Array.isArray(snap.data().items) ? snap.data().items : [];
        const entries = orderSourceEntries(items, mergedSourceById);
        if (entries.length) {
          tx.set(db.collection(ORDER_SOURCES).doc(o.id), { orderId: o.id, items: entries, migratedAt: FieldValue.serverTimestamp() }, { merge: true });
        }
        tx.update(ref, { items: items.map(stripOrderItem) });
      });
      ordersDone++;
    } catch (error) {
      failures.push({ order: o.id, message: error.message });
    }
  }
  console.log(`Orders written: ${ordersDone}/${orderWork.length}`);

  let cartsDone = 0;
  for (const c of cartWork) {
    try {
      const update = {};
      for (const f of c.fields) update[f] = FieldValue.delete();
      await db.doc(c.path).update(update);
      cartsDone++;
    } catch (error) {
      failures.push({ cart: c.path, message: error.message });
    }
  }
  console.log(`Cart items written: ${cartsDone}/${cartWork.length}`);

  // ---- verify -------------------------------------------------------------
  const after = await db.collection("products").get();
  const stillLeaking = after.docs.filter((d) => privateFieldsOn(d.data()).length);
  const noSlug = after.docs.filter((d) => !text(d.data().urlSlug));
  console.log(`Verify: products still carrying private fields: ${stillLeaking.length}; without urlSlug: ${noSlug.length}`);
  if (failures.length) {
    console.log("FAILURES:", failures);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { productChanges };
