#!/usr/bin/env node
// -----------------------------------------------------------------------------
// RETIRED (2026-11): Mobile Parts › "Motherboard & Mainboard" was retired by
// scripts/categoryMerge.js --retire-subcategory; motherboards are now the
// top-level "Motherboard" category with brand subcategories. Once that runs,
// the retired subcategory has no normalizedName, so this script aborts at
// loadSubcategory() instead of filing boards under Mobile Parts again.
// -----------------------------------------------------------------------------
// Second-stage, one-time backfill: moves the products that
// backfillAliExpressCategoryReview.js flagged Uncategorized/needsCategoryReview
// into the real "Mobile Parts" category (see functions/category/), splitting
// them into its two subcategories — "Motherboard & Mainboard" and
// "Display & Digitizer" — by a keyword match on the product name/title.
//
// This script does NOT create the "Mobile Parts" category or its
// subcategories — they must already exist (created once via the shared
// ensureCategoryExists()/ensureSubcategoryExists() resolvers, same as any
// other admin-sourced category) before this script is run. It only ever
// reads them, never creates — if either is missing, the script aborts
// immediately rather than silently creating a possibly-misconfigured
// category as a side effect of a "backfill" run.
//
// Products whose name/title matches neither keyword group are left
// untouched (still Uncategorized/needsCategoryReview: true) and reported
// separately — this script never guesses a category for a product it can't
// confidently classify.
//
// DRY RUN BY DEFAULT. No Firestore write happens unless --apply is passed
// explicitly.
//
// Usage:
//   node functions/scripts/backfillMobilePartsSubcategory.js [--limit=500] [--apply]
//
// Credentials: standard firebase-admin resolution — set
// GOOGLE_APPLICATION_CREDENTIALS for a real project, or FIRESTORE_EMULATOR_HOST
// to point at a local Firestore emulator instead.
// -----------------------------------------------------------------------------

const admin = require("firebase-admin");
const { normalizeCategoryKey } = require("../category/categoryNormalize");

const TARGET_CATEGORY_NAME = "Mobile Parts";
const SUBCATEGORY_MOTHERBOARD = "Motherboard & Mainboard";
const SUBCATEGORY_DISPLAY = "Display & Digitizer";
const WRITE_BATCH_LIMIT = 400; // stays under Firestore's 500-op cap

// Order matters: motherboard/mainboard checked first — a title mentioning
// both (rare) is filed under the board, since a cracked-display listing
// would say so far more prominently than in passing.
const MOTHERBOARD_KEYWORDS_RE = /\b(motherboard|main\s?board|logic\s?board)\b/i;
const DISPLAY_KEYWORDS_RE = /\b(display|digitizer|touch\s?screen|\blcd\b|amoled|oled)\b/i;

function classifyByTitle(name) {
  const text = String(name || "");
  if (MOTHERBOARD_KEYWORDS_RE.test(text)) return SUBCATEGORY_MOTHERBOARD;
  if (DISPLAY_KEYWORDS_RE.test(text)) return SUBCATEGORY_DISPLAY;
  return null;
}

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

// Read-only lookups — never creates. Throws if the taxonomy this script
// depends on doesn't exist yet.
async function loadMobilePartsTaxonomy(db) {
  const categorySnap = await db
    .collection("categories")
    .where("normalizedName", "==", normalizeCategoryKey(TARGET_CATEGORY_NAME))
    .limit(1)
    .get();
  if (categorySnap.empty) {
    throw new Error(
      `"${TARGET_CATEGORY_NAME}" category does not exist yet — create it (and its subcategories) first, then re-run this script.`
    );
  }
  const categoryDoc = categorySnap.docs[0];
  const categoryId = categoryDoc.id;
  const categoryName = categoryDoc.data().name || TARGET_CATEGORY_NAME;

  async function loadSubcategory(name) {
    const snap = await db
      .collection("subcategories")
      .where("categoryId", "==", categoryId)
      .where("normalizedName", "==", normalizeCategoryKey(name))
      .limit(1)
      .get();
    if (snap.empty) {
      throw new Error(
        `Subcategory "${name}" under "${TARGET_CATEGORY_NAME}" does not exist yet — create it first, then re-run this script.`
      );
    }
    return snap.docs[0].id;
  }

  const [motherboardSubcategoryId, displaySubcategoryId] = await Promise.all([
    loadSubcategory(SUBCATEGORY_MOTHERBOARD),
    loadSubcategory(SUBCATEGORY_DISPLAY),
  ]);

  return {
    categoryId,
    categoryName,
    subcategoryIdByName: {
      [SUBCATEGORY_MOTHERBOARD]: motherboardSubcategoryId,
      [SUBCATEGORY_DISPLAY]: displaySubcategoryId,
    },
  };
}

async function findNeedsReviewProducts(db, limit) {
  const snapshot = await db
    .collection("products")
    .where("needsCategoryReview", "==", true)
    .limit(limit)
    .get();
  return snapshot.docs;
}

function buildReportRow(doc, taxonomy) {
  const data = doc.data() || {};
  const name = data.name || data.title || "";
  const matchedSubcategoryName = classifyByTitle(name);

  const row = {
    productId: doc.id,
    sourceProductId: data.sourceProductId || null,
    name,
    currentCategory: data.category || null,
    matched: Boolean(matchedSubcategoryName),
    nextCategory: matchedSubcategoryName ? TARGET_CATEGORY_NAME : data.category || null,
    nextSubcategory: matchedSubcategoryName,
    nextNeedsCategoryReview: matchedSubcategoryName ? false : true,
  };
  if (matchedSubcategoryName) {
    row.nextSubcategoryId = taxonomy.subcategoryIdByName[matchedSubcategoryName];
  }
  return row;
}

async function applyUpdates(db, docs, report, taxonomy) {
  const reportById = new Map(report.map((row) => [row.productId, row]));
  let batch = db.batch();
  let ops = 0;

  for (const doc of docs) {
    const row = reportById.get(doc.id);
    if (!row || !row.matched) continue;

    batch.update(doc.ref, {
      category: TARGET_CATEGORY_NAME,
      categoryId: taxonomy.categoryId,
      subcategoryId: row.nextSubcategoryId,
      needsCategoryReview: false,
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

  const taxonomy = await loadMobilePartsTaxonomy(db);
  const docs = await findNeedsReviewProducts(db, limit);
  const report = docs.map((doc) => buildReportRow(doc, taxonomy));

  const matchedMotherboard = report.filter((r) => r.nextSubcategory === SUBCATEGORY_MOTHERBOARD).length;
  const matchedDisplay = report.filter((r) => r.nextSubcategory === SUBCATEGORY_DISPLAY).length;
  const unmatched = report.filter((r) => !r.matched).length;

  console.log(
    `[backfillMobilePartsSubcategory] scanned ${report.length} product(s) with needsCategoryReview == true`
  );
  console.log(
    `[backfillMobilePartsSubcategory] would move: ${matchedMotherboard} -> "${SUBCATEGORY_MOTHERBOARD}", ${matchedDisplay} -> "${SUBCATEGORY_DISPLAY}", ${unmatched} left unmatched (untouched)`
  );
  if (report.length) {
    if (console.table) console.table(report);
    else console.log(JSON.stringify(report, null, 2));
  }

  if (!apply) {
    console.log(
      `[backfillMobilePartsSubcategory] DRY RUN — no Firestore writes performed. Re-run with --apply to update ${matchedMotherboard + matchedDisplay} product(s).`
    );
    return { dryRun: true, scanned: report.length, matchedMotherboard, matchedDisplay, unmatched, report };
  }

  await applyUpdates(db, docs, report, taxonomy);
  console.log(
    `[backfillMobilePartsSubcategory] APPLIED — updated ${matchedMotherboard + matchedDisplay} product(s) (${unmatched} left unmatched/untouched).`
  );
  return { dryRun: false, scanned: report.length, matchedMotherboard, matchedDisplay, unmatched, report };
}

if (require.main === module) {
  run().catch((error) => {
    console.error("[backfillMobilePartsSubcategory] failed", error);
    process.exitCode = 1;
  });
}

module.exports = {
  run,
  classifyByTitle,
  loadMobilePartsTaxonomy,
  findNeedsReviewProducts,
  buildReportRow,
  parseArgs,
  TARGET_CATEGORY_NAME,
  SUBCATEGORY_MOTHERBOARD,
  SUBCATEGORY_DISPLAY,
};
