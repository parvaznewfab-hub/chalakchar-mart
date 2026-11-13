const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  computeVariantImagePatches,
  applyVariantImagePatchesToLatest,
} = require("../aliexpress/backfillVariantImages");

describe("computeVariantImagePatches", () => {
  test("matches by sourceSkuId and produces a patch with the fresh image", () => {
    const existing = [
      { sourceSkuId: "sku-1", name: "Red", price: 100, stock: 5 },
      { sourceSkuId: "sku-2", name: "Blue", price: 120, stock: 3 },
    ];
    const fresh = [
      { sourceSkuId: "sku-1", name: "Red", image: "https://a/red.jpg", imageUrl: "https://a/red.jpg" },
      { sourceSkuId: "sku-2", name: "Blue", image: "https://a/blue.jpg", imageUrl: "https://a/blue.jpg" },
    ];
    const { patches, skipped } = computeVariantImagePatches(existing, fresh);
    assert.equal(patches.length, 2);
    assert.equal(skipped.length, 0);
    assert.equal(patches[0].matchField, "sourceSkuId");
    assert.equal(patches[0].image, "https://a/red.jpg");
    assert.equal(patches[1].image, "https://a/blue.jpg");
  });

  test("unmatched variants are skipped and reported, not guessed", () => {
    const existing = [{ sourceSkuId: "sku-missing", name: "Green" }];
    const fresh = [{ sourceSkuId: "sku-other", name: "Green", image: "https://a/green.jpg" }];
    const { patches, skipped } = computeVariantImagePatches(existing, fresh);
    assert.equal(patches.length, 0);
    assert.equal(skipped.length, 1);
    assert.equal(skipped[0].reason, "no_confident_match");
  });

  test("duplicate cleaned names in fresh data are treated as ambiguous and skipped", () => {
    const existing = [{ name: "Red" }]; // no id-like fields at all
    const fresh = [
      { name: "red", image: "https://a/1.jpg" },
      { name: "RED", image: "https://a/2.jpg" },
    ];
    const { patches, skipped } = computeVariantImagePatches(existing, fresh);
    assert.equal(patches.length, 0);
    assert.equal(skipped.length, 1);
    assert.equal(skipped[0].reason, "ambiguous_match_by_name");
  });

  test("a confidently matched variant with no fresh image is skipped, not left half-patched", () => {
    const existing = [{ sourceSkuId: "sku-1", name: "Red" }];
    const fresh = [{ sourceSkuId: "sku-1", name: "Red" }]; // no image/imageUrl
    const { patches, skipped } = computeVariantImagePatches(existing, fresh);
    assert.equal(patches.length, 0);
    assert.equal(skipped[0].reason, "fresh_variant_has_no_image");
  });
});

describe("applyVariantImagePatchesToLatest (concurrency-safe re-merge)", () => {
  test("preserves order and applies only image/imageUrl on matched entries", () => {
    const latest = [
      { sourceSkuId: "sku-1", name: "Red", price: 100, stock: 5 },
      { sourceSkuId: "sku-2", name: "Blue", price: 120, stock: 3 },
    ];
    const patches = [
      { matchField: "sourceSkuId", matchValue: "sku-2", name: "Blue", image: "https://a/blue.jpg", imageUrl: "https://a/blue.jpg" },
    ];
    const { updatedVariants, appliedCount, reappliedSkipped } = applyVariantImagePatchesToLatest(latest, patches);
    assert.equal(appliedCount, 1);
    assert.equal(reappliedSkipped.length, 0);
    // Order preserved exactly.
    assert.equal(updatedVariants[0].sourceSkuId, "sku-1");
    assert.equal(updatedVariants[1].sourceSkuId, "sku-2");
    // Only the matched entry's image/imageUrl changed.
    assert.equal(updatedVariants[0].image, undefined);
    assert.equal(updatedVariants[1].image, "https://a/blue.jpg");
    // Every other field on every variant is untouched.
    assert.equal(updatedVariants[0].price, 100);
    assert.equal(updatedVariants[1].price, 120);
    assert.equal(updatedVariants[1].stock, 3);
  });

  test('latest-document re-merge preserves a simulated concurrent price/stock edit', () => {
    // The patch was computed against an OLDER read (price 120, stock 3).
    const patches = [
      { matchField: "sourceSkuId", matchValue: "sku-2", name: "Blue", image: "https://a/blue.jpg", imageUrl: "https://a/blue.jpg" },
    ];
    // But an admin concurrently changed price/stock before the real write happens.
    const latestReReadFromFirestore = [
      { sourceSkuId: "sku-1", name: "Red", price: 100, stock: 5 },
      { sourceSkuId: "sku-2", name: "Blue", price: 999, stock: 42 }, // concurrent admin edit
    ];
    const { updatedVariants } = applyVariantImagePatchesToLatest(latestReReadFromFirestore, patches);
    const blue = updatedVariants.find((v) => v.sourceSkuId === "sku-2");
    // The concurrent price/stock edit survives untouched...
    assert.equal(blue.price, 999);
    assert.equal(blue.stock, 42);
    // ...while the image patch is still applied.
    assert.equal(blue.image, "https://a/blue.jpg");
  });

  test("if the matched variant no longer exists in the latest data, skip and report — never overwrite blindly", () => {
    const patches = [
      { matchField: "sourceSkuId", matchValue: "sku-deleted", name: "Green", image: "https://a/green.jpg", imageUrl: "https://a/green.jpg" },
    ];
    const latest = [{ sourceSkuId: "sku-1", name: "Red", price: 100 }]; // sku-deleted no longer present
    const { updatedVariants, appliedCount, reappliedSkipped } = applyVariantImagePatchesToLatest(latest, patches);
    assert.equal(appliedCount, 0);
    assert.equal(reappliedSkipped.length, 1);
    assert.equal(reappliedSkipped[0].reason, "not_found_in_latest");
    // Latest data is returned completely unmodified.
    assert.deepEqual(updatedVariants, latest);
  });

  test("does not mutate the input array's objects (pure function)", () => {
    const latest = [{ sourceSkuId: "sku-1", name: "Red", price: 100 }];
    const patches = [{ matchField: "sourceSkuId", matchValue: "sku-1", name: "Red", image: "https://a/red.jpg", imageUrl: "https://a/red.jpg" }];
    applyVariantImagePatchesToLatest(latest, patches);
    assert.equal(latest[0].image, undefined);
  });
});

describe("computeVariantImagePatches with real stored/fetched shapes", () => {
  test("saved sourceSkuId matches fresh skuId (regression: previously matched nothing)", () => {
    // Saved shape as stored in Firestore today; fresh shape from normalizeAliExpressProduct.
    const saved = [{ id: "v1", variantId: "v1", name: "Black", sourceSkuId: "12000045", image: "" }];
    const fresh = [{ id: "12000045", skuId: "12000045", name: "Black", image: "https://a/black.jpg", imageUrl: "https://a/black.jpg" }];
    const { patches, skipped } = computeVariantImagePatches(saved, fresh);
    assert.equal(skipped.length, 0);
    assert.equal(patches.length, 1);
    assert.equal(patches[0].matchField, "sourceSkuId");
    assert.equal(patches[0].matchValue, "12000045");
    assert.equal(patches[0].image, "https://a/black.jpg");
  });
});
