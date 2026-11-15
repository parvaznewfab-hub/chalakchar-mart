#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Moves products to a category › subcategory (audit #10: the HP Probook
// laptop motherboard was in Mobile Parts).
//
// DRY RUN BY DEFAULT: shows each product's current and new category, and
// whether the subcategory exists or would be created. --apply saves a
// backup of the old fields, creates the subcategory if missing (through
// ensureSubcategoryExists, the same resolver imports use) and writes
// category, categoryId, subcategoryId, needsCategoryReview=false.
// lastWriteSource "taxonomy_move": no price change, so no marketing fires.
//
// Usage (from functions/):
//   node scripts/moveProductTaxonomy.js --ids=a,b --category="Motherboard" --subcategory="Laptop Motherboard" [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { ensureSubcategoryExists } = require("../category/ensureSubcategoryExists");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const arg = (name) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || "").slice(name.length + 3).replace(/^"|"$/g, "");

async function main() {
  const apply = process.argv.includes("--apply");
  const ids = arg("ids").split(",").map((s) => s.trim()).filter(Boolean);
  const categoryName = arg("category");
  const subcategoryName = arg("subcategory");
  if (!ids.length || !categoryName) throw new Error('--ids and --category are required');

  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const cats = await db.collection("categories").where("name", "==", categoryName).get();
  if (cats.size !== 1) throw new Error(`category "${categoryName}" found ${cats.size} times`);
  const category = { id: cats.docs[0].id, ...cats.docs[0].data() };
  let sub = null;
  if (subcategoryName) {
    const subs = await db.collection("subcategories").where("categoryId", "==", category.id).get();
    const hit = subs.docs.find((d) => String(d.data().name || "").trim().toLowerCase() === subcategoryName.toLowerCase());
    sub = hit ? { id: hit.id, exists: true } : { id: null, exists: false };
  }
  console.log(`Target: ${category.name} (${category.id}, active=${category.isActive !== false})` +
    (subcategoryName ? ` › ${subcategoryName} (${sub.exists ? `exists ${sub.id}` : "will be CREATED"})` : ""));

  const backup = [];
  for (const id of ids) {
    const doc = await db.collection("products").doc(id).get();
    if (!doc.exists) throw new Error(`product ${id} not found`);
    const x = doc.data();
    backup.push({ id, before: { category: x.category ?? null, categoryId: x.categoryId ?? null, subcategoryId: x.subcategoryId ?? null, needsCategoryReview: x.needsCategoryReview ?? null } });
    console.log(`  ${id}  [${x.category}${x.subcategoryId ? " › " + x.subcategoryId : ""}] -> [${category.name}${subcategoryName ? " › " + subcategoryName : ""}]  ${String(x.name).slice(0, 60)}`);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const file = path.join(OUT_DIR, `move-taxonomy-${apply ? "backup" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(file, JSON.stringify({ category: category.name, subcategoryName, products: backup }, null, 2));
  console.log(`Report/backup: ${file}`);
  if (!apply) {
    console.log("DRY RUN — nothing written. Write with --apply.");
    return;
  }

  let subcategoryId = sub?.id || null;
  if (subcategoryName && !subcategoryId) {
    const created = await ensureSubcategoryExists(db, category.id, category.name, subcategoryName, { source: "admin" });
    subcategoryId = created?.subcategoryId || null;
    console.log(`Subcategory: ${subcategoryName} -> ${subcategoryId}${created?.createdSubcategory ? " (created)" : ""}`);
  }
  for (const id of ids) {
    await db.collection("products").doc(id).update({
      category: category.name,
      categoryId: category.id,
      subcategoryId: subcategoryId,
      needsCategoryReview: false,
      lastWriteSource: "taxonomy_move",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  console.log(`Moved: ${ids.length} product(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
