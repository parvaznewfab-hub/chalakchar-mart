#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Sets Cache-Control on existing Storage images so browsers keep them instead
// of downloading them again on every visit (Storage default: "private,
// max-age=0"). New uploads already set it (lib/services/image_upload_service
// kImageCacheControl). Image names are timestamped and never overwritten, so
// a long, immutable cache is safe.
//
// Only metadata changes: no image is moved, re-encoded or deleted, and the
// download URLs/tokens stay the same. Reversing = setting the old value from
// the backup file.
//
// Report (always): per folder count, total size, current cache values, and
// the largest images (candidates for re-uploading smaller in the admin).
//
// Usage (from functions/, application-default credentials):
//   node scripts/setImageCacheControl.js            dry run
//   node scripts/setImageCacheControl.js --apply    write metadata
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const BUCKET = "chalakchar-mart.firebasestorage.app";
const FOLDERS = ["products/", "banners/", "categories/"];
const CACHE_CONTROL = "public, max-age=31536000, immutable";
const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: "chalakchar-mart", storageBucket: BUCKET });
  const bucket = admin.storage().bucket(BUCKET);

  const todo = [];
  const largest = [];
  for (const prefix of FOLDERS) {
    const [files] = await bucket.getFiles({ prefix });
    const images = files.filter((f) => /^image\//.test(f.metadata.contentType || "") || /\.(jpe?g|png|webp|gif)$/i.test(f.name));
    const bytes = images.reduce((a, f) => a + Number(f.metadata.size || 0), 0);
    const values = {};
    for (const f of images) {
      const cc = f.metadata.cacheControl || "(none)";
      values[cc] = (values[cc] || 0) + 1;
      if (f.metadata.cacheControl !== CACHE_CONTROL) todo.push(f);
      largest.push({ name: f.name, kb: Math.round(Number(f.metadata.size || 0) / 1024) });
    }
    console.log(`${prefix.padEnd(12)} ${String(images.length).padStart(4)} images, ${(bytes / 1048576).toFixed(1)} MB, cache: ${JSON.stringify(values)}`);
  }
  largest.sort((a, b) => b.kb - a.kb);
  console.log("\nLargest images:");
  for (const f of largest.slice(0, 15)) console.log(`  ${String(f.kb).padStart(6)} KB  ${f.name}`);
  console.log(`\nTo update: ${todo.length} image(s) -> Cache-Control "${CACHE_CONTROL}"`);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = path.join(OUT_DIR, `image-cache-control-${apply ? "backup" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(backupPath, JSON.stringify(todo.map((f) => ({ name: f.name, cacheControl: f.metadata.cacheControl ?? null })), null, 2));
  console.log(`Backup/report: ${backupPath}`);

  if (!apply) {
    console.log("DRY RUN — nothing written. Write with --apply.");
    return;
  }
  let done = 0;
  for (const f of todo) {
    await f.setMetadata({ cacheControl: CACHE_CONTROL });
    done++;
  }
  console.log(`Updated: ${done} image(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
