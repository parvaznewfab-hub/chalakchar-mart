#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Deletes searchImportLog/query — the dedupe doc every all-Bangla search used
// to share (ASCII-only slug -> "query"; fixed in aliexpress/searchImportLogId.js).
// It still lists the 5 incident costume products, and until it expires any
// Bangla search that maps to it is answered "already_done" with them.
//
// Also reports whether anyone was told about it: its waitingUserIds (the only
// users notifyUser "Product found!" is sent to) and every
// search_import_done notification of the last 24h.
//
// DRY RUN BY DEFAULT; --apply saves a JSON backup to tools/backfill/ first.
// Usage (from functions/): node scripts/deleteSearchImportLogQueryDoc.js [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const iso = (v) => (v && typeof v.toDate === "function" ? v.toDate().toISOString() : v ?? null);

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const ref = db.collection("searchImportLog").doc("query");

  const snap = await ref.get();
  if (!snap.exists) {
    console.log("searchImportLog/query does not exist — nothing to do.");
  } else {
    const x = snap.data();
    console.log("searchImportLog/query:", JSON.stringify({
      query: x.query, status: x.status, requestedAt: iso(x.requestedAt), completedAt: iso(x.completedAt),
      waitingUserIds: x.waitingUserIds || [], productIds: x.productIds || [],
    }, null, 1));
  }

  const since = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const notes = await db.collection("notifications").where("createdAt", ">=", since).get();
  const found = notes.docs.filter((d) => {
    const data = d.get("data") || {};
    return data.type === "search_import_done" || /product found/i.test(String(d.get("title") || ""));
  });
  console.log(`"Product found" / search_import_done notifications in the last 24h: ${found.length}`);
  for (const d of found) {
    console.log(`  ${d.id} user=${d.get("userId")} query=${JSON.stringify(d.get("data")?.query)} at=${iso(d.get("createdAt"))}`);
  }

  if (!apply || !snap.exists) {
    if (snap.exists) console.log("DRY RUN — nothing deleted. Re-run with --apply to delete.");
    return;
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const backup = path.join(OUT_DIR, `searchImportLog-query-backup-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  fs.writeFileSync(backup, JSON.stringify({ path: ref.path, data: snap.data() }, null, 2));
  await ref.delete();
  console.log(`Backup: ${backup}\nDeleted searchImportLog/query.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
