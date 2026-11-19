#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time cleanup: supplier wording out of public product text.
//
//   description, overview, banglaDescription, metaDescription: every sentence
//     that names the supplier/origin (catalog/customerText.js mentionsSupplier:
//     AliExpress, China, Cainiao, Taobao, 1688, চীন) is removed, line by line,
//     so the rest keeps its shape ("... delivery from AliExpress official
//     warehouse.)" goes, the sentence before it stays).
//   overviewHtml: the same, per text run; tags (and images) untouched.
//   seoTags, searchKeywords: entries naming the supplier removed.
//   suggestedCategory / suggestedSubCategory "AliExpress": replaced by the
//     product's real category ("" when it has none).
//
// Only supplier sentences are removed here; other seller boilerplate is
// already hidden at display time (cleanCustomerText) and left in the data.
// Not changed: variant names ("... / China Mainland" — the app strips the
// ship-from part when showing them) and specifications (hidden by
// isHiddenSpecification).
//
// DRY RUN BY DEFAULT: prints counts + before/after samples, writes a report
// to tools/backfill/. --apply first writes a JSON backup of every changed
// field, then updates each product in a transaction that recomputes from the
// current doc. Writes stamp systemWriteAt (onProductStockUpdated sends
// nothing) and lastWriteSource "supplier_text_cleanup".
//
// Usage (from functions/): node scripts/cleanSupplierText.js [--apply] [--products=id,id] [--samples=5]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { mentionsSupplier, stripSupplierSentences, withoutSupplierKeywords } = require("../catalog/customerText");
const { SYSTEM_WRITE_FIELD } = require("../catalog/systemWrite");

const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");
const TEXT_FIELDS = ["description", "overview", "banglaDescription", "metaDescription"];
const LIST_FIELDS = ["seoTags", "searchKeywords"];
const CATEGORY_FIELDS = ["suggestedCategory", "suggestedSubCategory"];

function text(v) {
  return v == null ? "" : String(v);
}

/** ")" left without "(" and empty "()" after a sentence was removed. */
function tidyBrackets(s) {
  let depth = 0;
  let out = "";
  for (const ch of s) {
    if (ch === "(") depth++;
    if (ch === ")") {
      if (depth === 0) { out = out.replace(/\s+$/, ""); continue; }
      depth--;
    }
    out += ch;
  }
  return out.replace(/\s*\(\s*\)/g, "").replace(/[ \t]{2,}/g, " ").trim();
}

/** Text without its supplier sentences; lines without one stay byte-identical. */
function stripSupplierText(value) {
  const s = text(value);
  if (!mentionsSupplier(s)) return s;
  const lines = s.split("\n");
  const out = [];
  const isHeading = (l) => l && l.trim().length <= 40 && !/[.!?।,:;)]\s*$/.test(l.trim());
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!mentionsSupplier(line)) { out.push(line); continue; }
    const cleaned = tidyBrackets(stripSupplierSentences(line));
    if (cleaned) { out.push(cleaned); continue; }
    // The whole section under a short heading ("Shipping Method") was the
    // supplier sentence: the heading goes too.
    const next = lines[i + 1];
    const prev = out[out.length - 1];
    const beforePrev = out[out.length - 2];
    if (isHeading(prev) && (beforePrev === undefined || !beforePrev.trim()) && (next === undefined || !next.trim())) out.pop();
  }
  return out.join("\n").replace(/\n\s*\n(\s*\n)+/g, "\n\n").trim();
}

/** [stripSupplierText] for every text run of an HTML string; tags stay. */
function stripSupplierHtml(html) {
  const s = text(html);
  if (!mentionsSupplier(s.replace(/<[^>]*>/g, " "))) return s;
  const wrapped = `>${s}<`;
  return wrapped.replace(/>([^<>]+)</g, (whole, run) => {
    if (!mentionsSupplier(run)) return whole;
    return `>${stripSupplierText(run)}<`;
  }).slice(1, -1);
}

/** The field updates for one product: { field: newValue }, {} when clean. */
function supplierTextChanges(product) {
  const changes = {};
  for (const f of TEXT_FIELDS) {
    if (typeof product[f] !== "string") continue;
    const next = stripSupplierText(product[f]);
    if (next !== product[f]) changes[f] = next;
  }
  if (typeof product.overviewHtml === "string") {
    const next = stripSupplierHtml(product.overviewHtml);
    if (next !== product.overviewHtml) changes.overviewHtml = next;
  }
  for (const f of LIST_FIELDS) {
    if (!Array.isArray(product[f])) continue;
    const next = withoutSupplierKeywords(product[f]);
    if (next.length !== product[f].length) changes[f] = next;
  }
  const realCategory = mentionsSupplier(product.category) ? "" : text(product.category).trim();
  if (mentionsSupplier(product.suggestedCategory)) changes.suggestedCategory = realCategory;
  if (mentionsSupplier(product.suggestedSubCategory)) changes.suggestedSubCategory = "";
  return changes;
}

function parseArgs(argv) {
  const args = { apply: false, products: [], samples: 5 };
  for (const arg of argv) {
    if (arg === "--apply") args.apply = true;
    else if (arg.startsWith("--products=")) args.products = arg.slice(11).split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg.startsWith("--samples=")) args.samples = Math.max(0, parseInt(arg.slice(10), 10) || 0);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();
  const target = process.env.FIRESTORE_EMULATOR_HOST ? `EMULATOR ${process.env.FIRESTORE_EMULATOR_HOST}` : "LIVE";
  console.log(`Target: ${target}  Mode: ${args.apply ? "APPLY" : "dry run"}`);

  const snap = await db.collection("products").get();
  const only = args.products.length ? new Set(args.products) : null;
  const work = snap.docs
    .filter((d) => !only || only.has(d.id))
    .map((d) => ({ id: d.id, before: d.data(), changes: supplierTextChanges(d.data()) }))
    .filter((w) => Object.keys(w.changes).length);

  const perField = {};
  for (const w of work) for (const f of Object.keys(w.changes)) perField[f] = (perField[f] || 0) + 1;
  console.log(`Products to change: ${work.length}`, perField);

  const samples = work.filter((w) => w.changes.description !== undefined).slice(0, args.samples);
  for (const w of samples) {
    console.log(`\n--- ${w.id} (${text(w.before.name).slice(0, 60)})`);
    console.log(`BEFORE: ${text(w.before.description)}`);
    console.log(`AFTER:  ${w.changes.description}`);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const tag = process.env.FIRESTORE_EMULATOR_HOST ? "emulator" : "live";
  const reportPath = path.join(OUT_DIR, `supplier-text-${tag}-${stamp}-${args.apply ? "apply" : "dryrun"}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(work.map((w) => ({
    id: w.id,
    changes: Object.fromEntries(Object.entries(w.changes).map(([f, v]) => [f, { from: w.before[f], to: v }])),
  })), null, 1));
  console.log(`\nReport: ${reportPath}`);
  if (!args.apply) return;

  const backupPath = path.join(OUT_DIR, `supplier-text-${tag}-${stamp}-BACKUP.json`);
  fs.writeFileSync(backupPath, JSON.stringify(work.map((w) => ({
    id: w.id,
    fields: Object.fromEntries(Object.keys(w.changes).map((f) => [f, w.before[f] ?? null])),
  })), null, 1));
  console.log(`Backup: ${backupPath}`);

  let done = 0;
  const failures = [];
  for (const w of work) {
    try {
      await db.runTransaction(async (tx) => {
        const ref = db.collection("products").doc(w.id);
        const fresh = await tx.get(ref);
        if (!fresh.exists) return;
        const changes = supplierTextChanges(fresh.data());
        if (!Object.keys(changes).length) return;
        tx.update(ref, {
          ...changes,
          [SYSTEM_WRITE_FIELD]: admin.firestore.FieldValue.serverTimestamp(),
          lastWriteSource: "supplier_text_cleanup",
        });
      });
      done++;
    } catch (error) {
      failures.push({ id: w.id, message: error.message });
    }
  }
  console.log(`Products written: ${done}/${work.length}`);
  const after = await db.collection("products").get();
  const left = after.docs.filter((d) => Object.keys(supplierTextChanges(d.data())).length);
  console.log(`Verify: products still needing cleanup: ${left.length}`);
  if (failures.length) { console.log("FAILURES:", failures); process.exitCode = 1; }
}

if (require.main === module) {
  main().catch((error) => { console.error(error); process.exit(1); });
}

module.exports = { stripSupplierText, stripSupplierHtml, supplierTextChanges };
