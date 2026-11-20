'use strict';

// 14b step B: vendor and rider personal data in vendor_private/{vendorId}
// and delivery_partner_private/{uid}. One test per role from the step B plan.
// Skipped when RULES_FILE points at an old live copy.

const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { db, allowed, denied, SERVER_TS } = require('./emu');
const { resetWorld, OLD_RULES } = require('./fixtures');

const opts = { skip: OLD_RULES ? 'step B suite (RULES_FILE is an old copy)' : false };

beforeEach(resetWorld);

describe('step B: vendors', opts, () => {
  test('no login / customer: public vendor doc readable (shop page, cart ownerId); private denied', async () => {
    for (const who of [null, 'cust1']) {
      const r = allowed(await db(who).get('vendors/vend2'));
      assert.equal(r.data.ownerId, 'vendU2'); // cart_page.dart:503 needs it
      denied(await db(who).get('vendor_private/vend1'));
      denied(await db(who).query('vendor_private'));
      denied(await db(who).set('vendor_private/vend1', { phone: 'x' }, { merge: true }));
    }
  });

  test('other vendor / rider: cannot read or write vendor 1 private', async () => {
    for (const who of ['vendU2', 'rider1']) {
      denied(await db(who).get('vendor_private/vend1'));
      denied(await db(who).query('vendor_private', [['vendorId', '==', 'vend1']]));
      denied(await db(who).set('vendor_private/vend1', { payoutAccount: 'mine' }, { merge: true }));
    }
  });

  test('vendor owner: reads own private, edits contact/documents/payout account', async () => {
    allowed(await db('vendU1').get('vendor_private/vend1'));
    allowed(await db('vendU1').set('vendor_private/vend1', {
      phone: '01711111111', email: 'a@b.c', address: 'Road 2', ownerName: 'Owner',
      nidFront: 'n1', nidBack: 'n2', tradeLicense: 't', payoutAccount: 'bkash 019', updatedAt: SERVER_TS,
    }, { merge: true }));
  });

  test('vendor owner: cannot change commission, balances or admin note', async () => {
    denied(await db('vendU1').update('vendor_private/vend1', { commissionPercent: 0 }));
    denied(await db('vendU1').update('vendor_private/vend1', { withdrawableBalance: 99999 }));
    denied(await db('vendU1').update('vendor_private/vend1', { totalSales: 1 }));
    denied(await db('vendU1').update('vendor_private/vend1', { note: 'approved by me' }));
  });

  test('applicant (not approved, not isVendor yet) can create own private doc, without money keys', async () => {
    allowed(await db('vendNew').create('vendor_private/vendNew', {
      vendorId: 'vendNew', phone: '0170', nidFront: 'n', createdAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
    denied(await db('vendNew').create('vendor_private/vendNew2', { vendorId: 'vendNew2', phone: '0' }));
  });
  test('applicant cannot create own private doc with commission or balance', async () => {
    denied(await db('vendNew').create('vendor_private/vendNew', { vendorId: 'vendNew', commissionPercent: 0 }));
    denied(await db('vendNew').create('vendor_private/vendNew', { vendorId: 'vendNew', withdrawableBalance: 10 }));
  });

  test('public vendor doc: no NEW or CHANGED private value, by anyone', async () => {
    // Owner (approved vendor) profile edit with a new phone: refused.
    denied(await db('vendU2').update('vendors/vend2', { phone: '0199' }));
    denied(await db('vendU2').update('vendors/vend2', { payoutAccount: 'x' }));
    // Admin edit with NID link or balance: refused.
    denied(await db('boss').update('vendors/vend2', { nidFront: 'https://x' }));
    denied(await db('boss').update('vendors/vend2', { withdrawableBalance: 5 }));
    // Application create carrying private fields: refused.
    denied(await db('cust1').create('vendors/cust1', {
      ownerId: 'cust1', userId: 'cust1', shopName: 'S', status: 'pending', isActive: false, phone: '017',
    }));
  });

  test('public vendor doc: harmless edits still work, also with old copies left in (pre-move)', async () => {
    allowed(await db('vendU2').update('vendors/vend2', { shopName: 'Shop Two!', shopArea: 'Chalakchar', updatedAt: SERVER_TS }));
    // vend1 still has phone + nidFront in the public doc: an old build re-sends them unchanged.
    allowed(await db('vendU1').update('vendors/vend1', {
      shopName: 'Shop One!', phone: '01700000001', nidFront: 'https://example.invalid/nid?token=x',
    }));
    // ...or blanks them: also fine.
    allowed(await db('vendU1').update('vendors/vend1', { phone: '' }));
    // but not a changed value.
    denied(await db('vendU1').update('vendors/vend1', { phone: '01799999999' }));
    allowed(await db('cust1').create('vendors/cust1', {
      ownerId: 'cust1', userId: 'cust1', shopName: 'S', shopArea: 'Ramgati', status: 'pending', isActive: false,
    }));
  });

  test('expression limit: big admin form save and blanking many old copies stay under 1000', async () => {
    const form = {
      shopName: 'Shop One', shopArea: 'Chalakchar', businessType: 'Retail', status: 'approved',
      isActive: true, isVerified: true, rating: 4.5, totalOrders: 3, logoUrl: '', bannerUrl: '', updatedAt: SERVER_TS,
    };
    allowed(await db('admin').update('vendors/vend1', form));
    allowed(await db('vendU1').update('vendors/vend1', { shopName: 'S', shopArea: 'A', updatedAt: SERVER_TS }));
    allowed(await db('admin').update('vendors/vend1', {
      ...form, phone: '', nidFront: '', email: '', address: '', payoutAccount: '', note: '', ownerName: '',
    }));
    allowed(await db('admin').update('deliveryPartners/rider1', {
      name: 'R', phone: '018', status: 'approved', isActive: true, nidNumber: '', nidFrontUrl: '', address: '', email: '',
    }));
  });

  test('vendors.view staff: reads private; cannot write it', async () => {
    allowed(await db('vendStaff').get('vendor_private/vend1'));
    allowed(await db('vendStaff').query('vendor_private'));
    denied(await db('vendStaff').set('vendor_private/vend1', { phone: 'x' }, { merge: true }));
  });

  test('vendors.payouts staff: reads private, changes money fields only', async () => {
    allowed(await db('payStaff').get('vendor_private/vend1'));
    allowed(await db('payStaff').update('vendor_private/vend1', { withdrawableBalance: 300, updatedAt: SERVER_TS }));
    denied(await db('payStaff').update('vendor_private/vend1', { payoutAccount: 'staff account' }));
    denied(await db('payStaff').update('vendor_private/vend1', { nidFront: 'x' }));
  });

  test('admin (default permissions) and superAdmin: read and write everything', async () => {
    allowed(await db('admin').query('vendor_private'));
    allowed(await db('admin').update('vendor_private/vend1', { commissionPercent: 12, note: 'ok' }));
    allowed(await db('boss').set('vendor_private/vend2', { phone: '0', totalSales: 1 }, { merge: true }));
  });

  test('analytics staff / order-assign staff (catch-all rule): no private, no payout requests', async () => {
    for (const who of ['analyst', 'assignStaff', 'riderStaff']) {
      denied(await db(who).get('vendor_private/vend1'));
      denied(await db(who).query('vendor_private'));
      denied(await db(who).get('vendorWithdrawRequests/w1'));
      denied(await db(who).query('vendorWithdrawRequests'));
    }
    // ...but the catch-all still works for other collections (unchanged in step B).
    allowed(await db('analyst').query('orders'));
  });

  test('vendor doc delete: delete permission / superAdmin only, private too', async () => {
    denied(await db('vendU1').delete('vendor_private/vend1'));
    denied(await db('vendStaff').delete('vendor_private/vend1'));
    allowed(await db('boss').delete('vendor_private/vend1'));
  });
});

describe('step B: vendorWithdrawRequests', opts, () => {
  const req = {
    vendorId: 'vend1', vendorOwnerId: 'vendU1', vendorName: 'Shop One',
    amount: 200, status: 'pending', note: '', payoutAccount: 'bkash', createdAt: SERVER_TS, updatedAt: SERVER_TS,
  };
  test('new request without phone/email: allowed; with the old copies: refused', async () => {
    allowed(await db('vendU1').create('vendorWithdrawRequests/n1', req));
    denied(await db('vendU1').create('vendorWithdrawRequests/n2', { ...req, vendorPhone: '017' }));
    denied(await db('vendU1').create('vendorWithdrawRequests/n3', { ...req, vendorEmail: 'a@b.c' }));
  });
  test('payout staff still reads requests', async () => {
    allowed(await db('payStaff').query('vendorWithdrawRequests'));
    allowed(await db('vendStaff').get('vendorWithdrawRequests/w1'));
  });
});

describe('step B: riders', opts, () => {
  test('no login / customer / vendor / other rider: rider private denied', async () => {
    for (const who of [null, 'cust1', 'vendU1', 'rider3']) {
      denied(await db(who).get('delivery_partner_private/rider1'));
      denied(await db(who).query('delivery_partner_private'));
      denied(await db(who).set('delivery_partner_private/rider1', { address: 'x' }, { merge: true }));
    }
  });

  test('rider: reads own private; edits address and email only, never NID', async () => {
    allowed(await db('rider1').get('delivery_partner_private/rider1'));
    allowed(await db('rider1').update('delivery_partner_private/rider1', { address: 'House 10', email: 'r@x.y', updatedAt: SERVER_TS }));
    denied(await db('rider1').update('delivery_partner_private/rider1', { nidNumber: '999' }));
    denied(await db('rider1').update('delivery_partner_private/rider1', { nidFrontUrl: 'x' }));
  });

  test('applicant: creates own private doc with NID once; not for someone else', async () => {
    allowed(await db('cust1').create('delivery_partner_private/cust1', {
      uid: 'cust1', nidNumber: '1', nidFrontUrl: 'f', nidBackUrl: 'b', nidFrontPath: 'p1', nidBackPath: 'p2',
      address: 'A', createdAt: SERVER_TS, updatedAt: SERVER_TS,
    }));
    denied(await db('cust2').create('delivery_partner_private/cust1x', { uid: 'cust1x', nidNumber: '1' }));
    denied(await db('cust2').create('delivery_partner_private/cust2', { uid: 'cust2', nidNumber: '1', totalEarning: 5 }));
  });

  test('public rider doc: application with NID is refused; without is fine', async () => {
    const app = {
      uid: 'cust1', name: 'C', phone: '0', status: 'pending', isActive: false,
      totalDeliveries: 0, totalEarning: 0, withdrawnAmount: 0, pendingAmount: 0, codDue: 0, createdAt: SERVER_TS,
    };
    denied(await db('cust1').set('deliveryPartners/cust1', { ...app, nidNumber: '1' }));
    denied(await db('cust1').set('deliveryPartners/cust1', { ...app, address: 'Home' }));
    allowed(await db('cust1').set('deliveryPartners/cust1', app));
  });

  test('public rider doc: rider / admin cannot put a NEW private value back; old copy unchanged is fine', async () => {
    denied(await db('rider1').update('deliveryPartners/rider1', { address: 'New home' }));
    denied(await db('admin').update('deliveryPartners/rider1', { nidNumber: '42' }));
    allowed(await db('rider1').update('deliveryPartners/rider1', { preferredArea: 'Sadar', updatedAt: SERVER_TS }));
    allowed(await db('admin').update('deliveryPartners/rider1', { status: 'approved', nidNumber: '1234567890' }));
  });

  test('order-assign staff: public rider doc yes (name, phone), private no', async () => {
    allowed(await db('assignStaff').get('deliveryPartners/rider1'));
    denied(await db('assignStaff').get('delivery_partner_private/rider1'));
  });

  test('delivery.view staff reads private; admin / superAdmin read and write', async () => {
    allowed(await db('riderStaff').get('delivery_partner_private/rider1'));
    denied(await db('riderStaff').update('delivery_partner_private/rider1', { address: 'x' }));
    allowed(await db('admin').query('delivery_partner_private'));
    allowed(await db('admin').update('delivery_partner_private/rider1', { address: 'Checked' }));
    allowed(await db('boss').delete('delivery_partner_private/rider3'));
    denied(await db('admin').delete('delivery_partner_private/rider3'));
  });

  test('analytics staff: rider private denied (catch-all excludes it)', async () => {
    denied(await db('analyst').get('delivery_partner_private/rider1'));
    denied(await db('analyst').query('delivery_partner_private'));
  });
});
