#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill: product-level price/piecePrice/oldPrice/mrp/unit = the
// display variant (cheapest in-stock variant — catalog/displayPrice.js).
//
// Older imports, the sync and the app's stock updates copied variants[0],
// which follows AliExpress's arbitrary SKU order (live example:
// imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165 showed ৳47,546 = 4TB while
// the 128GB default is ৳2,851.49). Cards, search, price sort, SEO and the
// chat bot read these top-level fields.
//
// Only those five fields are written. variants[] (what the cart charges) is
// never touched. Products without a priced variant are skipped.
//
// DRY RUN BY DEFAULT: prints a summary and writes a JSON report to
// tools/backfill/ (git-ignored). --apply first saves a backup of every touched
// product's old values next to the report, then updates each product in a
// transaction that re-reads it and recomputes from its CURRENT variants (a
// sync or order in between is respected). Each write stamps a new
// priceBackfillAt (+ lastWriteSource "price_backfill"), on which
// onProductStockUpdated sends nothing at all (marketing/priceChange.js), and
// also syncDiscountMarketingSuppressedAt for the older deployed trigger.
//
// Credentials: application-default credentials (gcloud auth
// application-default login), or FIRESTORE_EMULATOR_HOST.
//
// Usage (from functions/):
//   node scripts/backfillDisplayPrice.js [--products=id,id] [--limit=N] [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { displayPriceFields } = require("../catalog/displayPrice");
const { SYNC_MARKETING_SUPPRESSED_FIELD } = require("../aliexpress/variantRefresh");
const { PRICE_BACKFILL_FIELD, PRICE_BACKFILL_SOURCE } = require("../marketing/priceChange");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const FIELDS = ["price", "piecePrice", "oldPrice", "mrp", "unit"];

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function sameValue(field, a, b) {
  if (field === "unit") return String(a ?? "").trim() === String(b ?? "").trim();
  return Math.abs(num(a) - num(b)) < 0.005;
}

/**
 * The fields of [product] that differ from its display variant, as
 * { field: { from, to } }; null when nothing differs or no variant is priced.
 */
function plannedChanges(product) {
  const target = displayPriceFields(product?.variants);
  if (!target) return null;
  const changes = {};
  for (const field of FIELDS) {
    if (!(field in target)) continue;
    if (!sameValue(field, product[field], target[field])) {
      changes[field] = { from: product[field] ?? null, to: target[field] };
    }
  }
  return Object.keys(changes).length ? changes : null;
}

function parseArgs(argv) {
  const args = { apply: false, products: [], limit: 0 };
  for (const arg of argv) {
    if (arg === "--apply") args.apply = true;
    else if (arg.startsWith("--products=")) args.products = arg.slice(11).split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg.startsWith("--limit=")) args.limit = Math.max(0, parseInt(arg.slice(8), 10) || 0);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  let docs;
  if (args.products.length) {
    const snaps = await db.getAll(...args.products.map((id) => db.collection("products").doc(id)));
    docs = snaps.filter((s) => s.exists);
  } else {
    docs = (await db.collection("products").get()).docs;
  }

  const planned = [];
  let skippedNoVariants = 0;
  for (const doc of docs) {
    const data = doc.data();
    if (!Array.isArray(data.variants) || !data.variants.length) {
      skippedNoVariants += 1;
      continue;
    }
    const changes = plannedChanges(data);
    if (changes) {
      planned.push({
        id: doc.id,
        name: String(data.name || "").slice(0, 80),
        source: data.source || "",
        isActive: data.isActive !== false,
        variantCount: data.variants.length,
        changes,
      });
    }
    if (args.limit && planned.length >= args.limit) break;
  }

  planned.sort((a, b) => num(b.changes.price?.from) - num(b.changes.price?.to) - (num(a.changes.price?.from) - num(a.changes.price?.to)));

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const reportPath = path.join(OUT_DIR, `display-price-${args.apply ? "apply" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(reportPath, JSON.stringify({ scanned: docs.length, skippedNoVariants, planned }, null, 2));

  const priceChanges = planned.filter((p) => p.changes.price);
  console.log(`Scanned ${docs.length} products (${skippedNoVariants} without variants).`);
  console.log(`${planned.length} need a change; ${priceChanges.length} of them change the shown price.`);
  for (const p of priceChanges.slice(0, 25)) {
    console.log(`  ${p.id}  ৳${num(p.changes.price.from).toFixed(2)} -> ৳${num(p.changes.price.to).toFixed(2)}  ${p.isActive ? "" : "[inactive] "}${p.name}`);
  }
  if (priceChanges.length > 25) console.log(`  ... ${priceChanges.length - 25} more in the report`);
  console.log(`Report: ${reportPath}`);

  if (!args.apply) {
    console.log("DRY RUN — nothing written. Re-run with --apply to write.");
    return;
  }

  const backupPath = path.join(OUT_DIR, `display-price-backup-${stamp}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(planned.map((p) => ({
    id: p.id,
    before: Object.fromEntries(Object.entries(p.changes).map(([f, c]) => [f, c.from])),
  })), null, 2));
  console.log(`Backup: ${backupPath}`);

  let written = 0;
  let unchanged = 0;
  for (const p of planned) {
    const ref = db.collection("products").doc(p.id);
    const didWrite = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const changes = plannedChanges(snap.data());
      if (!changes) return false;
      const update = Object.fromEntries(Object.entries(changes).map(([f, c]) => [f, c.to]));
      update[SYNC_MARKETING_SUPPRESSED_FIELD] = admin.firestore.FieldValue.serverTimestamp();
      update[PRICE_BACKFILL_FIELD] = admin.firestore.FieldValue.serverTimestamp();
      update.lastWriteSource = PRICE_BACKFILL_SOURCE;
      tx.update(ref, update);
      return true;
    });
    if (didWrite) written += 1;
    else unchanged += 1;
  }
  console.log(`Applied: ${written} written, ${unchanged} already correct by now.`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { plannedChanges };
