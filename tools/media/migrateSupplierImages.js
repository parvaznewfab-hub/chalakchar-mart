#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time: product images off the supplier's CDN (ae01.alicdn.com,
// *.aliexpress-media.com) into our own Firebase Storage, as WebP.
//
// For every distinct supplier image URL used by a product (image, imageUrl,
// images[], variants[].image/imageUrl, <img src> in overviewHtml):
//   1. download it;
//   2. keep the original, private: backups/supplier_images/{key}.{ext}
//      (storage.rules default deny: only the Admin SDK can read it);
//   3. WebP (already-WebP images up to 1600px are kept byte for byte; others
//      are converted, max 1600px wide, quality 82) and upload, public:
//      product_images/{key}.webp with a download token and a 1-year
//      immutable Cache-Control.
// {key} = first 24 hex of sha256(url): nothing about the product id or the
// supplier is in the path. Then every product field that used the old URL is
// rewritten to the new one (og:image follows, productSeo reads image).
//
// Resumable: a file already in Storage is reused (its token read back), and
// the URL map is saved after every image to tools/backfill/.
// Product writes stamp systemWriteAt (onProductStockUpdated does nothing for
// them) and lastWriteSource "image_migration".
//
// DRY RUN BY DEFAULT: counts images, sizes them with HEAD requests (total
// bytes), converts a sample to estimate the WebP total; writes nothing.
// --apply: Storage uploads, then a JSON backup of every product field it will
// change, then the product updates (one transaction per product).
//
// Emulators: FIRESTORE_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST.
// Usage (from tools/media/, after npm install):
//   node migrateSupplierImages.js [--apply] [--products=id,id] [--sample=25] [--concurrency=6]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const admin = require("firebase-admin");
const sharp = require("sharp");

const PROJECT = process.env.GCLOUD_PROJECT || "chalakchar-mart";
const BUCKET = process.env.STORAGE_BUCKET || "chalakchar-mart.firebasestorage.app";
const OUT_DIR = path.join(__dirname, "..", "backfill");
const SUPPLIER_HOST = /^(?:[a-z0-9-]+\.)*(?:alicdn\.com|aliexpress-media\.com|aliexpress\.com|alibaba\.com)$/i;
const PUBLIC_PREFIX = "product_images";
const BACKUP_PREFIX = "backups/supplier_images";
const SYSTEM_WRITE_FIELD = "systemWriteAt"; // functions/catalog/systemWrite.js

function parseArgs(argv) {
  const args = { apply: false, products: [], sample: 25, concurrency: 6 };
  for (const arg of argv) {
    if (arg === "--apply") args.apply = true;
    else if (arg.startsWith("--products=")) args.products = arg.slice(11).split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg.startsWith("--sample=")) args.sample = Math.max(0, parseInt(arg.slice(9), 10) || 0);
    else if (arg.startsWith("--concurrency=")) args.concurrency = Math.max(1, parseInt(arg.slice(14), 10) || 6);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

/** "https://..." for a URL as stored (some HTML uses "//host/..."). */
function fetchableUrl(raw) {
  const s = String(raw || "").trim();
  return s.startsWith("//") ? `https:${s}` : s;
}

function isSupplierUrl(raw) {
  try {
    return SUPPLIER_HOST.test(new URL(fetchableUrl(raw)).hostname);
  } catch (_) {
    return false;
  }
}

function keyFor(raw) {
  return crypto.createHash("sha256").update(fetchableUrl(raw)).digest("hex").slice(0, 24);
}

const IMG_SRC = /(<img\b[^>]*?\bsrc\s*=\s*)(["'])([^"']+)\2/gi;

/** Every supplier image URL a product uses, as stored. */
function supplierUrlsOf(product) {
  const urls = new Set();
  const add = (u) => { if (typeof u === "string" && isSupplierUrl(u)) urls.add(u); };
  add(product.image);
  add(product.imageUrl);
  (Array.isArray(product.images) ? product.images : []).forEach(add);
  (Array.isArray(product.variants) ? product.variants : []).forEach((v) => { add(v?.image); add(v?.imageUrl); });
  if (typeof product.overviewHtml === "string") {
    for (const m of product.overviewHtml.matchAll(IMG_SRC)) add(m[3]);
  }
  return [...urls];
}

/** The product's fields with every mapped URL replaced; {} when nothing changes. */
function imageFieldChanges(product, urlMap) {
  const swap = (u) => (typeof u === "string" && urlMap.has(u) ? urlMap.get(u) : u);
  const changes = {};
  for (const f of ["image", "imageUrl"]) {
    if (swap(product[f]) !== product[f]) changes[f] = swap(product[f]);
  }
  if (Array.isArray(product.images)) {
    const next = product.images.map(swap);
    if (next.some((u, i) => u !== product.images[i])) changes.images = next;
  }
  if (Array.isArray(product.variants)) {
    let changed = false;
    const next = product.variants.map((v) => {
      if (!v || typeof v !== "object") return v;
      const out = { ...v };
      for (const f of ["image", "imageUrl"]) {
        if (swap(v[f]) !== v[f]) { out[f] = swap(v[f]); changed = true; }
      }
      return out;
    });
    if (changed) changes.variants = next;
  }
  if (typeof product.overviewHtml === "string") {
    const next = product.overviewHtml.replace(IMG_SRC, (whole, pre, q, url) => (urlMap.has(url) ? `${pre}${q}${urlMap.get(url)}${q}` : whole));
    if (next !== product.overviewHtml) changes.overviewHtml = next;
  }
  return changes;
}

async function pool(items, size, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(size, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  }));
  return results;
}

async function headSize(url) {
  try {
    const r = await fetch(fetchableUrl(url), { method: "HEAD", redirect: "follow" });
    return { ok: r.ok, status: r.status, bytes: Number(r.headers.get("content-length")) || 0, type: r.headers.get("content-type") || "" };
  } catch (error) {
    return { ok: false, status: 0, bytes: 0, error: error.message };
  }
}

async function download(url) {
  const r = await fetch(fetchableUrl(url), { redirect: "follow" });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return { buffer: Buffer.from(await r.arrayBuffer()), type: (r.headers.get("content-type") || "").split(";")[0].trim() };
}

const MAX_WIDTH = 1600;

/**
 * WebP bytes for an image. Already WebP and at most MAX_WIDTH wide (what the
 * supplier CDN serves): kept byte for byte — re-encoding a lossy WebP only
 * loses quality. Anything else is converted (and shrunk to MAX_WIDTH).
 */
async function toWebp(buffer) {
  const meta = await sharp(buffer, { failOn: "none" }).metadata();
  if (meta.format === "webp" && (meta.width || 0) <= MAX_WIDTH && !meta.orientation) return buffer;
  return sharp(buffer, { failOn: "none", animated: false })
    .rotate()
    .resize({ width: MAX_WIDTH, withoutEnlargement: true })
    .webp({ quality: 82 })
    .toBuffer();
}

function extFor(type, url) {
  if (/png/.test(type)) return "png";
  if (/webp/.test(type)) return "webp";
  if (/gif/.test(type)) return "gif";
  if (/avif/.test(type)) return "avif";
  const m = fetchableUrl(url).split("?")[0].match(/\.(jpe?g|png|webp|gif|avif)$/i);
  return m ? m[1].toLowerCase().replace("jpeg", "jpg") : "jpg";
}

function downloadUrl(objectPath, token) {
  const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST
    ? `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`
    : "https://firebasestorage.googleapis.com";
  return `${host}/v0/b/${BUCKET}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
}

/** Upload (or reuse) one image; returns its public download URL. */
async function migrateOne(bucket, url) {
  const key = keyFor(url);
  const publicPath = `${PUBLIC_PREFIX}/${key}.webp`;
  const file = bucket.file(publicPath);
  const [exists] = await file.exists();
  if (exists) {
    const [meta] = await file.getMetadata();
    const token = String(meta.metadata?.firebaseStorageDownloadTokens || "").split(",")[0];
    if (token) return { url: downloadUrl(publicPath, token), reused: true, originalBytes: 0, webpBytes: Number(meta.size) || 0 };
  }
  const { buffer, type } = await download(url);
  await bucket.file(`${BACKUP_PREFIX}/${key}.${extFor(type, url)}`).save(buffer, {
    resumable: false,
    contentType: type || "application/octet-stream",
    metadata: { metadata: { sourceUrl: fetchableUrl(url) } },
  });
  const webp = await toWebp(buffer);
  const token = crypto.randomUUID();
  await file.save(webp, {
    resumable: false,
    contentType: "image/webp",
    metadata: {
      cacheControl: "public, max-age=31536000, immutable",
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  return { url: downloadUrl(publicPath, token), reused: false, originalBytes: buffer.length, webpBytes: webp.length };
}

const mb = (n) => `${(n / 1024 / 1024).toFixed(1)} MB`;

async function main() {
  const args = parseArgs(process.argv.slice(2));
  admin.initializeApp({ projectId: PROJECT, storageBucket: BUCKET });
  const db = admin.firestore();
  const target = process.env.FIRESTORE_EMULATOR_HOST
    ? `EMULATOR firestore=${process.env.FIRESTORE_EMULATOR_HOST} storage=${process.env.FIREBASE_STORAGE_EMULATOR_HOST || "(LIVE!)"}`
    : "LIVE";
  if (process.env.FIRESTORE_EMULATOR_HOST && !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
    throw new Error("Firestore emulator without the Storage emulator: refusing to mix live Storage with emulator data.");
  }
  console.log(`Target: ${target}  Mode: ${args.apply ? "APPLY" : "dry run"}  Bucket: ${BUCKET}`);

  const snap = await db.collection("products").get();
  const only = args.products.length ? new Set(args.products) : null;
  const products = snap.docs.filter((d) => !only || only.has(d.id));
  const usedBy = new Map();
  let fieldRefs = 0;
  for (const d of products) {
    for (const u of supplierUrlsOf(d.data())) {
      if (!usedBy.has(u)) usedBy.set(u, []);
      usedBy.get(u).push(d.id);
      fieldRefs++;
    }
  }
  const urls = [...usedBy.keys()];
  const productCount = new Set([...usedBy.values()].flat()).size;
  console.log(`Products with supplier images: ${productCount}; distinct image URLs: ${urls.length}`);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const tag = process.env.FIRESTORE_EMULATOR_HOST ? "emulator" : "live";

  if (!args.apply) {
    const heads = await pool(urls, args.concurrency, headSize);
    const ok = heads.filter((h) => h.ok);
    const total = ok.reduce((n, h) => n + h.bytes, 0);
    const types = {};
    ok.forEach((h) => { types[h.type] = (types[h.type] || 0) + 1; });
    console.log(`HEAD: ${ok.length} ok, ${heads.length - ok.length} failed; originals total ${mb(total)} (${total} bytes)`);
    console.log("Content types:", types);
    const failed = urls.filter((_, i) => !heads[i].ok);
    if (failed.length) console.log("Failed:", failed.slice(0, 10).map((u, i) => `${heads[urls.indexOf(u)].status} ${u}`));

    // WebP estimate from a sample (downloads + converts in memory only).
    const sample = urls.filter((_, i) => heads[i].ok).slice(0, args.sample);
    let sIn = 0, sOut = 0;
    await pool(sample, args.concurrency, async (u) => {
      try {
        const { buffer } = await download(u);
        const webp = await toWebp(buffer);
        sIn += buffer.length; sOut += webp.length;
      } catch (_) { /* counted as failed above if it really fails */ }
    });
    if (sIn) console.log(`WebP sample (${sample.length} images): ${mb(sIn)} -> ${mb(sOut)} (${Math.round((sOut / sIn) * 100)}%); estimated WebP total ~${mb(total * (sOut / sIn))}`);
    const reportPath = path.join(OUT_DIR, `supplier-images-${tag}-${stamp}-dryrun.json`);
    fs.writeFileSync(reportPath, JSON.stringify(urls.map((u, i) => ({ url: u, key: keyFor(u), bytes: heads[i].bytes, ok: heads[i].ok, products: usedBy.get(u) })), null, 1));
    console.log(`Report: ${reportPath}`);
    return;
  }

  // ---- apply: Storage first -------------------------------------------------
  const bucket = admin.storage().bucket(BUCKET);
  const mapPath = path.join(OUT_DIR, `supplier-images-${tag}-urlmap.json`);
  const urlMap = new Map(fs.existsSync(mapPath) ? Object.entries(JSON.parse(fs.readFileSync(mapPath, "utf8"))) : []);
  let uploaded = 0, reused = 0, inBytes = 0, outBytes = 0;
  const failures = [];
  await pool(urls.filter((u) => !urlMap.has(u)), args.concurrency, async (u) => {
    try {
      const r = await migrateOne(bucket, u);
      urlMap.set(u, r.url);
      if (r.reused) reused++; else { uploaded++; inBytes += r.originalBytes; outBytes += r.webpBytes; }
      fs.writeFileSync(mapPath, JSON.stringify(Object.fromEntries(urlMap), null, 1));
    } catch (error) {
      failures.push({ url: u, message: error.message });
    }
  });
  console.log(`Storage: ${uploaded} uploaded (${mb(inBytes)} -> ${mb(outBytes)} WebP), ${reused} reused, ${failures.length} failed. URL map: ${mapPath}`);

  // ---- backup + product updates ------------------------------------------------
  const work = products
    .map((d) => ({ id: d.id, before: d.data(), changes: imageFieldChanges(d.data(), urlMap) }))
    .filter((w) => Object.keys(w.changes).length);
  const backupPath = path.join(OUT_DIR, `supplier-images-${tag}-${stamp}-BACKUP.json`);
  fs.writeFileSync(backupPath, JSON.stringify(work.map((w) => ({
    id: w.id,
    fields: Object.fromEntries(Object.keys(w.changes).map((f) => [f, w.before[f] ?? null])),
  })), null, 1));
  console.log(`Backup of product fields: ${backupPath}`);

  let done = 0;
  for (const w of work) {
    try {
      await db.runTransaction(async (tx) => {
        const ref = db.collection("products").doc(w.id);
        const fresh = await tx.get(ref);
        if (!fresh.exists) return;
        const changes = imageFieldChanges(fresh.data(), urlMap);
        if (!Object.keys(changes).length) return;
        tx.update(ref, {
          ...changes,
          [SYSTEM_WRITE_FIELD]: admin.firestore.FieldValue.serverTimestamp(),
          lastWriteSource: "image_migration",
        });
      });
      done++;
    } catch (error) {
      failures.push({ product: w.id, message: error.message });
    }
  }
  console.log(`Products written: ${done}/${work.length}`);
  const after = await db.collection("products").get();
  const left = after.docs.filter((d) => (!only || only.has(d.id)) && supplierUrlsOf(d.data()).length);
  console.log(`Verify: products still using supplier images: ${left.length}`);
  if (failures.length) { console.log("FAILURES:", failures.slice(0, 20), failures.length > 20 ? `(+${failures.length - 20})` : ""); process.exitCode = 1; }
}

if (require.main === module) {
  main().catch((error) => { console.error(error); process.exit(1); });
}

module.exports = { supplierUrlsOf, imageFieldChanges, isSupplierUrl, keyFor, fetchableUrl };
