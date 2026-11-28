'use strict';

// 14b step F: changedOnly / changedAny used diff().changedKeys(), which
// misses keys that are newly ADDED or DELETED. Every attack below adds or
// removes a forbidden key.
//   RULES_FILE=docs/security/rules-backup/firestore.rules.live-be7e9c8a
//     -> the rules live before step F: every attack SUCCEEDS (proof of the gap)
//   firestore.rules (step F) -> every attack is DENIED
// The app's real writes (second half) are allowed on both, except the two
// staff writes that hit the 1000-expression limit before step F.
// Skipped for the older copies (they have other holes, see holes.test.js).

const { describe, test, beforeEach } = require('node:test');
const { db, seed, allowed, denied, SERVER_TS, inc } = require('./emu');
const { resetWorld, RULES_FILE, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const LIVE_BEFORE_F = /live-be7e9c8a/.test(RULES_FILE);
const opts = {
  skip: (OLD_RULES || STEP_B_ROLLBACK) && !LIVE_BEFORE_F ? 'step F suite (older rules copy)' : false,
};
const attack = LIVE_BEFORE_F ? allowed : denied;
const tag = LIVE_BEFORE_F ? '[be7e9c8a: gap open]' : '[step F: closed]';
// Fixed by step F (1000-expression limit): refused before, allowed now.
const limitFixed = LIVE_BEFORE_F ? denied : allowed;

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-chalakchar-rules';
const DOCS = `projects/${PROJECT}/databases/(default)/documents/`;
// What FieldValue.delete() sends: the key in the update mask, not in fields.
const removeKeys = (path, keys) => ({ update: { name: DOCS + path, fields: {} }, updateMask: { fieldPaths: keys } });
const remove = (who, path, keys) => db(who).batch([removeKeys(path, keys)]);

const staff = (permissions, extra = {}) => ({
  role: 'staff', roles: ['user', 'staff'], permissions, isActive: true, isBanned: false, vendorId: '', ...extra,
});

beforeEach(async () => {
  await resetWorld();
  await seed({
    // Like cust1, but without a vendorId key (older profile shape).
    'users/noVid': { role: 'user', roles: ['user'], isActive: true, isBanned: false },
    // A new user as auth_service.createOrGetUser writes it.
    'users/fresh': {
      uid: 'fresh', role: 'user', roles: ['user'], sellerStatus: 'none', vendorId: null,
      points: 0, totalEarnings: 0, isActive: true, isBanned: false, whatsappOptIn: false, whatsappNumber: '',
    },
    'users/editStaff': staff(['users.edit']),
    'users/blockStaff': staff(['users.block']),
    'users/walletStaff': staff(['wallet.edit']),
    'users/permStaff': staff(['users.permissions']),
    'users/vendApprover': staff(['vendors.approve']),
    'users/bannedStaff': staff(['vendors.view'], { isActive: false, isBanned: true }),
    'users/bannedCust': { role: 'user', roles: ['user'], isActive: false, isBanned: true, vendorId: '' },
    'users/notifAdmin': { role: 'admin', roles: ['user', 'admin'], permissions: ['orders.view'], isActive: true, isBanned: false, vendorId: '' },
    'notifications/n1': { userId: 'cust1', title: 'Order placed', isRead: false },
    'deliveryEarnings/rider1_o4': {
      deliveryPartnerId: 'rider1', orderId: 'o4', amount: 60, paymentMethod: 'cod', status: 'pending',
      grandTotal: 500, deliveryCharge: 60, partnerSynced: false,
    },
    'deliveryPartners/rider3': {
      uid: 'rider3', name: 'Rider Three', status: 'approved', isActive: true,
      totalDeliveries: 1, totalEarning: 60, withdrawnAmount: 0, pendingAmount: 0, codDue: 0,
      lastSyncedOrderId: 'o9', lastEarningSyncedAt: new Date('2026-11-01T00:00:00Z'),
    },
  });
});

describe('step F attacks: add or remove a forbidden key', opts, () => {
  test(`${tag} customer adds permissions to own profile, then reads vendor bank/bKash doc`, async () => {
    const r = await db('cust1').update('users/cust1', { permissions: ['users.view', 'vendors.payouts', 'settings.edit'] });
    attack(r);
    if (LIVE_BEFORE_F) allowed(await db('cust1').get('vendor_private/vend1'), 'what the gap gives');
    denied(await db('cust2').update('users/cust2', { roles: ['user', 'superAdmin'] }), 'changing an existing key was always refused');
  });

  test(`${tag} customer adds permissions through the "login refresh" and "seller link" rules`, async () => {
    attack(await db('fresh').update('users/fresh', { name: 'X', permissions: ['settings.edit'] }));
    attack(await db('fresh').update('users/fresh', { sellerStatus: 'pending', vendorId: 'fresh', permissions: ['settings.edit'] }));
  });

  test(`${tag} customer without a vendorId key adds another vendor's id, then changes its payout account`, async () => {
    attack(await db('noVid').update('users/noVid', { vendorId: 'vend1' }));
    if (LIVE_BEFORE_F) allowed(await db('noVid').update('vendor_private/vend1', { payoutAccount: 'attacker' }), 'what the gap gives');
  });

  test(`${tag} customer adds vendorStatus / isVendor / rider keys to own profile`, async () => {
    // vendorStatus was in no list at all; the others were not either.
    for (const k of ['vendorStatus', 'isVendor', 'isDeliveryPartner', 'deliveryPartnerStatus', 'deliveryPartnerId']) {
      const v = k === 'vendorStatus' || k === 'deliveryPartnerStatus' ? 'approved' : k === 'deliveryPartnerId' ? 'cust1' : true;
      const r = await db('cust1').update('users/cust1', { [k]: v });
      // vendorStatus etc. had no protection before step F, so these are open on be7e9c8a too.
      attack(r, k);
    }
  });

  test(`${tag} banned staff / banned customer delete their own ban keys`, async () => {
    attack(await remove('bannedStaff', 'users/bannedStaff', ['isBanned', 'isActive']));
    if (LIVE_BEFORE_F) allowed(await db('bannedStaff').get('vendor_private/vend1'), 'staff powers back');
    attack(await remove('bannedCust', 'users/bannedCust', ['isBanned', 'isActive']));
  });

  test(`${tag} users.edit staff adds permissions / vendorStatus to a customer`, async () => {
    attack(await db('editStaff').update('users/cust1', { permissions: ['users.permissions', 'settings.edit'] }));
    attack(await db('editStaff').update('users/cust2', { vendorStatus: 'approved' }));
  });

  // On be7e9c8a this one was refused only because the request ran out of the
  // 1000-expression budget (the role-change rule was evaluated last), not
  // because the gap was closed. With the budget fixed it must stay refused.
  test('role change by users.edit staff smuggles permissions in: refused', async () => {
    denied(await db('editStaff').update('users/cust1', { role: 'vendor', permissions: ['settings.edit'] }));
  });

  test(`${tag} admin adds a non-notification permission to own doc`, async () => {
    attack(await db('admin').update('users/admin', { permissions: ['users.permissions'] }));
  });

  test(`${tag} rider deletes codDue (COD debt) / withdrawnAmount from own doc`, async () => {
    denied(await db('rider1').update('deliveryPartners/rider1', { codDue: 0 }), 'changing it was always refused');
    attack(await remove('rider1', 'deliveryPartners/rider1', ['codDue']));
    attack(await remove('rider1', 'deliveryPartners/rider1', ['withdrawnAmount']));
  });

  test(`${tag} rider deletes lastSyncedOrderId + lastEarningSyncedAt (re-sync guard)`, async () => {
    attack(await remove('rider3', 'deliveryPartners/rider3', ['lastSyncedOrderId', 'lastEarningSyncedAt']));
  });

  test(`${tag} rider adds approval / settlement keys to own doc`, async () => {
    attack(await db('rider1').update('deliveryPartners/rider1', { approvedBy: 'rider1' }));
    attack(await db('rider1').update('deliveryPartners/rider1', { lastCodSettlementAt: SERVER_TS }));
  });

  test(`${tag} rider earning: mark synced and add / delete a key`, async () => {
    attack(await db('rider1').update('deliveryEarnings/rider1_o4', { partnerSynced: true, bonus: 999 }));
    attack(await remove('rider1', 'deliveryEarnings/rider1_o4', ['amount']));
  });

  test(`${tag} vendor adds approvedAt / deletes isVerified on own public doc`, async () => {
    attack(await db('vendU1').update('vendors/vend1', { approvedAt: SERVER_TS }));
    attack(await remove('vendU1', 'vendors/vend1', ['isVerified']));
    attack(await db('vendNew').update('vendors/vendNew', { status: 'pending', isActive: false, isVerified: false, approvedAt: SERVER_TS }));
  });

  test(`${tag} customer marks a notification read and adds a key`, async () => {
    attack(await db('cust1').update('notifications/n1', { isRead: true, extra: 'x' }));
  });
});

describe('step F: the app\'s real writes still work', opts, () => {
  test('customer: profile save, login refresh, logout, FCM token, referral code, notification prefs', async () => {
    const c = db('fresh');
    allowed(await c.set('users/fresh', {
      name: 'N', phone: '0', age: '30', gender: 'm', address: 'a', division: 'd', district: 'd', upazila: 'u', updatedAt: SERVER_TS,
    }, { merge: true }), 'profile_page.dart:107');
    allowed(await c.set('users/fresh', {
      uid: 'fresh', email: 'x', name: 'N', age: '30', gender: 'm', address: 'a', phone: '0',
      division: 'd', district: 'd', upazila: 'u', profileCompleted: true, updatedAt: SERVER_TS,
    }, { merge: true }), 'edit_profile_page.dart:88');
    allowed(await c.set('users/fresh', {
      uid: 'fresh', email: 'x', emailVerified: true, photoUrl: 'p', providerIds: ['google.com'], updatedAt: SERVER_TS, lastLoginAt: SERVER_TS,
    }, { merge: true }), 'auth_service createOrGetUser (existing user)');
    allowed(await c.set('users/fresh', { lastLogoutAt: SERVER_TS, updatedAt: SERVER_TS }, { merge: true }), 'signOut');
    allowed(await c.set('users/fresh', { fcmToken: 't', fcmTokens: ['t'], lastTokenAt: SERVER_TS }, { merge: true }), 'notification_service');
    allowed(await c.set('users/fresh', { refCode: 'ABC', updatedAt: SERVER_TS }, { merge: true }), 'referral_service');
    allowed(await c.set('users/fresh', { notificationPrefs: { orders: true }, marketing: false, updatedAt: SERVER_TS }, { merge: true }), 'notification_prefs_section');
  });

  test('customer: WhatsApp opt-in and opt-out (auth_service:725)', async () => {
    const c = db('fresh');
    allowed(await c.set('users/fresh', {
      whatsappOptIn: true, whatsappNumber: '8801712345678', whatsappConsentVersion: '2026-07',
      whatsappConsentSource: 'profile', whatsappOptInAt: SERVER_TS, updatedAt: SERVER_TS,
    }, { merge: true }));
    allowed(await c.set('users/fresh', { whatsappOptIn: false, whatsappOptOutAt: SERVER_TS, updatedAt: SERVER_TS }, { merge: true }));
    denied(await c.set('users/fresh', { whatsappNumber: '123' }, { merge: true }), 'bad number still refused');
  });

  test('customer: seller application links the user doc (vendor_apply_page:311, auth_service:400)', async () => {
    // Step H2: the user doc no longer takes a vendorId from the user (staff
    // set it on approval); the application sets sellerStatus only.
    const H2_RULES = !/rules-backup/.test(RULES_FILE);
    (H2_RULES ? denied : allowed)(await db('fresh').set('users/fresh', { vendorId: 'fresh', sellerStatus: 'pending', updatedAt: SERVER_TS }, { merge: true }), 'with own vendorId');
    // A doc without vendorId (older shape) linking its OWN id.
    (H2_RULES ? denied : allowed)(await db('noVid').set('users/noVid', { vendorId: 'noVid', sellerStatus: 'pending', updatedAt: SERVER_TS }, { merge: true }), 'older shape');
    allowed(await db('fresh').set('users/fresh', { sellerStatus: 'pending', updatedAt: SERVER_TS }, { merge: true }), 'sellerStatus only');
  });

  test('vendor: application re-save, pending and approved (vendor_apply_page:302)', async () => {
    const payload = (status, active, verified, owner) => ({
      shopName: 'S', shopArea: 'A', businessType: 'general', ownerId: owner, userId: owner,
      status, isActive: active, isVerified: verified, updatedAt: SERVER_TS,
    });
    allowed(await db('vendNew').set('vendors/vendNew', payload('pending', false, false, 'vendNew'), { merge: true }), 'pending applicant');
    allowed(await db('vendU1').set('vendors/vend1', payload('approved', true, true, 'vendU1'), { merge: true }), 'approved vendor');
  });

  test('rider: mark earning synced, as the dashboard does (step 5)', async () => {
    allowed(await db('rider1').set('deliveryEarnings/rider1_o4', { partnerSynced: true, updatedAt: SERVER_TS }, { merge: true }));
  });

  test('rider: first sync adds lastSyncedOrderId / lastEarningSyncedAt (keys absent before)', async () => {
    const r = db('rider1');
    allowed(await r.set('deliveryPartners/rider1', {
      totalDeliveries: inc(1), totalEarning: inc(60), codDue: inc(500),
      updatedAt: SERVER_TS, lastEarningSyncedAt: SERVER_TS, lastSyncedOrderId: 'o4',
    }, { merge: true }));
  });

  test('customer: notification marked read (notifications_page:19)', async () => {
    allowed(await db('cust1').set('notifications/n1', { isRead: true, readAt: SERVER_TS, updatedAt: SERVER_TS }, { merge: true }));
  });

  test('admin: rider approval syncs the user doc (admin_delivery_partner_approval_page:176)', async () => {
    const sync = {
      isDeliveryPartner: true, deliveryPartnerStatus: 'approved', deliveryPartnerId: 'rider2', updatedAt: SERVER_TS,
      role: 'deliveryPartner', roles: ['user', 'deliveryPartner'], isActive: true, isBanned: false,
    };
    allowed(await db('boss').set('users/rider2', sync, { merge: true }), 'super admin');
    await resetWorld();
    await seed({ 'users/editStaff': staff(['users.edit']) });
    limitFixed(await db('editStaff').set('users/rider2', sync, { merge: true }), 'users.edit staff [1000-expression limit fixed]');
  });

  test('admin: vendor approval syncs the user doc (admin_vendors_page:392) [1000-expression limit fixed]', async () => {
    limitFixed(await db('vendApprover').set('users/vendNew', {
      role: 'vendor', roles: ['user', 'vendor'], sellerStatus: 'approved', vendorId: 'vendNew', isVendor: true, updatedAt: SERVER_TS,
    }, { merge: true }));
  });

  test('staff: block and unblock a customer (auth_service:660/670) [1000-expression limit fixed]', async () => {
    limitFixed(await db('blockStaff').set('users/cust1', {
      isActive: false, isBanned: true, banReason: 'spam', bannedAt: SERVER_TS, updatedAt: SERVER_TS,
    }, { merge: true }), 'block');
    if (!LIVE_BEFORE_F) {
      // unblock deletes banReason (FieldValue.delete)
      allowed(await db('blockStaff').batch([{
        update: { name: DOCS + 'users/cust1', fields: { isActive: { booleanValue: true }, isBanned: { booleanValue: false } } },
        updateMask: { fieldPaths: ['isActive', 'isBanned', 'banReason'] },
      }]), 'unblock');
      denied(await db('blockStaff').set('users/cust2', { isBanned: true, permissions: ['settings.edit'] }, { merge: true }), 'block + permissions');
      denied(await db('blockStaff').set('users/boss', { isBanned: true }, { merge: true }), 'never a super admin');
    }
  });

  test('staff: wallet adjustment (admin_users_page:450) [1000-expression limit fixed]', async () => {
    limitFixed(await db('walletStaff').set('users/cust1', { points: 50, totalEarnings: 50, updatedAt: SERVER_TS }, { merge: true }));
    if (!LIVE_BEFORE_F) {
      denied(await db('walletStaff').set('users/cust2', { points: 5, permissions: ['wallet.edit'] }, { merge: true }), 'wallet + permissions');
      denied(await db('walletStaff').set('users/walletStaff', { points: 5 }, { merge: true }), 'not own wallet');
    }
  });

  test('staff: permissions of a staff user (admin_users_page:525) [1000-expression limit fixed]', async () => {
    limitFixed(await db('permStaff').set('users/analyst', { permissions: ['analytics.view', 'orders.view'], updatedAt: SERVER_TS }, { merge: true }));
    denied(await db('permStaff').set('users/analyst', { permissions: ['settings.edit'] }, { merge: true }), 'dangerous permission');
  });

  test('admin / super admin: Notifications page adds notifications.* to own doc (admin_notifications_page:83)', async () => {
    const notif = ['notifications.view', 'notifications.send', 'notifications.manage', 'notifications.delete', 'notifications.read', 'notifications.open_related'];
    allowed(await db('admin').set('users/admin', { permissions: notif, updatedAt: SERVER_TS }, { merge: true }), 'admin without permissions');
    allowed(await db('boss').set('users/boss', { permissions: notif, updatedAt: SERVER_TS }, { merge: true }), 'super admin');
    if (!LIVE_BEFORE_F) {
      // with an existing permissions list (arrayUnion keeps the old entries)
      allowed(await db('notifAdmin').set('users/notifAdmin', { permissions: ['orders.view', ...notif], updatedAt: SERVER_TS }, { merge: true }));
      denied(await db('notifAdmin').set('users/notifAdmin', { permissions: notif }, { merge: true }), 'dropping orders.view is not this rule');
      denied(await db('cust1').set('users/cust1', { permissions: notif }, { merge: true }), 'a customer may not');
    }
  });
});
