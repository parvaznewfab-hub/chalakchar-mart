// -----------------------------------------------------------------------------
// Order triggers for the vendor commission ledger (ledger-1). Wired up in
// functions/index.js as onOrderCreatedLedger / onOrderStatusLedger.
//
// Every write happens in ONE Firestore transaction per event, and every step
// is idempotent:
//   - creation: a ledger doc that already exists is left alone (tx.create
//     semantics, checked inside the transaction); priceCheck is written once;
//   - status change: the ledger only moves forward (pending -> delivered ->
//     cancelled/returned), so the same event delivered twice, or two events
//     racing, move the money once.
// deps: { db, FieldValue } (admin SDK in production, the emulator in tests).
// -----------------------------------------------------------------------------

const {
  HOUSE_VENDOR, priceOrder, newLedgerEntry, targetForOrder, transition, ledgerDocId,
} = require("./commissionLedger");

const LEDGER = "commission_ledger";

function increments(FieldValue, money) {
  const out = {};
  for (const [k, v] of Object.entries(money)) out[k] = FieldValue.increment(v);
  return out;
}

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

// Applies `target` to the ledger docs given (already read in tx). Writes only.
function applyTarget(tx, deps, { docs, target, eventId, vendorPrivates }) {
  const { db, FieldValue } = deps;
  let moved = 0;
  for (const { ref, data } of docs) {
    const step = transition(data, target);
    if (!step) continue;
    const vendorId = data.vendorId;
    const current = vendorPrivates[vendorId] || {};
    const withdrawableAfter = Number(current.withdrawableBalance || 0) + (step.money.withdrawableBalance || 0);
    const debt = (step.money.withdrawableBalance || 0) < 0 && withdrawableAfter < 0;
    tx.update(ref, {
      status: step.status,
      [`${step.status}At`]: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastEventId: eventId,
      appliedTransitions: FieldValue.arrayUnion(`${data.status || "pending"}->${step.status}`),
      ...(debt ? { debtCreated: true } : {}),
    });
    tx.set(db.collection("vendor_private").doc(vendorId), {
      ...increments(FieldValue, step.money),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    // Later steps in this same transaction see the new balance.
    vendorPrivates[vendorId] = { ...current, withdrawableBalance: withdrawableAfter };
    moved++;
  }
  return moved;
}

async function onOrderCreated({ orderId, eventId, deps }) {
  const { db, FieldValue } = deps;
  const orderRef = db.collection("orders").doc(orderId);
  const first = await orderRef.get();
  if (!first.exists) return { skipped: "order missing" };
  const products = await readProducts(db, first.data());

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return { skipped: "order missing" };
    const order = snap.data();
    const priced = priceOrder(order, products);
    const vendorIds = Object.keys(priced.byVendor).filter((v) => v && v !== HOUSE_VENDOR);

    // Reads first (transaction rule), then writes.
    const ledgerRefs = vendorIds.map((v) => db.collection(LEDGER).doc(ledgerDocId(orderId, v)));
    const ledgerSnaps = await Promise.all(ledgerRefs.map((r) => tx.get(r)));
    const privSnaps = await Promise.all(vendorIds.map((v) => tx.get(db.collection("vendor_private").doc(v))));
    const vendorPrivates = {};
    vendorIds.forEach((v, i) => { vendorPrivates[v] = privSnaps[i].exists ? privSnaps[i].data() : {}; });

    if (!order.priceCheck) {
      tx.update(orderRef, { priceCheck: { ...priced.priceCheck, checkedAt: FieldValue.serverTimestamp() } });
    }

    const created = [];
    vendorIds.forEach((vendorId, i) => {
      if (ledgerSnaps[i].exists) return; // already written by an earlier run
      const entry = newLedgerEntry({ orderId, vendorId, priced: priced.byVendor[vendorId], vendorPrivate: vendorPrivates[vendorId] });
      tx.set(ledgerRefs[i], {
        ...entry.ledger,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        lastEventId: eventId,
        appliedTransitions: ["created"],
      });
      tx.set(db.collection("vendor_private").doc(vendorId), {
        ...increments(FieldValue, entry.money),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("vendors").doc(vendorId), {
        totalOrders: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      created.push({ ref: ledgerRefs[i], data: entry.ledger, vendorId });
    });

    // An order that was already delivered / cancelled before this ran (the
    // status trigger found no ledger then): apply that state now.
    const target = targetForOrder({}, order);
    const moved = target ? applyTarget(tx, deps, { docs: created, target, eventId, vendorPrivates }) : 0;

    return { created: created.length, moved, priceOk: priced.priceCheck.ok };
  });
}

async function onOrderUpdated({ orderId, before, after, eventId, deps }) {
  const target = targetForOrder(before, after);
  if (!target) return { skipped: "no status change" };
  const { db } = deps;

  return db.runTransaction(async (tx) => {
    const q = await tx.get(db.collection(LEDGER).where("orderId", "==", orderId));
    if (q.empty) return { skipped: "no ledger" };
    const docs = q.docs.map((d) => ({ ref: d.ref, data: d.data() }));
    const vendorIds = [...new Set(docs.map((d) => d.data.vendorId))];
    const privSnaps = await Promise.all(vendorIds.map((v) => tx.get(db.collection("vendor_private").doc(v))));
    const vendorPrivates = {};
    vendorIds.forEach((v, i) => { vendorPrivates[v] = privSnaps[i].exists ? privSnaps[i].data() : {}; });
    const moved = applyTarget(tx, deps, { docs, target, eventId, vendorPrivates });
    return { target, moved };
  });
}

module.exports = { LEDGER, onOrderCreated, onOrderUpdated };
