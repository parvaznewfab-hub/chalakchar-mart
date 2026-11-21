const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const L = require("../ledger/commissionLedger");

const PRODUCTS = {
  p1: { vendorId: "v1", price: 100 },
  p2: { vendorId: "v1", price: 50, variants: [{ id: "small", name: "Small", price: 40 }, { id: "big", name: "Big", price: 70 }] },
  p3: { vendorId: "v2", price: 200 },
  house: { price: 30 }, // no vendorId: ChalakChar's own (super_admin)
};

const item = (productId, price, qty, vendorId, extra = {}) => ({ productId, price, qty, vendorId, ...extra });

test("commission rate: vendor_private value, 0 stays 0, 10 only when never set", () => {
  assert.equal(L.commissionPercentOf({ commissionPercent: 7.5 }), 7.5);
  assert.equal(L.commissionPercentOf({ commissionPercent: 0 }), 0);
  assert.equal(L.commissionPercentOf({ commissionRate: 12 }), 12);
  assert.equal(L.commissionPercentOf({}), 10);
  assert.equal(L.commissionPercentOf(null), 10);
  assert.equal(L.commissionPercentOf({ commissionPercent: "abc" }), 10);
});

test("right prices: priceCheck ok, per-vendor subtotals, house items checked but not in the ledger", () => {
  const order = { items: [item("p1", 100, 2, "v1"), item("p3", 200, 1, "v2"), item("house", 30, 3, "super_admin")] };
  const r = L.priceOrder(order, PRODUCTS);
  assert.equal(r.priceCheck.ok, true);
  assert.equal(r.priceCheck.clientTotal, 490);
  assert.equal(r.priceCheck.serverTotal, 490);
  assert.deepEqual(r.priceCheck.mismatchedItems, []);
  assert.deepEqual(Object.keys(r.byVendor).sort(), ["v1", "v2"]);
  assert.equal(r.byVendor.v1.subtotal, 200);
  assert.equal(r.byVendor.v1.itemCount, 2);
  assert.equal(r.byVendor.v1.priceMismatch, false);
});

test("wrong price: server price wins, mismatch recorded on the order and the vendor", () => {
  const r = L.priceOrder({ items: [item("p1", 1, 2, "v1")] }, PRODUCTS);
  assert.equal(r.priceCheck.ok, false);
  assert.equal(r.priceCheck.clientTotal, 2);
  assert.equal(r.priceCheck.serverTotal, 200);
  assert.deepEqual(r.priceCheck.mismatchedItems, [{ index: 0, productId: "p1", reasons: ["price"] }]);
  assert.equal(r.byVendor.v1.subtotal, 200);
  assert.equal(r.byVendor.v1.priceMismatch, true);
});

test("wrong vendorId: attributed to the product's own vendor", () => {
  const r = L.priceOrder({ items: [item("p3", 200, 1, "v1")] }, PRODUCTS);
  assert.equal(r.priceCheck.ok, false);
  assert.deepEqual(r.priceCheck.mismatchedItems[0].reasons, ["vendor"]);
  assert.deepEqual(Object.keys(r.byVendor), ["v2"]);
  assert.equal(r.byVendor.v2.subtotal, 200);
  assert.equal(r.byVendor.v2.priceMismatch, true);
});

test("a house product claimed for a vendor gets no ledger; a vendor product sold as house does", () => {
  const r1 = L.priceOrder({ items: [item("house", 30, 1, "v1")] }, PRODUCTS);
  assert.deepEqual(r1.byVendor, {});
  assert.equal(r1.priceCheck.ok, false);
  const r2 = L.priceOrder({ items: [item("p1", 100, 1, "super_admin")] }, PRODUCTS);
  assert.equal(r2.byVendor.v1.subtotal, 100);
  assert.equal(r2.byVendor.v1.priceMismatch, true);
});

test("variant: priced by variant id, then unit name; wrong variant price flagged", () => {
  assert.equal(L.priceOrder({ items: [item("p2", 70, 1, "v1", { variantId: "big" })] }, PRODUCTS).priceCheck.ok, true);
  assert.equal(L.priceOrder({ items: [item("p2", 40, 1, "v1", { variantId: "default", unit: "Small" })] }, PRODUCTS).priceCheck.ok, true);
  const bad = L.priceOrder({ items: [item("p2", 40, 1, "v1", { variantId: "big" })] }, PRODUCTS);
  assert.equal(bad.priceCheck.ok, false);
  assert.equal(bad.byVendor.v1.subtotal, 70);
});

test("bad quantity or missing product: mismatch, nothing invented", () => {
  const r = L.priceOrder({ items: [item("p1", 100, 0, "v1"), item("p1", 100, 1.5, "v1"), item("gone", 10, 1, "v1")] }, PRODUCTS);
  assert.equal(r.priceCheck.ok, false);
  assert.deepEqual(r.priceCheck.mismatchedItems.map((m) => m.reasons), [["qty"], ["qty"], ["product_missing"]]);
  assert.equal(r.byVendor.v1.subtotal, 0);
});

test("no items / no vendor: priceCheck still produced", () => {
  const r = L.priceOrder({ items: [item("house", 30, 2, "super_admin")] }, PRODUCTS);
  assert.equal(r.priceCheck.ok, true);
  assert.equal(r.priceCheck.serverTotal, 60);
  assert.deepEqual(r.byVendor, {});
  assert.equal(L.priceOrder({}, PRODUCTS).priceCheck.ok, true);
});

test("new ledger entry: commission from the vendor's rate, money increments", () => {
  const priced = { subtotal: 200, itemCount: 2, priceMismatch: false, mismatchedItems: [] };
  const e = L.newLedgerEntry({ orderId: "o1", vendorId: "v1", priced, vendorPrivate: { commissionPercent: 15 } });
  assert.equal(e.ledger.adminCommission, 30);
  assert.equal(e.ledger.vendorPayable, 170);
  assert.equal(e.ledger.status, "pending");
  assert.equal(e.ledger.needsReview, false);
  assert.deepEqual(e.money, { totalSales: 200, totalCommission: 30, pendingBalance: 170 });
  const zero = L.newLedgerEntry({ orderId: "o1", vendorId: "v1", priced, vendorPrivate: { commissionPercent: 0 } });
  assert.equal(zero.ledger.adminCommission, 0);
  assert.equal(zero.ledger.vendorPayable, 200);
});

test("target: only a status / deliveryStatus change counts; rider's delivered included", () => {
  assert.equal(L.targetForOrder({ status: "pending" }, { status: "delivered" }), "delivered");
  assert.equal(L.targetForOrder({ status: "on_the_way", deliveryStatus: "on_the_way" }, { status: "delivered", deliveryStatus: "delivered" }), "delivered");
  assert.equal(L.targetForOrder({ deliveryStatus: "on_the_way", status: "assigned_to_rider" }, { deliveryStatus: "delivered", status: "assigned_to_rider" }), "delivered");
  assert.equal(L.targetForOrder({ status: "pending" }, { status: "cancelled" }), "cancelled");
  assert.equal(L.targetForOrder({ status: "delivered" }, { status: "returned" }), "returned");
  assert.equal(L.targetForOrder({ status: "delivered" }, { status: "refunded" }), "returned");
  assert.equal(L.targetForOrder({ status: "pending" }, { status: "confirmed" }), null);
  // priceCheck or any other field changing: nothing.
  assert.equal(L.targetForOrder({ status: "delivered" }, { status: "delivered", priceCheck: { ok: true } }), null);
});

test("transitions move forward once; delivered -> returned can make the balance negative", () => {
  const l = { status: "pending", subtotal: 200, adminCommission: 20, vendorPayable: 180 };
  assert.deepEqual(L.transition(l, "delivered"), { status: "delivered", money: { pendingBalance: -180, withdrawableBalance: 180, deliveredOrders: 1 } });
  assert.deepEqual(L.transition(l, "cancelled").money, { pendingBalance: -180, totalSales: -200, totalCommission: -20, cancelledOrders: 1 });
  const d = { ...l, status: "delivered" };
  assert.equal(L.transition(d, "delivered"), null, "same event twice: nothing");
  assert.deepEqual(L.transition(d, "returned"), { status: "returned", money: { withdrawableBalance: -180, totalSales: -200, totalCommission: -20, cancelledOrders: 1 } });
  assert.equal(L.transition({ ...l, status: "returned" }, "cancelled"), null);
  assert.equal(L.transition({ ...l, status: "cancelled" }, "delivered"), null, "never backwards");
});

test("onOrderStatusUpdated: everything except the old commission block is unchanged", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8").replace(/\r\n/g, "\n");
  const start = src.indexOf("exports.onOrderStatusUpdated = onDocumentUpdated(");
  const end = src.indexOf("\n});\n", start) + 4;
  const expected = fs.readFileSync(path.join(__dirname, "fixtures", "onOrderStatusUpdated.expected.txt"), "utf8").replace(/\r\n/g, "\n");
  assert.equal(src.slice(start, end), expected);
  assert.ok(!src.includes("createVendorCommissions("), "old commission function gone");
  assert.ok(!src.includes('collection("vendor_earnings")'), "vendor_earnings no longer written");
});
