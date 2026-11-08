// Emulator-gated: only runs when FIRESTORE_EMULATOR_HOST is set (see
// functions/scripts/check-aliexpress-connection.sh style — no real Firestore
// emulator config exists in this repo yet, so this suite self-skips rather
// than failing `npm test` in environments without one running).
//
// Start an emulator first, e.g.:
//   firebase emulators:start --only firestore
// then, in another shell:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test
const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const skip = !emulatorHost ? "FIRESTORE_EMULATOR_HOST not set — start the Firestore emulator to run this suite" : false;

describe("backfillAliExpressCategoryReview (Firestore emulator)", { skip }, () => {
  let admin;
  let db;
  let backfill;

  test.before(() => {
    process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "chalakchar-mart-test";
    admin = require("firebase-admin");
    if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
    db = admin.firestore();
    backfill = require("../scripts/backfillAliExpressCategoryReview");
  });

  async function seedProduct(id, data) {
    await db.collection("products").doc(id).set(data);
  }

  async function clearProducts() {
    const snapshot = await db.collection("products").get();
    await Promise.all(snapshot.docs.map((doc) => doc.ref.delete()));
  }

  test("finds only aliexpress-sourced products literally stuck in 'AliExpress' category, and performs no writes in dry run", async () => {
    await clearProducts();

    await seedProduct("legacy_1", {
      source: "aliexpress",
      sourceProductId: "1001",
      name: "USB-C Phone Repair Flex Cable",
      category: "AliExpress",
      categoryId: "cat_aliexpress_auto_created",
    });
    await seedProduct("legacy_2", {
      source: "aliexpress",
      sourceProductId: "1002",
      name: "Mobile Motherboard Test Fixture",
      category: "AliExpress",
      categoryId: "cat_aliexpress_auto_created",
    });
    // Correctly categorized aliexpress product — must NOT be picked up.
    await seedProduct("ok_aliexpress", {
      source: "aliexpress",
      sourceProductId: "2001",
      name: "Bluetooth Earbuds",
      category: "Electronics",
      categoryId: "cat_electronics",
    });
    // Non-aliexpress product that happens to be named "AliExpress" — must
    // NOT be picked up (source filter matters).
    await seedProduct("vendor_named_aliexpress", {
      source: "vendor",
      sourceProductId: "",
      name: "Some vendor product",
      category: "AliExpress",
    });

    const result = await backfill.run({ db, apply: false, limit: 500 });

    assert.equal(result.dryRun, true);
    assert.equal(result.scanned, 2);
    const ids = result.report.map((row) => row.productId).sort();
    assert.deepEqual(ids, ["legacy_1", "legacy_2"]);
    for (const row of result.report) {
      assert.equal(row.currentCategory, "AliExpress");
      assert.equal(row.nextCategory, "Uncategorized");
      assert.equal(row.nextNeedsCategoryReview, true);
    }

    // Dry run must never write.
    const untouched = await db.collection("products").doc("legacy_1").get();
    assert.equal(untouched.data().category, "AliExpress");
    assert.equal(untouched.data().needsCategoryReview, undefined);

    await clearProducts();
  });

  test("--apply flips matched products to Uncategorized/needsCategoryReview and clears the stale categoryId", async () => {
    await clearProducts();

    await seedProduct("legacy_apply", {
      source: "aliexpress",
      sourceProductId: "1003",
      name: "Phone Repair Screwdriver Kit",
      category: "AliExpress",
      categoryId: "cat_aliexpress_auto_created",
      subcategoryId: "sub_aliexpress_auto_created",
    });

    const result = await backfill.run({ db, apply: true, limit: 500 });
    assert.equal(result.dryRun, false);
    assert.equal(result.scanned, 1);

    const updated = await db.collection("products").doc("legacy_apply").get();
    const data = updated.data();
    assert.equal(data.category, "Uncategorized");
    assert.equal(data.needsCategoryReview, true);
    assert.equal(data.categoryId, undefined);
    assert.equal(data.subcategoryId, undefined);

    await clearProducts();
  });
});
