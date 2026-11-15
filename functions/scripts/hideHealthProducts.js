#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Find (report) and hide medicine / health products — ChalakChar Mart no longer
// offers health features (Play Store Health apps declaration).
//
// Nothing is deleted. --apply sets, on the approved products only:
//   isActive/isVisible/isPublished/showOnHome = false,
//   hiddenReason = "health_removed", autoMarketingDisabled = true,
//   lastWriteSource = "health_removed"
// after saving a backup of the old values; reversing = restoring the backup.
//
// Report (always): three groups — (a) prescription medicine, (b) OTC/health
// products and medical devices, (c) unsure — by catalog/healthProduct.js, plus
// the products only the raw field rule (generic/strength/manufacturer filled)
// would flag, so the exclusions are visible; and any open order that contains
// a listed product.
//
// Usage (from functions/, application-default credentials):
//   node scripts/hideHealthProducts.js                       report only
//   node scripts/hideHealthProducts.js --apply --ids=a,b,c    hide exactly these ids
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { classifyHealthProduct } = require("../catalog/healthProduct");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const OPEN_ORDER_STATUSES = new Set(["pending", "confirmed", "processing", "packed", "shipped", "out_for_delivery", "on_the_way", "placed", "accepted"]);
const HIDE = {
  isActive: false,
  isVisible: false,
  isPublished: false,
  showOnHome: false,
  hiddenReason: "health_removed",
  autoMarketingDisabled: true,
  lastWriteSource: "health_removed",
};

const s = (v) => String(v ?? "").trim();

async function main() {
  const apply = process.argv.includes("--apply");
  const idsArg = process.argv.find((a) => a.startsWith("--ids="));
  const approvedIds = idsArg ? idsArg.slice(6).split(",").map((x) => x.trim()).filter(Boolean) : [];
  if (apply && !approvedIds.length) throw new Error("--apply needs --ids=<approved product ids>");

  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const products = await db.collection("products").get();
  const groups = { rx: [], otc: [], unsure: [] };
  const fieldOnly = [];
  for (const d of products.docs) {
    const x = d.data();
    const row = {
      id: d.id,
      name: s(x.name).slice(0, 80),
      category: s(x.category),
      generic: s(x.generic),
      strength: s(x.strength),
      type: s(x.type),
      manufacturer: s(x.manufacturer),
      isActive: x.isActive !== false,
      hiddenReason: s(x.hiddenReason),
    };
    const { group, reasons } = classifyHealthProduct(x);
    if (group) groups[group].push({ ...row, reasons });
    else if (row.generic || row.manufacturer || /\d/.test(row.strength)) fieldOnly.push(row);
  }

  const listed = new Set([...groups.rx, ...groups.otc, ...groups.unsure].map((p) => p.id));
  const orders = await db.collection("orders").get();
  const openOrders = [];
  for (const o of orders.docs) {
    const x = o.data();
    const status = s(x.status || x.orderStatus).toLowerCase();
    const items = Array.isArray(x.items) ? x.items : [];
    const hits = items.filter((it) => listed.has(s(it.productId || it.id)));
    if (hits.length) {
      openOrders.push({
        orderId: o.id,
        status,
        open: OPEN_ORDER_STATUSES.has(status),
        items: hits.map((it) => `${s(it.name).slice(0, 40)} x${it.qty ?? it.quantity ?? 1}`),
      });
    }
  }

  const label = { rx: "(ক) প্রেসক্রিপশনের ওষুধ", otc: "(খ) OTC / স্বাস্থ্যপণ্য / মেডিকেল ডিভাইস", unsure: "(গ) নিশ্চিত না" };
  for (const g of ["rx", "otc", "unsure"]) {
    console.log(`\n${label[g]}: ${groups[g].length}`);
    for (const p of groups[g]) {
      console.log(`  ${p.id}  ${p.isActive ? "active" : "inactive"}  [${p.category}]  ${p.name}`);
      console.log(`      ${p.reasons.join(", ")}${p.generic ? ` | generic=${p.generic}` : ""}${p.strength ? ` | strength=${p.strength}` : ""}${p.type ? ` | type=${p.type}` : ""}`);
    }
  }
  console.log(`\nField rule only (generic/manufacturer filled or a number in strength) — NOT listed: ${fieldOnly.length}`);
  const sample = fieldOnly.slice(0, 8).map((p) => `${p.name.slice(0, 40)} [${p.category}] strength=${p.strength}${p.generic ? ` generic=${p.generic}` : ""}`);
  for (const line of sample) console.log(`  e.g. ${line}`);
  console.log(`\nOrders containing a listed product: ${openOrders.length}`);
  for (const o of openOrders) console.log(`  ${o.orderId}  status=${o.status}${o.open ? " (OPEN)" : ""}  ${o.items.join("; ")}`);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const reportPath = path.join(OUT_DIR, `health-products-${apply ? "apply" : "report"}-${stamp}.json`);
  fs.writeFileSync(reportPath, JSON.stringify({ groups, fieldOnly, orders: openOrders }, null, 2));
  console.log(`\nReport: ${reportPath}`);

  if (!apply) {
    console.log("REPORT ONLY — nothing written. Hide with --apply --ids=<approved ids>.");
    return;
  }

  const byId = new Map(products.docs.map((d) => [d.id, d]));
  const unknown = approvedIds.filter((id) => !byId.has(id));
  if (unknown.length) throw new Error(`Unknown product ids: ${unknown.join(", ")}`);
  const backup = approvedIds.map((id) => {
    const x = byId.get(id).data();
    return { id, before: Object.fromEntries(Object.keys(HIDE).map((k) => [k, x[k] ?? null])) };
  });
  const backupPath = path.join(OUT_DIR, `health-products-backup-${stamp}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2));
  console.log(`Backup: ${backupPath}`);

  const batch = db.batch();
  for (const id of approvedIds) {
    batch.update(db.collection("products").doc(id), { ...HIDE, hiddenAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  await batch.commit();
  console.log(`Hidden: ${approvedIds.length} product(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
