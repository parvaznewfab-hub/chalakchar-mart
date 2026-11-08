#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill for AliExpress-sourced products and categories that went
// live/homepage-visible without admin review before the following fixes:
//
//   - buildMarketplaceProductPayload() callers now force isActive:false,
//     needsReview:true for every unattended AliExpress ingestion path —
//     aliexpressDiscoverProducts/aliexpressScheduledDiscover (Feature A) and
//     importAliExpressProduct (the n8n webhook). Only aliexpressSearchImport
//     (Feature B — a real shopper's search) and aliexpressImportByUrl (an
//     admin manually picking one specific product) are still allowed to
//     publish immediately, since a human explicitly chose those.
//   - ensureCategoryExists()/ensureSubcategoryExists() now default
//     source: "aliexpress" categories/subcategories to isActive:false,
//     showOnHome:false, status:"pending", same as vendor-sourced ones,
//     instead of the admin (immediately-visible) defaults.
//
// Products/categories imported/created BEFORE those fixes deployed are still
// sitting live in Firestore with the old (unsafe) values. This script finds
// them and resets them to the safe, needs-review state an admin can now
// review from the Admin Panel.
//
// Scope — products: source == "aliexpress", isActive == true, and
// importedBy NOT one of the two human-triggered tags ("search_trigger" =
// Feature B, "aliexpress_api" = admin one-click import-by-URL). Everything
// else (importedBy == "n8n", "aliexpress_discover", or unset) is unattended
// and gets reset.
//
// Scope — categories/subcategories: autoCreated == true, source ==
// "aliexpress", isActive == true. Manually-managed categories (autoCreated
// missing/false, or isActive already false) are never touched.
//
// DRY RUN BY DEFAULT. No Firestore write happens unless --apply is passed
// explicitly, and even then only documents this script itself found and
// printed are touched.
//
// Usage:
//   node functions/scripts/backfillAliExpressUnreviewedLive.js [--limit=500] [--apply]
//
// Credentials: standard firebase-admin resolution — set
// GOOGLE_APPLICATION_CREDENTIALS for a real project, or FIRESTORE_EMULATOR_HOST
// (e.g. 127.0.0.1:8080) to point at a local Firestore emulator instead.
// -----------------------------------------------------------------------------

const admin = require("firebase-admin");

const WRITE_BATCH_LIMIT = 400; // stays under Firestore's 500-op cap
// importedBy values that mean a human explicitly chose this specific
// product — these must never be reset by this script.
const HUMAN_TRIGGERED_IMPORTED_BY = new Set(["search_trigger", "aliexpress_api"]);

function parseArgs(argv) {
  const args = { limit: 1000, apply: false };
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

// Single equality filter (source == "aliexpress") plus a client-side filter
// on isActive/importedBy — avoids requiring a composite index for a
// three-way equality query that would only ever run this once.
async function findUnreviewedLiveProducts(db, limit) {
  const snapshot = await db.collection("products").where("source", "==", "aliexpress").limit(limit).get();
  return snapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    return data.isActive === true && !HUMAN_TRIGGERED_IMPORTED_BY.has(data.importedBy);
  });
}

async function findLiveAliExpressDocs(collectionName, db, limit) {
  const snapshot = await db
    .collection(collectionName)
    .where("source", "==", "aliexpress")
    .where("autoCreated", "==", true)
    .limit(limit)
    .get();
  return snapshot.docs.filter((doc) => (doc.data() || {}).isActive === true);
}

function buildProductReportRow(doc) {
  const data = doc.data() || {};
  return {
    productId: doc.id,
    name: data.name || null,
    importedBy: data.importedBy || "(none)",
    currentIsActive: data.isActive === true,
    currentNeedsReview: data.needsReview === true,
    nextIsActive: false,
    nextNeedsReview: true,
  };
}

function buildCategoryReportRow(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    name: data.name || null,
    currentIsActive: data.isActive === true,
    currentShowOnHome: data.showOnHome === true,
    nextIsActive: false,
    nextShowOnHome: false,
  };
}

async function applyProductUpdates(db, docs) {
  let batch = db.batch();
  let ops = 0;
  for (const doc of docs) {
    batch.update(doc.ref, {
      isActive: false,
      isVisible: false,
      isPublished: false,
      showOnHome: false,
      needsReview: true,
      approvalStatus: "draft",
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

async function applyCategoryUpdates(db, docs) {
  let batch = db.batch();
  let ops = 0;
  for (const doc of docs) {
    batch.update(doc.ref, {
      isActive: false,
      showOnHome: false,
      status: "pending",
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

function printReport(label, report) {
  console.log(`\n[backfillAliExpressUnreviewedLive] ${label}: ${report.length} found`);
  if (report.length) {
    if (console.table) console.table(report);
    else console.log(JSON.stringify(report, null, 2));
  }
}

async function run(options = {}) {
  const { limit, apply } = { ...parseArgs(process.argv.slice(2)), ...options };

  if (!admin.apps.length) admin.initializeApp();
  const db = options.db || admin.firestore();

  const productDocs = await findUnreviewedLiveProducts(db, limit);
  const categoryDocs = await findLiveAliExpressDocs("categories", db, limit);
  const subcategoryDocs = await findLiveAliExpressDocs("subcategories", db, limit);

  const productReport = productDocs.map(buildProductReportRow);
  const categoryReport = categoryDocs.map(buildCategoryReportRow);
  const subcategoryReport = subcategoryDocs.map(buildCategoryReportRow);

  printReport("unattended-imported products currently live", productReport);
  printReport("auto-created AliExpress categories currently live", categoryReport);
  printReport("auto-created AliExpress subcategories currently live", subcategoryReport);

  if (!apply) {
    console.log(
      `\n[backfillAliExpressUnreviewedLive] DRY RUN — no Firestore writes performed. ` +
      `Re-run with --apply to reset ${productReport.length} product(s), ${categoryReport.length} categor${categoryReport.length === 1 ? "y" : "ies"}, ` +
      `and ${subcategoryReport.length} subcategor${subcategoryReport.length === 1 ? "y" : "ies"}.`
    );
    return { dryRun: true, productReport, categoryReport, subcategoryReport };
  }

  await applyProductUpdates(db, productDocs);
  await applyCategoryUpdates(db, categoryDocs);
  await applyCategoryUpdates(db, subcategoryDocs);
  console.log(
    `\n[backfillAliExpressUnreviewedLive] APPLIED — reset ${productReport.length} product(s), ` +
    `${categoryReport.length} categor${categoryReport.length === 1 ? "y" : "ies"}, and ` +
    `${subcategoryReport.length} subcategor${subcategoryReport.length === 1 ? "y" : "ies"}.`
  );
  return { dryRun: false, productReport, categoryReport, subcategoryReport };
}

if (require.main === module) {
  run().catch((error) => {
    console.error("[backfillAliExpressUnreviewedLive] failed", error);
    process.exitCode = 1;
  });
}

module.exports = {
  run,
  findUnreviewedLiveProducts,
  findLiveAliExpressDocs,
  buildProductReportRow,
  buildCategoryReportRow,
  parseArgs,
  HUMAN_TRIGGERED_IMPORTED_BY,
};
