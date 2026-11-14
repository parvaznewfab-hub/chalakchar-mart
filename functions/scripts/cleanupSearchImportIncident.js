#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Cleanup for the 2026-11-14 incident: the chat question "Netac SSD 128GB
// price?" fell back to aliexpressSearchImport, which imported 5 unrelated
// medieval-costume products live and the create trigger marketed them.
//
// 1. REPORT (always): for each product, what was actually sent — Facebook
//    post id, Instagram media id, WhatsApp queued/eligible, push tokens,
//    in-app notifications — from marketing_outbox, marketing_logs and
//    notifications. Posts are NOT deleted here (done by hand).
// 2. UNPUBLISH (--apply only): isActive/isVisible/isPublished/showOnHome
//    false, needsReview true, autoMarketingDisabled true (the same four
//    publish flags the admin list toggle writes, so the product is hidden
//    everywhere, and can't be marketed again by accident).
//
// DRY RUN BY DEFAULT. A JSON report (with a backup of the old flags) is
// written to tools/backfill/ (git-ignored).
//
// Usage (from functions/, application-default credentials):
//   node scripts/cleanupSearchImportIncident.js [--apply] [--products=id,id]
// -----------------------------------------------------------------------------

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const INCIDENT_PRODUCT_IDS = [
  "imp_aliexpress_b5cc78b28153992191f553f5515075aa",
  "imp_aliexpress_050b41d6f80f0f1278ea9e85ff993086",
  "imp_aliexpress_a9acb95df73e8f3db88d95be84a54288",
  "imp_aliexpress_12d75d08afe3f3afe66db4d2771e29e6",
  "imp_aliexpress_0344343d050e3fa07ff7214cd540a965",
];
const FLAGS = ["isActive", "isVisible", "isPublished", "showOnHome", "needsReview", "autoMarketingDisabled"];
const TARGET = { isActive: false, isVisible: false, isPublished: false, showOnHome: false, needsReview: true, autoMarketingDisabled: true };
const OUT_DIR = path.join(__dirname, "..", "..", "tools", "backfill");

const iso = (v) => (v && typeof v.toDate === "function" ? v.toDate().toISOString() : v ?? null);

async function sentReport(db, productId) {
  const [outbox, logs, notifications] = await Promise.all([
    db.collection("marketing_outbox").where("productId", "==", productId).get(),
    db.collection("marketing_logs").where("productId", "==", productId).get(),
    db.collection("notifications").where("data.productId", "==", productId).get(),
  ]);

  const queueItems = outbox.docs.map((d) => {
    const x = d.data();
    const r = x.channelResults || {};
    return {
      queueId: d.id,
      reason: x.reason || null,
      status: x.status || null,
      audience: x.audience || null,
      createdAt: iso(x.createdAt),
      facebookPostId: r.facebook?.postId || r.facebook?.response?.post_id || null,
      facebookStatus: r.facebook?.status || null,
      instagramMediaId: r.instagram?.postId || r.instagram?.response?.id || null,
      instagramStatus: r.instagram?.status || null,
      whatsapp: r.whatsapp ? { status: r.whatsapp.status, queued: r.whatsapp.queuedCount ?? null, eligible: r.whatsapp.eligibleCount ?? null } : null,
      messenger: r.messenger?.status || null,
      tiktok: r.tiktok?.status || null,
    };
  });

  const newProductLogs = logs.docs.map((d) => d.data()).filter((l) => l.type === "new_product" && l.status === "completed");
  return {
    queueItems,
    pushTokens: newProductLogs.reduce((n, l) => n + Number(l.tokenCount || 0), 0),
    inAppUsers: newProductLogs.reduce((n, l) => n + Number(l.userCount || 0), 0),
    notificationDocs: notifications.size,
    notificationDocIds: notifications.docs.map((d) => d.id),
  };
}

async function main() {
  const apply = process.argv.includes("--apply");
  const productsArg = process.argv.find((a) => a.startsWith("--products="));
  const ids = productsArg ? productsArg.slice(11).split(",").map((s) => s.trim()).filter(Boolean) : INCIDENT_PRODUCT_IDS;

  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const report = [];
  for (const id of ids) {
    const snap = await db.collection("products").doc(id).get();
    if (!snap.exists) {
      report.push({ id, missing: true });
      continue;
    }
    const data = snap.data();
    const before = Object.fromEntries(FLAGS.map((f) => [f, data[f] ?? null]));
    const changes = Object.fromEntries(Object.entries(TARGET).filter(([f, v]) => data[f] !== v));
    report.push({
      id,
      name: String(data.name || "").slice(0, 90),
      importedBy: data.importedBy || null,
      category: data.category || null,
      before,
      changes,
      sent: await sentReport(db, id),
    });
  }

  for (const r of report) {
    if (r.missing) {
      console.log(`\n${r.id}: NOT FOUND`);
      continue;
    }
    console.log(`\n${r.id}  [${r.category}]  ${r.name}`);
    console.log(`  now: ${JSON.stringify(r.before)}`);
    console.log(`  would set: ${Object.keys(r.changes).length ? JSON.stringify(r.changes) : "(nothing — already cleaned)"}`);
    for (const q of r.sent.queueItems) {
      console.log(`  queue ${q.queueId} reason=${q.reason} status=${q.status} audience=${q.audience} at=${q.createdAt}`);
      console.log(`    Facebook post: ${q.facebookPostId || "-"} (${q.facebookStatus || "-"})`);
      console.log(`    Instagram media: ${q.instagramMediaId || "-"} (${q.instagramStatus || "-"})`);
      console.log(`    WhatsApp: ${q.whatsapp ? `${q.whatsapp.status}, queued ${q.whatsapp.queued}, eligible ${q.whatsapp.eligible}` : "-"}`);
      console.log(`    Messenger: ${q.messenger || "-"}   TikTok: ${q.tiktok || "-"}`);
    }
    console.log(`  push: ${r.sent.pushTokens} device token(s); in-app: ${r.sent.inAppUsers} user(s), ${r.sent.notificationDocs} notification doc(s)`);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const reportPath = path.join(OUT_DIR, `search-import-incident-${apply ? "apply" : "dryrun"}-${stamp}.json`);
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(`\nReport (incl. backup of old flags): ${reportPath}`);

  if (!apply) {
    console.log("DRY RUN — nothing written. Re-run with --apply to unpublish.");
    return;
  }

  let written = 0;
  for (const r of report) {
    if (r.missing || !Object.keys(r.changes).length) continue;
    await db.collection("products").doc(r.id).update({
      ...TARGET,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    written += 1;
  }
  console.log(`Applied: ${written} product(s) unpublished and flagged for review.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
