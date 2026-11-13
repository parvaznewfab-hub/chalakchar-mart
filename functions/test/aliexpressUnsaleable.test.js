const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  isAliExpressUnsaleableError,
  buildUnsaleableUpdate,
  restoreVariantStock,
  buildSaleableAgainUpdate,
  buildUnsaleableChangeNote,
} = require("../aliexpress/unsaleable");

const NOW = "SERVER_TS";

// Shape copied from the live error captured 2026-11-13 for 1005005100218548.
function liveUnsaleableError() {
  const error = new Error("All SKU Unsaleable");
  error.code = "ALIEXPRESS_SYNC_API_FAILED";
  error.api = { rsp_code: 604, rsp_msg: "All SKU Unsaleable", request_id: "x" };
  return error;
}

// Saved variant shape as stored in Firestore today (all 110 AliExpress products).
function savedVariant(sku, name, stock, extra = {}) {
  return { id: `v_${sku}`, variantId: `v_${sku}`, name, unit: name, variantName: name, price: 1000, piecePrice: 1000, mrp: 1200, oldPrice: 1200, stock, sourceSkuId: sku, image: `img_${sku}`, imageUrl: `img_${sku}`, ...extra };
}

// Fresh variant shape from normalizeAliExpressProduct (skuId, no sourceSkuId).
function freshVariant(sku, name, stock) {
  return { id: sku, skuId: sku, name, price: 9.5, mrp: 12, stock, image: "f", imageUrl: "f" };
}

describe("isAliExpressUnsaleableError", () => {
  test("matches the live AliExpress answer", () => {
    assert.equal(isAliExpressUnsaleableError(liveUnsaleableError()), true);
  });

  test("matches by message when no rsp_code is attached", () => {
    assert.equal(isAliExpressUnsaleableError(new Error("All SKU Unsaleable")), true);
  });

  test("rejects other errors, including the phrase with a different rsp_code", () => {
    assert.equal(isAliExpressUnsaleableError(null), false);
    const notConnected = new Error("AliExpress is not connected");
    notConnected.code = "ALIEXPRESS_NOT_CONNECTED";
    assert.equal(isAliExpressUnsaleableError(notConnected), false);
    const other = new Error("All SKU Unsaleable");
    other.api = { rsp_code: 500, rsp_msg: "All SKU Unsaleable" };
    assert.equal(isAliExpressUnsaleableError(other), false);
  });
});

describe("buildUnsaleableUpdate", () => {
  const product = {
    isActive: true,
    price: 1500,
    stock: 30,
    needsReview: false,
    variants: [savedVariant("111", "Black", 10), savedVariant("222", "White", 20)],
  };

  test("zeroes product and every variant's stock, flags for review, keeps other fields", () => {
    const { update, newlyUnsaleable } = buildUnsaleableUpdate(product, NOW);
    assert.equal(newlyUnsaleable, true);
    assert.equal(update.stock, 0);
    assert.equal(update.inStock, false);
    assert.equal(update.needsReview, true);
    assert.equal(update.aliexpressUnsaleable, true);
    assert.equal(update.aliexpressUnsaleableSince, NOW);
    assert.deepEqual(update.variants.map((v) => v.stock), [0, 0]);
    // Every other variant field preserved (hand-edited names/prices/images).
    assert.deepEqual({ ...update.variants[0], stock: 10 }, product.variants[0]);
  });

  test("never touches isActive or price", () => {
    const { update } = buildUnsaleableUpdate(product, NOW);
    assert.equal("isActive" in update, false);
    assert.equal("price" in update, false);
    assert.equal("oldPrice" in update, false);
  });

  test("already flagged: not 'newly', and first-detection time is kept", () => {
    const { update, newlyUnsaleable } = buildUnsaleableUpdate({ ...product, aliexpressUnsaleable: true, aliexpressUnsaleableSince: "EARLIER" }, NOW);
    assert.equal(newlyUnsaleable, false);
    assert.equal("aliexpressUnsaleableSince" in update, false);
  });

  test("products without variants still get product-level stock 0", () => {
    const { update } = buildUnsaleableUpdate({ stock: 5 }, NOW);
    assert.equal(update.stock, 0);
    assert.equal("variants" in update, false);
  });
});

describe("restoreVariantStock", () => {
  test("matches saved sourceSkuId to fresh skuId and only changes stock", () => {
    const saved = [savedVariant("111", "Black", 0, { price: 777 }), savedVariant("222", "White", 0)];
    const fresh = [freshVariant("222", "White", 7), freshVariant("111", "Black", 3)];
    const { variants, matched, unmatched } = restoreVariantStock(saved, fresh);
    assert.equal(matched, 2);
    assert.equal(unmatched, 0);
    assert.deepEqual(variants.map((v) => v.stock), [3, 7]);
    assert.equal(variants[0].price, 777, "hand-edited price is preserved");
    assert.equal(variants[0].image, "img_111", "saved image is preserved");
  });

  test("a variant gone from AliExpress (no SKU, no exact name) stays at 0 — never matched by index or fuzzy name", () => {
    const saved = [savedVariant("111", "Black", 0), savedVariant("999", "Red", 0)];
    const fresh = [freshVariant("111", "Black", 4), freshVariant("555", "Dark Red", 9)];
    const { variants, matched, unmatched } = restoreVariantStock(saved, fresh);
    assert.deepEqual(variants.map((v) => v.stock), [4, 0]);
    assert.equal(matched, 1);
    assert.equal(unmatched, 1);
  });

  test("SKU replaced but the exact same name exists once -> that variant's stock is used", () => {
    const saved = [savedVariant("999", "Red", 0)];
    const { variants, matched } = restoreVariantStock(saved, [freshVariant("555", "Red", 9)]);
    assert.equal(variants[0].stock, 9);
    assert.equal(matched, 1);
  });

  test("saved SKU belongs to a differently-named variant -> not used (live n8n data issue)", () => {
    const saved = [savedVariant("A", "16 128g No Face", 0)];
    const { variants, matched } = restoreVariantStock(saved, [freshVariant("A", "16 Pro 128g No Face", 50)]);
    assert.equal(variants[0].stock, 0);
    assert.equal(matched, 0);
  });

  test("bad stock values become 0", () => {
    const { variants } = restoreVariantStock([savedVariant("1", "A", 0)], [freshVariant("1", "A", "n/a")]);
    assert.equal(variants[0].stock, 0);
  });
});

describe("buildSaleableAgainUpdate", () => {
  const flagged = {
    isActive: false,
    needsReview: true,
    aliexpressUnsaleable: true,
    stock: 0,
    variants: [savedVariant("111", "Black", 0), savedVariant("222", "White", 0)],
  };

  test("returns null for a product that was never flagged (normal sync unchanged)", () => {
    assert.equal(buildSaleableAgainUpdate({ ...flagged, aliexpressUnsaleable: false }, [], NOW), null);
    assert.equal(buildSaleableAgainUpdate({ stock: 3 }, [], NOW), null);
  });

  test("restores variant stock, sums product stock, keeps needsReview, never touches isActive", () => {
    const result = buildSaleableAgainUpdate(flagged, [freshVariant("111", "Black", 5), freshVariant("222", "White", 2)], NOW);
    assert.equal(result.update.aliexpressUnsaleable, false);
    assert.equal(result.update.aliexpressSaleableAgainAt, NOW);
    assert.equal(result.update.needsReview, true);
    assert.equal("isActive" in result.update, false);
    assert.deepEqual(result.update.variants.map((v) => v.stock), [5, 2]);
    assert.equal(result.update.stock, 7);
    assert.equal(result.update.inStock, true);
  });

  test("saleable again but no SKU matches: stock stays 0, still flagged for review", () => {
    const result = buildSaleableAgainUpdate(flagged, [freshVariant("999", "Other", 50)], NOW);
    assert.equal(result.update.stock, 0);
    assert.equal(result.update.inStock, false);
    assert.equal(result.unmatched, 2);
    assert.equal(result.update.needsReview, true);
  });
});

describe("buildUnsaleableChangeNote", () => {
  const p = (i) => ({ productId: `imp_${i}`, sourceProductId: `100500${i}`, name: `Product ${i}` });

  test("no changes, no note", () => {
    assert.equal(buildUnsaleableChangeNote([], []), null);
  });

  test("lists both directions with counts", () => {
    const note = buildUnsaleableChangeNote([p(1), p(2)], [p(3)]);
    assert.equal(note.kind, "unsaleable_changes");
    assert.match(note.body, /2 products became unsaleable/);
    assert.match(note.body, /Product 1 \(1005001\)/);
    assert.match(note.body, /1 product is saleable again/);
    assert.equal(note.data.newlyUnsaleableCount, 2);
    assert.equal(note.data.saleableAgainIds, "imp_3");
  });

  test("long lists are truncated in the text and capped in the data payload", () => {
    const many = Array.from({ length: 60 }, (_, i) => p(i));
    const note = buildUnsaleableChangeNote(many, []);
    assert.match(note.body, /\+50 more/);
    assert.equal(note.data.newlyUnsaleableCount, 60);
    assert.equal(note.data.newlyUnsaleableIds.split(",").length, 40);
  });
});
