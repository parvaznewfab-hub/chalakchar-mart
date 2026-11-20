'use strict';

// New firestore.rules: for every changed rule, at least one "can" and one
// "cannot", across no login / other customer / self / other vendor / rider /
// admin. Each flow mirrors what the app code really sends (file refs below).
// Skipped when RULES_FILE points at the old live copy.

const { describe, test, beforeEach } = require('node:test');
const { db, allowed, denied, SERVER_TS, inc, setOp, updateOp, createOp } = require('./emu');
const { resetWorld, OLD_RULES } = require('./fixtures');

const opts = { skip: OLD_RULES ? 'new-rules suite (RULES_FILE is the old copy)' : false };

beforeEach(resetWorld);

describe('settings', opts, () => {
  test('no login: can read public settings/app (cart delivery charge, footer)', async () => {
    const r = allowed(await db(null).get('settings/app'));
    if (r.data.socialApi.facebookPageAccessToken) throw new Error('token leaked');
  });
  test('no login / customer / admin without settings.edit / analytics staff: cannot read app_secrets', async () => {
    denied(await db(null).get('settings/app_secrets'));
    denied(await db('cust1').get('settings/app_secrets'));
    denied(await db('admin').get('settings/app_secrets'));
    denied(await db('analyst').get('settings/app_secrets'));
  });
  test('superAdmin: can read and write app_secrets', async () => {
    allowed(await db('boss').get('settings/app_secrets'));
    allowed(await db('boss').set('settings/app_secrets', { socialApi: { whatsappAccessToken: 'NEW' } }, { merge: true }));
  });
  test('customer / admin without settings.edit: cannot write app_secrets', async () => {
    denied(await db('cust1').set('settings/app_secrets', { socialApi: { x: '1' } }));
    denied(await db('admin').set('settings/app_secrets', { socialApi: { x: '1' } }));
  });
  test('superAdmin: can save settings/app with secret fields empty (older admin build)', async () => {
    allowed(await db('boss').set('settings/app', {
      socialApi: { facebookPageId: '123', facebookPageAccessToken: '', whatsappAccessToken: '' },
      updatedAt: SERVER_TS,
    }, { merge: true }));
  });
  test('superAdmin: cannot put a token back into public settings/app', async () => {
    denied(await db('boss').set('settings/app', {
      socialApi: { facebookPageId: '123', facebookPageAccessToken: 'LEAK' },
    }, { merge: true }));
  });
  test('before the move: superAdmin can still save a logo while an old token sits in settings/app', async () => {
    const { seed } = require('./emu');
    await seed({ 'settings/app': { socialApi: { facebookPageId: '1', whatsappAccessToken: 'OLD' } } });
    allowed(await db('boss').set('settings/app', { logoUrl: 'x', updatedAt: SERVER_TS }, { merge: true }));
    // re-sending the same old value (older admin build) is fine; changing it is not
    allowed(await db('boss').set('settings/app', { socialApi: { whatsappAccessToken: 'OLD' } }, { merge: true }));
    denied(await db('boss').set('settings/app', { socialApi: { whatsappAccessToken: 'CHANGED' } }, { merge: true }));
  });
  test('customer: cannot write settings/app', async () => {
    denied(await db('cust1').update('settings/app', { deliveryCharge: 0 }));
  });
});

describe('doctor_appointments (closed)', opts, () => {
  test('nobody but the server: not even superAdmin through the app', async () => {
    denied(await db(null).get('doctor_appointments/a1'));
    denied(await db('cust1').get('doctor_appointments/a1'));
    denied(await db('cust1').create('doctor_appointments/n', { userId: 'cust1', bookedByUserId: 'cust1' }));
    denied(await db('boss').get('doctor_appointments/a1'));
  });
});

describe('orders: customer', opts, () => {
  const order = {
    userId: 'cust1', status: 'pending', paymentMethod: 'COD', paymentStatus: 'unpaid',
    vendorIds: [], grandTotal: 100, items: [], createdAt: SERVER_TS, updatedAt: SERVER_TS,
  };
  test('can place own pending order (cart_page.dart:550)', async () => {
    allowed(await db('cust1').create('orders/new1', order));
  });
  test('no login: cannot place or read orders', async () => {
    denied(await db(null).create('orders/new1', order));
    denied(await db(null).get('orders/o1'));
  });
  test('cannot place an order already confirmed', async () => {
    denied(await db('cust1').create('orders/new1', { ...order, status: 'confirmed' }));
  });
  test('can read own order and own order list (user_order_page.dart:75, tracking page)', async () => {
    allowed(await db('cust1').get('orders/o1'));
    const r = allowed(await db('cust1').query('orders', [['userId', '==', 'cust1']]));
    if (r.docs.length !== 3) throw new Error(`expected 3 own orders, got ${r.docs.length}`);
  });
  test("cannot read another customer's order or list theirs", async () => {
    denied(await db('cust1').get('orders/o2'));
    denied(await db('cust1').query('orders', [['userId', '==', 'cust2']]));
  });
  test('can cancel own pending order (user_order_page.dart:660)', async () => {
    allowed(await db('cust1').update('orders/o1', {
      status: 'cancelled', cancelledBy: 'customer', cancelledAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
  });
  test('cannot cancel a confirmed order', async () => {
    denied(await db('cust1').update('orders/o3', {
      status: 'cancelled', cancelledBy: 'customer', cancelledAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
  });
  test('cannot change price or anything else while cancelling', async () => {
    denied(await db('cust1').update('orders/o1', {
      status: 'cancelled', cancelledBy: 'customer', grandTotal: 1, updatedAt: SERVER_TS,
    }));
  });
  test("cannot cancel someone else's order", async () => {
    denied(await db('cust2').update('orders/o1', {
      status: 'cancelled', cancelledBy: 'customer', cancelledAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
  });
});

describe('orders: vendor', opts, () => {
  test('can list orders with own items (vendor_orders_page.dart:208)', async () => {
    const r = allowed(await db('vendU1').query('orders', [['vendorIds', 'array-contains', 'vend1']]));
    if (r.docs.length !== 1) throw new Error(`expected 1, got ${r.docs.length}`);
    allowed(await db('vendU1').get('orders/o1'));
  });
  test("cannot read another vendor's orders", async () => {
    denied(await db('vendU1').get('orders/o2'));
    denied(await db('vendU1').query('orders', [['vendorIds', 'array-contains', 'vend2']]));
  });
  test('can confirm own part (vendor_orders_page.dart:142)', async () => {
    allowed(await db('vendU1').update('orders/o1', {
      'vendorStatusUpdates.vend1.status': 'confirmed',
      'vendorStatusUpdates.vend1.updatedAt': SERVER_TS,
      vendorStatus: 'confirmed',
      updatedAt: SERVER_TS,
    }));
  });
  test('cannot change order status, price, or another vendor entry', async () => {
    denied(await db('vendU1').update('orders/o1', { status: 'delivered' }));
    denied(await db('vendU1').update('orders/o1', { vendorStatus: 'confirmed', grandTotal: 1 }));
    denied(await db('vendU1').update('orders/o1', {
      'vendorStatusUpdates.vend2.status': 'confirmed', vendorStatus: 'confirmed',
    }));
  });
  test("other vendor cannot touch vendor 1's order", async () => {
    denied(await db('vendU2').update('orders/o1', {
      'vendorStatusUpdates.vend2.status': 'confirmed', vendorStatus: 'confirmed', updatedAt: SERVER_TS,
    }));
  });
});

describe('orders + earnings + partner: rider', opts, () => {
  const step = (s, extra = {}) => ({
    deliveryStatus: s, status: s, updatedAt: SERVER_TS, [`deliveryTimeline.${s}`]: SERVER_TS, ...extra,
  });
  test('can list and read assigned orders only (delivery_partner_dashboard_page.dart:337)', async () => {
    allowed(await db('rider1').query('orders', [['deliveryPartnerId', '==', 'rider1']]));
    allowed(await db('rider1').query('orders', [
      ['deliveryPartnerId', '==', 'rider1'], ['deliveryStatus', 'in', ['assigned', 'picked_up', 'on_the_way']],
    ]));
    allowed(await db('rider1').get('orders/o1'));
    denied(await db('rider1').get('orders/o2'));
    denied(await db('rider1').query('orders'));
  });
  // The app does NOT use a batch or transaction for "delivered": it sends
  // these separate writes one after another (delivery_partner_dashboard_page.dart):
  //   1. orders/{id}.update(...)                     :131  (_updateDeliveryStatus)
  //   2. deliveryEarnings/{rider_order}.get()         :167  (_createEarning)
  //   3. deliveryEarnings/{rider_order}.set(merge)    :178
  //   4. deliveryPartners/{rider}.set(increments, merge) :207
  //   5. deliveryEarnings/{rider_order}.set({partnerSynced:true}, merge) :210
  // The "Sync earning" button (:216, _syncEarning) re-runs steps 2-5.
  const earningDoc = (orderId, amount, grandTotal, paymentMethod = 'cod') => ({
    deliveryPartnerId: 'rider1', orderId, amount, paymentMethod, status: 'pending',
    grandTotal, deliveryCharge: amount, partnerSynced: false, createdAt: SERVER_TS, updatedAt: SERVER_TS,
  });
  const totals = (orderId, earning, cod) => ({
    totalDeliveries: inc(1), totalEarning: inc(earning), ...(cod === null ? {} : { codDue: inc(cod) }),
    updatedAt: SERVER_TS, lastEarningSyncedAt: SERVER_TS, lastSyncedOrderId: orderId,
  });

  test('app write order 1-5 for a COD order, totals wrong in each way are refused', async () => {
    const r = db('rider1');
    allowed(await r.update('orders/o1', step('picked_up', { pickedUpAt: SERVER_TS })));
    allowed(await r.update('orders/o1', step('on_the_way', { onTheWayAt: SERVER_TS })));
    allowed(await r.update('orders/o1', step('delivered', { paymentStatus: 'paid', deliveredAt: SERVER_TS })), '1 delivered');
    if ((await r.get('deliveryEarnings/rider1_o1')).status !== 404) throw new Error('2: expected 404');
    allowed(await r.set('deliveryEarnings/rider1_o1', earningDoc('o1', 60, 500), { merge: true }), '3 earning');
    // 4 with wrong numbers
    denied(await r.set('deliveryPartners/rider1', totals('o1', 600, 500), { merge: true }), 'earning x10');
    denied(await r.set('deliveryPartners/rider1', totals('o1', 60, 0), { merge: true }), 'COD not added');
    denied(await r.set('deliveryPartners/rider1', totals('o1', 60, 50), { merge: true }), 'COD too small');
    denied(await r.set('deliveryPartners/rider1', { ...totals('o1', 60, 500), totalDeliveries: inc(2) }, { merge: true }), '2 deliveries');
    denied(await r.set('deliveryPartners/rider1', { ...totals('o1', 60, 500), withdrawnAmount: 9999 }, { merge: true }), 'extra money field');
    // 4 right, then 5
    allowed(await r.set('deliveryPartners/rider1', totals('o1', 60, 500), { merge: true }), '4 totals');
    allowed(await r.set('deliveryEarnings/rider1_o1', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }), '5 synced');
    const after = allowed(await r.get('deliveryPartners/rider1')).data;
    if (after.totalEarning !== 180 || after.codDue !== 1000 || after.totalDeliveries !== 3) {
      throw new Error(`totals wrong: ${JSON.stringify(after)}`);
    }
  });

  test('non-COD order: COD due must stay the same', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o5', earningDoc('o5', 80, 700, 'online'), { merge: true }));
    denied(await r.set('deliveryPartners/rider1', totals('o5', 80, 700), { merge: true }));
    allowed(await r.set('deliveryPartners/rider1', totals('o5', 80, null), { merge: true }));
  });

  test("another approved rider cannot record, sync or move rider 1's orders", async () => {
    const r3 = db('rider3');
    denied(await r3.set('deliveryEarnings/rider3_o4', { ...earningDoc('o4', 60, 500), deliveryPartnerId: 'rider3' }, { merge: true }), 'own id');
    denied(await r3.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }), "rider1's id");
    denied(await r3.set('deliveryPartners/rider3', totals('o4', 60, 500), { merge: true }), 'totals from o4');
    denied(await r3.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true }), "rider1's totals");
    denied(await r3.update('orders/o1', step('picked_up')), "rider1's order");
    denied(await r3.get('orders/o4'), 'read');
    denied(await r3.get('deliveryEarnings/rider1_old'), 'read earning');
  });

  // "Sync earning" (_syncEarning -> _createEarning) as the app runs it:
  //   2 get earning; stop if partnerSynced == true
  //   3 set earning (re-sends old createdAt); 4 add totals; 5 mark synced.
  // Any denied write throws and the app stops there.
  async function appSync(r, orderId, amount, grandTotal) {
    const g = await r.get(`deliveryEarnings/rider1_${orderId}`);
    if (g.status === 200 && g.data.partnerSynced === true) return 'already synced';
    const createdAt = g.status === 200 ? g.data.createdAt : SERVER_TS;
    const s3 = await r.set(`deliveryEarnings/rider1_${orderId}`, { ...earningDoc(orderId, amount, grandTotal), createdAt }, { merge: true });
    if (s3.status !== 200) return 'stopped at 3';
    const s4 = await r.set('deliveryPartners/rider1', totals(orderId, amount, grandTotal), { merge: true });
    if (s4.status !== 200) return 'stopped at 4';
    const s5 = await r.set(`deliveryEarnings/rider1_${orderId}`, { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true });
    return s5.status === 200 ? 'synced' : 'stopped at 5';
  }
  const money = async (r) => {
    const d = allowed(await r.get('deliveryPartners/rider1')).data;
    return { n: d.totalDeliveries, earning: d.totalEarning, cod: d.codDue };
  };
  const start = { n: 2, earning: 120, cod: 500 };

  test('network lost after step 4 (5 never sent), then "Sync earning": totals NOT added twice', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }), '3');
    allowed(await r.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true }), '4');
    // 5 lost.
    const once = { n: 3, earning: 180, cod: 1000 };
    if (JSON.stringify(await money(r)) !== JSON.stringify(once)) throw new Error('after 4');
    const result = await appSync(r, 'o4', 60, 500);
    if (JSON.stringify(await money(r)) !== JSON.stringify(once)) throw new Error(`added twice: ${JSON.stringify(await money(r))}`);
    // Known app limitation (see docs/plans): the app does not skip step 4 when
    // it was already done, so it stops at 4 and never sets the mark.
    if (result !== 'stopped at 4') throw new Error(`unexpected: ${result}`);
    if (allowed(await r.get('deliveryEarnings/rider1_o4')).data.partnerSynced !== false) throw new Error('mark');
    // Setting the mark directly (what a fixed app would do) is allowed:
    allowed(await r.set('deliveryEarnings/rider1_o4', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
    if ((await appSync(r, 'o4', 60, 500)) !== 'already synced') throw new Error('after mark');
  });

  test('network lost after step 3 (4 and 5 never sent), then "Sync earning": added exactly once and marked', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }), '3');
    if (JSON.stringify(await money(r)) !== JSON.stringify(start)) throw new Error('before');
    if ((await appSync(r, 'o4', 60, 500)) !== 'synced') throw new Error('sync did not finish');
    if (JSON.stringify(await money(r)) !== JSON.stringify({ n: 3, earning: 180, cod: 1000 })) throw new Error('not once');
    if (allowed(await r.get('deliveryEarnings/rider1_o4')).data.partnerSynced !== true) throw new Error('mark');
    if ((await appSync(r, 'o4', 60, 500)) !== 'already synced') throw new Error('third press');
    if (JSON.stringify(await money(r)) !== JSON.stringify({ n: 3, earning: 180, cod: 1000 })) throw new Error('third press added');
  });

  test('step 5 lost on order A, another delivery B synced, then "Sync earning" on A', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }));
    allowed(await r.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true })); // A counted, 5 lost
    // B (o5, not COD) delivered and synced normally
    allowed(await r.set('deliveryEarnings/rider1_o5', earningDoc('o5', 80, 700, 'online'), { merge: true }));
    allowed(await r.set('deliveryPartners/rider1', totals('o5', 80, null), { merge: true }));
    allowed(await r.set('deliveryEarnings/rider1_o5', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
    const before = await money(r);
    await appSync(r, 'o4', 60, 500);
    const after = await money(r);
    if (JSON.stringify(before) !== JSON.stringify(after)) {
      throw new Error(`A added twice: ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    }
  });

  test('trade-off: step 4 lost on A, another delivery B synced, then sync A -> A is NOT added, but stays visibly unsynced', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true })); // A: 3 only
    allowed(await r.set('deliveryEarnings/rider1_o5', earningDoc('o5', 80, 700, 'online'), { merge: true }));
    allowed(await r.set('deliveryPartners/rider1', totals('o5', 80, null), { merge: true }));
    allowed(await r.set('deliveryEarnings/rider1_o5', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
    const before = await money(r);
    if ((await appSync(r, 'o4', 60, 500)) !== 'stopped at 4') throw new Error('expected refusal');
    if (JSON.stringify(await money(r)) !== JSON.stringify(before)) throw new Error('changed');
    // Under-count, not double count: admin can find it (partnerSynced == false).
    if (allowed(await r.get('deliveryEarnings/rider1_o4')).data.partnerSynced !== false) throw new Error('not visible');
  });

  test('earning createdAt must be server time; totals must stamp server time', async () => {
    const r = db('rider1');
    denied(await r.set('deliveryEarnings/rider1_o4', { ...earningDoc('o4', 60, 500), createdAt: new Date('2030-01-01') }), 'future createdAt');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }));
    denied(await r.set('deliveryPartners/rider1', { ...totals('o4', 60, 500), lastEarningSyncedAt: new Date('2000-01-01') }, { merge: true }), 'old stamp');
  });

  test('writing the same earning twice: totals once only, amount cannot change', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryEarnings/rider1_o4', earningDoc('o4', 60, 500), { merge: true }));
    // "Sync earning" pressed again before step 5: step 3 again is a no-op, allowed
    // (the app re-sends the old createdAt it just read: dashboard:189-191)
    const old = allowed(await r.get('deliveryEarnings/rider1_o4')).data;
    allowed(await r.set('deliveryEarnings/rider1_o4', { ...earningDoc('o4', 60, 500), createdAt: old.createdAt }, { merge: true }));
    denied(await r.set('deliveryEarnings/rider1_o4', { amount: 600, deliveryCharge: 600 }, { merge: true }), 'raise amount');
    allowed(await r.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true }), 'first totals');
    allowed(await r.set('deliveryEarnings/rider1_o4', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
    // Sync pressed again after it completed
    denied(await r.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true }), 'same order again');
    // ...or alternating with another order to dodge the "same as last" check
    allowed(await r.set('deliveryEarnings/rider1_o5', earningDoc('o5', 80, 700, 'online'), { merge: true }));
    allowed(await r.set('deliveryPartners/rider1', totals('o5', 80, null), { merge: true }));
    allowed(await r.set('deliveryEarnings/rider1_o5', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
    denied(await r.set('deliveryPartners/rider1', totals('o4', 60, 500), { merge: true }), 'o4 again after o5');
  });

  test('pending applicant rider cannot read assigned orders', async () => {
    denied(await db('rider2').query('orders', [['deliveryPartnerId', '==', 'rider2']]));
  });
  test('full delivery: picked_up -> on_the_way -> delivered -> earning -> totals (dashboard:79-214)', async () => {
    const r = db('rider1');
    allowed(await r.update('orders/o1', step('picked_up', { pickedUpAt: SERVER_TS })), 'picked_up');
    allowed(await r.update('orders/o1', step('on_the_way', { onTheWayAt: SERVER_TS })), 'on_the_way');
    allowed(await r.update('orders/o1', step('delivered', { paymentStatus: 'paid', deliveredAt: SERVER_TS })), 'delivered');
    // earning doc read before it exists
    const g = await r.get('deliveryEarnings/rider1_o1');
    if (g.status !== 404) throw new Error(`expected 404 for missing own earning, got ${g.status}`);
    allowed(await r.set('deliveryEarnings/rider1_o1', {
      deliveryPartnerId: 'rider1', orderId: 'o1', amount: 60, paymentMethod: 'cod', status: 'pending',
      grandTotal: 500, deliveryCharge: 60, partnerSynced: false, createdAt: SERVER_TS, updatedAt: SERVER_TS,
    }, { merge: true }), 'earning create');
    allowed(await r.set('deliveryPartners/rider1', {
      totalDeliveries: inc(1), totalEarning: inc(60), codDue: inc(500),
      updatedAt: SERVER_TS, lastEarningSyncedAt: SERVER_TS, lastSyncedOrderId: 'o1',
    }, { merge: true }), 'partner totals');
    allowed(await r.set('deliveryEarnings/rider1_o1', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }), 'mark synced');
    // Replaying the totals step for the same delivery is refused.
    denied(await r.set('deliveryPartners/rider1', {
      totalDeliveries: inc(1), totalEarning: inc(60), codDue: inc(500),
      updatedAt: SERVER_TS, lastEarningSyncedAt: SERVER_TS, lastSyncedOrderId: 'o1',
    }, { merge: true }), 'replay totals');
    denied(await r.set('deliveryEarnings/rider1_o1', { partnerSynced: false }, { merge: true }), 'unsync');
  });
  test('cannot skip a step, go backward, or change the price', async () => {
    const r = db('rider1');
    denied(await r.update('orders/o1', step('delivered', { paymentStatus: 'paid' })));
    denied(await r.update('orders/o1', { ...step('picked_up'), grandTotal: 1 }));
    denied(await r.update('orders/o4', step('on_the_way')));
  });
  test("other customer's order not assigned: rider cannot update it", async () => {
    denied(await db('rider1').update('orders/o2', step('picked_up')));
  });
  test('earning: wrong amount or undelivered order is refused', async () => {
    const base = {
      deliveryPartnerId: 'rider1', paymentMethod: 'cod', status: 'pending',
      partnerSynced: false, createdAt: SERVER_TS, updatedAt: SERVER_TS,
    };
    denied(await db('rider1').set('deliveryEarnings/rider1_o4',
      { ...base, orderId: 'o4', amount: 999, deliveryCharge: 999, grandTotal: 500 }));
    denied(await db('rider1').set('deliveryEarnings/rider1_o1',
      { ...base, orderId: 'o1', amount: 60, deliveryCharge: 60, grandTotal: 500 }));
    allowed(await db('rider1').set('deliveryEarnings/rider1_o4',
      { ...base, orderId: 'o4', amount: 60, deliveryCharge: 60, grandTotal: 500 }));
  });
  test('earnings: rider reads own, not others; customer none; admin all', async () => {
    allowed(await db('rider1').get('deliveryEarnings/rider1_old'));
    allowed(await db('rider1').query('deliveryEarnings', [['deliveryPartnerId', '==', 'rider1']]));
    denied(await db('rider2').get('deliveryEarnings/rider1_old'));
    denied(await db('cust1').query('deliveryEarnings'));
    allowed(await db('admin').query('deliveryEarnings'));
  });
  test('withdraw request batch works (dashboard:265-279); inflated pending amount refused', async () => {
    const ok = [
      createOp('deliveryWithdraws/dw1', {
        deliveryPartnerId: 'rider1', amount: 100, status: 'pending', createdAt: SERVER_TS, updatedAt: SERVER_TS,
      }),
      setOp('deliveryPartners/rider1', { pendingAmount: inc(100), lastWithdrawRequestId: 'dw1', updatedAt: SERVER_TS }, { merge: true }),
    ];
    allowed(await db('rider1').batch(ok));
    const bad = [
      createOp('deliveryWithdraws/dw2', {
        deliveryPartnerId: 'rider1', amount: 100, status: 'pending', createdAt: SERVER_TS, updatedAt: SERVER_TS,
      }),
      setOp('deliveryPartners/rider1', { pendingAmount: inc(5000), lastWithdrawRequestId: 'dw2', updatedAt: SERVER_TS }, { merge: true }),
    ];
    denied(await db('rider1').batch(bad));
  });
});

describe('deliveryPartners', opts, () => {
  test('rider reads own doc (main.dart:261); others cannot', async () => {
    allowed(await db('rider1').get('deliveryPartners/rider1'));
    allowed(await db('rider2').get('deliveryPartners/rider2'));
    denied(await db('rider2').get('deliveryPartners/rider1'));
    denied(await db('cust1').get('deliveryPartners/rider1'));
    denied(await db('cust1').query('deliveryPartners'));
    denied(await db(null).get('deliveryPartners/rider1'));
  });
  test('a user without a rider doc can check for it (main.dart:261)', async () => {
    const r = await db('cust1').get('deliveryPartners/cust1');
    if (r.status !== 404) throw new Error(`expected 404, got ${r.status}`);
  });
  test('apply: pending/inactive allowed (delivery_partner_apply_page.dart:177); self-approved refused', async () => {
    // Step B: NID goes to delivery_partner_private, not here (see step_b.test.js).
    const app = {
      uid: 'cust1', name: 'C', phone: '0', status: 'pending', isActive: false,
      totalDeliveries: 0, totalEarning: 0, withdrawnAmount: 0, pendingAmount: 0, codDue: 0,
      createdAt: SERVER_TS,
    };
    denied(await db('cust1').set('deliveryPartners/cust1', { ...app, status: 'approved', isActive: true }));
    denied(await db('cust1').set('deliveryPartners/cust1', { ...app, totalEarning: 5000 }));
    allowed(await db('cust1').set('deliveryPartners/cust1', app));
    denied(await db('cust2').set('deliveryPartners/cust1', app));
  });
  test('rider may edit harmless profile fields but not NID or approval', async () => {
    allowed(await db('rider1').update('deliveryPartners/rider1', { preferredArea: 'Sadar', updatedAt: SERVER_TS }));
    denied(await db('rider1').update('deliveryPartners/rider1', { nidNumber: '999' }));
    denied(await db('rider1').update('deliveryPartners/rider1', { isActive: false, status: 'blocked' }));
  });
  test('admin reads all and approves; analytics staff reads', async () => {
    allowed(await db('admin').query('deliveryPartners'));
    allowed(await db('admin').update('deliveryPartners/rider2', { status: 'approved', isActive: true, approvedAt: SERVER_TS }));
    allowed(await db('analyst').get('deliveryPartners/rider1'));
  });
});

describe('vendorWithdrawRequests', opts, () => {
  const req = {
    // Step B: no vendorEmail/vendorPhone copies any more (see step_b.test.js).
    vendorId: 'vend1', vendorOwnerId: 'vendU1', vendorName: 'Shop One',
    amount: 200, status: 'pending', note: '', payoutAccount: 'bkash', createdAt: SERVER_TS, updatedAt: SERVER_TS,
  };
  test('vendor can request for own vendor (vendor_withdraw_page.dart:197)', async () => {
    allowed(await db('vendU1').create('vendorWithdrawRequests/n1', req));
  });
  test('vendor cannot request for another vendor, as someone else, approved, or a silly amount', async () => {
    denied(await db('vendU2').create('vendorWithdrawRequests/n1', { ...req, vendorOwnerId: 'vendU2' }));
    denied(await db('vendU2').create('vendorWithdrawRequests/n1', req));
    denied(await db('vendU1').create('vendorWithdrawRequests/n1', { ...req, status: 'approved' }));
    denied(await db('vendU1').create('vendorWithdrawRequests/n1', { ...req, amount: -5 }));
    denied(await db('cust1').create('vendorWithdrawRequests/n1', { ...req, vendorId: 'cust1', vendorOwnerId: 'cust1' }));
  });
  test('vendor reads own history both ways the app queries it (vendor_withdraw_page.dart:186,269)', async () => {
    allowed(await db('vendU1').query('vendorWithdrawRequests', [['vendorOwnerId', '==', 'vendU1']]));
    allowed(await db('vendU1').query('vendorWithdrawRequests', [['vendorId', '==', 'vend1'], ['status', '==', 'pending']]));
    allowed(await db('vendU1').get('vendorWithdrawRequests/w1'));
  });
  test('other vendor / customer / no login cannot read it', async () => {
    denied(await db('vendU2').get('vendorWithdrawRequests/w1'));
    denied(await db('vendU2').query('vendorWithdrawRequests', [['vendorId', '==', 'vend1']]));
    denied(await db('cust1').query('vendorWithdrawRequests'));
    denied(await db(null).get('vendorWithdrawRequests/w1'));
  });
  test('vendor cannot change amount or approve; admin can', async () => {
    denied(await db('vendU1').update('vendorWithdrawRequests/w1', { amount: 9999 }));
    denied(await db('vendU1').update('vendorWithdrawRequests/w1', { status: 'approved' }));
    allowed(await db('admin').query('vendorWithdrawRequests'));
    allowed(await db('admin').update('vendorWithdrawRequests/w1', { status: 'approved', updatedAt: SERVER_TS }));
  });
});

describe('orders: admin', opts, () => {
  test('admin reads every order and updates any', async () => {
    allowed(await db('admin').query('orders'));
    allowed(await db('admin').update('orders/o2', { status: 'confirmed', updatedAt: SERVER_TS }));
    allowed(await db('admin').create('orders/fromList', { userId: 'cust2', status: 'pending', grandTotal: 1 }));
  });
  test('analytics staff reads orders but cannot change them', async () => {
    allowed(await db('analyst').query('orders'));
    denied(await db('analyst').update('orders/o2', { status: 'confirmed' }));
  });
});

describe('vendors: public doc still readable (personal data moved out in step B)', opts, () => {
  test('shop page and product page still read the vendor without login', async () => {
    allowed(await db(null).get('vendors/vend1'));
    allowed(await db(null).query('vendors', [['isActive', '==', true]]));
  });
});


