const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { buildVariantRefreshUpdate } = require("../aliexpress/variantRefresh");
const { buildUnsaleableUpdate, buildSaleableAgainUpdate } = require("../aliexpress/unsaleable");
const { computeVariantImagePatches, applyVariantImagePatchesToLatest } = require("../aliexpress/backfillVariantImages");

// What the 6-hourly sync (aliexpressScheduledSync -> syncAliExpressProduct)
// rewrites. It writes with ref.update(updates): fields not in `updates`
// (e.g. product-level variantAttributeName) are untouched by Firestore, and
// every variants[] rewrite must keep the per-variant label fields.
const LABELS = { sourceAttributeName: "Color", attributeName: "Model" };

function product(extra = {}) {
  return {
    variantAttributeName: "Phone model",
    variants: [
      { name: "Nova 3i / China Mainland", sourceSkuId: "111", price: 500, mrp: 600, stock: 3, ...LABELS },
      { name: "Nova 3 / China Mainland", sourceSkuId: "222", price: 520, mrp: 600, stock: 1, ...LABELS },
      { name: "Nova 2", sourceSkuId: "999", price: 480, mrp: 600, stock: 2, ...LABELS }, // gone from AliExpress
    ],
    ...extra,
  };
}

const fresh = [
  { skuId: "111", name: "Nova 3i / China Mainland", price: 3.6, mrp: 5, stock: 8, image: "https://x/3i.jpg" },
  { skuId: "222", name: "Nova 3 / China Mainland", price: 3.9, mrp: 5, stock: 0, image: "https://x/3.jpg" },
];

function assertLabelsKept(variants) {
  assert.equal(variants.length, 3);
  for (const v of variants) {
    assert.equal(v.sourceAttributeName, "Color", `${v.name}: sourceAttributeName kept`);
    assert.equal(v.attributeName, "Model", `${v.name}: attributeName kept`);
  }
}

function assertNoProductLabelWrite(update) {
  assert.equal("variantAttributeName" in update, false, "sync never writes the manual product label");
}

describe("6-hourly sync keeps variant label fields", () => {
  test("price/stock refresh (matched, missing and unchanged variants)", () => {
    const result = buildVariantRefreshUpdate(product(), fresh, () => ({ price: 700, mrp: 800 }));
    assertLabelsKept(result.update.variants);
    assert.equal(result.update.variants[0].stock, 8, "the refresh itself still happened");
    assert.equal(result.update.variants[2].stock, 0, "missing variant zeroed");
    assertNoProductLabelWrite(result.update);
  });

  test("AliExpress reports the product unsaleable", () => {
    const { update } = buildUnsaleableUpdate(product(), "now");
    assertLabelsKept(update.variants);
    assertNoProductLabelWrite(update);
  });

  test("product becomes saleable again", () => {
    const result = buildSaleableAgainUpdate(product({ aliexpressUnsaleable: true }), fresh, "now");
    assertLabelsKept(result.update.variants);
    assertNoProductLabelWrite(result.update);
  });

  test("variant image backfill patch", () => {
    const { patches } = computeVariantImagePatches(product().variants, fresh);
    assert.ok(patches.length > 0, "fixture produces image patches");
    const { updatedVariants } = applyVariantImagePatchesToLatest(product().variants, patches);
    assertLabelsKept(updatedVariants);
  });
});
