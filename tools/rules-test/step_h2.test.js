'use strict';

// Step H2: who may create / change / delete products, and vendor identity.
//
// The expectation is picked from the rules file itself: when RULES_FILE is
// byte-identical to the live ruleset fa5f0e22 (sha256 b5b6c626...), the
// attacks are expected to SUCCEED (proof of the gap) and the vendor's own
// edits to FAIL (ownsVendorProduct() was not defined). Any other rules file
// is treated as the fixed step H2 rules: attacks denied, vendor edits allowed.
//   node tools/rules-test/run.js                     (step H2 rules)
//   node tools/rules-test/run.js docs/security/rules-backup/firestore.rules.live-fa5f0e22
//
// Cast (fixtures.js + below): cust1/cust2 customers; vendU1 owner of the
// approved vendor vend1; vendNew a pending applicant (vendors/vendNew);
// vendSusU owner of a suspended vendor; rider1; staff with only
// products.view / products.status / products.edit / products.delete;
// admin; boss (super admin).

const fs = require('node:fs');
const crypto = require('node:crypto');
const { describe, test, beforeEach } = require('node:test');
const { db, seed, allowed, denied, SERVER_TS } = require('./emu');
const { resetWorld, RULES_FILE, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const LIVE_SHA = 'b5b6c62684291ca5aaba0b69fe5dd14408f65ba78261221d0a545d6c582ef50d';
const GAP_OPEN = crypto.createHash('sha256').update(fs.readFileSync(RULES_FILE)).digest('hex') === LIVE_SHA;
// Older rule copies (before step H) are not what this suite is about.
const OLDER = OLD_RULES || STEP_B_ROLLBACK || /live-(700f57c7|be7e9c8a|438c4999)/.test(RULES_FILE);
const opts = { skip: OLDER ? 'step H2 suite (older rules copy)' : false };
const attack = GAP_OPEN ? allowed : denied;
const vendorOwnEdit = GAP_OPEN ? denied : allowed;
const tag = GAP_OPEN ? '[fa5f0e22: gap open]' : '[H2: closed]';
const vtag = GAP_OPEN ? '[fa5f0e22: vendor blocked]' : '[H2: vendor allowed]';

const BUCKET = 'chalakchar-mart.firebasestorage.app';
const img = (vendorId, file = '1732.jpg', bucket = BUCKET) =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/vendor_products%2F${vendorId}%2F${file}?alt=media&token=abc-123`;

const u = (role, extra = {}) => ({ role, roles: ['user', role], isActive: true, isBanned: false, vendorId: '', ...extra });

// What an attacker would write: live, approved, on the home page, own text.
const fake = (vendorId, owner, extra = {}) => ({
  name: 'FAKE', price: 1, mrp: 9999, stock: 5, category: 'Mobile Parts',
  vendorId, vendorOwnerId: owner,
  approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true, showOnHome: true,
  facebookCaption: 'call 01XXXXXXXXX', whatsappCaption: 'call 01XXXXXXXXX',
  createdAt: SERVER_TS, ...extra,
});

// What vendor_products_page.dart writes for a new product (step H2 shape).
const vendorPending = (extra = {}) => ({
  name: 'V new', category: 'Mobile Parts', overview: 'Good', price: 100, piecePrice: 100, oldPrice: 120, mrp: 120,
  unit: 'Default', stock: 3, variants: [{ name: 'Default', price: 100, mrp: 120, stock: 3 }],
  image: img('vend1'), imageUrl: img('vend1'), images: [img('vend1'), img('vend1', '1733.jpg')],
  vendorName: 'Shop One', shopName: 'Shop One',
  vendorId: 'vend1', sellerId: 'vend1', vendorOwnerId: 'vendU1', vendorOwnerIds: ['vendU1'], sellerUid: 'vendU1',
  isMarketplace: true, approvalStatus: 'pending', isActive: false, showOnHome: false, isVisible: false, isPublished: false,
  createdAt: SERVER_TS, updatedAt: SERVER_TS, ...extra,
});

const approvedVendorProduct = {
  name: 'V1', category: 'Mobile Parts', price: 100, mrp: 120, stock: 4,
  variants: [{ name: 'Default', price: 100, mrp: 120, stock: 4 }],
  image: img('vend1'), imageUrl: img('vend1'), images: [img('vend1')],
  vendorId: 'vend1', sellerId: 'vend1', vendorOwnerId: 'vendU1', vendorOwnerIds: ['vendU1'],
  sellerUid: 'vendU1', isMarketplace: true, approvalStatus: 'approved', isActive: true, isVisible: true,
  isPublished: true, showOnHome: true,
};

beforeEach(async () => {
  await resetWorld();
  await seed({
    'users/vendSusU': u('vendor', { vendorId: 'vendSus' }),
    'vendors/vendSus': { ownerId: 'vendSusU', userId: 'vendSusU', shopName: 'Sus', status: 'suspended', isActive: false },
    'users/viewStaff': u('staff', { permissions: ['products.view'] }),
    'users/statusStaff': u('staff', { permissions: ['products.status'] }),
    'users/prodStaff': u('staff', { permissions: ['products.edit'] }),
    'users/delStaff': u('staff', { permissions: ['products.delete'] }),
    // An old profile that already carries someone else's vendor id
    // (possible before step H2): it must give nothing.
    'users/forger': u('user', { vendorId: 'vend1' }),
    'products/p1': { name: 'Shop', price: 100, vendorId: 'super_admin', approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true },
    'products/pv1': approvedVendorProduct,
    'products/pv2': { ...approvedVendorProduct, approvalStatus: 'pending', isActive: false, isVisible: false, isPublished: false, showOnHome: false },
  });
});

describe('step H2: fake live products', opts, () => {
  test('guest may never create a product (both rule sets)', async () => {
    denied(await db(null).create('products/g1', fake('x', 'x')));
  });

  for (const who of ['cust1', 'rider1', 'vendNew', 'vendSusU', 'viewStaff', 'statusStaff']) {
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

  test(`${tag} a profile with a forged users.vendorId creates a product for that vendor`, async () => {
    attack(await db('forger').create('products/fg', fake('vend1', 'forger')));
  });

  test('approved vendor creates a pending product as the app does (both rule sets)', async () => {
    allowed(await db('vendU1').create('products/v3', vendorPending()));
  });

  test('rating fields stay closed on create (step H, both rule sets)', async () => {
    denied(await db('cust1').create('products/c5', fake('cust1', 'cust1', { ratingAvg: 5, reviewCount: 99 })));
  });

  test('staff with products.edit still creates shop products (both rule sets)', async () => {
    allowed(await db('prodStaff').create('products/s1', fake('super_admin', 'prodStaff')));
  });
});

describe('step H2: vendor create, field by field (H2 rules)', { skip: GAP_OPEN || OLDER ? 'H2 rules only' : false }, () => {
  test('a pending (not approved) or suspended vendor may not create even a pending product', async () => {
    denied(await db('vendNew').create('products/n1', vendorPending({ vendorId: 'vendNew', sellerId: 'vendNew', vendorOwnerId: 'vendNew', vendorOwnerIds: ['vendNew'], sellerUid: 'vendNew', image: '', imageUrl: '', images: [] })), 'pending vendor');
    denied(await db('vendSusU').create('products/n2', vendorPending({ vendorId: 'vendSus', sellerId: 'vendSus', vendorOwnerId: 'vendSusU', vendorOwnerIds: ['vendSusU'], sellerUid: 'vendSusU', image: '', imageUrl: '', images: [] })), 'suspended vendor');
  });

  test('the new product must start pending and hidden', async () => {
    for (const [k, v] of [['approvalStatus', 'approved'], ['isActive', true], ['isVisible', true], ['isPublished', true], ['showOnHome', true]]) {
      denied(await db('vendU1').create(`products/x_${k}`, vendorPending({ [k]: v })), k);
    }
  });

  test('owner fields must be the caller and the vendor', async () => {
    denied(await db('vendU1').create('products/o1', vendorPending({ vendorOwnerId: 'vendU2' })), 'vendorOwnerId');
    denied(await db('vendU1').create('products/o2', vendorPending({ sellerId: 'vend2' })), 'sellerId');
    denied(await db('vendU1').create('products/o3', vendorPending({ vendorOwnerIds: ['vendU1', 'cust1'] })), 'vendorOwnerIds');
    denied(await db('vendU2').create('products/o4', vendorPending({ vendorOwnerId: 'vendU2', vendorOwnerIds: ['vendU2'], sellerUid: 'vendU2' })), 'vendU2 for vend1');
  });

  test('fields outside the vendor list are refused (pharmacy fields, marketing, SEO, commission, rating, review flags)', async () => {
    for (const k of ['generic', 'manufacturer', 'type', 'strength', 'facebookCaption', 'metaTitle', 'banglaTitle',
      'commissionPercent', 'featured', 'sponsored', 'needsReview', 'autoMarketingDisabled', 'ratingAvg', 'approvedAt']) {
      denied(await db('vendU1').create(`products/k_${k}`, vendorPending({ [k]: k === 'needsReview' || k === 'featured' ? false : 'x' })), k);
    }
  });

  test('images: only the vendor\'s own folder in this project\'s bucket', async () => {
    allowed(await db('vendU1').create('products/i0', vendorPending({ image: '', imageUrl: '', images: [] })), 'no image');
    denied(await db('vendU1').create('products/i1', vendorPending({ image: 'https://evil.example/x.jpg' })), 'outside site');
    denied(await db('vendU1').create('products/i2', vendorPending({ images: [img('vend1'), 'https://evil.example/x.jpg'] })), 'outside in list');
    denied(await db('vendU1').create('products/i3', vendorPending({ imageUrl: img('vend2') })), 'another vendor folder');
    denied(await db('vendU1').create('products/i4', vendorPending({ image: img('vend1', '1.jpg', 'attacker-project.appspot.com') })), 'another bucket');
    denied(await db('vendU1').create('products/i5', vendorPending({ image: img('vend1', '..%2F..%2Fproducts%2Fx.jpg') })), 'path escape');
    denied(await db('vendU1').create('products/i6', vendorPending({ images: Array(9).fill(img('vend1')) })), 'more than 8');
  });

  test('variants: name / price / mrp / stock only (no image)', async () => {
    denied(await db('vendU1').create('products/va1', vendorPending({ variants: [{ name: 'A', price: 1, mrp: 2, stock: 1, image: 'https://evil.example/x.jpg' }] })));
  });
});

describe('step H2: changing existing products', opts, () => {
  test('customer may not change or delete a shop product (both rule sets)', async () => {
    denied(await db('cust1').update('products/p1', { price: 1 }), 'price');
    denied(await db('cust1').update('products/p1', { approvalStatus: 'rejected' }), 'approvalStatus');
    denied(await db('cust1').delete('products/p1'), 'delete');
  });

  test('vendor may not change a shop product or another vendor\'s (both rule sets)', async () => {
    denied(await db('vendU1').update('products/p1', { price: 1 }), 'shop product');
    denied(await db('vendU2').update('products/pv1', { price: 1 }), 'other vendor');
    denied(await db('forger').update('products/pv1', { price: 1 }), 'forged users.vendorId');
  });

  test(`${vtag} approved vendor changes price / stock / variants of an approved product (stays approved)`, async () => {
    vendorOwnEdit(await db('vendU1').update('products/pv1', {
      price: 120, piecePrice: 120, mrp: 150, stock: 2, variants: [{ name: 'Default', price: 120, mrp: 150, stock: 2 }], updatedAt: SERVER_TS,
    }));
  });

  test(`${vtag} approved vendor hides own approved product (vendor_products_page toggle)`, async () => {
    vendorOwnEdit(await db('vendU1').update('products/pv1', { isActive: false, isVisible: false, updatedAt: SERVER_TS }));
  });

  test(`${vtag} renaming sends the product back to pending and hides it`, async () => {
    vendorOwnEdit(await db('vendU1').update('products/pv1', {
      name: 'V1 new name', approvalStatus: 'pending', isActive: false, isVisible: false, updatedAt: SERVER_TS,
    }));
  });

  test('vendor deletes own product: never (owner\'s decision; both rule sets)', async () => {
    denied(await db('vendU1').delete('products/pv1'));
  });

  test(`${tag} staff with only products.status changes the price and the rating`, async () => {
    attack(await db('statusStaff').update('products/p1', { price: 1 }), 'price');
    attack(await db('statusStaff').update('products/p1', { ratingAvg: 5 }), 'ratingAvg');
  });

  test('staff with products.status switches on / off and approves (both rule sets)', async () => {
    allowed(await db('statusStaff').update('products/p1', { isActive: false, updatedAt: SERVER_TS }), 'toggle');
    allowed(await db('statusStaff').set('products/pv2', {
      approvalStatus: 'approved', isActive: true, isVisible: true, isPublished: true, showOnHome: true,
      approvedAt: SERVER_TS, rejectedReason: '', updatedAt: SERVER_TS,
    }, { merge: true }), 'approve (admin_vendor_products_page)');
  });

  test('staff with products.edit edits a product; delete needs products.delete (both rule sets)', async () => {
    allowed(await db('prodStaff').update('products/p1', { price: 99, updatedAt: SERVER_TS }), 'edit');
    allowed(await db('delStaff').delete('products/p1'), 'delete');
  });

  test('product subcollections other than reviews are closed to every client (both rule sets)', async () => {
    denied(await db('cust1').set('products/p1/variants/x', { price: 1 }), 'customer');
    denied(await db('admin').set('products/p1/variants/x', { price: 1 }), 'admin');
  });
});

describe('step H2: vendor edits, field by field (H2 rules)', { skip: GAP_OPEN || OLDER ? 'H2 rules only' : false }, () => {
  test('renaming / new images / new category without going back to pending is refused', async () => {
    denied(await db('vendU1').update('products/pv1', { name: 'Sneaky' }), 'name');
    denied(await db('vendU1').update('products/pv1', { images: [img('vend1', 'new.jpg')] }), 'images');
    denied(await db('vendU1').update('products/pv1', { category: 'Other' }), 'category');
    denied(await db('vendU1').update('products/pv1', { overview: 'new text' }), 'overview');
  });

  test('going back to pending must also hide the product', async () => {
    denied(await db('vendU1').update('products/pv1', { name: 'X', approvalStatus: 'pending' }));
  });

  test('the vendor never approves, publishes or features a product', async () => {
    denied(await db('vendU1').update('products/pv2', { approvalStatus: 'approved' }), 'approve own');
    denied(await db('vendU1').update('products/pv2', { isActive: true, isVisible: true }), 'show a pending product');
    denied(await db('vendU1').update('products/pv1', { isPublished: false }), 'isPublished');
    denied(await db('vendU1').update('products/pv1', { showOnHome: false }), 'showOnHome');
    denied(await db('vendU1').update('products/pv1', { vendorId: 'vend2' }), 'vendorId');
    denied(await db('vendU1').update('products/pv1', { needsReview: false }), 'needsReview');
    denied(await db('vendU1').update('products/pv1', { facebookCaption: 'x' }), 'marketing text');
    denied(await db('vendU1').update('products/pv1', { commissionPercent: 0 }), 'commission');
  });

  test('outside image on edit is refused', async () => {
    denied(await db('vendU1').update('products/pv1', {
      image: 'https://evil.example/x.jpg', approvalStatus: 'pending', isActive: false, isVisible: false,
    }));
  });

  test('a suspended vendor may not edit', async () => {
    await seed({ 'products/ps': { ...approvedVendorProduct, vendorId: 'vendSus', sellerId: 'vendSus', vendorOwnerId: 'vendSusU', vendorOwnerIds: ['vendSusU'], sellerUid: 'vendSusU', image: '', imageUrl: '', images: [] } });
    denied(await db('vendSusU').update('products/ps', { price: 1 }));
  });
});

describe('step H2: users.vendorId and other vendor fields', opts, () => {
  test(`${tag} customer puts a vendor id in own profile`, async () => {
    attack(await db('cust1').update('users/cust1', { vendorId: 'cust1' }), 'own uid');
  });

  test(`${tag} seller application links users.vendorId (old app behaviour)`, async () => {
    attack(await db('cust1').set('users/cust1', { vendorId: 'cust1', sellerStatus: 'pending', updatedAt: SERVER_TS }, { merge: true }));
  });

  test('seller application without vendorId, as the step H2 app does (both rule sets)', async () => {
    allowed(await db('cust1').set('users/cust1', { sellerStatus: 'pending', updatedAt: SERVER_TS }, { merge: true }));
  });

  test(`${tag} new profile already carrying a vendor id / approved seller status`, async () => {
    attack(await db('newbie').create('users/newbie', { uid: 'newbie', role: 'user', vendorId: 'vend1' }), 'vendorId');
    attack(await db('newbie2').create('users/newbie2', { uid: 'newbie2', role: 'user', sellerStatus: 'approved' }), 'sellerStatus');
  });

  test('new profile as the app creates it (vendorId null) (both rule sets)', async () => {
    allowed(await db('newbie').create('users/newbie', {
      uid: 'newbie', role: 'user', roles: ['user'], sellerStatus: 'none', vendorId: null,
      points: 0, totalEarnings: 0, referralCount: 0, isActive: true, isBanned: false, createdAt: SERVER_TS,
    }));
  });

  test(`${tag} a forged users.vendorId reads that vendor's private data`, async () => {
    attack(await db('forger').get('vendor_private/vend1'));
  });

  test(`${tag} a forged users.vendorId asks for that vendor's payout`, async () => {
    attack(await db('forger').create('vendorWithdrawRequests/w_forger', {
      vendorId: 'vend1', vendorOwnerId: 'forger', vendorName: 'x', amount: 100, status: 'pending',
      payoutAccount: 'bkash 019', createdAt: SERVER_TS,
    }));
  });

  test(`${tag} a forged users.vendorId reads that vendor's orders`, async () => {
    attack(await db('forger').get('orders/o1'));
  });

  test(`${tag} anyone takes over a pending vendor application by setting ownerId`, async () => {
    attack(await db('cust1').update('vendors/vendNew', { ownerId: 'cust1', userId: 'cust1' }));
  });

  test('the real vendor still reads own private data, orders and asks for a payout (both rule sets)', async () => {
    allowed(await db('vendU1').get('vendor_private/vend1'), 'vendor_private');
    allowed(await db('vendU1').get('orders/o1'), 'order');
    allowed(await db('vendU1').create('vendorWithdrawRequests/w_v1', {
      vendorId: 'vend1', vendorOwnerId: 'vendU1', vendorName: 'Shop One', amount: 100, status: 'pending',
      payoutAccount: 'bkash 017', createdAt: SERVER_TS,
    }), 'withdraw');
  });
});
