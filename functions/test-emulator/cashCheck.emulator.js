// 14b step G: functions/cash/cashTriggers.js against the FIRESTORE EMULATOR
// (demo project, real transactions). Run: node tools/rules-test/run-cash.js

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
const T = require("../cash/cashTriggers");

async function clear() {
  for (const c of ["orders", "products", "users", "wallet_logs", "settings"]) {
    const s = await db.collection(c).get();
    await Promise.all(s.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.doc("products/p1").set({ price: 100 });
  await db.doc("products/p2").set({ vendorId: "v1", price: 50 });
  await db.doc("users/c1").set({ role: "user", points: 50 });
  await db.doc("settings/app").set({ enableAbdCash: true, maxAbdCashRedeem: 100 });
}

const points = async (u = "c1") => (await db.doc(`users/${u}`).get()).get("points");
const cashCheck = async (o) => (await db.doc(`orders/${o}`).get()).get("cashCheck");
const log = async (id) => (await db.doc(`wallet_logs/${id}`).get());

// grandTotal = 100*qty - cash + 60
async function placeOrder(id, cash, extra = {}) {
  const sub = 100;
  await db.doc(`orders/${id}`).set({
    userId: "c1", status: "pending",
    items: [{ productId: "p1", price: 100, qty: 1, vendorId: "super_admin" }],
    subtotal: sub, deliveryCharge: 60, couponDiscount: 0,
    chalakCharCashUsed: cash, paymentDiscounts: { chalakCharCashUsed: cash },
    grandTotal: sub - cash + 60, ...extra,
  });
  return T.onOrderCreated({ orderId: id, eventId: `create-${id}`, deps });
}

async function setStatus(id, status, eventId) {
  const before = (await db.doc(`orders/${id}`).get()).data();
  await db.doc(`orders/${id}`).update({ status });
  const after = (await db.doc(`orders/${id}`).get()).data();
  return T.onOrderUpdated({ orderId: id, before, after, eventId, deps });
}

test.beforeEach(async () => { await clear(); await seed(); });

test("Cash within points: points taken once, debit log, cashCheck ok", async () => {
  const r = await placeOrder("o1", 40);
  assert.deepEqual([r.ok, r.deducted, r.totalOk], [true, 40, true]);
  assert.equal(await points(), 10);
  const l = await log("cash_redeem_o1");
  assert.deepEqual([l.get("userId"), l.get("direction"), l.get("amount"), l.get("orderId")], ["c1", "debit", 40, "o1"]);
  const c = await cashCheck("o1");
  assert.deepEqual([c.ok, c.deducted, c.totalOk, c.serverGrandTotal], [true, 40, true, 120]);
  assert.ok(c.checkedAt);
});

test("same creation event twice: points taken once", async () => {
  await placeOrder("o2", 40);
  const again = await T.onOrderCreated({ orderId: "o2", eventId: "create-o2", deps });
  assert.equal(again.skipped, "already checked");
  assert.equal(await points(), 10);
});

test("more Cash than points: nothing taken, order flagged", async () => {
  const r = await placeOrder("o3", 80);
  assert.deepEqual([r.ok, r.reason, r.deducted], [false, "not_enough_points", 0]);
  assert.equal(await points(), 50);
  assert.equal((await log("cash_redeem_o3")).exists, false);
  const c = await cashCheck("o3");
  assert.deepEqual([c.ok, c.claimed, c.available], [false, 80, 50]);
});

test("over the per-order limit and Cash switched off", async () => {
  await db.doc("users/c1").update({ points: 500 });
  await db.doc("settings/app").update({ maxAbdCashRedeem: 30 });
  assert.equal((await placeOrder("o4", 40)).reason, "over_limit");
  await db.doc("settings/app").update({ enableAbdCash: false, maxAbdCashRedeem: 100 });
  assert.equal((await placeOrder("o5", 10)).reason, "cash_disabled");
  assert.equal(await points(), 500);
});

test("wrong grandTotal (server prices): totalOk false with both numbers, Cash still checked", async () => {
  // Client claims the 100-taka item costs 10 and sends grandTotal 70.
  await db.doc("orders/o6").set({
    userId: "c1", status: "pending",
    items: [{ productId: "p1", price: 10, qty: 1, vendorId: "super_admin" }],
    subtotal: 10, deliveryCharge: 60, couponDiscount: 0, grandTotal: 70,
  });
  const r = await T.onOrderCreated({ orderId: "o6", eventId: "create-o6", deps });
  assert.equal(r.totalOk, false);
  const c = await cashCheck("o6");
  assert.deepEqual([c.totalOk, c.clientGrandTotal, c.serverGrandTotal, c.serverSubtotal], [false, 70, 160, 100]);
  assert.equal(c.ok, true);
});

test("two orders at the same time for the same points: only one gets them", async () => {
  for (const id of ["o7", "o8"]) {
    await db.doc(`orders/${id}`).set({
      userId: "c1", status: "pending", items: [{ productId: "p1", price: 100, qty: 1 }],
      subtotal: 100, deliveryCharge: 60, chalakCharCashUsed: 40, grandTotal: 120,
    });
  }
  const rs = await Promise.all(["o7", "o8"].map((id) => T.onOrderCreated({ orderId: id, eventId: `c-${id}`, deps })));
  assert.deepEqual(rs.map((r) => r.deducted).sort(), [0, 40]);
  assert.equal(await points(), 10);
});

test("cancel gives the Cash back once (same event twice, then returned)", async () => {
  await placeOrder("o9", 40);
  const r1 = await setStatus("o9", "cancelled", "e1");
  assert.equal(r1.refunded, 40);
  assert.equal(await points(), 50);
  // Same event delivered again
  const snap = (await db.doc("orders/o9").get()).data();
  const r2 = await T.onOrderUpdated({ orderId: "o9", before: { ...snap, status: "pending" }, after: snap, eventId: "e1", deps });
  assert.ok(r2.skipped);
  // Admin puts it back to pending, then marks returned: nothing more
  await setStatus("o9", "pending", "e2");
  const r3 = await setStatus("o9", "returned", "e3");
  assert.ok(r3.skipped);
  assert.equal(await points(), 50);
  const l = await log("cash_refund_o9");
  assert.deepEqual([l.get("direction"), l.get("amount")], ["credit", 40]);
  const c = await cashCheck("o9");
  assert.deepEqual([c.refunded, c.refundedAmount], [true, 40]);
});

test("returned after delivery gives the Cash back; delivered alone does not", async () => {
  await placeOrder("o10", 30);
  assert.ok((await setStatus("o10", "delivered", "d1")).skipped);
  assert.equal(await points(), 20);
  assert.equal((await setStatus("o10", "returned", "r1")).refunded, 30);
  assert.equal(await points(), 50);
});

test("cancelled with no Cash taken (flagged order): nothing given back", async () => {
  await placeOrder("o11", 80); // not enough points -> nothing taken
  assert.ok((await setStatus("o11", "cancelled", "c1")).skipped);
  assert.equal(await points(), 50);
});

test("order already cancelled when the create trigger runs: nothing taken", async () => {
  const r = await placeOrder("o12", 40, { status: "cancelled" });
  assert.equal(r.deducted, 0);
  assert.equal(await points(), 50);
  assert.equal((await cashCheck("o12")).note, "order_cancelled_before_check");
});

test("a client-written cashCheck would skip the deduction (why the rules forbid it)", async () => {
  await db.doc("orders/o13").set({
    userId: "c1", status: "pending", items: [{ productId: "p1", price: 100, qty: 1 }],
    subtotal: 100, deliveryCharge: 60, chalakCharCashUsed: 40, grandTotal: 120,
    cashCheck: { ok: true, deducted: 0 },
  });
  const r = await T.onOrderCreated({ orderId: "o13", eventId: "x", deps });
  assert.equal(r.skipped, "already checked");
  assert.equal(await points(), 50, "free Cash: so firestore.rules refuse cashCheck on create");
});
