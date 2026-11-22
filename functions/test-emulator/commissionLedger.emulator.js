// ledger-1: functions/ledger/ledgerTriggers.js against the FIRESTORE EMULATOR
// (demo project, real transactions). Run: node tools/rules-test/run-ledger.js

const test = require("node:test");
const assert = require("node:assert/strict");

const PROJECT = process.env.GCLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  throw new Error("Refusing to run: needs FIRESTORE_EMULATOR_HOST and a demo-* project (emulator only).");
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const deps = { db, FieldValue: admin.firestore.FieldValue };
const T = require("../ledger/ledgerTriggers");

async function clear() {
  for (const c of ["orders", "products", "vendor_private", "vendors", "commission_ledger"]) {
    const s = await db.collection(c).get();
    await Promise.all(s.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.doc("products/p1").set({ vendorId: "v1", price: 100 });
  await db.doc("products/p2").set({ vendorId: "v2", price: 50, variants: [{ id: "big", name: "Big", price: 80 }] });
  await db.doc("products/house").set({ price: 30 });
  await db.doc("vendor_private/v1").set({ commissionPercent: 10 });
  await db.doc("vendor_private/v2").set({ commissionPercent: 0 });
}

const money = async (v) => (await db.doc(`vendor_private/${v}`).get()).data();
const ledger = async (o, v) => (await db.doc(`commission_ledger/${o}_${v}`).get()).data();

async function placeOrder(id, items, extra = {}) {
  await db.doc(`orders/${id}`).set({ userId: "c1", status: "pending", items, ...extra });
  return T.onOrderCreated({ orderId: id, eventId: `create-${id}`, deps });
}

async function setStatus(id, patch, eventId) {
  const before = (await db.doc(`orders/${id}`).get()).data();
  await db.doc(`orders/${id}`).update(patch);
  const after = (await db.doc(`orders/${id}`).get()).data();
  return T.onOrderUpdated({ orderId: id, before, after, eventId, deps });
}

test.beforeEach(async () => { await clear(); await seed(); });

test("order created: one ledger per vendor, house item excluded, money and priceCheck written", async () => {
  const r = await placeOrder("o1", [
    { productId: "p1", price: 100, qty: 2, vendorId: "v1" },
    { productId: "p2", price: 80, qty: 1, vendorId: "v2", variantId: "big" },
    { productId: "house", price: 30, qty: 1, vendorId: "super_admin" },
  ]);
  assert.equal(r.created, 2);
  const l1 = await ledger("o1", "v1");
  assert.equal(l1.subtotal, 200);
  assert.equal(l1.adminCommission, 20);
  assert.equal(l1.vendorPayable, 180);
  assert.equal(l1.status, "pending");
  assert.equal(l1.needsReview, false);
  assert.deepEqual(l1.appliedTransitions, ["created"]);
  assert.equal((await ledger("o1", "v2")).adminCommission, 0, "0% stays 0%");
  assert.equal((await db.doc("commission_ledger/o1_super_admin").get()).exists, false);
  const m = await money("v1");
  assert.deepEqual([m.totalSales, m.totalCommission, m.pendingBalance], [200, 20, 180]);
  assert.equal((await db.doc("vendors/v1").get()).get("totalOrders"), 1);
  const pc = (await db.doc("orders/o1").get()).get("priceCheck");
  assert.equal(pc.ok, true);
  assert.equal(pc.serverTotal, 310);
  assert.ok(pc.checkedAt);
});

test("same creation event twice: no second ledger, no double money", async () => {
  await placeOrder("o2", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  const again = await T.onOrderCreated({ orderId: "o2", eventId: "create-o2", deps });
  assert.equal(again.created, 0);
  const m = await money("v1");
  assert.deepEqual([m.totalSales, m.pendingBalance], [100, 90]);
  assert.equal((await db.doc("vendors/v1").get()).get("totalOrders"), 1);
});

test("wrong client price: ledger on the server price, flagged; priceCheck not ok", async () => {
  await placeOrder("o3", [{ productId: "p1", price: 1, qty: 3, vendorId: "v1" }]);
  const l = await ledger("o3", "v1");
  assert.equal(l.subtotal, 300);
  assert.equal(l.priceMismatch, true);
  assert.equal(l.needsReview, true);
  const pc = (await db.doc("orders/o3").get()).get("priceCheck");
  assert.equal(pc.ok, false);
  assert.equal(pc.clientTotal, 3);
  assert.equal(pc.serverTotal, 300);
});

test("house-only order (like the 6 live ones): priceCheck written, no ledger", async () => {
  const r = await placeOrder("o4", [{ productId: "house", price: 30, qty: 2, vendorId: "super_admin" }]);
  assert.equal(r.created, 0);
  assert.equal((await db.doc("orders/o4").get()).get("priceCheck.ok"), true);
  assert.equal((await db.collection("commission_ledger").where("orderId", "==", "o4").get()).size, 0);
});

test("delivered (admin) twice, and two deliveries racing: money moves once", async () => {
  await placeOrder("o5", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  const r = await setStatus("o5", { status: "delivered" }, "ev-1");
  assert.equal(r.moved, 1);
  // The same event delivered again by the platform:
  const before = { status: "pending" };
  const after = (await db.doc("orders/o5").get()).data();
  const dup = await T.onOrderUpdated({ orderId: "o5", before, after, eventId: "ev-1", deps });
  assert.equal(dup.moved, 0);
  // Two different events at once:
  const both = await Promise.all([
    T.onOrderUpdated({ orderId: "o5", before, after, eventId: "ev-2", deps }),
    T.onOrderUpdated({ orderId: "o5", before, after, eventId: "ev-3", deps }),
  ]);
  assert.equal(both[0].moved + both[1].moved, 0);
  const m = await money("v1");
  assert.deepEqual([m.pendingBalance, m.withdrawableBalance, m.deliveredOrders], [0, 90, 1]);
  const l = await ledger("o5", "v1");
  assert.equal(l.status, "delivered");
  assert.equal(l.lastEventId, "ev-1");
  assert.deepEqual(l.appliedTransitions, ["created", "pending->delivered"]);
});

test("racing first delivery (two events at once): still exactly one move", async () => {
  await placeOrder("o6", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  const after = { ...(await db.doc("orders/o6").get()).data(), status: "delivered" };
  await db.doc("orders/o6").update({ status: "delivered" });
  const res = await Promise.all([
    T.onOrderUpdated({ orderId: "o6", before: { status: "pending" }, after, eventId: "a", deps }),
    T.onOrderUpdated({ orderId: "o6", before: { status: "pending" }, after, eventId: "b", deps }),
  ]);
  assert.equal(res[0].moved + res[1].moved, 1);
  assert.equal((await money("v1")).withdrawableBalance, 90);
});

test("rider's delivered (deliveryStatus) counts", async () => {
  await placeOrder("o7", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }], { deliveryStatus: "on_the_way" });
  const r = await setStatus("o7", { status: "delivered", deliveryStatus: "delivered", paymentStatus: "paid" }, "rider-1");
  assert.equal(r.moved, 1);
  assert.equal((await money("v1")).withdrawableBalance, 90);
});

test("delivered -> paid out -> returned: balance goes negative, debtCreated", async () => {
  await placeOrder("o8", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  await setStatus("o8", { status: "delivered" }, "d");
  // Admin paid the vendor the whole 90 (the payout page does this).
  await db.doc("vendor_private/v1").update({ withdrawableBalance: 0, totalPaidOut: 90 });
  const r = await setStatus("o8", { status: "returned" }, "ret");
  assert.equal(r.moved, 1);
  const m = await money("v1");
  assert.equal(m.withdrawableBalance, -90);
  assert.equal(m.totalSales, 0);
  assert.equal(m.cancelledOrders, 1);
  const l = await ledger("o8", "v1");
  assert.equal(l.status, "returned");
  assert.equal(l.debtCreated, true);
  // refunded afterwards: final state, nothing more.
  assert.equal((await setStatus("o8", { status: "refunded" }, "ref")).moved, 0);
});

test("cancel while pending: pending reversed, no debt", async () => {
  await placeOrder("o9", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  await setStatus("o9", { status: "cancelled" }, "c");
  const m = await money("v1");
  assert.deepEqual([m.pendingBalance, m.totalSales, m.totalCommission], [0, 0, 0]);
  assert.equal((await ledger("o9", "v1")).debtCreated, false);
});

test("only status changes count: priceCheck or other fields do nothing", async () => {
  await placeOrder("o10", [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }]);
  const r = await setStatus("o10", { note: "x", priceCheck: { ok: false } }, "n");
  assert.equal(r.skipped, "no status change");
});

test("order already delivered when the creation trigger runs: ledger starts delivered", async () => {
  await db.doc("orders/o11").set({ status: "delivered", items: [{ productId: "p1", price: 100, qty: 1, vendorId: "v1" }] });
  const r = await T.onOrderCreated({ orderId: "o11", eventId: "late", deps });
  assert.deepEqual([r.created, r.moved], [1, 1]);
  const m = await money("v1");
  assert.deepEqual([m.pendingBalance, m.withdrawableBalance], [0, 90]);
});
