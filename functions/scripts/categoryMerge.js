#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Category duplicate merge. DRY RUN BY DEFAULT — writes nothing to Firestore
// unless --apply is passed.
//
// For each group of categories whose names share a merge key (trim, NFKC,
// collapse whitespace, lowercase, "&" == "and"):
//   - pick a canonical doc: source "admin" > no source (created by the
//     Category Manager UI, which never set `source`) > any other source;
//     then active; then most products by categoryId; then oldest; then id,
//   - copy image / imageUrl / description from the merged-away docs onto the
//     canonical where the canonical has none,
//   - repoint products (categoryId + category text), subcategories
//     (categoryId + categoryName) and banners from the others to it,
//   - mark the others isActive:false, showOnHome:false, mergedInto:<id> and
//     remove their normalizedName so ensureCategoryExists never matches them.
// Nothing is deleted.
//
// --retire-subcategory=<subId>:<categoryId> moves every product filed under
// that subcategory (and not already in <categoryId>) to <categoryId>, picks a
// brand subcategory under <categoryId> from the product title, and hides the
// retired subcategory (isActive:false, showOnHome:false, mergedInto).
// A brand that already exists as a subcategory there is assigned. A brand
// that does not is only PROPOSED (product moved with no subcategory) unless
// it is listed in --create-brand-subcategories=<a,b>, after review. A
// product whose brand is unclear gets no subcategory and is listed.
//
// --mark-manual=<categoryId,...> sets autoCreated:false on those categories.
//
// Also (every run):
//   - rewrites normalizedName (stored with normalizeCategoryKey, the key the
//     deployed ensureCategoryExists queries; grouping alone also folds "&")
//     on every non-merged category / subcategory whose stored key differs,
//   - products whose subcategoryId is not a child of their categoryId get it
//     cleared, or moved with --remap-subcategory=<fromSubId>:<toSubId>.
//
// --apply first writes a JSON backup of every doc it will touch to --out.
//
// Usage:
//   node functions/scripts/categoryMerge.js --out=<dir> [--apply]
//        [--remap-subcategory=<fromSubId>:<toSubId>]
//        [--retire-subcategory=<subId>:<categoryId>]
//        [--create-brand-subcategories=<brand,brand>] [--mark-manual=<categoryId,...>]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const { normalizeCategoryKey, slugifyCategoryName } = require("../category/categoryNormalize");

const WRITE_BATCH_LIMIT = 400;
const COPYABLE_FIELDS = ["image", "imageUrl", "description"];

// Brand subcategory names (lowercase, matching the existing "iphone").
// First column is the subcategory name; a title matching two different
// brands is "unclear".
const BRAND_RULES = [
  ["iphone", /\b(iphone|icloud|face\s?id|touch\s?id)\b/i],
  ["samsung", /\b(samsung|galaxy)\b/i],
  ["xiaomi", /\b(xiaomi|redmi|poco)\b/i],
  ["huawei", /\bhuawei\b/i],
  ["honor", /\bhonor\b/i],
  ["oppo", /\boppo\b/i],
  ["vivo", /\bvivo\b/i],
  ["realme", /\brealme\b/i],
  ["oneplus", /\bone\s?plus\b/i],
  ["google pixel", /\b(google\s+)?pixel\s?\d/i],
  ["motorola", /\b(motorola|moto\s?[a-z]\d*)\b/i],
  ["nokia", /\bnokia\b/i],
  ["infinix", /\binfinix\b/i],
  ["tecno", /\btecno\b/i],
];

function text(value) {
  return String(value ?? "").trim();
}

/** Dedup key: NFKC, "&" == "and", collapse whitespace, trim, lowercase. */
function mergeKey(raw) {
  const t = text(raw);
  if (!t) return "";
  return t
    .normalize("NFKC")
    .toLowerCase()
    .replace(/\s*&\s*/g, " and ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Returns a brand subcategory name, or null when none / more than one match. */
function classifyBrand(title) {
  const t = String(title || "");
  const hits = BRAND_RULES.filter(([, re]) => re.test(t)).map(([name]) => name);
  return hits.length === 1 ? hits[0] : null;
}

function millis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value._seconds === "number") return value._seconds * 1000;
  return null;
}

function sourceRank(cat) {
  const s = text(cat.source);
  if (s === "admin") return 0;
  if (!s) return 1;
  return 2;
}

function compareCanonical(a, b) {
  if (a.sourceRank !== b.sourceRank) return a.sourceRank - b.sourceRank;
  if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
  if (b.productsById !== a.productsById) return b.productsById - a.productsById;
  const ca = a.createdAtMs ?? Number.MAX_SAFE_INTEGER;
  const cb = b.createdAtMs ?? Number.MAX_SAFE_INTEGER;
  if (ca !== cb) return ca - cb;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/**
 * Pure planning step. Inputs are arrays of { id, ...data }.
 * options: { remapSubcategory: {from: to}, retireSubcategories: [{subId, toCategoryId}] }
 * Returns { totals, groups, collisions, invalidSubcategory, retired, creates, writes }.
 * New docs are referenced by placeholder ids "new:<collection>:<n>" until apply.
 */
function buildMergePlan({ categories, subcategories, products, banners = [] }, options = {}) {
  const remap = options.remapSubcategory || {};
  const retireList = options.retireSubcategories || [];
  const createBrands = new Set((options.createBrandSubcategories || []).map((b) => normalizeCategoryKey(b)));
  const markManual = options.markManual || [];
  const catById = new Map(categories.map((c) => [c.id, c]));
  const subById = new Map(subcategories.map((s) => [s.id, s]));
  const productsByCatId = new Map();
  for (const p of products) {
    const id = text(p.categoryId);
    if (id) productsByCatId.set(id, (productsByCatId.get(id) || 0) + 1);
  }

  // Writes are merged per doc so each doc gets one update.
  const writes = new Map();
  const write = (collection, id, set, reason, deleteFields = []) => {
    const k = `${collection}/${id}`;
    if (!writes.has(k)) writes.set(k, { collection, id, set: {}, deleteFields: [], reasons: [] });
    const w = writes.get(k);
    Object.assign(w.set, set);
    for (const f of deleteFields) if (!w.deleteFields.includes(f)) w.deleteFields.push(f);
    w.reasons.push(reason);
  };

  // --- 1. Duplicate groups ---------------------------------------------------
  const byKey = new Map();
  for (const c of categories) {
    if (text(c.mergedInto)) continue; // already merged on a previous run
    const key = mergeKey(c.name);
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(c);
  }

  const groups = [];
  const mergedAway = new Map(); // loserId -> canonical summary
  for (const [key, members] of byKey) {
    if (members.length < 2) continue;
    const ranked = members
      .map((c) => ({
        id: c.id,
        name: text(c.name),
        source: text(c.source) || null,
        sourceRank: sourceRank(c),
        isActive: c.isActive === true,
        showOnHome: c.showOnHome !== false,
        productsById: productsByCatId.get(c.id) || 0,
        subcategories: subcategories.filter((s) => text(s.categoryId) === c.id).length,
        createdAtMs: millis(c.createdAt),
      }))
      .sort(compareCanonical);
    const [canonical, ...losers] = ranked;

    // Fill the canonical's empty presentation fields from the losers, in rank order.
    const copied = {};
    const canonicalDoc = catById.get(canonical.id);
    for (const field of COPYABLE_FIELDS) {
      if (text(canonicalDoc[field])) continue;
      const donor = losers.find((l) => text(catById.get(l.id)[field]));
      if (donor) copied[field] = { value: text(catById.get(donor.id)[field]), from: donor.id };
    }
    if (Object.keys(copied).length) {
      write("categories", canonical.id,
        Object.fromEntries(Object.entries(copied).map(([f, v]) => [f, v.value])),
        `copied ${Object.entries(copied).map(([f, v]) => `${f} from ${v.from}`).join(", ")}`);
    }

    groups.push({ key, canonical, losers, copied });
    for (const l of losers) mergedAway.set(l.id, canonical);
  }
  const finalCategoryId = (id) => mergedAway.get(text(id))?.id || text(id);
  const finalCategoryName = (id) => text(catById.get(finalCategoryId(id))?.name);

  for (const [loserId, canonical] of mergedAway) {
    write("categories", loserId,
      { isActive: false, showOnHome: false, mergedInto: canonical.id },
      `merged into ${canonical.id}`, ["normalizedName"]);
  }

  const handledProducts = new Set();
  for (const p of products) {
    const canonical = mergedAway.get(text(p.categoryId));
    if (!canonical) continue;
    write("products", p.id, { categoryId: canonical.id, category: canonical.name },
      `category ${text(p.categoryId)} merged into ${canonical.id}`);
  }

  // Subcategory parents after the merge (and after retirement below).
  const subParent = new Map(subcategories.map((s) => [s.id, finalCategoryId(s.categoryId)]));
  const collisions = [];
  for (const s of subcategories) {
    const canonical = mergedAway.get(text(s.categoryId));
    if (!canonical) continue;
    const clash = subcategories.find(
      (o) => o.id !== s.id && subParent.get(o.id) === canonical.id && mergeKey(o.name) === mergeKey(s.name)
    );
    if (clash) collisions.push({ moving: s.id, name: text(s.name), existing: clash.id, canonical: canonical.id });
    write("subcategories", s.id, { categoryId: canonical.id, categoryName: canonical.name },
      `parent ${text(s.categoryId)} merged into ${canonical.id}`);
  }
  for (const b of banners) {
    for (const field of ["categoryId", "clickValue"]) {
      const canonical = mergedAway.get(text(b[field]));
      if (canonical) write("banners", b.id, { [field]: canonical.id }, `${field} merged into ${canonical.id}`);
    }
  }

  // --- 2. Retire subcategories into a top-level category ---------------------
  const creates = [];
  const retired = [];
  const retiredIds = new Set();
  for (const { subId, toCategoryId: rawTarget } of retireList) {
    const sub = subById.get(subId);
    const toCategoryId = finalCategoryId(rawTarget);
    const target = catById.get(toCategoryId);
    if (!sub || !target) throw new Error(`retire: unknown subcategory ${subId} or category ${rawTarget}`);
    retiredIds.add(subId);
    write("subcategories", subId, { isActive: false, showOnHome: false, mergedInto: toCategoryId },
      `retired into category ${toCategoryId}`, ["normalizedName"]);

    // Brand subcategories available under the target after the merge, plus new ones.
    const brandSubId = (brand) => {
      const existing = subcategories.find(
        (s) => !retiredIds.has(s.id) && subParent.get(s.id) === toCategoryId && normalizeCategoryKey(s.name) === normalizeCategoryKey(brand)
      );
      if (existing) return { id: existing.id, isNew: false };
      if (!createBrands.has(normalizeCategoryKey(brand))) return { id: null, isNew: true };
      let created = creates.find((c) => c.collection === "subcategories" && c.data.categoryId === toCategoryId && c.data.normalizedName === normalizeCategoryKey(brand));
      if (!created) {
        created = {
          placeholder: `new:subcategories:${creates.length + 1}`,
          collection: "subcategories",
          data: {
            categoryId: toCategoryId,
            categoryName: text(target.name),
            name: brand,
            normalizedName: normalizeCategoryKey(brand),
            slug: slugifyCategoryName(brand),
            priority: 0,
            isActive: true,
            isFeatured: false,
            showOnHome: true,
            status: "active",
            autoCreated: true,
            source: "admin",
          },
        };
        creates.push(created);
      }
      return { id: created.placeholder, isNew: true };
    };

    for (const p of products) {
      if (text(p.subcategoryId) !== subId) continue;
      if (finalCategoryId(p.categoryId) === toCategoryId) continue; // left to the invalid-subcategory pass
      handledProducts.add(p.id);
      const brand = classifyBrand(`${text(p.name)} ${text(p.title)}`);
      const fromCategory = finalCategoryId(p.categoryId);
      const proposal = brand ? brandSubId(brand) : null;
      if (proposal && proposal.id) {
        const { id, isNew } = proposal;
        write("products", p.id, { categoryId: toCategoryId, category: text(target.name), subcategoryId: id },
          `retired subcategory ${subId}: moved to ${toCategoryId}, brand "${brand}"${isNew ? " (new subcategory)" : ""}`);
        retired.push({ productId: p.id, name: text(p.name), fromCategory, brand, subcategoryId: id, isNew });
      } else if (proposal) {
        // Brand known, subcategory does not exist and was not approved for creation.
        write("products", p.id, { categoryId: toCategoryId, category: text(target.name) },
          `retired subcategory ${subId}: moved to ${toCategoryId}, brand "${brand}" proposed (subcategory not created)`, ["subcategoryId"]);
        retired.push({ productId: p.id, name: text(p.name), fromCategory, brand, subcategoryId: null, isNew: true, pending: true });
      } else {
        write("products", p.id, { categoryId: toCategoryId, category: text(target.name) },
          `retired subcategory ${subId}: moved to ${toCategoryId}, brand unclear`, ["subcategoryId"]);
        retired.push({ productId: p.id, name: text(p.name), fromCategory, brand: "unclear", subcategoryId: null, isNew: false });
      }
    }
  }

  for (const id of markManual) {
    const target = finalCategoryId(id);
    if (!catById.has(target)) throw new Error(`mark-manual: unknown category ${id}`);
    if (catById.get(target).autoCreated !== false) {
      write("categories", target, { autoCreated: false }, "marked manually managed (autoCreated:false)");
    }
  }
  const proposedNewSubcategories = [...new Set(retired.filter((r) => r.pending).map((r) => r.brand))];

  // --- 3. normalizedName repair on surviving docs ----------------------------
  for (const c of categories) {
    if (mergedAway.has(c.id) || text(c.mergedInto)) continue;
    const key = normalizeCategoryKey(c.name);
    if (key && text(c.normalizedName) !== key) {
      write("categories", c.id, { normalizedName: key },
        `normalizedName "${text(c.normalizedName) || "(none)"}" -> "${key}"`);
    }
  }
  for (const s of subcategories) {
    if (retiredIds.has(s.id) || text(s.mergedInto)) continue;
    const key = normalizeCategoryKey(s.name);
    if (key && text(s.normalizedName) !== key) {
      write("subcategories", s.id, { normalizedName: key },
        `normalizedName "${text(s.normalizedName) || "(none)"}" -> "${key}"`);
    }
  }

  // --- 4. Products whose subcategoryId is not a child of their categoryId ----
  const invalidSubcategory = [];
  for (const p of products) {
    const subId = text(p.subcategoryId);
    if (!subId || handledProducts.has(p.id)) continue;
    const catId = finalCategoryId(p.categoryId);
    if (subById.has(subId) && !retiredIds.has(subId) && subParent.get(subId) === catId) continue;
    const to = remap[subId];
    if (to && subParent.get(to) === catId && !retiredIds.has(to)) {
      write("products", p.id, { subcategoryId: to }, `subcategory ${subId} -> ${to} (remap)`);
      invalidSubcategory.push({ productId: p.id, name: text(p.name), from: subId, action: `remap to ${to}` });
    } else {
      write("products", p.id, {}, `subcategory ${subId} is not a child of ${catId}: cleared`, ["subcategoryId"]);
      invalidSubcategory.push({ productId: p.id, name: text(p.name), from: subId, action: "clear" });
    }
  }

  const list = [...writes.values()];
  const count = (c) => list.filter((w) => w.collection === c).length;
  return {
    totals: {
      duplicateGroups: groups.length,
      categoriesMergedAway: mergedAway.size,
      categoryWrites: count("categories"),
      subcategoryWrites: count("subcategories"),
      subcategoriesCreated: creates.length,
      productWrites: count("products"),
      bannerWrites: count("banners"),
      retiredSubcategoryProductsMoved: retired.length,
      retiredSubcategoryBrandUnclear: retired.filter((r) => r.brand === "unclear").length,
      retiredSubcategoryBrandPendingCreation: retired.filter((r) => r.pending).length,
      invalidSubcategoryProducts: invalidSubcategory.length,
      subcategoryNameCollisions: collisions.length,
    },
    groups,
    collisions,
    retired,
    proposedNewSubcategories,
    invalidSubcategory,
    creates,
    writes: list,
    finalCategoryName,
  };
}

function renderMarkdown(plan, catById, subById) {
  const subLabel = (id) => {
    if (!id) return "— (none)";
    const created = plan.creates.find((c) => c.placeholder === id);
    if (created) return `"${created.data.name}" (NEW)`;
    return `"${text(subById.get(id)?.name)}" ${id}`;
  };
  const lines = ["# Category merge plan", "", "## Totals", ...Object.entries(plan.totals).map(([k, v]) => `- ${k}: ${v}`), "", "## Duplicate groups"];
  for (const g of plan.groups) {
    lines.push("", `### ${g.canonical.name} (key "${g.key}")`, "| role | id | source | active | home | prods by id | subs |", "|---|---|---|---|---|---|---|");
    for (const [role, c] of [["KEEP", g.canonical], ...g.losers.map((l) => ["merge", l])]) {
      lines.push(`| ${role} | ${c.id} | ${c.source || "—"} | ${c.isActive} | ${c.showOnHome} | ${c.productsById} | ${c.subcategories} |`);
    }
    for (const [f, v] of Object.entries(g.copied)) lines.push(`- copy \`${f}\` from ${v.from}: ${v.value.slice(0, 80)}`);
  }
  if (plan.collisions.length) {
    lines.push("", "## Subcategory name collisions (decide before apply)");
    plan.collisions.forEach((c) => lines.push(`- "${c.name}" ${c.moving} collides with ${c.existing} under ${c.canonical}`));
  }
  if (plan.retired.length) {
    lines.push("", "## Retired-subcategory products — review brand per product",
      "| productId | title | from category | → brand subcategory |", "|---|---|---|---|");
    for (const r of plan.retired) {
      const to = r.brand === "unclear" ? "**unclear** (no subcategory)"
        : r.pending ? `"${r.brand}" PROPOSED — not created (no subcategory until approved)`
        : subLabel(r.subcategoryId);
      lines.push(`| ${r.productId} | ${r.name.slice(0, 80)} | ${text(catById.get(r.fromCategory)?.name)} | ${to} |`);
    }
    if (plan.proposedNewSubcategories.length) {
      lines.push("", `Proposed new brand subcategories (pass --create-brand-subcategories=${plan.proposedNewSubcategories.join(",")} after review): ${plan.proposedNewSubcategories.join(", ")}`);
    } else {
      lines.push("", "No new brand subcategories needed.");
    }
  }
  if (plan.invalidSubcategory.length) {
    lines.push("", "## Products with a subcategory outside their category",
      "| productId | title | from | action |", "|---|---|---|---|");
    for (const r of plan.invalidSubcategory) {
      const action = r.action.startsWith("remap to ") ? `→ ${subLabel(r.action.slice(9))}` : "clear";
      lines.push(`| ${r.productId} | ${r.name.slice(0, 80)} | ${subLabel(r.from)} | ${action} |`);
    }
  }
  if (plan.creates.length) {
    lines.push("", "## New docs");
    plan.creates.forEach((c) => lines.push(`- ${c.placeholder}: ${c.collection} "${c.data.name}" under ${c.data.categoryId}`));
  }
  lines.push("", "## All writes");
  for (const w of plan.writes) {
    const set = JSON.stringify(w.set);
    const del = w.deleteFields.length ? ` delete[${w.deleteFields.join(",")}]` : "";
    const label = w.collection === "categories" ? ` (${text(catById.get(w.id)?.name)})`
      : w.collection === "subcategories" ? ` (${text(subById.get(w.id)?.name)})` : "";
    lines.push(`- ${w.collection}/${w.id}${label}: set ${set}${del} — ${w.reasons.join("; ")}`);
  }
  return lines.join("\n") + "\n";
}

function parseArgs(argv) {
  const args = { apply: false, out: null, remapSubcategory: {}, retireSubcategories: [], createBrandSubcategories: [], markManual: [] };
  const list = (v) => v.split(",").map((x) => x.trim()).filter(Boolean);
  for (const a of argv) {
    if (a === "--apply") args.apply = true;
    else if (a.startsWith("--out=")) args.out = path.resolve(a.slice(6));
    else if (a.startsWith("--remap-subcategory=")) {
      const [from, to] = a.slice("--remap-subcategory=".length).split(":");
      if (from && to) args.remapSubcategory[from] = to;
    } else if (a.startsWith("--retire-subcategory=")) {
      const [subId, toCategoryId] = a.slice("--retire-subcategory=".length).split(":");
      if (subId && toCategoryId) args.retireSubcategories.push({ subId, toCategoryId });
    } else if (a.startsWith("--create-brand-subcategories=")) {
      args.createBrandSubcategories.push(...list(a.slice("--create-brand-subcategories=".length)));
    } else if (a.startsWith("--mark-manual=")) {
      args.markManual.push(...list(a.slice("--mark-manual=".length)));
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.out) {
    console.error("Usage: node functions/scripts/categoryMerge.js --out=<dir> [--apply] [--remap-subcategory=<from>:<to>] [--retire-subcategory=<subId>:<categoryId>] [--create-brand-subcategories=<a,b>] [--mark-manual=<categoryId,...>]");
    process.exit(1);
  }
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();

  const read = async (name) => (await db.collection(name).get()).docs.map((d) => ({ id: d.id, ...d.data() }));
  const [categories, subcategories, products, banners] = await Promise.all(
    ["categories", "subcategories", "products", "banners"].map(read)
  );
  const plan = buildMergePlan({ categories, subcategories, products, banners }, args);
  const catById = new Map(categories.map((c) => [c.id, c]));
  const subById = new Map(subcategories.map((s) => [s.id, s]));

  fs.mkdirSync(args.out, { recursive: true });
  const { finalCategoryName, ...serializable } = plan;
  fs.writeFileSync(path.join(args.out, "category-merge-plan.json"), JSON.stringify(serializable, null, 2));
  fs.writeFileSync(path.join(args.out, "category-merge-plan.md"), renderMarkdown(plan, catById, subById));
  console.log(JSON.stringify(plan.totals, null, 2));

  if (!args.apply) {
    console.log(`DRY RUN — no writes. Plan written to ${args.out}`);
    return;
  }
  if (plan.collisions.length) {
    console.error("Refusing to apply: subcategory name collisions need a decision first.");
    process.exit(1);
  }

  const all = { categories, subcategories, products, banners };
  const backup = plan.writes.map((w) => ({
    path: `${w.collection}/${w.id}`,
    before: all[w.collection].find((d) => d.id === w.id) || null,
  }));
  const backupFile = path.join(args.out, `category-merge-backup-${Date.now()}.json`);
  fs.writeFileSync(backupFile, JSON.stringify({ updated: backup, created: [] }, null, 2));
  console.log(`Backup written to ${backupFile}`);

  const { FieldValue } = admin.firestore;
  const realId = new Map();
  for (const c of plan.creates) realId.set(c.placeholder, db.collection(c.collection).doc().id);
  const resolveIds = (obj) =>
    Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, realId.get(v) || v]));

  let batch = db.batch();
  let ops = 0;
  let done = 0;
  const flush = async (force) => {
    if (ops && (force || ops >= WRITE_BATCH_LIMIT)) {
      await batch.commit();
      done += ops;
      batch = db.batch();
      ops = 0;
    }
  };
  for (const c of plan.creates) {
    batch.set(db.collection(c.collection).doc(realId.get(c.placeholder)), {
      ...c.data,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    ops++;
    await flush(false);
  }
  // Record created ids in the backup so they can be removed on rollback.
  fs.writeFileSync(backupFile, JSON.stringify({
    updated: backup,
    created: plan.creates.map((c) => `${c.collection}/${realId.get(c.placeholder)}`),
  }, null, 2));
  for (const w of plan.writes) {
    const payload = { ...resolveIds(w.set), updatedAt: FieldValue.serverTimestamp() };
    for (const f of w.deleteFields) payload[f] = FieldValue.delete();
    if (w.set.mergedInto) payload.mergedAt = FieldValue.serverTimestamp();
    batch.update(db.collection(w.collection).doc(w.id), payload);
    ops++;
    await flush(false);
  }
  await flush(true);
  console.log(`APPLIED ${done} doc writes (${plan.creates.length} created).`);
}

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { buildMergePlan, mergeKey, classifyBrand, compareCanonical, renderMarkdown, parseArgs };
