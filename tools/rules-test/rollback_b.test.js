'use strict';

// Only with RULES_FILE=docs/security/rules-backup/firestore.rules.rollback-step-b:
// after a rollback, the data moved by step B (NID, phone, payout account,
// balances) must stay unreadable from the app, for every role.

const { describe, test, beforeEach } = require('node:test');
const { db, allowed, denied } = require('./emu');
const { resetWorld, STEP_B_ROLLBACK } = require('./fixtures');

const opts = { skip: STEP_B_ROLLBACK ? false : 'only for firestore.rules.rollback-step-b' };

beforeEach(resetWorld);

const everyone = [null, 'cust1', 'vendU1', 'vendU2', 'rider1', 'rider3',
  'analyst', 'assignStaff', 'riderStaff', 'vendStaff', 'payStaff', 'admin', 'boss'];

describe('step B rollback: private halves closed', opts, () => {
  test('vendor_private: nobody reads or writes (owner, staff, admin, superAdmin included)', async () => {
    for (const who of everyone) {
      denied(await db(who).get('vendor_private/vend1'), `get as ${who}`);
      denied(await db(who).query('vendor_private'), `list as ${who}`);
      denied(await db(who).set('vendor_private/vend1', { phone: 'x' }, { merge: true }), `write as ${who}`);
    }
  });
  test('delivery_partner_private (NID): nobody reads or writes', async () => {
    for (const who of everyone) {
      denied(await db(who).get('delivery_partner_private/rider1'), `get as ${who}`);
      denied(await db(who).query('delivery_partner_private'), `list as ${who}`);
      denied(await db(who).set('delivery_partner_private/rider1', { nidNumber: '1' }, { merge: true }), `write as ${who}`);
    }
  });
  test('catch-all no longer gives analytics / plain staff the payout requests', async () => {
    for (const who of ['analyst', 'assignStaff', 'riderStaff']) {
      denied(await db(who).get('vendorWithdrawRequests/w1'), `get as ${who}`);
      denied(await db(who).query('vendorWithdrawRequests'), `list as ${who}`);
    }
    // Vendor managers keep their own access.
    allowed(await db('vendStaff').get('vendorWithdrawRequests/w1'));
  });
  test('the pre-step-B behaviour is back: public vendor doc readable, shop works', async () => {
    allowed(await db(null).get('vendors/vend2'));
    allowed(await db('rider1').get('deliveryPartners/rider1'));
  });
});
