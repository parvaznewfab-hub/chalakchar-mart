#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Move the social media tokens out of the public settings/app doc into
// settings/app_secrets (readable only by settings editors).
//
// Keys moved: see settings/socialSecrets.js (FB/IG/WA/Messenger tokens and the
// legacy TikTok client secret). Token VALUES are never printed or logged:
// output shows key names and lengths only.
//
// Order (the owner runs --apply, after approval):
//   1. firestore.rules with settings/app_secrets deployed
//   2. functions deployed (they read app_secrets, falling back to settings/app)
//   3. this script --apply
//   4. hosting with the admin settings page that reads/writes app_secrets
//
// --apply, in one transaction:
//   - copies each non-empty token into settings/app_secrets.socialApi
//     (never overwrites a different value already there: that is a conflict
//      and the script stops)
//   - deletes those keys from settings/app.socialApi
// Before it, a backup of the old settings/app.socialApi token keys is saved
// to functions/scripts/backups/ (git-ignored). It CONTAINS THE TOKENS: delete
// it once the move is checked, and after the tokens are rotated it is useless.
//
// Usage (from functions/, application-default credentials):
//   node scripts/moveSocialSecrets.js            dry run: what would move
//   node scripts/moveSocialSecrets.js --apply    move it
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const { SECRET_SOCIAL_API_KEYS } = require("../settings/socialSecrets");

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasText(value) {
  return value !== null && value !== undefined && String(value).trim().length > 0;
}

// Pure plan from the two docs' data. Returns key names only.
function planSecretsMove(appData, secretsData) {
  const pub = isPlainObject(appData?.socialApi) ? appData.socialApi : {};
  const sec = isPlainObject(secretsData?.socialApi) ? secretsData.socialApi : {};
  const copyKeys = [];
  const removeKeys = [];
  const conflicts = [];
  for (const key of SECRET_SOCIAL_API_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(pub, key)) continue;
    const value = pub[key];
    if (!hasText(value)) {
      removeKeys.push(key); // empty leftover: just tidy it away
      continue;
    }
    if (hasText(sec[key]) && sec[key] !== value) {
      conflicts.push(key);
      continue;
    }
    if (!hasText(sec[key])) copyKeys.push(key);
    removeKeys.push(key);
  }
  if (conflicts.length) return { copyKeys: [], removeKeys: [], conflicts };
  return { copyKeys, removeKeys, conflicts };
}

function describe(pub, keys) {
  return keys.map((k) => `${k} (length ${String(pub[k] ?? "").length})`).join(", ") || "-";
}

async function main() {
  const admin = require("firebase-admin");
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const appRef = db.collection("settings").doc("app");
  const secretsRef = db.collection("settings").doc("app_secrets");

  const [appSnap, secretsSnap] = await Promise.all([appRef.get(), secretsRef.get()]);
  const appData = appSnap.data() || {};
  const pub = isPlainObject(appData.socialApi) ? appData.socialApi : {};
  const plan = planSecretsMove(appData, secretsSnap.data() || {});

  console.log(`settings/app_secrets exists: ${secretsSnap.exists}`);
  console.log(`copy to app_secrets: ${describe(pub, plan.copyKeys)}`);
  console.log(`remove from settings/app: ${describe(pub, plan.removeKeys)}`);
  if (plan.conflicts.length) {
    console.log(`CONFLICT (different value already in app_secrets, nothing done): ${plan.conflicts.join(", ")}`);
    process.exitCode = 2;
    return;
  }
  if (!plan.removeKeys.length) {
    console.log("Nothing to move.");
    return;
  }
  if (!apply) {
    console.log("Dry run. Nothing written. Re-run with --apply after approval.");
    return;
  }

  const backupDir = path.join(__dirname, "backups");
  fs.mkdirSync(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupFile = path.join(backupDir, `settings_app_socialApi_secrets_${stamp}.json`);
  const backup = {};
  for (const key of plan.removeKeys) backup[key] = pub[key];
  fs.writeFileSync(backupFile, JSON.stringify({ doc: "settings/app", socialApi: backup }, null, 2), { mode: 0o600 });
  console.log(`Backup (contains tokens, delete after checking): ${backupFile}`);

  const { FieldValue } = admin.firestore;
  await db.runTransaction(async (tx) => {
    const [a, s] = await Promise.all([tx.get(appRef), tx.get(secretsRef)]);
    const again = planSecretsMove(a.data() || {}, s.data() || {});
    if (again.conflicts.length || again.removeKeys.join() !== plan.removeKeys.join()) {
      throw new Error("settings changed while running; nothing written, run again");
    }
    const livePub = (a.data() || {}).socialApi || {};
    const copy = {};
    for (const key of again.copyKeys) copy[key] = livePub[key];
    if (Object.keys(copy).length) {
      tx.set(secretsRef, { socialApi: copy, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    const removal = {};
    for (const key of again.removeKeys) removal[`socialApi.${key}`] = FieldValue.delete();
    tx.update(appRef, removal);
  });

  const [after, afterSecrets] = await Promise.all([appRef.get(), secretsRef.get()]);
  const leftover = SECRET_SOCIAL_API_KEYS.filter((k) => hasText(((after.data() || {}).socialApi || {})[k]));
  const stored = SECRET_SOCIAL_API_KEYS.filter((k) => hasText(((afterSecrets.data() || {}).socialApi || {})[k]));
  console.log(`Done. Tokens left in settings/app: ${leftover.join(", ") || "none"}`);
  console.log(`Tokens in settings/app_secrets: ${stored.join(", ") || "none"}`);
}

module.exports = { planSecretsMove };

if (require.main === module) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
