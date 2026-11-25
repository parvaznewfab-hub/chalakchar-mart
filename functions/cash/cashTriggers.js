// -----------------------------------------------------------------------------
// Order triggers for ChalakChar Cash and the order total check (14b step G).
// Wired up in functions/index.js as onOrderCreatedCash / onOrderStatusCash.
//
// One Firestore transaction per event; both steps are idempotent:
//   - creation: cashCheck is written once. If it is already on the order
//     (an earlier run, or the event delivered twice) nothing happens, so the
//     points are taken at most once;
//   - cancel / return: the Cash comes back once (cashCheck.refundedAt plus a
//     fixed wallet_logs id), and is never taken again afterwards.
// deps: { db, FieldValue } (admin SDK in production, the emulator in tests).
// -----------------------------------------------------------------------------

const { priceOrder } = require("../ledger/commissionLedger");
const {
  checkOrderCash, isRefundStatus, refundDue, redeemLogId, refundLogId,
} = require("./cashCheck");

async function readProducts(db, order) {
  const ids = [...new Set((Array.isArray(order.items) ? order.items : [])
    .map((i) => (i && i.productId ? String(i.productId).trim() : ""))
    .filter(Boolean))];
  if (!ids.length) return {};
  const snaps = await db.getAll(...ids.map((id) => db.collection("products").doc(id)));
  const out = {};
  snaps.forEach((s, i) => { out[ids[i]] = s.exists ? s.data() : null; });
  return out;
}

function userIdOf(order) {
  const u = order && order.userId;
  return typeof u === "string" && u.trim() ? u.trim() : "";
}

async function onOrderCreated({ orderId, eventId, deps }) {
  const { db, FieldValue } = deps;
  const orderRef = db.collection("orders").doc(orderId);
  const first = await orderRef.get();
  if (!first.exists) return { skipped: "order missing" };
  if (first.data().cashCheck) return { skipped: "already checked" };
  // Server prices of the items (same pricing as priceCheck / the ledger).
  const serverSubtotal = priceOrder(first.data(), await readProducts(db, first.data())).priceCheck.serverTotal;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return { skipped: "order missing" };
    const order = snap.data();
    if (order.cashCheck) return { skipped: "already checked" };

    const uid = userIdOf(order);
    const userRef = uid ? db.collection("users").doc(uid) : null;
    const userSnap = userRef ? await tx.get(userRef) : null;
    const settingsSnap = await tx.get(db.collection("settings").doc("app"));
    const points = userSnap && userSnap.exists ? userSnap.data().points : 0;

    const check = checkOrderCash({
      order,
      serverSubtotal,
      points,
      appSettings: settingsSnap.exists ? settingsSnap.data() : {},
    });

    // Cancelled before this ran (the cancel trigger found no cashCheck):
    // take nothing, so nothing has to come back.
    if (check.deducted > 0 && isRefundStatus(order)) {
      check.deducted = 0;
      check.note = "order_cancelled_before_check";
    }

    tx.update(orderRef, {
      cashCheck: { ...check, checkedAt: FieldValue.serverTimestamp(), eventId },
    });

    if (check.deducted > 0) {
      tx.set(userRef, {
        points: FieldValue.increment(-check.deducted),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("wallet_logs").doc(redeemLogId(orderId)), {
        userId: uid,
        type: "cash_redeem",
        direction: "debit",
        amount: check.deducted,
        source: "order",
        orderId,
        note: "Cash used on order",
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return { ok: check.ok, reason: check.reason, deducted: check.deducted, totalOk: check.totalOk };
  });
}

async function onOrderUpdated({ orderId, before, after, eventId, deps }) {
  // Only the moment the order becomes cancelled / returned.
  if (!isRefundStatus(after) || isRefundStatus(before)) return { skipped: "no refund status change" };
  const { db, FieldValue } = deps;
  const orderRef = db.collection("orders").doc(orderId);
  const logRef = db.collection("wallet_logs").doc(refundLogId(orderId));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return { skipped: "order missing" };
    const order = snap.data();
    const due = refundDue(order.cashCheck);
    if (!due) return { skipped: "nothing to refund" };
    const log = await tx.get(logRef);
    if (log.exists) return { skipped: "already refunded" };
    const uid = userIdOf(order);
    if (!uid) return { skipped: "no user" };

    tx.set(db.collection("users").doc(uid), {
      points: FieldValue.increment(due),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(logRef, {
      userId: uid,
      type: "cash_refund",
      direction: "credit",
      amount: due,
      source: "order",
      orderId,
      note: "Cash returned (order cancelled / returned)",
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, {
      "cashCheck.refunded": true,
      "cashCheck.refundedAmount": due,
      "cashCheck.refundedAt": FieldValue.serverTimestamp(),
      "cashCheck.refundEventId": eventId,
    });
    return { refunded: due };
  });
}

module.exports = { onOrderCreated, onOrderUpdated };
