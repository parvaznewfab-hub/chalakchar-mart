#!/usr/bin/env node
// -----------------------------------------------------------------------------
// 14b step C: remove the Firebase download tokens from vendor / rider identity
// documents, so no download link (old or copied) opens them any more. After
// this, staff open them only through getIdentityDocumentUrl (V4 signed URL,
// 5 minutes; signed URLs do not use download tokens).
//
// Files: every *Path in vendor_private (nidFrontPath, nidBackPath,
// tradeLicensePath) and delivery_partner_private (nidFrontPath, nidBackPath),
// only inside the owner's own document folder. Removes the
// firebaseStorageDownloadTokens metadata key; does NOT create a new token
// (the Console's "Revoke" does create one) and does not touch the file.
// TOKEN VALUES ARE NEVER PRINTED OR SAVED: tokens are credentials, and an old
// token must never come back, so there is nothing to restore. The script
// saves a list of file names + token counts to ~/cc-backups as the record.
//
// Usage (from functions/, application-default credentials):
//   node scripts/revokeIdentityDocTokens.js            dry run
//   node scripts/revokeIdentityDocTokens.js --apply    remove (owner approval first)
// Exit: 0 ok, 3 a token is still there afterwards.
// -----------------------------------------------------------------------------

const fs = require("fs");
const os = require("os");
const path = require("path");
const { KINDS, pathInsideOwnerFolder } = require("../identity/identityDocumentUrl");

function tokenCount(metadata) {
  const raw = metadata && metadata.metadata && metadata.metadata.firebaseStorageDownloadTokens;
  return typeof raw === "string" && raw.trim() ? raw.split(",").filter((t) => t.trim()).length : 0;
}

// Pure: private docs -> the files to look at. Paths outside the owner's
// folder are reported, never touched.
//   docs: [{ kind, id, data }]
function filesFromPrivateDocs(docs) {
  const files = [];
  const skipped = [];
  for (const { kind, id, data } of docs) {
    const spec = KINDS[kind];
    for (const [which, field] of Object.entries(spec.files)) {
      const p = typeof (data || {})[field] === "string" ? data[field].trim() : "";
      if (!p) continue;
      if (pathInsideOwnerFolder(spec, id, p)) files.push({ kind, id, which, path: p });
      else skipped.push({ kind, id, which });
    }
  }
  return { files, skipped };
}

async function main() {
  const apply = process.argv.includes("--apply");
  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    const projectId = process.env.GCLOUD_PROJECT || "chalakchar-mart";
    admin.initializeApp({ projectId, storageBucket: process.env.STORAGE_BUCKET || `${projectId}.firebasestorage.app` });
  }
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const docs = [];
  for (const kind of Object.keys(KINDS)) {
    const snap = await db.collection(KINDS[kind].privateCollection).get();
    snap.docs.forEach((d) => docs.push({ kind, id: d.id, data: d.data() }));
  }
  const { files, skipped } = filesFromPrivateDocs(docs);
  skipped.forEach((s) => console.log(`SKIPPED (path outside the owner's folder): ${s.kind}/${s.id}/${s.which}`));

  const work = [];
  for (const f of files) {
    const [exists] = await bucket.file(f.path).exists();
    if (!exists) {
      console.log(`${f.kind} ${f.id.slice(0, 4)}… ${f.which}: file missing`);
      continue;
    }
    const [meta] = await bucket.file(f.path).getMetadata();
    const count = tokenCount(meta);
    console.log(`${f.kind} ${f.id.slice(0, 4)}… ${f.which}: ${count} token(s)`);
    if (count) work.push({ ...f, count });
  }

  if (!work.length) {
    console.log("\nNo download token left on any identity document.");
    return;
  }
  if (!apply) {
    console.log(`\nDry run: ${work.length} file(s) would lose their token(s). Nothing changed. Re-run with --apply after approval.`);
    return;
  }

  const dir = path.join(os.homedir(), "cc-backups");
  fs.mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const record = path.join(dir, `identity_doc_tokens_removed_${stamp}.json`);
  fs.writeFileSync(record, JSON.stringify(work.map((w) => ({ kind: w.kind, id: w.id, which: w.which, path: w.path, tokens: w.count })), null, 2), { mode: 0o600 });
  console.log(`\nRecord (file names + counts, no token): ${record}`);

  for (const w of work) {
    await bucket.file(w.path).setMetadata({ metadata: { firebaseStorageDownloadTokens: null } });
    console.log(`removed: ${w.kind} ${w.id.slice(0, 4)}… ${w.which}`);
  }

  let left = 0;
  for (const w of work) {
    const [meta] = await bucket.file(w.path).getMetadata();
    if (tokenCount(meta)) {
      left++;
      console.log(`STILL HAS A TOKEN: ${w.kind} ${w.id.slice(0, 4)}… ${w.which}`);
    }
  }
  console.log(left ? `\nFAILED CHECK: ${left} file(s) still have a token.` : "\nDone. No download token left.");
  if (left) process.exitCode = 3;
}

module.exports = { tokenCount, filesFromPrivateDocs };

if (require.main === module) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
