// The display-price change and its backfill must never look like a price
// drop to onProductStockUpdated (wishlist "discount" message).
// Live case: imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165 (Netac SSD),
// top-level price ৳47,546.14 (4TB = variants[0]) -> ৳2,851.49 (128GB).
const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const {
  displayDiscountPercent,
  isPriceBackfillWrite,
  wishlistDiscountDecision,
  PRICE_BACKFILL_FIELD,
} = require("../marketing/priceChange");
const { plannedChanges } = require("../scripts/backfillDisplayPrice");

const ts = (ms) => ({ toMillis: () => ms });

const variants = [
  { name: "4TB Black / China Mainland", price: 47546.14, mrp: 68907.2, oldPrice: 68907.2, stock: 3 },
  { name: "512GB Black / China Mainland", price: 7606.24, mrp: 11022.87, oldPrice: 11022.87, stock: 636 },
  { name: "1TB Black / China Mainland", price: 13583.64, mrp: 19686.02, oldPrice: 19686.02, stock: 0 },
  { name: "128GB Black / China Mainland", price: 2851.49, mrp: 4132.56, oldPrice: 4132.56, stock: 1337 },
];
// Stored as it is live today: top-level = variants[0] (4TB).
const netacBefore = {
  name: "Netac SATA SSD",
  isActive: true,
  approvalStatus: "approved",
  price: 47546.14,
  piecePrice: 47546.14,
  oldPrice: 68907.2,
  mrp: 68907,
  unit: "4TB Black / China Mainland",
  variants,
};

describe("wishlist discount decision", () => {
  test("discount is computed from the variants, not the stored top-level price", () => {
    // 128GB: (4132.56 - 2851.49) / 4132.56 = 31%
    assert.equal(displayDiscountPercent(netacBefore), 31);
    // A stale/odd top-level pair would read 94% if it were used — it isn't.
    assert.equal(displayDiscountPercent({ ...netacBefore, price: 2851.49, oldPrice: 47546.14 }), 31);
  });

  test("Netac 47,546 -> 2,851 (top-level correction, same variants) sends nothing", () => {
    const after = { ...netacBefore, price: 2851.49, piecePrice: 2851.49, oldPrice: 4132.56, mrp: 4132.56, unit: "128GB Black / China Mainland" };
    const d = wishlistDiscountDecision(netacBefore, after);
    assert.equal(d.notify, false);
    assert.equal(d.beforeDiscount, d.afterDiscount);
  });

  test("the backfill's own write is recognised and sends nothing, even with a variant change", () => {
    const after = {
      ...netacBefore,
      price: 2851.49,
      [PRICE_BACKFILL_FIELD]: ts(1000),
      // even if a variant had changed in the same write
      variants: variants.map((v) => (v.name.startsWith("128GB") ? { ...v, price: 1000 } : v)),
    };
    assert.equal(isPriceBackfillWrite(netacBefore, after), true);
    assert.deepEqual(wishlistDiscountDecision(netacBefore, after).notify, false);
  });

  test("a later write on a backfilled product is not treated as a backfill", () => {
    const backfilled = { ...netacBefore, [PRICE_BACKFILL_FIELD]: ts(1000) };
    assert.equal(isPriceBackfillWrite(backfilled, { ...backfilled, stock: 5 }), false);
  });

  test("a real drop of the display variant still notifies", () => {
    const after = {
      ...netacBefore,
      variants: variants.map((v) => (v.name.startsWith("128GB") ? { ...v, price: 2400 } : v)),
    };
    const d = wishlistDiscountDecision(netacBefore, after);
    assert.equal(d.notify, true);
    assert.equal(d.afterDiscount, 42);
  });

  test("a drop below 5% total discount is not announced", () => {
    const p = { variants: [{ name: "A", price: 100, mrp: 100, stock: 1 }] };
    const after = { variants: [{ name: "A", price: 97, mrp: 100, stock: 1 }] };
    assert.equal(wishlistDiscountDecision(p, after).notify, false);
  });
});

describe("backfillDisplayPrice plan for Netac", () => {
  test("moves top-level price/mrp/unit to the 128GB variant and nothing else", () => {
    const changes = plannedChanges(netacBefore);
    assert.deepEqual(Object.keys(changes).sort(), ["mrp", "oldPrice", "piecePrice", "price", "unit"]);
    assert.equal(changes.price.to, 2851.49);
    assert.equal(changes.mrp.to, 4132.56);
    assert.equal(changes.unit.to, "128GB Black / China Mainland");
  });
});
