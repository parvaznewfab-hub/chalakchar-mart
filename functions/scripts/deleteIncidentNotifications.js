#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Deletes the in-app notification docs created for the 5 products of the
// 2026-11-14 search-import incident (notifications where data.productId is
// one of them). Push messages already delivered can't be recalled; this only
// removes them from the users' in-app notification lists.
//
// DRY RUN BY DEFAULT: lists every doc (user, type, title, created). --apply
// saves a full JSON backup of the docs to tools/backfill/ first, then deletes.
//
// Usage (from functions/, application-default credentials):
//   node scripts/deleteIncidentNotifications.js [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const INCIDENT_PRODUCT_IDS = [
  "imp_aliexpress_b5cc78b28153992191f553f5515075aa",
  "imp_aliexpress_050b41d6f80f0f1278ea9e85ff993086",
  "imp_aliexpress_a9acb95df73e8f3db88d95be84a54288",
  "imp_aliexpress_12d75d08afe3f3afe66db4d2771e29e6",
  "imp_aliexpress_0344343d050e3fa07ff7214cd540a965",
];
const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");

const iso = (v) => (v && typeof v.toDate === "function" ? v.toDate().toISOString() : v ?? null);

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const docs = [];
  for (const productId of INCIDENT_PRODUCT_IDS) {
    const snap = await db.collection("notifications").where("data.productId", "==", productId).get();
    docs.push(...snap.docs);
  }

  const users = new Set(docs.map((d) => d.get("userId")));
  console.log(`${docs.length} notification doc(s) for ${users.size} user(s):`);
  for (const d of docs) {
    const x = d.data();
    console.log(`  ${d.id}  user=${x.userId}  type=${x.type}  product=${x.data?.productId}  read=${x.isRead === true}  at=${iso(x.createdAt)}  "${String(x.title || "").slice(0, 40)}"`);
  }

  if (!apply) {
    console.log("DRY RUN — nothing deleted. Re-run with --apply to delete.");
    return;
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const backupPath = path.join(OUT_DIR, `incident-notifications-backup-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(docs.map((d) => ({ id: d.id, path: d.ref.path, data: d.data() })), null, 2));
  console.log(`Backup: ${backupPath}`);

  const batch = db.batch();
  for (const d of docs) batch.delete(d.ref);
  await batch.commit();
  console.log(`Deleted ${docs.length} notification doc(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
