const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  SYNC_MARKETING_SUPPRESSED_FIELD,
  isVariantSyncEnabled,
  refreshSavedVariants,
  deriveProductFromVariants,
  buildVariantRefreshUpdate,
  isSyncDiscountMarketingSuppressed,
} = require("../aliexpress/variantRefresh");

// Saved shape as stored in Firestore for all 110 AliExpress products.
function saved(sku, name, price, stock, extra = {}) {
  return { id: `v_${sku}`, variantId: `v_${sku}`, name, unit: name, variantName: name, price, piecePrice: price, mrp: price + 100, oldPrice: price + 100, stock, sourceSkuId: sku, image: `img_${sku}`, imageUrl: `img_${sku}`, ...extra };
}

// Fresh shape from normalizeAliExpressProduct (USD, skuId only).
function fresh(sku, name, price, stock, mrp = price * 1.2) {
  return { id: sku, skuId: sku, name, price, mrp, stock, image: "fresh_img", imageUrl: "fresh_img" };
}

// Stand-in for the import price rule: 100 BDT per USD, + 50 shipping.
const priceFor = (v) => ({ price: Math.round(v.price * 100 + 50), mrp: Math.round((v.mrp ?? v.price) * 100 + 50) });

describe("isVariantSyncEnabled", () => {
  test("defaults to true; only an explicit false opts out", () => {
    assert.equal(isVariantSyncEnabled({}), true);
    assert.equal(isVariantSyncEnabled({ variantSyncEnabled: true }), true);
    assert.equal(isVariantSyncEnabled({ variantSyncEnabled: "false" }), true);
    assert.equal(isVariantSyncEnabled({ variantSyncEnabled: false }), false);
  });
});

describe("refreshSavedVariants", () => {
  test("matches by SKU (any order) and refreshes price/piecePrice/mrp/oldPrice/stock only", () => {
    const savedVariants = [saved("111", "Black", 900, 5), saved("222", "White", 900, 5)];
    const { variants, changes, matched, unmatched } = refreshSavedVariants(
      savedVariants,
      [fresh("222", "White", 12, 40), fresh("111", "Black", 10, 30, 15)],
      priceFor
    );
    assert.equal(matched, 2);
    assert.equal(unmatched, 0);
    assert.deepEqual(variants[0], { ...savedVariants[0], price: 1050, piecePrice: 1050, mrp: 1550, oldPrice: 1550, stock: 30 });
    assert.equal(variants[1].price, 1250);
    assert.equal(variants[1].stock, 40);
    // Name, image, ids, order untouched.
    assert.equal(variants[0].name, "Black");
    assert.equal(variants[0].image, "img_111");
    assert.equal(changes.length, 2);
    assert.deepEqual(
      { oldPrice: changes[0].oldPrice, newPrice: changes[0].newPrice, oldStock: changes[0].oldStock, newStock: changes[0].newStock, matched: changes[0].matched },
      { oldPrice: 900, newPrice: 1050, oldStock: 5, newStock: 30, matched: true }
    );
  });

  test("mrp is never below price", () => {
    const { variants } = refreshSavedVariants([saved("1", "A", 100, 1)], [fresh("1", "A", 10, 1, 5)], priceFor);
    assert.equal(variants[0].mrp, variants[0].price);
    assert.equal(variants[0].oldPrice, variants[0].price);
  });

  test("an unchanged variant produces no change entry", () => {
    const { changes } = refreshSavedVariants([saved("1", "A", 1050, 30, { mrp: 1250, oldPrice: 1250 })], [fresh("1", "A", 10, 30, 12)], priceFor);
    assert.equal(changes.length, 0);
  });

  test("a SKU no longer on AliExpress: stock 0, price kept, reported missing", () => {
    const { variants, changes, missing, unmatched } = refreshSavedVariants([saved("999", "Gone", 900, 7)], [fresh("111", "Other", 10, 30)], priceFor);
    assert.equal(unmatched, 1);
    assert.equal(variants[0].stock, 0);
    assert.equal(variants[0].price, 900);
    assert.deepEqual(missing, [{ index: 0, name: "Gone", sourceSkuId: "999", reason: "not_on_aliexpress" }]);
    assert.equal(changes[0].matched, false);
  });

  test("a zero/invalid fresh price never overwrites a real price (stock still refreshed)", () => {
    const zeroPrice = () => ({ price: 0, mrp: 0 });
    const { variants } = refreshSavedVariants([saved("1", "A", 900, 2)], [fresh("1", "A", 0, 9)], zeroPrice);
    assert.equal(variants[0].price, 900);
    assert.equal(variants[0].stock, 9);
  });
});

describe("deriveProductFromVariants", () => {
  test("stock = sum of saved variants, price/oldPrice = first saved variant (not cheapest)", () => {
    const fields = deriveProductFromVariants([
      { price: 7033, mrp: 8000, stock: 10 },
      { price: 5214, mrp: 6000, stock: 20 },
    ]);
    assert.deepEqual(fields, { stock: 30, inStock: true, price: 7033, oldPrice: 8000 });
  });

  test("zero stock -> inStock false; no variants -> null", () => {
    assert.equal(deriveProductFromVariants([{ price: 10, stock: 0 }]).inStock, false);
    assert.equal(deriveProductFromVariants([]), null);
  });
});

describe("buildVariantRefreshUpdate", () => {
  // Mirrors the live case: AliExpress's first SKU is not one of the 2 saved
  // variants, and AliExpress has more SKUs than the store sells.
  const product = {
    price: 29691,
    oldPrice: 30000,
    stock: 249,
    variants: [saved("111", "Black", 7033, 10), saved("222", "White", 5214, 20)],
  };
  const freshVariants = [fresh("999", "Expensive one we don't sell", 218.56, 121), fresh("111", "Black", 70, 12), fresh("222", "White", 52, 25)];

  test("product price comes from the first SAVED variant and stock from saved variants only", () => {
    const result = buildVariantRefreshUpdate(product, freshVariants, priceFor);
    assert.equal(result.update.price, 7050);
    assert.equal(result.update.stock, 37);
    assert.equal(result.update.inStock, true);
    assert.equal(result.update.originalPrice, 70);
    assert.deepEqual(result.omit, []);
    assert.equal(result.update.variants.length, 2);
  });

  test("first saved variant gone from AliExpress: keep old originalPrice/originalMrp", () => {
    const result = buildVariantRefreshUpdate(product, [fresh("222", "White", 52, 25)], priceFor);
    assert.deepEqual(result.omit, ["originalPrice", "originalMrp"]);
    assert.equal("originalPrice" in result.update, false);
    assert.equal(result.update.variants[0].stock, 0);
    assert.equal(result.update.stock, 25);
  });

  test("opted-out or variant-less products are left to the old behaviour (null)", () => {
    assert.equal(buildVariantRefreshUpdate({ ...product, variantSyncEnabled: false }, freshVariants, priceFor), null);
    assert.equal(buildVariantRefreshUpdate({ price: 10 }, freshVariants, priceFor), null);
  });

  test("never sets isActive or needsReview", () => {
    const { update } = buildVariantRefreshUpdate(product, freshVariants, priceFor);
    assert.equal("isActive" in update, false);
    assert.equal("needsReview" in update, false);
  });
});

describe("isSyncDiscountMarketingSuppressed", () => {
  const ts = (ms) => ({ toMillis: () => ms });

  test("suppressed only on the write that set a new stamp", () => {
    assert.equal(isSyncDiscountMarketingSuppressed({}, { [SYNC_MARKETING_SUPPRESSED_FIELD]: ts(1000) }), true);
    assert.equal(isSyncDiscountMarketingSuppressed({ [SYNC_MARKETING_SUPPRESSED_FIELD]: ts(1000) }, { [SYNC_MARKETING_SUPPRESSED_FIELD]: ts(2000) }), true);
  });

  test("a later admin edit (stamp unchanged) is not suppressed; no stamp is not suppressed", () => {
    assert.equal(isSyncDiscountMarketingSuppressed({ [SYNC_MARKETING_SUPPRESSED_FIELD]: ts(1000) }, { [SYNC_MARKETING_SUPPRESSED_FIELD]: ts(1000) }), false);
    assert.equal(isSyncDiscountMarketingSuppressed({}, {}), false);
  });
});

describe("refreshSavedVariants with mis-assigned SKUs (live n8n data)", () => {
  test("uses the same-name variant's price, never the SKU's other variant", () => {
    const savedVariants = [saved("A", "16 128g No Face", 36053, 0)];
    const freshVariants = [fresh("A", "16 Pro 128g No Face", 276.76, 2), fresh("B", "16 128g No Face", 200, 5)];
    const { variants, matchedBy, unresolved } = refreshSavedVariants(savedVariants, freshVariants, priceFor);
    assert.equal(variants[0].price, 20050); // from "B", the variant with the saved name
    assert.equal(variants[0].stock, 5);
    assert.equal(variants[0].sourceSkuId, "A", "identity fields are never rewritten");
    assert.deepEqual(matchedBy, { name_sku_mismatch: 1 });
    assert.equal(unresolved.length, 0);
  });

  test("unresolvable variant is left exactly as is (no stock 0, no price change)", () => {
    const original = saved("A", "Renamed by admin", 900, 7);
    const { variants, unresolved, missing, changes } = refreshSavedVariants([original], [fresh("A", "16 Pro 128g No Face", 276.76, 2)], priceFor);
    assert.equal(variants[0], original);
    assert.deepEqual(unresolved, [{ index: 0, name: "Renamed by admin", sourceSkuId: "A", reason: "sku_name_mismatch" }]);
    assert.equal(missing.length, 0);
    assert.equal(changes.length, 0);
  });
});
