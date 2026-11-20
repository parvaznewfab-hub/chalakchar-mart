#!/usr/bin/env node
// -----------------------------------------------------------------------------
// 14b step B, one-off before movePrivateProfiles.js: remove the stale
// vendors/{id}.ownerName when vendor_private/{id}.ownerName already holds the
// owner's (newer) value. Otherwise the move script sees two different values
// and stops with a CONFLICT.
//
// Deletes ONLY vendors/{id}.ownerName, nothing else (updatedAt untouched).
// It refuses when the private doc has no non-empty ownerName: then the public
// value is the only copy and must be moved, not deleted.
// VALUES ARE NEVER PRINTED: key names and lengths only.
//
// --apply: backup of the removed value to ~/cc-backups (outside the repo and
// OneDrive; same format as movePrivateProfiles.js, so
// restorePrivateProfiles.js --from-backup can put it back), then one
// transaction that re-checks and deletes, then a re-read check.
//
// Usage (from functions/, application-default credentials):
//   node scripts/clearPublicOwnerName.js <vendorId>            dry run
//   node scripts/clearPublicOwnerName.js <vendorId> --apply    delete (owner approval first)
// Exit: 0 ok / nothing to do, 1 usage or missing doc, 2 refused, 3 check failed.
// -----------------------------------------------------------------------------

const fs = require("fs");
const os = require("os");
const path = require("path");

function hasValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.trim().length > 0;
  return true;
}

// Pure decision for one vendor.
//   { action: "delete" | "nothing" | "refuse", reason }
function planClearOwnerName(publicData, privateData) {
  const pub = publicData && typeof publicData === "object" ? publicData : null;
  const priv = privateData && typeof privateData === "object" ? privateData : {};
  if (!pub) return { action: "refuse", reason: "public vendor doc missing" };
  if (!Object.prototype.hasOwnProperty.call(pub, "ownerName")) {
    return { action: "nothing", reason: "vendors doc has no ownerName" };
  }
  if (!hasValue(priv.ownerName)) {
    return { action: "refuse", reason: "vendor_private has no non-empty ownerName; the public value is the only copy" };
  }
  return { action: "delete", reason: "vendor_private already has ownerName" };
}

function len(value) {
  return value === undefined ? "absent" : String(value ?? "").length;
}

async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const ids = args.filter((a) => !a.startsWith("--"));
  if (ids.length !== 1) {
    console.error("give exactly one vendor id: node scripts/clearPublicOwnerName.js <vendorId> [--apply]");
    process.exitCode = 1;
    return;
  }
  const id = ids[0];

  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;
  const pubRef = db.collection("vendors").doc(id);
  const privRef = db.collection("vendor_private").doc(id);

  const [pubSnap, privSnap] = await Promise.all([pubRef.get(), privRef.get()]);
  const pub = pubSnap.exists ? pubSnap.data() : null;
  const priv = privSnap.exists ? privSnap.data() : {};
  const plan = planClearOwnerName(pub, priv);
  console.log(`vendors/${id}: ownerName length ${pub ? len(pub.ownerName) : "-"} | vendor_private ownerName length ${len(priv.ownerName)}`);
  console.log(`plan: ${plan.action} (${plan.reason})`);

  if (plan.action === "refuse") {
    console.log("\nREFUSED. Nothing written.");
    process.exitCode = pub ? 2 : 1;
    return;
  }
  if (plan.action === "nothing") {
    console.log("\nNothing to do.");
    return;
  }
  if (!apply) {
    console.log("\nDry run: would delete vendors/" + id + ".ownerName. Nothing written. Re-run with --apply after approval.");
    return;
  }

  // Backup (contains the old value): same shape as movePrivateProfiles.js.
  const backupDir = path.join(os.homedir(), "cc-backups");
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupFile = path.join(backupDir, `clear_public_ownerName_${stamp}.json`);
  fs.writeFileSync(backupFile, JSON.stringify([{ collection: "vendors", id, removed: { ownerName: pub.ownerName } }], null, 2), { mode: 0o600 });
  console.log(`\nBackup (contains the old value, delete it after the check): ${backupFile}`);

  await db.runTransaction(async (tx) => {
    const [p, q] = await Promise.all([tx.get(pubRef), tx.get(privRef)]);
    const again = planClearOwnerName(p.exists ? p.data() : null, q.exists ? q.data() : {});
    if (again.action !== "delete" || JSON.stringify(p.get("ownerName")) !== JSON.stringify(pub.ownerName)) {
      throw new Error(`vendors/${id} changed while running; nothing written, run again`);
    }
    tx.update(pubRef, { ownerName: FieldValue.delete() });
  });

  const after = (await pubRef.get()).data() || {};
  const privAfter = (await privRef.get()).data() || {};
  if (Object.prototype.hasOwnProperty.call(after, "ownerName") || !hasValue(privAfter.ownerName)) {
    console.log("FAILED CHECK: ownerName still in vendors doc, or missing in vendor_private.");
    process.exitCode = 3;
    return;
  }
  console.log(`Done. vendors/${id} has no ownerName; vendor_private keeps it.`);
}

module.exports = { planClearOwnerName };

if (require.main === module) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
