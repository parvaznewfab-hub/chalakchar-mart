#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill for products stuck with the literal "AliExpress" category.
//
// Background: normalizeAliExpressProduct() (functions/index.js) used to fall
// back to the literal string "AliExpress" whenever an AliExpress product
// response had no category_name — common for mobile-parts/repair-accessory
// listings. That string then flowed into resolveProductTaxonomy(), which
// happily created (or reused) a real "AliExpress" category document. The bug
// is fixed (empty category_name now reaches the resolver as empty, which
// resolves to category: "Uncategorized", needsCategoryReview: true — see
// functions/category/resolveProductTaxonomy.js), but products imported
// before the fix are still sitting in that fake "AliExpress" category.
//
// This script finds those already-imported products and reports what they
// would become under the fixed logic. It NEVER invents a real category and
// NEVER forces them into an existing category (e.g. "Electronics") — only
// ever flips them to Uncategorized + needsCategoryReview: true, exactly like
// a fresh import with no category_name would resolve today. An admin then
// re-files each one manually via the Category Manager.
//
// DRY RUN BY DEFAULT — this script has never been run against production.
// No Firestore write happens unless --apply is passed explicitly, and even
// then it only touches products this script itself found and printed.
//
// Usage:
//   node functions/scripts/backfillAliExpressCategoryReview.js [--limit=500] [--apply]
//
// Credentials: standard firebase-admin resolution — set
// GOOGLE_APPLICATION_CREDENTIALS for a real project, or FIRESTORE_EMULATOR_HOST
// (e.g. 127.0.0.1:8080) to point at a local Firestore emulator instead.
// -----------------------------------------------------------------------------

const admin = require("firebase-admin");

const LEGACY_CATEGORY_NAME = "AliExpress";
const UNCATEGORIZED_NAME = "Uncategorized";
const WRITE_BATCH_LIMIT = 400; // stays under Firestore's 500-op cap

function parseArgs(argv) {
  const args = { limit: 500, apply: false };
  for (const raw of argv) {
    if (raw === "--apply") {
      args.apply = true;
    } else if (raw.startsWith("--limit=")) {
      const parsed = parseInt(raw.slice("--limit=".length), 10);
      if (Number.isFinite(parsed) && parsed > 0) args.limit = parsed;
    }
  }
  return args;
}

// Two equality filters (no range/orderBy on a different field) — no
// composite index required.
async function findLegacyAliExpressProducts(db, limit) {
  const snapshot = await db
    .collection("products")
    .where("source", "==", "aliexpress")
    .where("category", "==", LEGACY_CATEGORY_NAME)
    .limit(limit)
    .get();
  return snapshot.docs;
}

function buildReportRow(doc) {
  const data = doc.data() || {};
  return {
    productId: doc.id,
    sourceProductId: data.sourceProductId || null,
    name: data.name || data.title || null,
    currentCategory: data.category || null,
    currentCategoryId: data.categoryId || null,
    nextCategory: UNCATEGORIZED_NAME,
    nextCategoryId: null,
    nextNeedsCategoryReview: true,
  };
}

async function applyUpdates(db, docs) {
  let batch = db.batch();
  let ops = 0;

  for (const doc of docs) {
    batch.update(doc.ref, {
      category: UNCATEGORIZED_NAME,
      needsCategoryReview: true,
      categoryId: admin.firestore.FieldValue.delete(),
      subcategoryId: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    ops += 1;
    if (ops >= WRITE_BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
}

async function run(options = {}) {
  const { limit, apply } = { ...parseArgs(process.argv.slice(2)), ...options };

  if (!admin.apps.length) admin.initializeApp();
  const db = options.db || admin.firestore();

  const docs = await findLegacyAliExpressProducts(db, limit);
  const report = docs.map(buildReportRow);

  console.log(
    `[backfillAliExpressCategoryReview] scanned ${report.length} product(s) with source == "aliexpress" and category == "${LEGACY_CATEGORY_NAME}"`
  );
  if (report.length) {
    if (console.table) console.table(report);
    else console.log(JSON.stringify(report, null, 2));
  }

  if (!apply) {
    console.log(
      `[backfillAliExpressCategoryReview] DRY RUN — no Firestore writes performed. Re-run with --apply to update ${report.length} product(s).`
    );
    return { dryRun: true, scanned: report.length, report };
  }

  await applyUpdates(db, docs);
  console.log(`[backfillAliExpressCategoryReview] APPLIED — updated ${report.length} product(s).`);
  return { dryRun: false, scanned: report.length, report };
}

if (require.main === module) {
  run().catch((error) => {
    console.error("[backfillAliExpressCategoryReview] failed", error);
    process.exitCode = 1;
  });
}

module.exports = {
  run,
  findLegacyAliExpressProducts,
  buildReportRow,
  parseArgs,
  LEGACY_CATEGORY_NAME,
  UNCATEGORIZED_NAME,
};
