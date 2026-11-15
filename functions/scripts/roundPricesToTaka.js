#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Audit item 16: prices in whole taka, nearest (.5 up).
//
// Rounds every product's variants[].price/piecePrice/mrp/oldPrice and the
// top-level price/piecePrice/mrp/oldPrice (2851.49 -> 2851). With --apply it
// also sets settings/app.importSettings.roundingMode = "round", so imports and
// the AliExpress sync keep producing whole-taka prices (applyImportPriceRule),
// the app shows them as they are (formatTaka) and the admin edit form
// (toStringAsFixed(0)) saves the same value back: nobody keeps changing
// anybody else's price.
//
// Orders are never touched (they keep the price that was charged).
//
// DRY RUN BY DEFAULT: summary + JSON report in tools/backfill/. --apply saves
// a backup of every touched product's old values first, then updates each
// product in a transaction from its CURRENT data. Each write stamps
// priceBackfillAt + lastWriteSource "price_backfill" (and the sync marketing
// suppression), on which the price triggers send nothing: no "price dropped"
// notifications or posts from rounding.
//
// Usage (from functions/, application-default credentials):
//   node scripts/roundPricesToTaka.js [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { SYNC_MARKETING_SUPPRESSED_FIELD } = require("../aliexpress/variantRefresh");
const { PRICE_BACKFILL_FIELD, PRICE_BACKFILL_SOURCE } = require("../marketing/priceChange");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const PRICE_KEYS = ["price", "piecePrice", "mrp", "oldPrice"];

/** Rounded copy of the price fields that need it, or null when nothing changes. */
function roundedPriceUpdate(product) {
  const update = {};
  for (const key of PRICE_KEYS) {
    const v = product[key];
    if (typeof v === "number" && Number.isFinite(v) && Math.round(v) !== v) update[key] = Math.round(v);
  }
  if (Array.isArray(product.variants)) {
    let changed = false;
    const variants = product.variants.map((variant) => {
      if (!variant || typeof variant !== "object") return variant;
      const copy = { ...variant };
      for (const key of PRICE_KEYS) {
        const v = copy[key];
        if (typeof v === "number" && Number.isFinite(v) && Math.round(v) !== v) {
          copy[key] = Math.round(v);
          changed = true;
        }
      }
      return copy;
    });
    if (changed) update.variants = variants;
  }
  return Object.keys(update).length ? update : null;
}

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const settingsRef = db.collection("settings").doc("app");
  const currentMode = (await settingsRef.get()).data()?.importSettings?.roundingMode ?? "(unset)";
  console.log(`importSettings.roundingMode now: ${currentMode} -> "round"`);

  const snap = await db.collection("products").get();
  const rows = [];
  let maxDelta = 0;
  for (const doc of snap.docs) {
    const x = doc.data();
    const update = roundedPriceUpdate(x);
    if (!update) continue;
    const delta = Math.abs((update.price ?? x.price ?? 0) - (x.price ?? 0));
    maxDelta = Math.max(maxDelta, delta);
    rows.push({
      id: doc.id,
      active: x.isActive !== false,
      name: String(x.name || "").slice(0, 60),
      price: [x.price, update.price ?? x.price],
      variantsChanged: Array.isArray(update.variants),
      before: Object.fromEntries(Object.keys(update).map((k) => [k, x[k] ?? null])),
    });
  }
  console.log(`Products: ${snap.size}, to round: ${rows.length} (active ${rows.filter((r) => r.active).length}), max top-level price change: ৳${maxDelta.toFixed(2)}`);
  for (const r of rows.slice(0, 8)) console.log(`  ${r.id.slice(0, 40)}  ${r.price[0]} -> ${r.price[1]}${r.variantsChanged ? " (+variants)" : ""}  ${r.name}`);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const file = path.join(OUT_DIR, `round-prices-${apply ? "backup" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify({ roundingModeBefore: currentMode, products: rows }, null, 2));
  console.log(`Report/backup: ${file}`);

  if (!apply) {
    console.log("DRY RUN — nothing written. Write with --apply.");
    return;
  }

  let written = 0;
  for (const row of rows) {
    const ref = db.collection("products").doc(row.id);
    const did = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      const update = fresh.exists ? roundedPriceUpdate(fresh.data()) : null;
      if (!update) return false;
      update[SYNC_MARKETING_SUPPRESSED_FIELD] = admin.firestore.FieldValue.serverTimestamp();
      update[PRICE_BACKFILL_FIELD] = admin.firestore.FieldValue.serverTimestamp();
      update.lastWriteSource = PRICE_BACKFILL_SOURCE;
      tx.update(ref, update);
      return true;
    });
    if (did) written++;
  }
  await settingsRef.set({ importSettings: { roundingMode: "round" } }, { merge: true });
  console.log(`Rounded: ${written} product(s); importSettings.roundingMode = "round".`);
}

module.exports = { roundedPriceUpdate };

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
