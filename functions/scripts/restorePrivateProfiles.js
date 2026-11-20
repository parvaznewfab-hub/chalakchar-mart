#!/usr/bin/env node
// -----------------------------------------------------------------------------
// 14b step B ROLLBACK: put vendor / rider private values back into the public
// docs (the reverse of movePrivateProfiles.js). Only for a real rollback: it
// makes phone, NID number and payout account readable again under the old
// rules. VALUES ARE NEVER PRINTED: doc ids, key names and lengths only.
//
// Source (pick one):
//   --from-backup <file>   the JSON backup movePrivateProfiles.js wrote to
//                          ~/cc-backups (has the old download links too)
//   --from-private         vendor_private / delivery_partner_private
//                          (no download links: those were never copied)
//
// Per document, in one transaction: sets the values on the public doc. The
// private docs are left as they are (the new app reads them first; removing
// them is a separate decision). A public doc that already holds a DIFFERENT
// non-empty value for a key is a conflict: the script stops before writing.
// Before writing, the current public values of the touched keys are backed up
// to ~/cc-backups (outside the repo and OneDrive).
//
// Usage (from functions/, application-default credentials):
//   node scripts/restorePrivateProfiles.js --from-backup <file>            dry run
//   node scripts/restorePrivateProfiles.js --from-backup <file> --apply    restore
//   node scripts/restorePrivateProfiles.js --from-private [--apply]
// -----------------------------------------------------------------------------

const fs = require("fs");
const os = require("os");
const path = require("path");
const { VENDOR_PRIVATE_KEYS, RIDER_PRIVATE_KEYS } = require("./movePrivateProfiles");

const KINDS = Object.freeze({
  vendor: { publicCollection: "vendors", privateCollection: "vendor_private", keys: VENDOR_PRIVATE_KEYS },
  rider: { publicCollection: "deliveryPartners", privateCollection: "delivery_partner_private", keys: RIDER_PRIVATE_KEYS },
});
const KIND_BY_COLLECTION = Object.freeze({ vendors: "vendor", deliveryPartners: "rider" });

function hasValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.trim().length > 0;
  return true;
}

function sameValue(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

// Pure plan for one public doc.
//   set:       public key -> value to write back
//   conflicts: keys where the public doc already has a different value
function planRestore(kind, publicData, values) {
  const spec = KINDS[kind];
  const pub = publicData && typeof publicData === "object" ? publicData : {};
  const src = values && typeof values === "object" ? values : {};
  const set = {};
  const conflicts = [];
  for (const key of spec.keys) {
    if (!hasValue(src[key])) continue;
    if (hasValue(pub[key])) {
      if (!sameValue(pub[key], src[key])) conflicts.push(key);
      continue; // same value already there
    }
    set[key] = src[key];
  }
  if (conflicts.length) return { set: {}, conflicts };
  return { set, conflicts };
}

// Backup file -> [{ kind, id, values }]
function sourcesFromBackup(backup) {
  if (!Array.isArray(backup)) throw new Error("backup file: expected a JSON array");
  return backup.map((entry) => {
    const kind = KIND_BY_COLLECTION[entry && entry.collection];
    if (!kind || !entry.id || typeof entry.removed !== "object") {
      throw new Error("backup file: every entry needs collection (vendors|deliveryPartners), id, removed");
    }
    return { kind, id: String(entry.id), values: entry.removed };
  });
}

function lengths(obj) {
  return Object.keys(obj).map((k) => `${k}(${String(obj[k] ?? "").length})`).join(", ") || "-";
}

function argValue(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main() {
  const apply = process.argv.includes("--apply");
  const backupPath = argValue("--from-backup");
  const fromPrivate = process.argv.includes("--from-private");
  if (!!backupPath === fromPrivate) {
    throw new Error("give exactly one source: --from-backup <file> or --from-private");
  }

  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;

  // 1. Sources.
  let sources = [];
  if (backupPath) {
    sources = sourcesFromBackup(JSON.parse(fs.readFileSync(backupPath, "utf8")));
  } else {
    for (const kind of Object.keys(KINDS)) {
      const snap = await db.collection(KINDS[kind].privateCollection).get();
      for (const doc of snap.docs) sources.push({ kind, id: doc.id, values: doc.data() });
    }
  }

  // 2. Plan (read only).
  const plans = [];
  for (const s of sources) {
    const spec = KINDS[s.kind];
    const pubSnap = await db.collection(spec.publicCollection).doc(s.id).get();
    if (!pubSnap.exists) {
      console.log(`${spec.publicCollection}/${s.id}: public doc missing, skipped`);
      continue;
    }
    const plan = planRestore(s.kind, pubSnap.data(), s.values);
    plans.push({ ...s, plan, publicData: pubSnap.data() });
    console.log(`${spec.publicCollection}/${s.id}: put back ${lengths(plan.set)}`);
    if (plan.conflicts.length) console.log(`  CONFLICT (public doc has a different value): ${plan.conflicts.join(", ")}`);
  }

  if (plans.some((p) => p.plan.conflicts.length)) {
    console.log("\nCONFLICT. Nothing written.");
    process.exitCode = 2;
    return;
  }
  const work = plans.filter((p) => Object.keys(p.plan.set).length);
  if (!work.length) {
    console.log("\nNothing to restore.");
    return;
  }
  if (!apply) {
    console.log(`\nDry run: ${work.length} doc(s) would change. Nothing written. Re-run with --apply after approval.`);
    return;
  }

  // 3. Backup of the public values about to be overwritten (normally absent).
  const backupDir = path.join(os.homedir(), "cc-backups");
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const before = path.join(backupDir, `restore_private_profiles_before_${stamp}.json`);
  fs.writeFileSync(before, JSON.stringify(work.map((p) => ({
    collection: KINDS[p.kind].publicCollection,
    id: p.id,
    before: Object.fromEntries(Object.keys(p.plan.set).map((k) => [k, p.publicData[k] ?? null])),
  })), null, 2), { mode: 0o600 });
  console.log(`\nBackup of overwritten public values: ${before}`);

  // 4. One transaction per document.
  for (const p of work) {
    const spec = KINDS[p.kind];
    const pubRef = db.collection(spec.publicCollection).doc(p.id);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(pubRef);
      const again = planRestore(p.kind, snap.data() || {}, p.values);
      if (again.conflicts.length || !sameValue(again.set, p.plan.set)) {
        throw new Error(`${spec.publicCollection}/${p.id} changed while running; nothing written for it, run again`);
      }
      tx.update(pubRef, { ...again.set, updatedAt: FieldValue.serverTimestamp() });
    });
    console.log(`restored ${spec.publicCollection}/${p.id}: ${Object.keys(p.plan.set).length} key(s)`);
  }

  // 5. Check: every planned key now holds the planned value.
  let missing = 0;
  for (const p of work) {
    const data = (await db.collection(KINDS[p.kind].publicCollection).doc(p.id).get()).data() || {};
    for (const [k, v] of Object.entries(p.plan.set)) {
      if (!sameValue(data[k], v)) {
        missing++;
        console.log(`NOT RESTORED ${KINDS[p.kind].publicCollection}/${p.id}: ${k}`);
      }
    }
  }
  console.log(missing ? `\nFAILED CHECK: ${missing} key(s) not restored.` : "\nDone. All planned values are back in the public docs.");
  if (missing) process.exitCode = 3;
}

module.exports = { planRestore, sourcesFromBackup };

if (require.main === module) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
