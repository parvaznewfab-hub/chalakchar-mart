#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time repair of wrong variants[].sourceSkuId on AliExpress products
// imported by n8n, whose workflow paired variant names and SKU ids by
// position from two differently-ordered lists (see
// aliexpress/importVariantGuard.js). Found on 6 products on 2026-11-13.
//
// For each saved variant, the SKU AliExpress itself gives that exact name is
// looked up (pickFreshVariantForSaved). sourceSkuId is changed ONLY when:
//   - the saved SKU belongs to a differently-named AliExpress variant, or is
//     gone, AND
//   - exactly one AliExpress variant has the saved name.
// Nothing else on the product or variant is touched (price/stock are the
// sync's job). Variants that can't be resolved are reported and left alone.
//
// DRY RUN BY DEFAULT. --apply writes, after saving a backup of every touched
// product's variants to scripts/backups/. Writes re-read each product in a
// transaction and only change a variant whose name and sourceSkuId are still
// what the plan saw, so a concurrent edit is never overwritten.
//
// Usage (Git Bash, from functions/):
//   PRODUCT_IMPORT_API_KEY=$(firebase functions:secrets:access PRODUCT_IMPORT_API_KEY) \
//     node scripts/repairAliExpressVariantSkuIds.js [--products=id,id] [--apply]
// AliExpress data comes from the deployed read-only aliexpressProductDetails.
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { pickFreshVariantForSaved } = require("../aliexpress/variantMatch");

const DEFAULT_PRODUCTS = [
  "1005008148298908",
  "1005006323693930",
  "1005006262104060",
  "1005008585495746",
  "1005012494656822",
  "1005008591232954",
];
const DETAILS_URL = "https://asia-south1-chalakchar-mart.cloudfunctions.net/aliexpressProductDetails";

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}

async function freshVariants(sourceProductId) {
  const res = await fetch(`${DETAILS_URL}?productId=${encodeURIComponent(sourceProductId)}`, {
    headers: { "x-import-api-key": process.env.PRODUCT_IMPORT_API_KEY },
  });
  const json = await res.json();
  if (!json.ok) throw new Error(`${sourceProductId}: AliExpress lookup failed: ${json.error} ${json.message || ""}`);
  return json.product.variants || [];
}

// Explicit, admin-decided extras (each named in the command line):
//   clearSkuNames: variant names whose sourceSkuId is REMOVED (the variant
//     doesn't exist on AliExpress; the sync then treats it as gone, stock 0)
//   renameToAliExpress: for variants whose saved SKU belongs to exactly one
//     AliExpress variant with a different name and no same-name variant
//     exists (seller renamed it), rename name/unit/variantName to
//     AliExpress's name. Variant ids are never changed.
function planForProduct(variants, fresh, extras = {}) {
  const changes = [];
  const unresolved = [];
  const clearSkuNames = new Set(extras.clearSkuNames || []);
  (Array.isArray(variants) ? variants : []).forEach((variant, index) => {
    if (!variant || typeof variant !== "object") return;
    const fromSkuId = String(variant.sourceSkuId || "");
    if (clearSkuNames.has(variant.name)) {
      const owner = fresh.find((f) => String(f.skuId) === fromSkuId);
      changes.push({ type: "clear_sku", index, name: variant.name, fromSkuId, toSkuId: "", why: "admin: not on AliExpress", oldSkuBelongsTo: owner ? owner.name : "(not on AliExpress)" });
      return;
    }
    const pick = pickFreshVariantForSaved(variant, fresh);
    if (!pick.fresh && pick.how === "sku_name_mismatch" && extras.renameToAliExpress) {
      const owner = fresh.find((f) => String(f.skuId) === fromSkuId);
      changes.push({ type: "rename", index, name: variant.name, fromSkuId, toSkuId: fromSkuId, toName: owner.name, why: "admin: seller renamed on AliExpress" });
      return;
    }
    if (pick.fresh && (pick.how === "name_sku_mismatch" || pick.how === "name_sku_changed")) {
      const owner = fresh.find((f) => String(f.skuId) === fromSkuId);
      changes.push({
        type: "sku",
        index,
        name: variant.name,
        fromSkuId,
        toSkuId: String(pick.fresh.skuId),
        why: pick.how,
        oldSkuBelongsTo: owner ? owner.name : "(not on AliExpress)",
      });
    } else if (!pick.fresh && pick.how !== "not_on_aliexpress") {
      unresolved.push({ index, name: variant.name, sourceSkuId: fromSkuId, reason: pick.how });
    }
  });

  // Never leave two variants of one product pointing at the same SKU.
  const finalIds = (variants || []).map((v, i) => {
    const c = changes.find((x) => x.index === i);
    return c ? c.toSkuId : String(v?.sourceSkuId || "");
  }).filter(Boolean);
  const duplicates = finalIds.filter((id, i) => finalIds.indexOf(id) !== i);
  return { changes, unresolved, duplicates: [...new Set(duplicates)] };
}

async function main() {
  if (!process.env.PRODUCT_IMPORT_API_KEY) {
    console.error("Set PRODUCT_IMPORT_API_KEY in the environment first (see usage).");
    process.exit(1);
  }
  const apply = process.argv.includes("--apply");
  const ids = arg("products", "").split(",").map((s) => s.trim()).filter(Boolean);
  const targets = ids.length ? ids : DEFAULT_PRODUCTS;
  // --clear-sku=<sourceProductId>:<exact variant name>   (repeatable)
  const clearSku = process.argv.filter((a) => a.startsWith("--clear-sku=")).map((a) => {
    const value = a.slice("--clear-sku=".length);
    const sep = value.indexOf(":");
    return { sourceProductId: value.slice(0, sep), name: value.slice(sep + 1) };
  });
  // --rename-to-aliexpress=<sourceProductId>   (repeatable)
  const renameTargets = new Set(process.argv.filter((a) => a.startsWith("--rename-to-aliexpress=")).map((a) => a.slice("--rename-to-aliexpress=".length)));

  admin.initializeApp({ projectId: "chalakchar-mart" });
  const db = admin.firestore();

  const plans = [];
  for (const sourceProductId of targets) {
    const snap = await db.collection("products").where("source", "==", "aliexpress").where("sourceProductId", "==", sourceProductId).get();
    if (snap.empty) {
      console.log(`${sourceProductId}: no product found, skipped`);
      continue;
    }
    const doc = snap.docs[0];
    const data = doc.data();
    const plan = planForProduct(data.variants, await freshVariants(sourceProductId), {
      clearSkuNames: clearSku.filter((c) => c.sourceProductId === sourceProductId).map((c) => c.name),
      renameToAliExpress: renameTargets.has(sourceProductId),
    });
    plans.push({ productId: doc.id, sourceProductId, name: data.name, variants: data.variants, ...plan });
  }

  for (const p of plans) {
    console.log(`\n${p.name.slice(0, 60)} (${p.sourceProductId}) — ${p.changes.length} change(s), ${p.unresolved.length} unresolved${p.duplicates.length ? `, DUPLICATE SKUs ${p.duplicates.join(",")} — product skipped` : ""}`);
    p.changes.forEach((c) => {
      if (c.type === "rename") console.log(`  [${c.index}] RENAME "${c.name}" -> "${c.toName}" (SKU ${c.fromSkuId} unchanged)  [${c.why}]`);
      else if (c.type === "clear_sku") console.log(`  [${c.index}] "${c.name}": REMOVE sourceSkuId ${c.fromSkuId} (AliExpress: "${c.oldSkuBelongsTo}")  [${c.why}]`);
      else console.log(`  [${c.index}] "${c.name}": ${c.fromSkuId} (AliExpress: "${c.oldSkuBelongsTo}") -> ${c.toSkuId}  [${c.why}]`);
    });
    p.unresolved.forEach((u) => console.log(`  [${u.index}] "${u.name}": left as ${u.sourceSkuId} (${u.reason})`));
  }
  const total = plans.reduce((n, p) => n + (p.duplicates.length ? 0 : p.changes.length), 0);
  console.log(`\nTotal sourceSkuId changes: ${total}${apply ? "" : " (DRY RUN — nothing written; pass --apply to write)"}`);
  if (!apply || !total) return;

  const backupPath = path.join(__dirname, "backups", `variant_sku_repair_backup_${new Date().toISOString().slice(0, 10)}.json`);
  fs.mkdirSync(path.dirname(backupPath), { recursive: true });
  fs.writeFileSync(backupPath, JSON.stringify(plans.map((p) => ({ productId: p.productId, variants: p.variants })), null, 2));
  console.log(`Backup written: ${backupPath}`);

  for (const p of plans) {
    if (p.duplicates.length || !p.changes.length) continue;
    const ref = db.collection("products").doc(p.productId);
    const applied = await db.runTransaction(async (tx) => {
      const latest = (await tx.get(ref)).data() || {};
      const variants = Array.isArray(latest.variants) ? latest.variants.map((v) => ({ ...v })) : [];
      let count = 0;
      for (const c of p.changes) {
        const v = variants[c.index];
        if (!v || v.name !== c.name || String(v.sourceSkuId || "") !== c.fromSkuId) continue; // changed since planning
        if (c.type === "rename") {
          v.name = c.toName;
          v.unit = c.toName;
          v.variantName = c.toName;
        } else if (c.type === "clear_sku") {
          delete v.sourceSkuId;
        } else {
          v.sourceSkuId = c.toSkuId;
        }
        count += 1;
      }
      if (count) tx.update(ref, { variants, variantSkuRepairedAt: admin.firestore.FieldValue.serverTimestamp() });
      return count;
    });
    console.log(`${p.sourceProductId}: applied ${applied}/${p.changes.length}`);
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e.stack || e.message || String(e));
  process.exit(1);
});
