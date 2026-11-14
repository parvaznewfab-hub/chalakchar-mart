#!/usr/bin/env node
// -----------------------------------------------------------------------------
// One-time backfill of products/{id}.wishlistCount = number of
// users/*/wishlist/{id} docs. After it, the onWishlistItemCreated/Deleted
// triggers keep the count current. The product page shows this field instead
// of running collectionGroup('wishlist').count(), which the Firestore rules
// deny for every visitor (it was the guest 403s).
//
// Run it right AFTER deploying the two triggers, so no wishlist change falls
// between the count and the triggers.
//
// DRY RUN BY DEFAULT (prints what would change). --apply writes only the
// products whose stored count differs; products that no longer exist are
// skipped.
//
// Usage (from functions/, application-default credentials):
//   node scripts/backfillWishlistCount.js [--apply]
// -----------------------------------------------------------------------------

const admin = require("firebase-admin");

async function main() {
  const apply = process.argv.includes("--apply");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "chalakchar-mart" });
  const db = admin.firestore();

  const counts = new Map();
  const wishlists = await db.collectionGroup("wishlist").get();
  for (const doc of wishlists.docs) {
    // Only users/{uid}/wishlist/{productId}; the doc id is the product id.
    if (doc.ref.parent.parent?.parent?.id !== "users") continue;
    counts.set(doc.id, (counts.get(doc.id) || 0) + 1);
  }

  const products = await db.collection("products").get();
  const changes = [];
  for (const doc of products.docs) {
    const want = counts.get(doc.id) || 0;
    const have = Number(doc.get("wishlistCount") || 0);
    if (want !== have) changes.push({ id: doc.id, from: have, to: want, name: String(doc.get("name") || "").slice(0, 60) });
  }
  const orphans = [...counts.keys()].filter((id) => !products.docs.some((d) => d.id === id));

  console.log(`${wishlists.size} wishlist entries, ${counts.size} distinct products, ${orphans.length} for deleted products (skipped).`);
  console.log(`${changes.length} products need wishlistCount updated:`);
  for (const c of changes) console.log(`  ${c.id}  ${c.from} -> ${c.to}  ${c.name}`);

  if (!apply) {
    console.log("DRY RUN — nothing written. Re-run with --apply to write.");
    return;
  }
  for (let i = 0; i < changes.length; i += 400) {
    const batch = db.batch();
    for (const c of changes.slice(i, i + 400)) {
      batch.update(db.collection("products").doc(c.id), { wishlistCount: c.to });
    }
    await batch.commit();
  }
  console.log(`Applied: ${changes.length} products updated.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
