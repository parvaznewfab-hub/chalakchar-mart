'use strict';

// 14b step G: orders.cashCheck (Cash taken from the points, order total
// check) is written only by the onOrderCreatedCash / onOrderStatusCash
// functions. A client-written cashCheck on create makes the function skip
// the order, so the Cash would be free.
//   RULES_FILE=docs/security/rules-backup/firestore.rules.live-700f57c7
//     -> the rules live before step G: the attacks SUCCEED (proof of the gap)
//   firestore.rules (step G) -> the attacks are DENIED
// The app's real order writes are allowed on both.

const { describe, test, beforeEach } = require('node:test');
const { db, seed, allowed, denied, SERVER_TS, inc } = require('./emu');
const { resetWorld, RULES_FILE, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const LIVE_BEFORE_G = /live-700f57c7/.test(RULES_FILE);
const LIVE_BEFORE_F = /live-be7e9c8a/.test(RULES_FILE);
const opts = {
  skip: OLD_RULES || STEP_B_ROLLBACK || LIVE_BEFORE_F ? 'step G suite (older rules copy)' : false,
};
const attack = LIVE_BEFORE_G ? allowed : denied;
const tag = LIVE_BEFORE_G ? '[700f57c7: gap open]' : '[step G: closed]';

const cashOrder = (extra = {}) => ({
  userId: 'cust1', status: 'pending', paymentMethod: 'COD', paymentStatus: 'unpaid',
  items: [{ productId: 'p1', qty: 1, price: 100, vendorId: 'super_admin' }],
  subtotal: 100, deliveryCharge: 60, couponDiscount: 0,
  chalakCharCashUsed: 40, paymentDiscounts: { chalakCharCashUsed: 40, couponDiscount: 0, productDiscount: 0 },
  total: 120, grandTotal: 120, finalTotal: 120, discount: 40,
  createdAt: SERVER_TS, updatedAt: SERVER_TS,
  ...extra,
});
const checked = { ok: true, deducted: 40, claimed: 40, totalOk: true, serverGrandTotal: 120 };

beforeEach(async () => {
  await resetWorld();
  await seed({
    'users/cust1': { role: 'user', roles: ['user'], isActive: true, isBanned: false, vendorId: '', points: 50 },
    // already checked by the function, Cash taken
    'orders/g1': { ...cashOrder(), cashCheck: checked, deliveryPartnerId: 'rider1', deliveryStatus: 'assigned' },
  });
});

describe('step G attacks: client-written cashCheck', opts, () => {
  test(`${tag} customer creates an order that already carries cashCheck (function would skip it)`, async () => {
    attack(await db('cust1').create('orders/new1', cashOrder({ cashCheck: { ok: true, deducted: 0 } })));
  });

  test(`${tag} staff (orders.edit) adds / changes cashCheck`, async () => {
    attack(await db('admin').update('orders/o1', { cashCheck: { ok: true, deducted: 0, totalOk: true } }), 'add');
    attack(await db('admin').update('orders/g1', { 'cashCheck.refunded': true }), 'change');
  });
});

describe('step G: what stays refused / allowed', opts, () => {
  test('customer may still not touch own points or wallet_logs (unchanged)', async () => {
    denied(await db('cust1').update('users/cust1', { points: inc(-40) }), 'points');
    denied(await db('cust1').create('wallet_logs/cash_redeem_x', { userId: 'cust1', amount: 40, direction: 'debit' }), 'wallet_logs');
  });

  test('customer places an order with Cash, as cart_page does (no cashCheck)', async () => {
    allowed(await db('cust1').create('orders/new2', cashOrder()));
  });

  test('customer cancels a pending order that has cashCheck', async () => {
    allowed(await db('cust1').update('orders/g1', {
      status: 'cancelled', cancelledBy: 'customer', cancelledAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
  });

  test('staff confirms / edits an order with cashCheck left as it is', async () => {
    allowed(await db('admin').update('orders/g1', { status: 'confirmed', updatedAt: SERVER_TS }));
    allowed(await db('admin').set('orders/g1', { adminNote: 'checked' }, { merge: true }));
  });

  test('rider moves an order with cashCheck one step', async () => {
    // as rules.test.js step(): delivery_partner_dashboard_page writes status too
    allowed(await db('rider1').update('orders/g1', {
      deliveryStatus: 'picked_up', status: 'picked_up', pickedUpAt: SERVER_TS, updatedAt: SERVER_TS,
      'deliveryTimeline.picked_up': SERVER_TS,
    }));
  });

  test('everyone with read access sees cashCheck; others do not', async () => {
    allowed(await db('cust1').get('orders/g1'));
    allowed(await db('admin').get('orders/g1'));
    denied(await db('cust2').get('orders/g1'));
  });
});
