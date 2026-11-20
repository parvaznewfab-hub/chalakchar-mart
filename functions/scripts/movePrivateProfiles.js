#!/usr/bin/env node
// -----------------------------------------------------------------------------
// 14b step B: move vendor and rider personal data out of the public docs.
//
//   vendors/{id}          -> vendor_private/{id}
//   deliveryPartners/{id} -> delivery_partner_private/{id}
//
// Keys: VENDOR_PRIVATE_KEYS / RIDER_PRIVATE_KEYS below (same lists as
// lib/utils/private_profile_fields.dart and firestore.rules; a test checks).
// VALUES ARE NEVER PRINTED: output shows doc ids, key names and lengths only.
//
// Old document download links (vendor nidFront/nidBack/tradeLicense, rider
// nidFrontUrl/nidBackUrl) are NOT copied: they carry a token. The Storage
// path inside the link is stored instead (*Path), and the link is removed.
//
// --apply, per document, in one transaction:
//   - copies each non-empty private value into the private doc (never
//     overwrites a DIFFERENT value already there: that is a conflict, the
//     script stops before writing anything)
//   - deletes those keys from the public doc
// Before any write, a backup of every removed public value is saved to
// ~/cc-backups/ (outside the repo and OneDrive). It CONTAINS personal data
// (phone, NID number, payout account): delete it once the move is checked.
// At the end it re-reads every public doc and fails if a private key is left.
//
// Usage (from functions/, application-default credentials):
//   node scripts/movePrivateProfiles.js            dry run: what would move
//   node scripts/movePrivateProfiles.js --apply    move it (owner approval first)
// -----------------------------------------------------------------------------

const fs = require("fs");
const os = require("os");
const path = require("path");

const VENDOR_PRIVATE_KEYS = Object.freeze([
  "phone", "email", "address", "ownerName", "note",
  "nidFront", "nidBack", "tradeLicense",
  "nidFrontPath", "nidBackPath", "tradeLicensePath",
  "payoutAccount", "payoutNumber",
  "commissionPercent", "commissionRate",
  "totalSales", "totalCommission",
  "pendingBalance", "withdrawableBalance", "withdrawPendingBalance",
  "totalPaidOut", "deliveredOrders", "cancelledOrders",
]);

const RIDER_PRIVATE_KEYS = Object.freeze([
  "nidNumber", "nidFrontUrl", "nidBackUrl", "nidFrontPath", "nidBackPath",
  "address", "email", "note",
]);

// Download-link key -> the path key that replaces it.
const VENDOR_LINK_KEYS = Object.freeze({ nidFront: "nidFrontPath", nidBack: "nidBackPath", tradeLicense: "tradeLicensePath" });
const RIDER_LINK_KEYS = Object.freeze({ nidFrontUrl: "nidFrontPath", nidBackUrl: "nidBackPath" });

const KINDS = Object.freeze({
  vendor: { publicCollection: "vendors", privateCollection: "vendor_private", keys: VENDOR_PRIVATE_KEYS, linkKeys: VENDOR_LINK_KEYS },
  rider: { publicCollection: "deliveryPartners", privateCollection: "delivery_partner_private", keys: RIDER_PRIVATE_KEYS, linkKeys: RIDER_LINK_KEYS },
});

function hasValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.trim().length > 0;
  return true;
}

function sameValue(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

// The Storage object path inside a Firebase download link, or "" (never the token).
function storagePathFromLink(value) {
  const text = String(value || "").trim();
  if (!text) return "";
  if (!/^https?:\/\//.test(text)) return text;
  let url;
  try {
    url = new URL(text);
  } catch {
    return "";
  }
  const m = url.pathname.match(/\/o\/(.+)$/);
  return m ? decodeURIComponent(m[1]) : "";
}

// Pure plan for one document. Returns key names only, plus the private
// values to write (kept in memory, never printed).
//   copy:      private key -> value to set in the private doc
//   remove:    public keys to delete
//   conflicts: private keys where the private doc already has a different value
//   skippedLinks: link keys dropped without a usable path
function planProfileMove(kind, publicData, privateData) {
  const spec = KINDS[kind];
  const pub = publicData && typeof publicData === "object" ? publicData : {};
  const priv = privateData && typeof privateData === "object" ? privateData : {};
  const copy = {};
  const remove = [];
  const conflicts = [];
  const skippedLinks = [];

  const want = (key, value) => {
    if (hasValue(priv[key]) && !sameValue(priv[key], value)) {
      conflicts.push(key);
      return;
    }
    if (!hasValue(priv[key])) copy[key] = value;
  };

  for (const key of spec.keys) {
    if (!Object.prototype.hasOwnProperty.call(pub, key)) continue;
    remove.push(key);
    const value = pub[key];
    if (!hasValue(value)) continue; // empty leftover: just tidy it away

    const pathKey = spec.linkKeys[key];
    if (pathKey) {
      // A link: store its path (unless a path is already given), drop the link.
      const linkPath = storagePathFromLink(value);
      if (!linkPath) {
        skippedLinks.push(key);
        continue;
      }
      if (!hasValue(pub[pathKey])) want(pathKey, linkPath);
      continue;
    }
    want(key, value);
  }

  if (conflicts.length) return { copy: {}, remove: [], conflicts, skippedLinks };
  return { copy, remove, conflicts, skippedLinks };
}

function lengths(obj, keys) {
  return keys.map((k) => `${k}(${String(obj[k] ?? "").length})`).join(", ") || "-";
}

async function main() {
  const admin = require("firebase-admin");
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;

  // 1. Plan everything first (read only).
  const plans = [];
  for (const kind of Object.keys(KINDS)) {
    const spec = KINDS[kind];
    const snap = await db.collection(spec.publicCollection).get();
    for (const doc of snap.docs) {
      const privSnap = await db.collection(spec.privateCollection).doc(doc.id).get();
      const plan = planProfileMove(kind, doc.data(), privSnap.data() || {});
      plans.push({ kind, id: doc.id, plan, publicData: doc.data() });
      console.log(`${spec.publicCollection}/${doc.id}: private doc ${privSnap.exists ? "exists" : "new"}`);
      console.log(`  copy to ${spec.privateCollection}: ${lengths(plan.copy, Object.keys(plan.copy))}`);
      console.log(`  remove from ${spec.publicCollection}: ${lengths(doc.data(), plan.remove)}`);
      if (plan.skippedLinks.length) console.log(`  link without a Storage path (dropped, not copied): ${plan.skippedLinks.join(", ")}`);
      if (plan.conflicts.length) console.log(`  CONFLICT (different value already in private doc): ${plan.conflicts.join(", ")}`);
    }
  }

  const conflicted = plans.filter((p) => p.plan.conflicts.length);
  if (conflicted.length) {
    console.log(`\nCONFLICT in ${conflicted.length} doc(s). Nothing written.`);
    process.exitCode = 2;
    return;
  }
  const work = plans.filter((p) => p.plan.remove.length);
  if (!work.length) {
    console.log("\nNothing to move.");
    return;
  }
  if (!apply) {
    console.log(`\nDry run: ${work.length} doc(s) would change. Nothing written. Re-run with --apply after approval.`);
    return;
  }

  // 2. Backup of every value that will leave the public docs.
  const backupDir = path.join(os.homedir(), "cc-backups");
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupFile = path.join(backupDir, `private_profiles_${stamp}.json`);
  const backup = work.map((p) => ({
    collection: KINDS[p.kind].publicCollection,
    id: p.id,
    removed: Object.fromEntries(p.plan.remove.map((k) => [k, p.publicData[k]])),
  }));
  fs.writeFileSync(backupFile, JSON.stringify(backup, null, 2), { mode: 0o600 });
  console.log(`\nBackup (contains personal data, delete after checking): ${backupFile}`);

  // 3. One transaction per document.
  for (const p of work) {
    const spec = KINDS[p.kind];
    const pubRef = db.collection(spec.publicCollection).doc(p.id);
    const privRef = db.collection(spec.privateCollection).doc(p.id);
    await db.runTransaction(async (tx) => {
      const [pubSnap, privSnap] = await Promise.all([tx.get(pubRef), tx.get(privRef)]);
      const again = planProfileMove(p.kind, pubSnap.data() || {}, privSnap.data() || {});
      if (again.conflicts.length || !sameValue(again.remove, p.plan.remove) || !sameValue(again.copy, p.plan.copy)) {
        throw new Error(`${spec.publicCollection}/${p.id} changed while running; nothing written for it, run again`);
      }
      tx.set(privRef, { ...again.copy, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      const removal = Object.fromEntries(again.remove.map((k) => [k, FieldValue.delete()]));
      tx.update(pubRef, removal);
    });
    console.log(`moved ${spec.publicCollection}/${p.id}: ${p.plan.remove.length} key(s)`);
  }

  // 4. Check: no private key with a value left in any public doc.
  let left = 0;
  for (const kind of Object.keys(KINDS)) {
    const spec = KINDS[kind];
    const snap = await db.collection(spec.publicCollection).get();
    for (const doc of snap.docs) {
      const keys = spec.keys.filter((k) => Object.prototype.hasOwnProperty.call(doc.data(), k));
      if (keys.length) {
        left += keys.length;
        console.log(`LEFT in ${spec.publicCollection}/${doc.id}: ${keys.join(", ")}`);
      }
    }
  }
  console.log(left ? `\nFAILED CHECK: ${left} private key(s) still in public docs.` : "\nDone. No private key left in vendors or deliveryPartners.");
  if (left) process.exitCode = 3;
}

module.exports = {
  VENDOR_PRIVATE_KEYS,
  RIDER_PRIVATE_KEYS,
  planProfileMove,
  storagePathFromLink,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
