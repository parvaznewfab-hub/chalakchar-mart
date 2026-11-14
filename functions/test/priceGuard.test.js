// Price guard in the products triggers: older installed app builds (admin
// save, client stock updates) and vendor saves still write variants[0] as the
// top-level price. The trigger re-derives it, stamped price_guard, which
// sends no marketing and causes no further correction (no loop).
const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const {
  priceGuardUpdate,
  isPriceGuardWrite,
  isSystemPriceWrite,
  wishlistDiscountDecision,
  PRICE_GUARD_FIELD,
  PRICE_GUARD_SOURCE,
} = require("../marketing/priceChange");
const { shouldAutoMarketProduct } = require("../marketing/eligibility");

const STAMP = { toMillis: () => 5000 };

const variants = [
  { name: "4TB Black / China Mainland", price: 47546.14, mrp: 68907.2, stock: 3 },
  { name: "512GB Black / China Mainland", price: 7606.24, mrp: 11022.87, stock: 636 },
  { name: "128GB Black / China Mainland", price: 2851.49, mrp: 4132.56, stock: 1337 },
];
const correct = {
  name: "Netac SATA SSD",
  isActive: true,
  approvalStatus: "approved",
  price: 2851.49,
  piecePrice: 2851.49,
  oldPrice: 4132.56,
  mrp: 4132.56,
  unit: "128GB Black / China Mainland",
  variants,
  stock: 1976,
};
// What an older app build writes on admin save / stock update.
const oldAppWrite = {
  ...correct,
  price: 47546.14,
  piecePrice: 47546.14,
  oldPrice: 68907.2,
  mrp: 68907.2,
  unit: "4TB Black / China Mainland",
};

function apply(doc, update) {
  return { ...doc, ...update };
}

describe("price guard", () => {
  test("an old-app write (variants[0] as price) is corrected to the display variant", () => {
    const update = priceGuardUpdate(oldAppWrite, STAMP);
    assert.equal(update.price, 2851.49);
    assert.equal(update.piecePrice, 2851.49);
    assert.equal(update.oldPrice, 4132.56);
    assert.equal(update.mrp, 4132.56);
    assert.equal(update.unit, "128GB Black / China Mainland");
    assert.equal(update.lastWriteSource, PRICE_GUARD_SOURCE);
    assert.equal(update[PRICE_GUARD_FIELD], STAMP);
    assert.equal("variants" in update, false, "variants (what the cart charges) are never touched");
  });

  test("a consistent product needs nothing", () => {
    assert.equal(priceGuardUpdate(correct, STAMP), null);
  });

  test("no loop: the corrected doc needs no further correction, and its write is recognised", () => {
    const corrected = apply(oldAppWrite, priceGuardUpdate(oldAppWrite, STAMP));
    assert.equal(priceGuardUpdate(corrected, { toMillis: () => 6000 }), null);
    assert.equal(isPriceGuardWrite(oldAppWrite, corrected), true);
    assert.equal(isSystemPriceWrite(oldAppWrite, corrected), true);
  });

  test("the guard's write sends no wishlist discount, even though the price fell 47,546 -> 2,851", () => {
    const corrected = apply(oldAppWrite, priceGuardUpdate(oldAppWrite, STAMP));
    const d = wishlistDiscountDecision(oldAppWrite, corrected);
    assert.equal(d.notify, false);
    assert.equal(d.reason, "price_guard");
  });

  test("the old-app write itself sends no wishlist discount (decided on variants, not the stored price)", () => {
    const d = wishlistDiscountDecision(correct, oldAppWrite);
    assert.equal(d.notify, false);
    assert.equal(d.beforeDiscount, d.afterDiscount);
  });

  test("cheapest variant sells out (server order stock update): price moves to the next in-stock one", () => {
    const soldOut = { ...correct, variants: variants.map((v) => (v.name.startsWith("128GB") ? { ...v, stock: 0 } : v)) };
    const update = priceGuardUpdate(soldOut, STAMP);
    assert.equal(update.price, 7606.24);
    assert.equal(update.unit, "512GB Black / China Mainland");
  });

  test("a later ordinary write on a guarded product is not mistaken for a guard write", () => {
    const guarded = { ...correct, [PRICE_GUARD_FIELD]: STAMP };
    assert.equal(isPriceGuardWrite(guarded, { ...guarded, stock: 10 }), false);
  });

  test("products without priced variants are left alone", () => {
    assert.equal(priceGuardUpdate({ price: 50, variants: [] }, STAMP), null);
    assert.equal(priceGuardUpdate({ price: 50 }, STAMP), null);
  });

  test("the guard never changes marketing eligibility fields", () => {
    const update = priceGuardUpdate(oldAppWrite, STAMP);
    for (const f of ["isActive", "needsReview", "approvalStatus", "autoMarketingDisabled"]) {
      assert.equal(f in update, false, f);
    }
    assert.equal(shouldAutoMarketProduct(apply(oldAppWrite, update)), shouldAutoMarketProduct(oldAppWrite));
  });
});
