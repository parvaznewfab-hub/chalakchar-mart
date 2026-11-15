// Audit item 16: whole-taka prices (nearest) in data and in the import rule.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const { roundedPriceUpdate } = require("../scripts/roundPricesToTaka");

test("rounds top-level and variant prices to the nearest taka", () => {
  const u = roundedPriceUpdate({
    price: 2851.49, mrp: 4132.56, oldPrice: 4132.56,
    variants: [{ id: "a", name: "128GB", price: 2851.49, mrp: 4132.56, stock: 3 }, { id: "b", price: 7606.5, mrp: 11022 }],
  });
  assert.equal(u.price, 2851);
  assert.equal(u.mrp, 4133);
  assert.deepEqual(u.variants.map((v) => [v.price, v.mrp]), [[2851, 4133], [7607, 11022]]);
  assert.equal(u.variants[0].stock, 3, "other variant fields kept");
});

test("already whole -> nothing to write", () => {
  assert.equal(roundedPriceUpdate({ price: 500, variants: [{ price: 500, mrp: 600 }] }), null);
});
