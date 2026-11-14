#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill of variants[].sourceAttributeName — AliExpress's own
// attribute name (e.g. "Color", "SSD Capacity") — on existing AliExpress
// products. New imports already store it (aliexpress/variantLabelFields).
//
// It is stored for reference only. The storefront label is NOT taken from
// it (sellers misuse "Color" for models/storage/frames); it comes from the
// manual product.variantAttributeName or the values (catalog/variantLabel).
// The report shows that display label per product so it can be reviewed,
// using the live subcategory/category `variantLabel` defaults plus any
// --assume-* overrides (applied in memory only, never written).
//
// Source of truth: product docs do NOT keep the raw AliExpress response
// (rawAliExpress is dropped on save), so each product's SKU properties are
// read from the deployed, read-only aliexpressProductDetails endpoint, whose
// response still carries rawAliExpress. Attribute names are derived from
// that raw SKU data locally — works whether or not the importer change that
// adds sourceAttributeName is deployed yet.
//
// Each saved variant is matched to its AliExpress SKU with the same rule the
// sync uses (pickFreshVariantForSaved: SKU id, then exact name). Only
// sourceAttributeName is ever added; it is never overwritten, and nothing
// else on the product or variant is touched.
//
// DRY RUN BY DEFAULT: prints a summary and writes a local report to
// tools/backfill/ (git-ignored). --apply writes, after saving a backup of every touched
// product's variants; each write re-reads the product in a transaction and
// only sets sourceAttributeName on a variant whose name is unchanged and
// which still has none.
//
// Usage (Git Bash, from functions/):
//   PRODUCT_IMPORT_API_KEY=$(firebase functions:secrets:access PRODUCT_IMPORT_API_KEY) \
//     node scripts/backfillVariantAttributeName.js [--products=sourceId,sourceId] [--limit=N] [--sample=15]
//       [--assume-category="Motherboard=Model"] [--assume-subcategory="Display & Digitizer=Type"]   (repeatable;
//        name or doc id; report only — never written)
//       [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const { resolveAliExpressVariantAttributeName } = require("../aliexpress/variantName");
const { pickFreshVariantForSaved } = require("../aliexpress/variantMatch");
const { labelForProduct, cleanVariantDisplayName } = require("../catalog/variantLabel");

const DETAILS_URL = "https://asia-south1-chalakchar-mart.cloudfunctions.net/aliexpressProductDetails";
const REQUEST_DELAY_MS = 400; // gentle on the AliExpress API quota
const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");

/**
 * id -> variantLabel for a category/subcategory collection snapshot, with
 * report-only overrides ("<name or id>=<label>") applied on top.
 */
function variantLabelMap(docs, assumptions) {
  const map = new Map();
  for (const d of docs) {
    const label = text(d.data.variantLabel);
    if (label) map.set(d.id, label);
  }
  for (const raw of assumptions) {
    const sep = raw.lastIndexOf("=");
    const key = text(raw.slice(0, sep)).toLowerCase();
    const label = text(raw.slice(sep + 1));
    const hits = docs.filter((d) => d.id.toLowerCase() === key || text(d.data.name).toLowerCase() === key);
    if (sep < 1 || !label || !hits.length) throw new Error(`--assume-*: no category/subcategory matches "${raw}"`);
    hits.forEach((d) => map.set(d.id, label));
  }
  return map;
}

function text(value) {
  return String(value ?? "").trim();
}

/** Every raw AliExpress SKU object (has an id and a property list). */
function rawSkus(raw) {
  const out = [];
  const seen = new Set();
  const walk = (node) => {
    if (!node || typeof node !== "object" || seen.has(node)) return;
    seen.add(node);
    if (Array.isArray(node)) return node.forEach(walk);
    const id = text(node.sku_id ?? node.id);
    if (id && (node.ae_sku_property_dtos || node.sku_property_dtos || node.properties)) {
      out.push(node);
    }
    Object.values(node).forEach(walk);
  };
  walk(raw);
  return out;
}

/** skuId -> attribute name, from the raw AliExpress response. */
function attributeNamesBySku(raw) {
  const map = new Map();
  for (const sku of rawSkus(raw)) {
    const name = resolveAliExpressVariantAttributeName(sku);
    if (name) map.set(text(sku.sku_id ?? sku.id), name);
  }
  return map;
}

/**
 * Pure planning step. Returns which saved variants get which
 * sourceAttributeName.
 *   savedVariants: product.variants from Firestore
 *   freshProduct:  aliexpressProductDetails `product` (variants + rawAliExpress)
 */
function planAttributeNames(savedVariants, freshProduct) {
  const bySku = attributeNamesBySku(freshProduct && freshProduct.rawAliExpress);
  const fresh = (Array.isArray(freshProduct && freshProduct.variants) ? freshProduct.variants : [])
    .map((f) => ({
      ...f,
      sourceAttributeName: text(f.sourceAttributeName) || bySku.get(text(f.skuId || f.id)) || "",
    }));

  const changes = [];
  const unresolved = [];
  let alreadySet = 0;
  (Array.isArray(savedVariants) ? savedVariants : []).forEach((variant, index) => {
    if (!variant || typeof variant !== "object") return;
    if (text(variant.sourceAttributeName)) {
      alreadySet += 1;
      return;
    }
    const pick = pickFreshVariantForSaved(variant, fresh);
    if (!pick.fresh) {
      unresolved.push({ index, name: variant.name, reason: pick.how });
      return;
    }
    if (!pick.fresh.sourceAttributeName) {
      unresolved.push({ index, name: variant.name, reason: "no_attribute_name_from_aliexpress" });
      return;
    }
    changes.push({ index, name: variant.name, sourceAttributeName: pick.fresh.sourceAttributeName, how: pick.how });
  });

  const labels = [...new Set(changes.map((c) => c.sourceAttributeName))];
  return { changes, unresolved, alreadySet, labels, rawSkuCount: bySku.size };
}

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}

// AliExpress answers "Api access frequency exceeds the limit. this ban will
// last 1 seconds" when called too fast — wait and retry once for that only.
async function fetchFresh(sourceProductId) {
  try {
    return await fetchFreshOnce(sourceProductId);
  } catch (e) {
    if (!/frequency exceeds the limit/i.test(e.message)) throw e;
    await new Promise((r) => setTimeout(r, 2000));
    return fetchFreshOnce(sourceProductId);
  }
}

async function fetchFreshOnce(sourceProductId) {
  const res = await fetch(`${DETAILS_URL}?productId=${encodeURIComponent(sourceProductId)}`, {
    headers: { "x-import-api-key": process.env.PRODUCT_IMPORT_API_KEY },
  });
  const json = await res.json().catch(() => ({ ok: false, error: `HTTP_${res.status}` }));
  if (!json.ok) {
    const err = new Error(`${json.error || "LOOKUP_FAILED"} ${json.message || ""}`.trim());
    err.code = json.error || "LOOKUP_FAILED";
    throw err;
  }
  return json.product || {};
}

async function main() {
  if (!process.env.PRODUCT_IMPORT_API_KEY) {
    console.error("Set PRODUCT_IMPORT_API_KEY in the environment first (see usage).");
    process.exit(1);
  }
  const admin = require("firebase-admin");
  const apply = process.argv.includes("--apply");
  const only = new Set(arg("products", "").split(",").map((s) => s.trim()).filter(Boolean));
  const limit = Number(arg("limit", "0")) || 0;
  const sampleSize = Number(arg("sample", "15")) || 15;
  const many = (name) => process.argv.filter((a) => a.startsWith(`--${name}=`)).map((a) => a.slice(name.length + 3));

  admin.initializeApp({ projectId: "chalakchar-mart" });
  const db = admin.firestore();

  const toDocs = (s) => s.docs.map((d) => ({ id: d.id, data: d.data() }));
  const categoryLabels = variantLabelMap(toDocs(await db.collection("categories").get()), many("assume-category"));
  const subcategoryLabels = variantLabelMap(toDocs(await db.collection("subcategories").get()), many("assume-subcategory"));
  const defaultsFor = (data) => ({
    subcategoryLabel: subcategoryLabels.get(text(data.subcategoryId)) || "",
    categoryLabel: categoryLabels.get(text(data.categoryId)) || "",
  });

  const snap = await db.collection("products").where("source", "==", "aliexpress").get();
  const summary = {
    scanned: 0, alreadyComplete: 0, singleVariant: 0, noSourceId: 0,
    lookupFailed: 0, lookupErrors: {}, wouldChangeProducts: 0, wouldChangeVariants: 0,
    unresolvedVariants: 0, unresolvedReasons: {}, labels: {}, mixedLabelProducts: 0,
    // Storefront label each multi-variant product displays (independent of
    // this backfill), and how it relates to AliExpress's own name.
    displayLabels: {}, displayLabelBySourceName: {}, displayLabelSource: {},
    assumptions: { categories: many("assume-category"), subcategories: many("assume-subcategory") },
  };
  const plans = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    const sourceProductId = text(data.sourceProductId);
    if (only.size && !only.has(sourceProductId) && !only.has(doc.id)) continue;
    summary.scanned += 1;
    const variants = Array.isArray(data.variants) ? data.variants : [];
    if (variants.length <= 1) { summary.singleVariant += 1; continue; } // no selector shown
    const defaults = defaultsFor(data);
    const displayLabel = labelForProduct(data, defaults);
    summary.displayLabels[displayLabel] = (summary.displayLabels[displayLabel] || 0) + 1;
    const via = text(data.variantAttributeName) ? "product" : defaults.subcategoryLabel ? "subcategory"
      : defaults.categoryLabel ? "category" : "values";
    summary.displayLabelSource[via] = (summary.displayLabelSource[via] || 0) + 1;
    if (variants.every((v) => text(v && v.sourceAttributeName))) { summary.alreadyComplete += 1; continue; }
    if (!sourceProductId) { summary.noSourceId += 1; continue; }
    if (limit && plans.length + summary.lookupFailed >= limit) break;

    let fresh;
    try {
      fresh = await fetchFresh(sourceProductId);
    } catch (e) {
      summary.lookupFailed += 1;
      summary.lookupErrors[e.code || "ERROR"] = (summary.lookupErrors[e.code || "ERROR"] || 0) + 1;
      console.log(`  ! ${sourceProductId}: ${e.message}`);
      await new Promise((r) => setTimeout(r, REQUEST_DELAY_MS));
      continue;
    }
    const plan = planAttributeNames(variants, fresh);
    plan.unresolved.forEach((u) => {
      summary.unresolvedVariants += 1;
      summary.unresolvedReasons[u.reason] = (summary.unresolvedReasons[u.reason] || 0) + 1;
    });
    if (plan.changes.length) {
      summary.wouldChangeProducts += 1;
      summary.wouldChangeVariants += plan.changes.length;
      plan.labels.forEach((l) => { summary.labels[l] = (summary.labels[l] || 0) + 1; });
      if (plan.labels.length > 1) summary.mixedLabelProducts += 1;
    }
    const key = `${plan.labels[0] || "(none)"} -> ${displayLabel}`;
    summary.displayLabelBySourceName[key] = (summary.displayLabelBySourceName[key] || 0) + 1;
    plans.push({
      productId: doc.id, sourceProductId, name: text(data.name), variants, ...plan,
      displayLabel,
      sampleValues: [...new Set(variants.map((v) => cleanVariantDisplayName(text(v && (v.name ?? v.unit)))))].slice(0, 3),
    });
    console.log(`  ${plan.changes.length ? "~" : "="} ${sourceProductId} ${text(data.name).slice(0, 50)} — ` +
      `${plan.changes.length} to set [${plan.labels.join(", ")}], ${plan.unresolved.length} unresolved`);
    await new Promise((r) => setTimeout(r, REQUEST_DELAY_MS));
  }

  const date = new Date().toISOString().slice(0, 10);
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const reportPath = path.join(OUT_DIR, `attribute_name_${apply ? "apply" : "dry_run"}_${date}.json`);
  fs.writeFileSync(reportPath, JSON.stringify({ summary, plans: plans.map(({ variants, ...p }) => p) }, null, 2));

  console.log(`\n=== Sample of ${Math.min(sampleSize, plans.length)} products: label shown on the product page ===`);
  const ordered = [...plans].sort((a, b) => a.sourceProductId.localeCompare(b.sourceProductId));
  const step = Math.max(1, Math.floor(ordered.length / sampleSize));
  ordered.filter((_, i) => i % step === 0).slice(0, sampleSize).forEach((p) => {
    console.log(`  ${p.displayLabel.padEnd(9)} | AliExpress: ${(p.labels[0] || "-").padEnd(13)} | ${p.name.slice(0, 38).padEnd(38)} | ${p.sampleValues.join(", ")}`);
  });

  console.log("\n=== Summary ===");
  console.log(JSON.stringify(summary, null, 2));
  console.log(`Report: ${reportPath}`);
  if (!apply) {
    console.log(`DRY RUN — nothing written. Would set sourceAttributeName on ${summary.wouldChangeVariants} variant(s) ` +
      `across ${summary.wouldChangeProducts} product(s). Re-run with --apply to write.`);
    return;
  }

  const touched = plans.filter((p) => p.changes.length);
  if (!touched.length) return;
  const backupPath = path.join(OUT_DIR, `attribute_name_backup_${date}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(touched.map((p) => ({ productId: p.productId, variants: p.variants })), null, 2));
  console.log(`Backup written: ${backupPath}`);

  for (const p of touched) {
    const ref = db.collection("products").doc(p.productId);
    const applied = await db.runTransaction(async (tx) => {
      const latest = (await tx.get(ref)).data() || {};
      const variants = Array.isArray(latest.variants) ? latest.variants.map((v) => ({ ...v })) : [];
      let count = 0;
      for (const c of p.changes) {
        const v = variants[c.index];
        if (!v || v.name !== c.name || text(v.sourceAttributeName)) continue; // changed since planning
        v.sourceAttributeName = c.sourceAttributeName;
        count += 1;
      }
      if (count) tx.update(ref, { variants, variantAttributeBackfilledAt: admin.firestore.FieldValue.serverTimestamp() });
      return count;
    });
    console.log(`${p.sourceProductId}: applied ${applied}/${p.changes.length}`);
  }
}

module.exports = { planAttributeNames, attributeNamesBySku, rawSkus, variantLabelMap };

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => {
    console.error(e.stack || e.message || String(e));
    process.exit(1);
  });
}
