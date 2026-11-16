#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill of products' modelKeys / modelSeries (device models in
// the name, catalog/deviceModel.js) for the product page's "more parts for
// this model" row. New and renamed products get them from the product
// triggers (applyProductModelKeys in index.js).
//
// Only modelKeys, modelSeries, modelKeysAt and lastWriteSource ("model_keys")
// are written. The deployed onProductStockUpdated skips that write
// (isModelKeysWrite), so NO marketing or notification follows — run --apply
// only AFTER the functions with isModelKeysWrite are deployed.
//
// DRY RUN BY DEFAULT: prints every product that would change and writes a
// report to tools/backfill/ (git-ignored). --apply first saves a backup of
// each touched product's old modelKeys/modelSeries/lastWriteSource there.
//
// Usage (Git Bash, from repo root):
//   node functions/scripts/backfillModelKeys.js [--apply]
// Credentials: standard firebase-admin resolution (gcloud ADC).
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { modelKeysUpdate } = require("../catalog/deviceModel");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const WRITE_BATCH_LIMIT = 400;

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const snap = await db.collection("products").select("name", "modelKeys", "modelSeries", "lastWriteSource", "category", "isActive").get();
  const changes = [];
  for (const doc of snap.docs) {
    const p = doc.data();
    const update = modelKeysUpdate(p, admin.firestore.FieldValue.serverTimestamp());
    if (!update) continue;
    changes.push({
      id: doc.id,
      name: p.name || "",
      category: p.category || "",
      isActive: p.isActive,
      before: { modelKeys: p.modelKeys ?? null, modelSeries: p.modelSeries ?? null, lastWriteSource: p.lastWriteSource ?? null },
      after: { modelKeys: update.modelKeys, modelSeries: update.modelSeries },
      update,
    });
  }

  const withKeys = changes.filter((c) => c.after.modelKeys.length);
  console.log(`${snap.size} products; ${changes.length} to update (${withKeys.length} with a device model, ${changes.length - withKeys.length} get empty lists).`);
  for (const c of withKeys) {
    console.log(`- ${c.id} [${c.category}${c.isActive === false ? ", inactive" : ""}] ${c.name.slice(0, 80)}\n    keys: ${c.after.modelKeys.join(", ")}\n    series: ${c.after.modelSeries.join(", ")}`);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const report = path.join(OUT_DIR, `model-keys-${apply ? "apply" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(report, JSON.stringify(changes.map(({ update, ...rest }) => rest), null, 2));
  console.log(`\nReport: ${report}`);

  if (!apply) {
    console.log("DRY RUN — nothing written. Re-run with --apply (after deploying the trigger change).");
    return;
  }

  const backup = path.join(OUT_DIR, `model-keys-backup-${stamp}.json`);
  fs.writeFileSync(backup, JSON.stringify(changes.map((c) => ({ id: c.id, ...c.before })), null, 2));
  console.log(`Backup: ${backup}`);

  for (let i = 0; i < changes.length; i += WRITE_BATCH_LIMIT) {
    const batch = db.batch();
    for (const c of changes.slice(i, i + WRITE_BATCH_LIMIT)) batch.update(db.collection("products").doc(c.id), c.update);
    await batch.commit();
  }
  console.log(`Applied ${changes.length} updates.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
