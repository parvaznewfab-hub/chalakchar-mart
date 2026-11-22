'use strict';

// ledger-1: commission_ledger (functions only), orders.priceCheck (functions
// only), vendor_private balances (functions only, plus the payout step).
// Skipped when RULES_FILE points at an old copy or the step B rollback.

const { describe, test, beforeEach } = require('node:test');
const { db, allowed, denied, SERVER_TS } = require('./emu');
const { resetWorld, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const opts = {
  skip: OLD_RULES || STEP_B_ROLLBACK ? 'ledger-1 suite (RULES_FILE is an old copy / the step B rollback)' : false,
};

beforeEach(resetWorld);

const everyone = [null, 'cust1', 'cust2', 'vendU1', 'vendU2', 'rider1', 'analyst', 'vendStaff', 'payStaff', 'admin', 'boss'];

describe('ledger-1: commission_ledger', opts, () => {
  test('read: the vendor (own docs), vendors.view / payout staff, admins; nobody else', async () => {
    for (const who of ['vendU1', 'vendStaff', 'payStaff', 'admin', 'boss']) {
      allowed(await db(who).get('commission_ledger/o1_vend1'), `get as ${who}`);
    }
    for (const who of [null, 'cust1', 'cust2', 'vendU2', 'rider1', 'analyst']) {
      denied(await db(who).get('commission_ledger/o1_vend1'), `get as ${who}`);
    }
    // A vendor lists only their own entries.
    allowed(await db('vendU1').query('commission_ledger', [['vendorId', '==', 'vend1']]));
    denied(await db('vendU1').query('commission_ledger'));
  });

  test('write: nobody, admins and superAdmin included', async () => {
    for (const who of everyone) {
      denied(await db(who).set('commission_ledger/o1_vend1', { vendorPayable: 1e6 }, { merge: true }), `update as ${who}`);
      denied(await db(who).create('commission_ledger/new_vend1', { vendorId: 'vend1', orderId: 'new' }), `create as ${who}`);
      denied(await db(who).delete('commission_ledger/o1_vend1'), `delete as ${who}`);
    }
  });

  test('vendorCommissions (retired): nobody reads or writes', async () => {
    for (const who of everyone) {
      denied(await db(who).get('vendorCommissions/x'), `get as ${who}`);
      denied(await db(who).set('vendorCommissions/x', { a: 1 }), `write as ${who}`);
    }
  });
});

describe('ledger-1: orders.priceCheck is function-only', opts, () => {
  const order = {
    userId: 'cust1', status: 'pending', paymentMethod: 'COD', items: [], grandTotal: 100, createdAt: SERVER_TS,
  };

  test('create with priceCheck: refused for the customer and for order staff; without it: fine', async () => {
    denied(await db('cust1').create('orders/n1', { ...order, priceCheck: { ok: true } }));
    denied(await db('admin').create('orders/n2', { ...order, priceCheck: { ok: true } }));
    allowed(await db('cust1').create('orders/n3', order));
  });

  test('update: nobody adds, changes or removes priceCheck', async () => {
    // o1 gets a priceCheck the way the function would.
    allowed(await db('admin').update('orders/o1', { note: 'x' }));
    for (const who of ['admin', 'boss']) {
      denied(await db(who).update('orders/o1', { priceCheck: { ok: true } }), `add as ${who}`);
    }
    denied(await db('cust1').update('orders/o1', { status: 'cancelled', cancelledBy: 'customer', priceCheck: { ok: true } }));
    denied(await db('rider1').update('orders/o1', { deliveryStatus: 'picked_up', status: 'picked_up', priceCheck: { ok: true } }));
    // The customer's own cancel without it still works.
    allowed(await db('cust1').update('orders/o1', { status: 'cancelled', cancelledBy: 'customer', updatedAt: SERVER_TS }));
  });

  test('an existing priceCheck cannot be changed or deleted by staff', async () => {
    denied(await db('admin').update('orders/o6', { 'priceCheck.ok': true }));
    denied(await db('boss').update('orders/o6', { priceCheck: null }));
    allowed(await db('admin').update('orders/o6', { note: 'reviewed' }));
  });
});

describe('ledger-1: vendor_private balances', opts, () => {
  test('nobody writes ledger balances from the app (functions do)', async () => {
    for (const key of ['totalSales', 'totalCommission', 'pendingBalance', 'deliveredOrders', 'cancelledOrders', 'withdrawPendingBalance']) {
      for (const who of ['vendU1', 'payStaff', 'vendStaff', 'admin', 'boss']) {
        denied(await db(who).set('vendor_private/vend1', { [key]: 1 }, { merge: true }), `${key} as ${who}`);
      }
    }
  });

  test('payout step: down by exactly what is paid, more than 0, never below 0', async () => {
    // vend1: withdrawableBalance 500.
    allowed(await db('admin').update('vendor_private/vend1', { withdrawableBalance: 450, totalPaidOut: 50 }));
    denied(await db('admin').update('vendor_private/vend1', { withdrawableBalance: 400, totalPaidOut: 60 }), 'amounts differ');
    denied(await db('admin').update('vendor_private/vend1', { withdrawableBalance: 400, totalPaidOut: 100, phone: 'x' }), 'other keys');
    denied(await db('payStaff').update('vendor_private/vend1', { withdrawableBalance: -50, totalPaidOut: 550 }), 'below 0');
    denied(await db('payStaff').update('vendor_private/vend1', { withdrawableBalance: 600, totalPaidOut: -100 }), 'negative payout');
    denied(await db('vendU1').update('vendor_private/vend1', { withdrawableBalance: 400, totalPaidOut: 100 }), 'vendor');
    denied(await db('vendStaff').update('vendor_private/vend1', { withdrawableBalance: 400, totalPaidOut: 100 }), 'view-only staff');
  });

  test('a vendor in debt (balance <= 0) cannot be paid out', async () => {
    denied(await db('admin').update('vendor_private/vendDebt', { withdrawableBalance: -110, totalPaidOut: 10 }));
    denied(await db('payStaff').update('vendor_private/vendDebt', { withdrawableBalance: -101, totalPaidOut: 1 }));
    // Touching the debt any other way: also refused.
    denied(await db('boss').update('vendor_private/vendDebt', { withdrawableBalance: 0 }));
  });
});
