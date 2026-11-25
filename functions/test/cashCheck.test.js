// 14b step G: functions/cash/cashCheck.js (pure). Run: cd functions && node --test
const test = require("node:test");
const assert = require("node:assert/strict");
const C = require("../cash/cashCheck");

const settings = { enableAbdCash: true, maxAbdCashRedeem: 100 };
// subtotal 200 (server), delivery 60, no coupon
const order = (extra = {}) => ({ subtotal: 200, deliveryCharge: 60, couponDiscount: 0, ...extra });
const check = (o, points = 50, s = settings, serverSubtotal = 200) =>
  C.checkOrderCash({ order: o, serverSubtotal, points, appSettings: s });

test("no Cash, right total: ok, nothing taken, totalOk", () => {
  const r = check(order({ grandTotal: 260 }));
  assert.equal(r.ok, true);
  assert.equal(r.deducted, 0);
  assert.equal(r.totalOk, true);
  assert.equal(r.serverGrandTotal, 260);
});

test("Cash within points and limit: taken, total includes it", () => {
  const r = check(order({ chalakCharCashUsed: 40, paymentDiscounts: { chalakCharCashUsed: 40 }, grandTotal: 220 }));
  assert.deepEqual([r.ok, r.reason, r.deducted, r.totalOk, r.serverGrandTotal], [true, null, 40, true, 220]);
});

test("more Cash than points: not taken, flagged", () => {
  const r = check(order({ chalakCharCashUsed: 80, grandTotal: 180 }), 50);
  assert.deepEqual([r.ok, r.reason, r.deducted, r.available], [false, "not_enough_points", 0, 50]);
  assert.equal(r.totalOk, true, "the total itself follows the claimed Cash");
});

test("over the per-order limit (taka), and limit 0", () => {
  assert.equal(check(order({ chalakCharCashUsed: 150, grandTotal: 110 }), 500).reason, "over_limit");
  assert.equal(check(order({ chalakCharCashUsed: 10, grandTotal: 250 }), 500, { maxAbdCashRedeem: 0 }).reason, "over_limit");
  assert.equal(check(order({ chalakCharCashUsed: 100, grandTotal: 160 }), 500).ok, true, "exactly the limit");
});

test("default limit 100 when the setting is missing", () => {
  assert.equal(C.cashSettings({}).maxPerOrder, 100);
  assert.equal(check(order({ chalakCharCashUsed: 101, grandTotal: 159 }), 500, {}).reason, "over_limit");
});

test("Cash switched off: any Cash flagged, no Cash fine", () => {
  const off = { enableAbdCash: false, maxAbdCashRedeem: 100 };
  assert.equal(check(order({ chalakCharCashUsed: 10, grandTotal: 250 }), 50, off).reason, "cash_disabled");
  assert.equal(check(order({ grandTotal: 260 }), 50, off).ok, true);
  // enableChalakCharCash wins over enableAbdCash, like the app
  assert.equal(C.cashSettings({ enableChalakCharCash: true, enableAbdCash: false }).enabled, true);
  assert.equal(C.cashSettings({ enableChalakCharCash: false }).enabled, false);
});

test("more Cash than the goods are worth (after coupon)", () => {
  const r = check(order({ chalakCharCashUsed: 90, couponDiscount: 150, grandTotal: 20 }), 500, { maxAbdCashRedeem: 1000 });
  assert.equal(r.reason, "over_order_value");
});

test("negative / text / two different claims", () => {
  assert.equal(check(order({ chalakCharCashUsed: -5, grandTotal: 265 })).reason, "invalid_amount");
  assert.equal(check(order({ chalakCharCashUsed: "abc", grandTotal: 260 })).reason, "invalid_amount");
  assert.equal(check(order({ chalakCharCashUsed: 10, paymentDiscounts: { chalakCharCashUsed: 40 }, grandTotal: 250 })).reason, "claim_mismatch");
  assert.equal(check(order({ chalakCharCashUsed: "20", grandTotal: 240 })).ok, true, "numeric text is a number");
});

test("grandTotal checked against the SERVER subtotal, not the client's", () => {
  // Client says subtotal 100 (cheaper prices) and grandTotal 160; server prices make it 260.
  const r = check(order({ subtotal: 100, grandTotal: 160 }), 0, settings, 200);
  assert.deepEqual([r.totalOk, r.clientGrandTotal, r.serverGrandTotal, r.serverSubtotal], [false, 160, 260, 200]);
  assert.equal(r.ok, true, "no Cash: the Cash part is fine");
});

test("grandTotal 0 / missing; finalTotal and total as fallbacks", () => {
  assert.equal(check(order({ grandTotal: 0 })).totalOk, false);
  const missing = check(order({}));
  assert.deepEqual([missing.totalOk, missing.clientGrandTotal], [false, null]);
  assert.equal(check(order({ finalTotal: 260 })).totalOk, true);
  assert.equal(check(order({ total: 260 })).totalOk, true);
});

test("total never below 0 (client clamps the same way)", () => {
  const r = check(order({ couponDiscount: 300, deliveryCharge: 0, grandTotal: 0 }));
  assert.deepEqual([r.serverGrandTotal, r.totalOk], [0, true]);
});

test("refund helpers: status and once only", () => {
  assert.equal(C.isRefundStatus({ status: "cancelled" }), true);
  assert.equal(C.isRefundStatus({ status: "Returned" }), true);
  assert.equal(C.isRefundStatus({ status: "refunded" }), true);
  assert.equal(C.isRefundStatus({ status: "delivered" }), false);
  assert.equal(C.refundDue({ deducted: 40 }), 40);
  assert.equal(C.refundDue({ deducted: 40, refundedAt: new Date() }), 0);
  assert.equal(C.refundDue({ deducted: 40, refunded: true }), 0);
  assert.equal(C.refundDue({ deducted: 0 }), 0);
  assert.equal(C.refundDue(undefined), 0);
  assert.equal(C.redeemLogId("o1"), "cash_redeem_o1");
  assert.equal(C.refundLogId("o1"), "cash_refund_o1");
});
