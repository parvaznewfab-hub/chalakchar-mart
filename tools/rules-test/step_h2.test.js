'use strict';

// Step H2: who may create / change / delete products.
//
// The expectation is picked from the rules file itself: when RULES_FILE is
// byte-identical to the live ruleset fa5f0e22 (sha256 b5b6c626...), the
// attacks are expected to SUCCEED (proof of the gap) and the vendor's own
// edits to FAIL (ownsVendorProduct() is not defined). Any other rules file
// is treated as the fixed rules: attacks denied, vendor edits allowed.
//   RULES_FILE=docs/security/rules-backup/firestore.rules.live-fa5f0e22 \
//     firebase emulators:exec --only firestore "node --test tools/rules-test/step_h2.test.js"
//
// Cast (fixtures.js + below): cust1/cust2 customers; vendU1 owner of the
// approved vendor vend1; vendNew a pending applicant; vendSusU owner of a
// suspended vendor; rider1; staff with only products.view / products.status /
// products.edit; admin; boss (super admin).

const fs = require('node:fs');
const crypto = require('node:crypto');
const { describe, test, beforeEach } = require('node:test');
const { db, seed, allowed, denied, SERVER_TS } = require('./emu');
const { resetWorld, RULES_FILE } = require('./fixtures');

const LIVE_SHA = 'b5b6c62684291ca5aaba0b69fe5dd14408f65ba78261221d0a545d6c582ef50d';
const GAP_OPEN = crypto.createHash('sha256').update(fs.readFileSync(RULES_FILE)).digest('hex') === LIVE_SHA;
const attack = GAP_OPEN ? allowed : denied;
const vendorOwnEdit = GAP_OPEN ? denied : allowed;
const tag = GAP_OPEN ? '[fa5f0e22: gap open]' : '[fixed: closed]';
const vtag = GAP_OPEN ? '[fa5f0e22: vendor blocked]' : '[fixed: vendor allowed]';

const u = (role, extra = {}) => ({ role, roles: ['user', role], isActive: true, isBanned: false, vendorId: '', ...extra });

// What an attacker would write: live, approved, on the home page, own text.
const fake = (vendorId, owner, extra = {}) => ({
  name: 'FAKE', price: 1, mrp: 9999, stock: 5, category: 'Mobile Parts',
  vendorId, vendorOwnerId: owner,
  approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true, showOnHome: true,
  facebookCaption: 'call 01XXXXXXXXX', whatsappCaption: 'call 01XXXXXXXXX',
  createdAt: SERVER_TS, ...extra,
});

// What vendor_products_page.dart writes for a new product.
const vendorPending = (extra = {}) => ({
  name: 'V new', category: 'Mobile Parts', price: 100, mrp: 120, stock: 3, variants: [],
  vendorId: 'vend1', sellerId: 'vend1', vendorOwnerId: 'vendU1', vendorOwnerIds: ['vendU1'], sellerUid: 'vendU1',
  isMarketplace: true, approvalStatus: 'pending', isActive: false, showOnHome: false, isVisible: false, isPublished: false,
  createdAt: SERVER_TS, updatedAt: SERVER_TS, ...extra,
});

beforeEach(async () => {
  await resetWorld();
  await seed({
    'users/vendSusU': u('vendor', { vendorId: 'vendSus' }),
    'vendors/vendSus': { ownerId: 'vendSusU', userId: 'vendSusU', shopName: 'Sus', status: 'suspended', isActive: false },
    'users/viewStaff': u('staff', { permissions: ['products.view'] }),
    'users/statusStaff': u('staff', { permissions: ['products.status'] }),
    'users/prodStaff': u('staff', { permissions: ['products.edit'] }),
    'products/p1': { name: 'Shop', price: 100, vendorId: 'super_admin', approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true },
    'products/pv1': {
      name: 'V1', price: 100, vendorId: 'vend1', sellerId: 'vend1', vendorOwnerId: 'vendU1', vendorOwnerIds: ['vendU1'],
      sellerUid: 'vendU1', isMarketplace: true, approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true,
    },
  });
});

describe('step H2: fake live products', () => {
  test('guest may never create a product (both rule sets)', async () => {
    denied(await db(null).create('products/g1', fake('x', 'x')));
  });

  for (const who of ['cust1', 'rider1', 'vendNew', 'vendSusU', 'viewStaff']) {
    test(`${tag} ${who} creates an approved, live product under own uid`, async () => {
      attack(await db(who).create(`products/f_${who}`, fake(who, who)));
    });
  }

  test(`${tag} customer creates a product in the name of another vendor (vend1)`, async () => {
    attack(await db('cust1').create('products/c2', fake('vend1', 'cust1')));
  });

  test(`${tag} customer creates a product in the shop's own name (super_admin)`, async () => {
    attack(await db('cust1').create('products/c3', fake('super_admin', 'cust1')));
  });

  test(`${tag} customer sets commission / featured / sponsored on create`, async () => {
    attack(await db('cust1').create('products/c4', fake('cust1', 'cust1', { commissionPercent: 0, featured: true, sponsored: true })));
  });

  test(`${tag} approved vendor creates a product that is already approved and live`, async () => {
    attack(await db('vendU1').create('products/v2', fake('vend1', 'vendU1')));
  });

  test('approved vendor creates a pending product as the app does (both rule sets)', async () => {
    allowed(await db('vendU1').create('products/v3', vendorPending()));
  });

  test('rating fields stay closed on create (step H, both rule sets)', async () => {
    denied(await db('cust1').create('products/c5', fake('cust1', 'cust1', { ratingAvg: 5, reviewCount: 99 })));
  });
});

describe('step H2: changing existing products', () => {
  test('customer may not change or delete a shop product (both rule sets)', async () => {
    denied(await db('cust1').update('products/p1', { price: 1 }), 'price');
    denied(await db('cust1').update('products/p1', { approvalStatus: 'rejected' }), 'approvalStatus');
    denied(await db('cust1').delete('products/p1'), 'delete');
  });

  test('vendor may not change a shop product or another vendor\'s (both rule sets)', async () => {
    denied(await db('vendU1').update('products/p1', { price: 1 }), 'shop product');
    denied(await db('vendU2').update('products/pv1', { price: 1 }), 'other vendor');
  });

  test(`${vtag} approved vendor edits own product (vendor_products_page update)`, async () => {
    vendorOwnEdit(await db('vendU1').update('products/pv1', { name: 'V1b', price: 120, stock: 2, updatedAt: SERVER_TS }));
  });

  test(`${vtag} approved vendor hides own product (vendor_products_page toggle)`, async () => {
    vendorOwnEdit(await db('vendU1').update('products/pv1', { isActive: false, isVisible: false, updatedAt: SERVER_TS }));
  });

  test(`${vtag} approved vendor deletes own product`, async () => {
    vendorOwnEdit(await db('vendU1').delete('products/pv1'));
  });

  test(`${tag} staff with only products.status changes the price and the rating`, async () => {
    attack(await db('statusStaff').update('products/p1', { price: 1 }), 'price');
    attack(await db('statusStaff').update('products/p1', { ratingAvg: 5 }), 'ratingAvg');
  });

  test('staff with products.status still switches a product on / off (both rule sets)', async () => {
    allowed(await db('statusStaff').update('products/p1', { isActive: false, updatedAt: SERVER_TS }));
  });

  test('staff with products.edit edits a product (both rule sets)', async () => {
    allowed(await db('prodStaff').update('products/p1', { price: 99, updatedAt: SERVER_TS }));
  });

  test('product subcollections other than reviews are closed to every client (both rule sets)', async () => {
    denied(await db('cust1').set('products/p1/variants/x', { price: 1 }), 'customer');
    denied(await db('admin').set('products/p1/variants/x', { price: 1 }), 'admin');
  });
});
