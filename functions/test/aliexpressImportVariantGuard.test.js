const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { verifyIncomingVariants, isAliExpressIdOnlyImport } = require("../aliexpress/importVariantGuard");

// Fresh AliExpress variants as normalizeAliExpressProduct returns them (USD).
const fresh = [
  { id: "A", skuId: "A", name: "16 Pro 128g No Face", price: 276.76, mrp: 407, stock: 2 },
  { id: "B", skuId: "B", name: "16 128g No Face", price: 258.4, mrp: 380, stock: 1 },
  { id: "C", skuId: "C", name: "16 Pro 256g No Face", price: 297.16, mrp: 437, stock: 6 },
];

describe("verifyIncomingVariants", () => {
  test("variants whose SKU and name agree pass through unchanged", () => {
    const incoming = [{ skuId: "B", name: "16 128g No Face", price: 250, stock: 3, image: "x" }];
    const result = verifyIncomingVariants(incoming, fresh);
    assert.deepEqual(result.variants, incoming);
    assert.equal(result.verified, 1);
    assert.deepEqual(result.repaired, []);
    assert.deepEqual(result.rejected, []);
  });

  test("live n8n bug: name paired with another variant's SKU -> repaired from the same-name AliExpress SKU", () => {
    // n8n zipped names and SKU ids by position: "16 128g No Face" got SKU "A".
    const incoming = [{ skuId: "A", name: "16 128g No Face", price: 276.76, mrp: 407, stock: 2, image: "keep.jpg" }];
    const result = verifyIncomingVariants(incoming, fresh);
    assert.equal(result.repaired.length, 1);
    assert.deepEqual(result.repaired[0], { index: 0, name: "16 128g No Face", fromSkuId: "A", toSkuId: "B", skuBelongsTo: "16 Pro 128g No Face" });
    const v = result.variants[0];
    assert.equal(v.skuId, "B");
    // Price/mrp/stock come from the repaired SKU too — the n8n values were
    // paired with the wrong SKU, so they can't be trusted either.
    assert.equal(v.price, 258.4);
    assert.equal(v.mrp, 380);
    assert.equal(v.stock, 1);
    assert.equal(v.image, "keep.jpg", "other incoming fields are kept");
    assert.equal(v.name, "16 128g No Face");
  });

  test("repair also clears alternative price/stock fields the importer would otherwise prefer", () => {
    const incoming = [{ skuId: "A", name: "16 128g No Face", salePrice: 999, oldPrice: 999, quantity: 50 }];
    const v = verifyIncomingVariants(incoming, fresh).variants[0];
    assert.equal(v.price, 258.4);
    assert.equal("salePrice" in v, false);
    assert.equal("oldPrice" in v, false);
    assert.equal("quantity" in v, false);
  });

  test("mismatch with no unique same-name SKU -> rejected (never saved with a guessed SKU)", () => {
    const incoming = [{ skuId: "A", name: "Something else entirely", price: 10 }];
    const result = verifyIncomingVariants(incoming, fresh);
    assert.deepEqual(result.rejected, [{ index: 0, name: "Something else entirely", skuId: "A", reason: "sku_name_mismatch" }]);
  });

  test("SKU not on AliExpress but exact name exists once -> repaired; neither -> rejected", () => {
    const ok = verifyIncomingVariants([{ skuId: "Z", name: "16 pro 256G  no face" }], fresh);
    assert.equal(ok.repaired[0].toSkuId, "C");
    const bad = verifyIncomingVariants([{ skuId: "Z", name: "Unknown" }], fresh);
    assert.equal(bad.rejected[0].reason, "not_on_aliexpress");
  });

  test("variants without a SKU id can't be verified: kept as-is and listed", () => {
    const incoming = [{ name: "Default", price: 5 }];
    const result = verifyIncomingVariants(incoming, fresh);
    assert.deepEqual(result.variants, incoming);
    assert.deepEqual(result.unverified, [{ index: 0, name: "Default" }]);
    assert.equal(result.rejected.length, 0);
  });

  test("accepts the other SKU id field names n8n may send", () => {
    const result = verifyIncomingVariants([{ sku_id: "A", skuName: "16 128g No Face" }], fresh);
    assert.equal(result.repaired[0].toSkuId, "B");
    assert.equal(result.variants[0].skuId, "B");
  });

  test("non-array input is treated as no variants", () => {
    const result = verifyIncomingVariants(undefined, fresh);
    assert.deepEqual(result.variants, []);
  });
});

describe("isAliExpressIdOnlyImport", () => {
  test("ID/URL with no product data is an ID-only import", () => {
    assert.equal(isAliExpressIdOnlyImport({ productId: "1005008591232954" }), true);
    assert.equal(isAliExpressIdOnlyImport({ productUrl: "https://www.aliexpress.com/item/1005008591232954.html" }), true);
    assert.equal(isAliExpressIdOnlyImport({ product: { productId: "1005008591232954" } }), true);
  });

  test("a body carrying a product name is the existing full-data import", () => {
    assert.equal(isAliExpressIdOnlyImport({ product: { name: "X", sourceProductId: "1" } }), false);
    assert.equal(isAliExpressIdOnlyImport({ title: "X", sourceProductId: "1" }), false);
  });

  test("other marketplaces are never treated as AliExpress ID-only", () => {
    assert.equal(isAliExpressIdOnlyImport({ source: "daraz", productId: "123" }), false);
  });
});
