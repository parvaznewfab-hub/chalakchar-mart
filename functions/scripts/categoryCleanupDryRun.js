#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Category cleanup — DRY RUN ONLY.
//
// Reads categories, subcategories, products and banners and writes a report
// (JSON + Markdown) describing what the cleanup WOULD do:
//   1. merge each group of same-named categories into one canonical doc
//      (same key as ensureCategoryExists: normalizeCategoryKey),
//   2. assign categoryId to products that only carry a category name,
//   3. list empty categories,
//   4. list the URL / SEO / homepage effects.
//
// This script never writes to Firestore: it only calls .get(). It has no
// --apply mode; the apply step will be a separate, reviewed script.
// Products named "Other" / "Uncategorized" / empty are reported but skipped
// (fixed by hand in the admin Product Manager "Uncategorized" filter).
//
// Usage:
//   node functions/scripts/categoryCleanupDryRun.js --out=<dir>
//
// Credentials: standard firebase-admin resolution (Application Default
// Credentials or GOOGLE_APPLICATION_CREDENTIALS), or FIRESTORE_EMULATOR_HOST.
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const { normalizeCategoryKey } = require("../category/categoryNormalize");

// Product category names that mean "no real category"; skipped, fixed by hand.
const SKIPPED_PRODUCT_CATEGORY_KEYS = new Set(["", "other", "uncategorized"]);

function text(value) {
  return String(value ?? "").trim();
}

/** Same slug as functions/index.js seoSlug and the Flutter _categorySlug. */
function seoSlug(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value._seconds === "number") return value._seconds * 1000;
  return null;
}

function isVisibleOnHome(cat) {
  return cat.isActive === true && cat.showOnHome !== false;
}

function hasImage(cat) {
  return Boolean(text(cat.image) || text(cat.imageUrl));
}

/**
 * Canonical pick, in order: most products by id, visible on the homepage,
 * has an image, oldest createdAt (missing last), then lowest id for stability.
 */
function compareCanonicalCandidates(a, b) {
  if (b.productsById !== a.productsById) return b.productsById - a.productsById;
  if (a.visibleOnHome !== b.visibleOnHome) return a.visibleOnHome ? -1 : 1;
  if (a.hasImage !== b.hasImage) return a.hasImage ? -1 : 1;
  const ca = a.createdAtMs ?? Number.MAX_SAFE_INTEGER;
  const cb = b.createdAtMs ?? Number.MAX_SAFE_INTEGER;
  if (ca !== cb) return ca - cb;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/**
 * Pure planning step (no Firestore). Each input is an array of
 * { id, ...docData }.
 */
function buildCleanupPlan({ categories, subcategories, products, banners }) {
  const catById = new Map(categories.map((c) => [c.id, c]));

  const productsByCatId = new Map();
  for (const p of products) {
    const id = text(p.categoryId);
    if (id) productsByCatId.set(id, (productsByCatId.get(id) || 0) + 1);
  }
  const subsByCatId = new Map();
  for (const s of subcategories) {
    const id = text(s.categoryId);
    if (!subsByCatId.has(id)) subsByCatId.set(id, []);
    subsByCatId.get(id).push(s);
  }
  const bannerRefs = (catId) =>
    banners.filter((b) => text(b.categoryId) === catId || text(b.clickValue) === catId);

  // --- 1. Group categories by normalized name -------------------------------
  const groups = new Map();
  for (const c of categories) {
    const key = normalizeCategoryKey(c.name);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(c);
  }

  const canonicalIdByKey = new Map();
  const mergeGroups = [];
  const canonicalFixes = [];
  for (const [key, members] of groups) {
    const candidates = members
      .map((c) => ({
        id: c.id,
        name: text(c.name),
        productsById: productsByCatId.get(c.id) || 0,
        subcategories: (subsByCatId.get(c.id) || []).length,
        bannerRefs: bannerRefs(c.id).map((b) => b.id),
        isActive: c.isActive === true,
        showOnHome: c.showOnHome !== false,
        visibleOnHome: isVisibleOnHome(c),
        hasImage: hasImage(c),
        priority: c.priority ?? null,
        createdAtMs: millis(c.createdAt),
        normalizedName: c.normalizedName ?? null,
        mergedInto: c.mergedInto ?? null,
        slug: seoSlug(c.name),
      }))
      .sort(compareCanonicalCandidates);

    const canonical = candidates[0];
    canonicalIdByKey.set(key, canonical.id);
    if (canonical.normalizedName !== key) {
      canonicalFixes.push({ categoryId: canonical.id, set: { normalizedName: key } });
    }
    if (members.length < 2) continue;

    const losers = candidates.slice(1);
    const canonicalSubNames = new Set(
      (subsByCatId.get(canonical.id) || []).map((s) => normalizeCategoryKey(s.name))
    );

    mergeGroups.push({
      key,
      canonical,
      losers,
      decisionsNeeded: [
        ...(losers.some((l) => l.visibleOnHome) && !canonical.visibleOnHome
          ? ["A merged-away doc is visible on the homepage but the canonical is not."]
          : []),
        ...(losers.some((l) => l.hasImage) && !canonical.hasImage
          ? ["Canonical has no image but a merged-away doc does (copy it?)."]
          : []),
      ],
      writes: {
        products: products
          .filter((p) => losers.some((l) => l.id === text(p.categoryId)))
          .map((p) => ({
            productId: p.id,
            from: text(p.categoryId),
            set: { categoryId: canonical.id, category: canonical.name },
            categoryTextChanges: text(p.category) !== canonical.name,
          })),
        subcategories: losers.flatMap((l) =>
          (subsByCatId.get(l.id) || []).map((s) => ({
            subcategoryId: s.id,
            name: text(s.name),
            from: l.id,
            set: { categoryId: canonical.id },
            nameCollidesUnderCanonical: canonicalSubNames.has(normalizeCategoryKey(s.name)),
          }))
        ),
        banners: losers.flatMap((l) =>
          bannerRefs(l.id).map((b) => ({
            bannerId: b.id,
            from: l.id,
            fields: ["categoryId", "clickValue"].filter((f) => text(b[f]) === l.id),
            set: { categoryId: canonical.id },
          }))
        ),
        mergedAway: losers.map((l) => ({
          categoryId: l.id,
          set: { isActive: false, showOnHome: false, mergedInto: canonical.id },
          deleteFields: ["normalizedName"],
        })),
      },
    });
  }

  // --- 2. Products with no categoryId ---------------------------------------
  const nameOnly = { assign: [], skippedForManualFix: [], unknownName: [] };
  const danglingCategoryId = [];
  for (const p of products) {
    const id = text(p.categoryId);
    if (id) {
      if (!catById.has(id)) {
        danglingCategoryId.push({ productId: p.id, categoryId: id, category: text(p.category) });
      }
      continue;
    }
    const key = normalizeCategoryKey(p.category);
    if (SKIPPED_PRODUCT_CATEGORY_KEYS.has(key)) {
      nameOnly.skippedForManualFix.push({ productId: p.id, name: text(p.name), category: text(p.category) });
    } else if (canonicalIdByKey.has(key)) {
      const canonicalId = canonicalIdByKey.get(key);
      const canonicalName = text(catById.get(canonicalId).name);
      nameOnly.assign.push({
        productId: p.id,
        category: text(p.category),
        set: { categoryId: canonicalId, category: canonicalName },
        categoryTextChanges: text(p.category) !== canonicalName,
      });
    } else {
      nameOnly.unknownName.push({ productId: p.id, name: text(p.name), category: text(p.category) });
    }
  }

  // --- 3. Empty categories (after the plan) ---------------------------------
  const mergedAwayIds = new Set(mergeGroups.flatMap((g) => g.losers.map((l) => l.id)));
  const afterCounts = new Map(productsByCatId);
  for (const g of mergeGroups) {
    for (const l of g.losers) {
      afterCounts.set(g.canonical.id, (afterCounts.get(g.canonical.id) || 0) + (afterCounts.get(l.id) || 0));
      afterCounts.set(l.id, 0);
    }
  }
  for (const a of nameOnly.assign) {
    afterCounts.set(a.set.categoryId, (afterCounts.get(a.set.categoryId) || 0) + 1);
  }
  const emptyCategories = {
    mergedAway: [...mergedAwayIds].map((id) => ({ id, name: text(catById.get(id).name) })),
    uniqueAndEmpty: categories
      .filter((c) => !mergedAwayIds.has(c.id) && !(afterCounts.get(c.id) > 0))
      .map((c) => ({
        id: c.id,
        name: text(c.name),
        visibleOnHome: isVisibleOnHome(c),
        subcategories: (subsByCatId.get(c.id) || []).length,
        bannerRefs: bannerRefs(c.id).map((b) => b.id),
      })),
  };

  // --- 4. URLs, SEO and homepage --------------------------------------------
  const activeSlugUses = new Map();
  for (const c of categories.filter((x) => x.isActive === true)) {
    const slug = seoSlug(c.name);
    if (!activeSlugUses.has(slug)) activeSlugUses.set(slug, []);
    activeSlugUses.get(slug).push(c.id);
  }
  const visibleBefore = categories.filter(isVisibleOnHome);
  const visibleAfter = visibleBefore.filter((c) => !mergedAwayIds.has(c.id));
  const seo = {
    categoryUrlPattern: "/category/{seoSlug(name)} — contains no categoryId",
    duplicateSlugsInSitemapAndHomeSeo: [...activeSlugUses]
      .filter(([, ids]) => ids.length > 1)
      .map(([slug, ids]) => ({ slug, categoryIds: ids })),
    slugChanges: mergeGroups.flatMap((g) =>
      g.losers
        .filter((l) => l.slug !== g.canonical.slug)
        .map((l) => ({ from: `/category/${l.slug}`, to: `/category/${g.canonical.slug}`, loserId: l.id }))
    ),
  };
  const homepage = {
    categoryTilesBefore: visibleBefore.map((c) => text(c.name)).sort(),
    categoryTilesAfter: visibleAfter.map((c) => text(c.name)).sort(),
    // The customer category page queries products by exact `category` text,
    // so only products whose text changes can appear/disappear there.
    productsWhoseCategoryTextChanges: [
      ...mergeGroups.flatMap((g) => g.writes.products.filter((w) => w.categoryTextChanges)),
      ...nameOnly.assign.filter((a) => a.categoryTextChanges),
    ].map((w) => ({ productId: w.productId, newCategory: w.set.category })),
  };

  return {
    totals: {
      categories: categories.length,
      subcategories: subcategories.length,
      products: products.length,
      banners: banners.length,
      duplicateGroups: mergeGroups.length,
      categoriesMergedAway: mergedAwayIds.size,
      productsRepointedByMerge: mergeGroups.reduce((n, g) => n + g.writes.products.length, 0),
      nameOnlyProductsAssigned: nameOnly.assign.length,
      nameOnlyProductsSkipped: nameOnly.skippedForManualFix.length,
      nameOnlyProductsUnknownName: nameOnly.unknownName.length,
      productsWithDanglingCategoryId: danglingCategoryId.length,
      uniqueEmptyCategories: emptyCategories.uniqueAndEmpty.length,
    },
    mergeGroups,
    canonicalFixes,
    nameOnly,
    danglingCategoryId,
    emptyCategories,
    seo,
    homepage,
  };
}

function renderMarkdown(plan) {
  const t = plan.totals;
  const lines = [
    "# Category cleanup — dry run",
    "",
    "No Firestore writes were made.",
    "",
    "## Totals",
    ...Object.entries(t).map(([k, v]) => `- ${k}: ${v}`),
    "",
    "## Duplicate groups",
  ];
  for (const g of plan.mergeGroups) {
    lines.push("", `### ${g.canonical.name}`);
    lines.push("| role | id | products | subs | banners | visible | image | created |");
    lines.push("|---|---|---|---|---|---|---|---|");
    for (const [role, c] of [["canonical", g.canonical], ...g.losers.map((l) => ["merge", l])]) {
      const created = c.createdAtMs ? new Date(c.createdAtMs).toISOString().slice(0, 10) : "—";
      lines.push(`| ${role} | ${c.id} | ${c.productsById} | ${c.subcategories} | ${c.bannerRefs.length} | ${c.visibleOnHome ? "yes" : "no"} | ${c.hasImage ? "yes" : "no"} | ${created} |`);
    }
    const collisions = g.writes.subcategories.filter((s) => s.nameCollidesUnderCanonical);
    for (const d of g.decisionsNeeded) lines.push(`- **Decision:** ${d}`);
    for (const s of collisions) lines.push(`- **Decision:** subcategory "${s.name}" (${s.subcategoryId}) already exists under the canonical.`);
  }
  lines.push(
    "",
    "## Name-only products",
    `- assign categoryId: ${plan.nameOnly.assign.length}`,
    `- skipped (fix by hand via admin "Uncategorized" filter): ${plan.nameOnly.skippedForManualFix.length}`,
    `- unknown category name (needs review): ${plan.nameOnly.unknownName.length}`,
    ...plan.nameOnly.unknownName.map((p) => `  - ${p.productId} "${p.name}" → "${p.category}"`),
    `- products whose categoryId points at a missing category: ${plan.danglingCategoryId.length}`,
    "",
    "## Empty categories after cleanup",
    `- merged-away (emptied by the merge): ${plan.emptyCategories.mergedAway.length}`,
    `- unique and empty: ${plan.emptyCategories.uniqueAndEmpty.length}`,
    ...plan.emptyCategories.uniqueAndEmpty.map(
      (c) => `  - ${c.name} (${c.id})${c.visibleOnHome ? " — visible on homepage" : ""}${c.bannerRefs.length ? ` — ${c.bannerRefs.length} banner(s)` : ""}`
    ),
    "",
    "## URLs and SEO",
    `- Category URL pattern: ${plan.seo.categoryUrlPattern}`,
    `- Duplicate /category slugs today (sitemap + homeSeo list them twice): ${plan.seo.duplicateSlugsInSitemapAndHomeSeo.map((d) => d.slug).join(", ") || "none"}`,
    `- Category URLs that change: ${plan.seo.slugChanges.length ? plan.seo.slugChanges.map((s) => `${s.from} → ${s.to}`).join(", ") : "none"}`,
    "",
    "## Customer homepage",
    `- Category tiles before (${plan.homepage.categoryTilesBefore.length}): ${plan.homepage.categoryTilesBefore.join(", ")}`,
    `- Category tiles after (${plan.homepage.categoryTilesAfter.length}): ${plan.homepage.categoryTilesAfter.join(", ")}`,
    `- Products whose category text changes (can appear/disappear on /category pages): ${plan.homepage.productsWhoseCategoryTextChanges.length}`,
    ...plan.homepage.productsWhoseCategoryTextChanges.map((p) => `  - ${p.productId} → "${p.newCategory}"`)
  );
  return lines.join("\n") + "\n";
}

async function main() {
  const outArg = process.argv.find((a) => a.startsWith("--out="));
  if (!outArg) {
    console.error("Usage: node functions/scripts/categoryCleanupDryRun.js --out=<dir>");
    process.exit(1);
  }
  const outDir = path.resolve(outArg.slice("--out=".length));

  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();

  // READ-ONLY.
  const read = async (name) =>
    (await db.collection(name).get()).docs.map((d) => ({ id: d.id, ...d.data() }));
  const [categories, subcategories, products, banners] = await Promise.all(
    ["categories", "subcategories", "products", "banners"].map(read)
  );

  const plan = buildCleanupPlan({ categories, subcategories, products, banners });
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, "category-cleanup-plan.json"), JSON.stringify(plan, null, 2));
  fs.writeFileSync(path.join(outDir, "category-cleanup-plan.md"), renderMarkdown(plan));
  console.log(JSON.stringify(plan.totals, null, 2));
  console.log(`Report written to ${outDir}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { buildCleanupPlan, renderMarkdown, compareCanonicalCandidates, seoSlug };
