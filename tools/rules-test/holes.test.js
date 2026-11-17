'use strict';

// The holes found in the 2026-11-17 audit. With the live rules copy
// (RULES_FILE=docs/security/rules-backup/...) every attack here SUCCEEDS,
// which proves the hole. With the new firestore.rules every one is DENIED.
// Exception: "vendors readable without login" stays open until step B.

const { test, beforeEach } = require('node:test');
const { db, allowed, denied, SERVER_TS } = require('./emu');
const { resetWorld, OLD_RULES, KEEP_SECRETS } = require('./fixtures');

const expectHole = OLD_RULES ? allowed : denied;
const label = OLD_RULES ? '[OLD rules: hole open]' : '[NEW rules: closed]';

beforeEach(resetWorld);

// The rollback file keeps app_secrets locked even on the old rules.
const expectSecretsHole = KEEP_SECRETS ? denied : expectHole;
const secretsLabel = KEEP_SECRETS ? '[ROLLBACK rules: tokens stay locked]' : label;

test(`${secretsLabel} no login: read the social media tokens doc`, async () => {
  expectSecretsHole(await db(null).get('settings/app_secrets'));
});

test(`${secretsLabel} customer: read the social media tokens doc`, async () => {
  expectSecretsHole(await db('cust1').get('settings/app_secrets'));
});

test(`${label} no login: read doctor appointments (patient data)`, async () => {
  expectHole(await db(null).get('doctor_appointments/a1'));
});

test(`${label} another customer reads someone else's order`, async () => {
  expectHole(await db('cust2').get('orders/o1'));
});

test(`${label} another customer lists every order`, async () => {
  expectHole(await db('cust2').query('orders'));
});

test(`${label} another customer changes someone else's order`, async () => {
  expectHole(await db('cust2').update('orders/o1', { status: 'cancelled', grandTotal: 0 }));
});

test(`${label} customer marks own order delivered`, async () => {
  expectHole(await db('cust1').update('orders/o1', { status: 'delivered' }));
});

test(`${label} customer creates an order for someone else`, async () => {
  expectHole(await db('cust1').create('orders/fake', { userId: 'cust2', status: 'pending', grandTotal: 1 }));
});

test(`${label} customer writes a delivery earning with any amount`, async () => {
  expectHole(await db('cust1').set('deliveryEarnings/cust1_x', {
    deliveryPartnerId: 'cust1', orderId: 'x', amount: 99999, status: 'pending',
  }));
});

test(`${label} rider writes an earning for an undelivered order`, async () => {
  expectHole(await db('rider1').set('deliveryEarnings/rider1_o1', {
    deliveryPartnerId: 'rider1', orderId: 'o1', amount: 60, deliveryCharge: 60, grandTotal: 500,
    paymentMethod: 'cod', status: 'pending', partnerSynced: false,
  }));
});

test(`${label} rider raises own totalEarning directly`, async () => {
  expectHole(await db('rider1').update('deliveryPartners/rider1', { totalEarning: 99999 }));
});

test(`${label} rider clears own COD due`, async () => {
  // rider1 starts with codDue 500 (cash collected, not yet handed in).
  expectHole(await db('rider1').update('deliveryPartners/rider1', { codDue: 0, updatedAt: SERVER_TS }));
});

test(`${label} pending rider approves themselves`, async () => {
  expectHole(await db('rider2').update('deliveryPartners/rider2', { status: 'approved', isActive: true }));
});

test(`${label} customer reads a rider's NID details`, async () => {
  expectHole(await db('cust1').get('deliveryPartners/rider1'));
});

test(`${label} customer lists all earnings`, async () => {
  expectHole(await db('cust1').query('deliveryEarnings'));
});

test(`${label} vendor 2 asks to withdraw vendor 1's money`, async () => {
  expectHole(await db('vendU2').create('vendorWithdrawRequests/evil', {
    vendorId: 'vend1', vendorOwnerId: 'vendU2', amount: 5000, status: 'pending',
  }));
});

test(`${label} customer lists every withdraw request (payout accounts)`, async () => {
  expectHole(await db('cust1').query('vendorWithdrawRequests'));
});

test(`${secretsLabel} analytics staff reads the tokens doc via the catch-all`, async () => {
  // Old rules: allowed through the public settings rule anyway.
  expectSecretsHole(await db('analyst').get('settings/app_secrets'));
});

test('[both] vendors are still readable without login (closed in step B)', async () => {
  allowed(await db(null).get('vendors/vend1'));
});

