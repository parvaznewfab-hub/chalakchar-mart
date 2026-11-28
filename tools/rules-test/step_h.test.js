'use strict';

// 14b step H: product reviews and referrals.
//   - reviews (products/{id}/reviews/{uid}): everyone may read; no client
//     writes at all (submitProductReview / deleteProductReview functions).
//   - referrals: no client create / update / delete (applyReferralReward,
//     approveReferral, rejectReferral functions). Reading is unchanged.
//   - users.referralCount: never written by a client (only the functions).
//   RULES_FILE=docs/security/rules-backup/firestore.rules.live-438c4999
//     -> the rules live before step H: the attacks SUCCEED (proof of the gap)
//        and reviews cannot be read by customers or guests
//   firestore.rules (step H) -> the attacks are DENIED, reviews are readable

const { describe, test, beforeEach } = require('node:test');
const { db, seed, allowed, denied, SERVER_TS, inc } = require('./emu');
const { resetWorld, RULES_FILE, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const LIVE_BEFORE_H = /live-438c4999/.test(RULES_FILE);
const OLDER = /live-700f57c7|live-be7e9c8a/.test(RULES_FILE);
const opts = {
  skip: OLD_RULES || STEP_B_ROLLBACK || OLDER ? 'step H suite (older rules copy)' : false,
};
const attack = LIVE_BEFORE_H ? allowed : denied;
const readable = LIVE_BEFORE_H ? denied : allowed;
const tag = LIVE_BEFORE_H ? '[438c4999: gap open]' : '[step H: closed]';
const rtag = LIVE_BEFORE_H ? '[438c4999: not readable]' : '[step H: readable]';

const review = (uid, extra = {}) => ({
  productId: 'p1', userId: uid, userName: 'Rahim', rating: 5, comment: 'ভালো পণ্য',
  verifiedBuyer: true, createdAt: SERVER_TS, updatedAt: SERVER_TS, ...extra,
});

const staff = (permissions) => ({
  role: 'staff', roles: ['user', 'staff'], isActive: true, isBanned: false, vendorId: '', permissions,
});

beforeEach(async () => {
  await resetWorld();
  await seed({
    'products/p1': {
      name: 'Phone case', price: 100, isActive: true, vendorId: 'vend1', vendorOwnerId: 'vendU1',
      ratingAvg: 4, ratingCount: 1, reviewCount: 1, ratingTotal: 4,
    },
    'products/p1/reviews/cust2': review('cust2', { rating: 4 }),
    'referrals/ref1': {
      referrerId: 'cust2', referredUserId: 'cust1', referredByCode: 'CUST2X',
      referrerReward: 25, refereeReward: 25, status: 'pending', autoApprove: false,
      createdAt: SERVER_TS, updatedAt: SERVER_TS,
    },
    'users/walletStaff': staff(['wallet.edit']),
    'users/usersStaff': staff(['users.view', 'users.edit']),
    'users/cust1': {
      role: 'user', roles: ['user'], isActive: true, isBanned: false, vendorId: '',
      name: 'Karim', points: 0, totalEarnings: 0, referralCount: 0,
    },
  });
});

describe('step H: reviews are public to read', opts, () => {
  test(`${rtag} guest reads one review and the review list`, async () => {
    readable(await db(null).get('products/p1/reviews/cust2'), 'get');
    readable(await db(null).query('products/p1/reviews'), 'list');
  });

  test(`${rtag} customer reads one review, the list, and checks own (missing) review`, async () => {
    readable(await db('cust1').get('products/p1/reviews/cust2'), 'get');
    readable(await db('cust1').query('products/p1/reviews'), 'list');
    // "already reviewed?" = read own doc; missing doc must not be an error
    const own = await db('cust1').get('products/p1/reviews/cust1');
    if (LIVE_BEFORE_H) denied(own, 'own'); else if (own.status !== 404) allowed(own, 'own');
  });
});

describe('step H: no client writes to reviews (both rule sets)', opts, () => {
  test('customer may not create own review (only the function writes)', async () => {
    denied(await db('cust1').create('products/p1/reviews/cust1', review('cust1')));
  });

  test('customer may not update or delete own review', async () => {
    denied(await db('cust2').update('products/p1/reviews/cust2', { rating: 1, updatedAt: SERVER_TS }), 'update');
    denied(await db('cust2').delete('products/p1/reviews/cust2'), 'delete');
  });

  test('customer may not touch someone else\'s review', async () => {
    denied(await db('cust1').update('products/p1/reviews/cust2', { comment: 'x' }), 'update');
    denied(await db('cust1').delete('products/p1/reviews/cust2'), 'delete');
  });

  test('admin and super admin may not write reviews from the client either', async () => {
    denied(await db('admin').delete('products/p1/reviews/cust2'), 'admin delete');
    denied(await db('boss').set('products/p1/reviews/boss', review('boss')), 'boss create');
  });
});

describe('step H attacks: client-written referrals', opts, () => {
  test(`${tag} customer creates a referral for self, "Pending" with a big reward`, async () => {
    attack(await db('cust1').create('referrals/fake1', {
      referrerId: 'cust2', referredUserId: 'cust1', status: 'Pending',
      referrerReward: 10000, refereeReward: 10000, createdAt: SERVER_TS,
    }));
  });

  test(`${tag} customer creates an "approved" referral for self`, async () => {
    attack(await db('cust1').create('referrals/fake2', {
      referrerId: 'cust2', referredUserId: 'cust1', status: 'approved', referrerReward: 25, refereeReward: 25,
    }));
  });

  test(`${tag} staff with users.edit approves a referral from the client`, async () => {
    attack(await db('usersStaff').update('referrals/ref1', { status: 'Approved', approvedAt: SERVER_TS }));
  });

  test(`${tag} super admin deletes a referral from the client`, async () => {
    attack(await db('boss').delete('referrals/ref1'));
  });

  test('customer may not update or delete a referral (both rule sets)', async () => {
    denied(await db('cust1').update('referrals/ref1', { refereeReward: 999 }), 'update');
    denied(await db('cust1').delete('referrals/ref1'), 'delete');
  });

  test('reading: super admin and users.view staff read, customer and guest do not (both rule sets)', async () => {
    allowed(await db('boss').get('referrals/ref1'), 'boss');
    allowed(await db('usersStaff').query('referrals'), 'usersStaff list');
    denied(await db('cust1').get('referrals/ref1'), 'customer');
    denied(await db(null).query('referrals'), 'guest');
  });

  // Same permission list as before; on 438c4999 the four can() calls ran
  // past the 1000-expression limit for these two, so the admin referral
  // page could not even load the list for them.
  test(`${LIVE_BEFORE_H ? '[438c4999: 1000-expression limit]' : '[step H: canAnyOf]'} admin and wallet.edit staff read the referral list`, async () => {
    const ok = LIVE_BEFORE_H ? denied : allowed;
    ok(await db('admin').get('referrals/ref1'), 'admin get');
    ok(await db('admin').query('referrals'), 'admin list');
    ok(await db('walletStaff').query('referrals'), 'walletStaff list');
  });
});

describe('step H (ক): product rating fields', opts, () => {
  test('customer may not change ratingAvg / ratingCount / reviewCount / ratingTotal (both rule sets)', async () => {
    for (const f of ['ratingAvg', 'ratingCount', 'reviewCount', 'ratingTotal']) {
      denied(await db('cust1').update('products/p1', { [f]: 999 }), f);
    }
    denied(await db('cust1').set('products/p1', { ratingAvg: 5, reviewCount: inc(1) }, { merge: true }), 'merge');
  });

  test(`${tag} customer creates a product (vendorId = own uid) carrying a made-up rating`, async () => {
    attack(await db('cust1').create('products/fake', {
      name: 'Fake', price: 1, vendorId: 'cust1', ratingAvg: 5, ratingCount: 999, reviewCount: 999, ratingTotal: 4995,
    }));
  });

  test(`${tag} vendor creates own product carrying a made-up rating`, async () => {
    attack(await db('vendU1').create('products/v2', {
      name: 'V', price: 1, vendorId: 'vend1', vendorOwnerId: 'vendU1', ratingAvg: 5, reviewCount: 50,
    }));
  });

  test('vendor still creates own product without rating fields (both rule sets)', async () => {
    // step H2: the full pending shape vendor_products_page writes.
    allowed(await db('vendU1').create('products/v3', {
      name: 'V3', category: 'Mobile Parts', price: 1, mrp: 1, stock: 1, image: '', imageUrl: '', images: [],
      variants: [{ name: 'Default', price: 1, mrp: 1, stock: 1 }],
      vendorId: 'vend1', sellerId: 'vend1', vendorOwnerId: 'vendU1', vendorOwnerIds: ['vendU1'], sellerUid: 'vendU1',
      isMarketplace: true, approvalStatus: 'pending', isActive: false, isVisible: false, isPublished: false, showOnHome: false,
    }));
  });

  test('staff with products.edit (admin) still sets rating fields (both rule sets)', async () => {
    allowed(await db('admin').update('products/p1', { ratingAvg: 4.5 }));
  });
});

describe('step H (খ): points, totalEarnings, referralCount', opts, () => {
  test('customer may not change own points or totalEarnings (both rule sets)', async () => {
    denied(await db('cust1').update('users/cust1', { points: inc(2) }), 'points');
    denied(await db('cust1').update('users/cust1', { totalEarnings: 500 }), 'totalEarnings');
  });

  test(`${tag} customer raises own referralCount`, async () => {
    attack(await db('cust1').update('users/cust1', { referralCount: 99, updatedAt: SERVER_TS }));
  });

  test(`${tag} customer removes own referralCount`, async () => {
    // set without the key = remove it (affectedKeys sees the removal)
    attack(await db('cust1').set('users/cust1', {
      role: 'user', roles: ['user'], isActive: true, isBanned: false, vendorId: '',
      name: 'Karim', points: 0, totalEarnings: 0,
    }));
  });

  test(`${tag} new customer creates own profile with referralCount 50`, async () => {
    attack(await db('newbie').create('users/newbie', {
      uid: 'newbie', role: 'user', points: 0, totalEarnings: 0, referralCount: 50,
    }));
  });

  test(`${tag} staff with users.edit sets someone's referralCount`, async () => {
    attack(await db('usersStaff').update('users/cust1', { referralCount: 7 }));
  });

  test('new customer creates own profile as the app does (zeros) (both rule sets)', async () => {
    allowed(await db('newbie').create('users/newbie', {
      uid: 'newbie', name: 'New', role: 'user', roles: ['user'], isActive: true, isBanned: false,
      points: 0, totalEarnings: 0, referralCount: 0, refCode: '', createdAt: SERVER_TS,
    }));
  });

  test('customer still edits own name and refCode (both rule sets)', async () => {
    allowed(await db('cust1').update('users/cust1', { name: 'Karim Uddin', refCode: 'CUST1X', updatedAt: SERVER_TS }));
  });

  test('wallet.edit staff (super admin) still adjusts points / totalEarnings (both rule sets)', async () => {
    allowed(await db('boss').update('users/cust1', { points: inc(10), totalEarnings: inc(10), updatedAt: SERVER_TS }));
  });
});
