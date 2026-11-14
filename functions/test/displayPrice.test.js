const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  pickDisplayVariantIndex,
  hasPriceRange,
  displayPriceFields,
  productDisplayPrice,
  productDisplayMrp,
} = require("../catalog/displayPrice");

// Live case: imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165 (Netac SSD).
const netac = [
  { name: "4TB Black / China Mainland", price: 47546.14, mrp: 68907.2, stock: 3 },
  { name: "512GB Black / China Mainland", price: 7606.24, mrp: 11022.87, stock: 636 },
  { name: "256GB Black / China Mainland", price: 4481.69, mrp: 6494.99, stock: 2358 },
  { name: "2TB Black / China Mainland", price: 24451.64, mrp: 35437.83, stock: 2 },
  { name: "1TB Black / China Mainland", price: 13583.64, mrp: 19686.02, stock: 0 },
  { name: "128GB Black / China Mainland", price: 2851.49, mrp: 4132.56, stock: 1337 },
];

describe("displayPrice", () => {
  test("cheapest in-stock variant, not the first one", () => {
    assert.equal(pickDisplayVariantIndex(netac), 5);
    assert.deepEqual(displayPriceFields(netac), {
      price: 2851.49, piecePrice: 2851.49, oldPrice: 4132.56, mrp: 4132.56, unit: "128GB Black / China Mainland",
    });
    assert.equal(productDisplayPrice({ price: 47546.14, variants: netac }), 2851.49);
    assert.equal(productDisplayMrp({ oldPrice: 68907.2, variants: netac }), 4132.56);
  });

  test("in-stock beats cheaper out-of-stock; all out of stock → cheapest", () => {
    assert.equal(pickDisplayVariantIndex([{ price: 10, stock: 0 }, { price: 20, stock: 1 }]), 1);
    assert.equal(pickDisplayVariantIndex([{ price: 30, stock: 0 }, { price: 20, stock: 0 }]), 1);
  });

  test("unpriced variants are ignored; none priced → null / stored price", () => {
    assert.equal(pickDisplayVariantIndex([{ price: 0, stock: 5 }, { price: 9, stock: 0 }]), 1);
    assert.equal(displayPriceFields([{ price: 0 }]), null);
    assert.equal(displayPriceFields([]), null);
    assert.equal(productDisplayPrice({ price: 120 }), 120);
    assert.equal(productDisplayMrp({ price: 120, oldPrice: 150 }), 150);
  });

  test("mrp never below price; piecePrice-only variants work", () => {
    assert.equal(displayPriceFields([{ piecePrice: 50, mrp: 40, stock: 1 }]).mrp, 50);
  });

  test("hasPriceRange", () => {
    assert.equal(hasPriceRange(netac), true);
    assert.equal(hasPriceRange([{ price: 5 }, { price: 5 }]), false);
    assert.equal(hasPriceRange([{ price: 5 }]), false);
  });
});
