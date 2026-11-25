'use strict';

const path = require('node:path');
const { loadRules, clearData, seed } = require('./emu');

const REPO = path.resolve(__dirname, '..', '..');
const RULES_FILE = path.resolve(REPO, process.env.RULES_FILE || 'firestore.rules');
// Step B rollback = the step A rules (closed holes) with the private halves
// shut. It lives in rules-backup but is NOT "old rules" for the hole tests.
const STEP_B_ROLLBACK = /rollback-step-b/.test(RULES_FILE);
// The live copy from just before step F (be7e9c8a) is a current rule set,
// not "old rules": only the step F suite expects a difference there.
const LIVE_BEFORE_F = /live-be7e9c8a/.test(RULES_FILE);
// Same for the live copy from just before step G (700f57c7).
const LIVE_BEFORE_G = /live-700f57c7/.test(RULES_FILE);
const OLD_RULES = /rules-backup/.test(RULES_FILE) && !STEP_B_ROLLBACK && !LIVE_BEFORE_F && !LIVE_BEFORE_G;
// The rollback file = old rules with only settings/app_secrets locked.
const KEEP_SECRETS = /keep-secrets/.test(RULES_FILE);
// Step 6 (current firestore.rules): the move script has run, so the public
// vendor / rider docs hold no private key. Old copies (and the step B
// rollback, which runs after the restore script) keep the pre-move docs.
const POST_MOVE = !OLD_RULES && !STEP_B_ROLLBACK;
const { VENDOR_PRIVATE_KEYS, RIDER_PRIVATE_KEYS } = require('../../functions/scripts/movePrivateProfiles');

function withoutPrivateKeys(docs) {
  const out = { ...docs };
  for (const [p, data] of Object.entries(out)) {
    const keys = p.startsWith('vendors/') ? VENDOR_PRIVATE_KEYS
      : p.startsWith('deliveryPartners/') ? RIDER_PRIVATE_KEYS : null;
    if (keys) out[p] = Object.fromEntries(Object.entries(data).filter(([k]) => !keys.includes(k)));
  }
  return out;
}

// Cast:
//   cust1, cust2          ordinary customers
//   vendU1 / vendU2       vendor owners of vendors/vend1 and vendors/vend2
//   rider1                approved rider; rider2 = still pending applicant
//   admin                 role admin (default admin permissions, no settings.edit)
//   boss                  role superAdmin
//   analyst               role staff with analytics.view
// Every live users/* doc has role, roles, isActive, isBanned and vendorId
// (checked 2026-11-17), so the fixtures do too.
const u = (role, extra = {}) => ({
  role, roles: ['user', role], isActive: true, isBanned: false, vendorId: '', ...extra,
});
const users = {
  'users/cust1': u('user'),
  'users/cust2': u('user'),
  'users/vendU1': u('vendor', { vendorId: 'vend1' }),
  'users/vendU2': u('vendor', { vendorId: 'vend2' }),
  'users/rider1': u('deliveryPartner'),
  'users/rider2': u('user'),
  'users/rider3': u('deliveryPartner'),
  'users/admin': u('admin'),
  'users/boss': u('superAdmin'),
  'users/analyst': u('staff', { permissions: ['analytics.view'] }),
  // Step B staff: one permission each.
  'users/vendStaff': u('staff', { permissions: ['vendors.view'] }),
  'users/payStaff': u('staff', { permissions: ['vendors.payouts'] }),
  'users/assignStaff': u('staff', { permissions: ['orders.assign_rider'] }),
  'users/riderStaff': u('staff', { permissions: ['delivery.view'] }),
  // A vendor applicant: owns vendors/vendNew (doc id = uid), not approved yet.
  'users/vendNew': u('user'),
};

function baseDocs() {
  return {
    ...users,
    'vendors/vend1': {
      ownerId: 'vendU1', userId: 'vendU1', shopName: 'Shop One', phone: '01700000001',
      nidFront: 'https://example.invalid/nid?token=x', status: 'approved', isActive: true, isVerified: true,
    },
    'vendors/vend2': { ownerId: 'vendU2', userId: 'vendU2', shopName: 'Shop Two', status: 'approved', isActive: true, isVerified: true },
    // Step B: the private halves. vend1's public doc above still carries the
    // old copies (state before the move script); vend2's is already clean.
    'vendor_private/vend1': {
      vendorId: 'vend1', phone: '01700000001', nidFront: 'https://example.invalid/nid?token=x',
      payoutAccount: 'bkash 017', commissionPercent: 10, withdrawableBalance: 500,
    },
    'vendor_private/vend2': { vendorId: 'vend2', phone: '01700000002', payoutAccount: 'nagad 018' },
    'vendors/vendNew': { ownerId: 'vendNew', userId: 'vendNew', shopName: 'New Shop', status: 'pending', isActive: false, isVerified: false },
    'delivery_partner_private/rider1': {
      uid: 'rider1', nidNumber: '1234567890', nidFrontUrl: 'https://example.invalid/r?token=y', address: 'House 9',
    },
    'delivery_partner_private/rider3': { uid: 'rider3', nidNumber: '555' },
    'deliveryPartners/rider1': {
      uid: 'rider1', name: 'Rider One', phone: '01800000001', nidNumber: '1234567890',
      nidFrontUrl: 'https://example.invalid/r?token=y', status: 'approved', isActive: true,
      totalDeliveries: 2, totalEarning: 120, withdrawnAmount: 0, pendingAmount: 0, codDue: 500,
    },
    // A second approved rider, to try someone else's deliveries.
    'deliveryPartners/rider3': {
      uid: 'rider3', name: 'Rider Three', status: 'approved', isActive: true,
      totalDeliveries: 0, totalEarning: 0, withdrawnAmount: 0, pendingAmount: 0, codDue: 0,
    },
    'deliveryPartners/rider2': {
      uid: 'rider2', name: 'Rider Two', status: 'pending', isActive: false,
      totalDeliveries: 0, totalEarning: 0, withdrawnAmount: 0, pendingAmount: 0, codDue: 0,
    },
    // cust1's order: has vend1 items, assigned to rider1, not picked up yet.
    'orders/o1': {
      userId: 'cust1', userPhone: '01900000001', address: { address: 'House 1' },
      status: 'pending', paymentMethod: 'COD', paymentStatus: 'unpaid',
      vendorIds: ['vend1'], vendorOwnerIds: ['vendU1'],
      deliveryPartnerId: 'rider1', deliveryStatus: 'assigned',
      grandTotal: 500, deliveryCharge: 60,
    },
    // cust2's order: nobody else's business.
    'orders/o2': {
      userId: 'cust2', userPhone: '01900000002', status: 'pending', paymentMethod: 'COD',
      vendorIds: ['vend2'], vendorOwnerIds: ['vendU2'], grandTotal: 300, deliveryCharge: 60,
    },
    // cust1's confirmed order (too late for the customer to cancel).
    'orders/o3': { userId: 'cust1', status: 'confirmed', paymentMethod: 'COD', grandTotal: 200, deliveryCharge: 60 },
    // Delivered by rider1, earning not recorded yet.
    'orders/o4': {
      userId: 'cust2', status: 'delivered', deliveryStatus: 'delivered', paymentStatus: 'paid',
      paymentMethod: 'COD', deliveryPartnerId: 'rider1', grandTotal: 500, deliveryCharge: 60,
    },
    // Delivered by rider1, paid online (not COD): codDue must not grow.
    'orders/o5': {
      userId: 'cust1', status: 'delivered', deliveryStatus: 'delivered', paymentStatus: 'paid',
      paymentMethod: 'online', deliveryPartnerId: 'rider1', grandTotal: 700, deliveryCharge: 80,
    },
    'vendorWithdrawRequests/w1': {
      vendorId: 'vend1', vendorOwnerId: 'vendU1', amount: 150, status: 'pending', payoutAccount: 'bkash 017',
    },
    'deliveryEarnings/rider1_old': { deliveryPartnerId: 'rider1', orderId: 'old', amount: 60, partnerSynced: true },
    // Server-only collections (14b step D), shaped like the live docs.
    'conversations/app_cust1': {
      channel: 'app', externalUserId: 'cust1', customerName: 'C One', status: 'open', needsHuman: false,
      lastMessagePreview: 'hello', unreadByAdmin: true,
    },
    'conversations/app_cust1/messages/m1': { sender: 'customer', text: 'hello' },
    'marketplace_connections/aliexpress': {
      provider: 'aliexpress', status: 'connected', accessToken: 'SECRET-ACCESS', refreshToken: 'SECRET-REFRESH',
    },
    'rateLimits/ip_203_0_113_5': { count: 1 },
    'whatsappProcessedMessages/wamid_1': { messageId: 'wamid.1' },
    'delivery_logs/dl1': { orderId: 'o4', riderId: 'rider1', userId: 'cust2', total: 500, status: 'delivered' },
    'searchImportLog/q1': { query: 'battery', status: 'done', waitingUserIds: ['cust1'] },
    // ledger-1: a ledger entry, an order that already has a priceCheck, a vendor in debt.
    'commission_ledger/o1_vend1': {
      orderId: 'o1', vendorId: 'vend1', subtotal: 500, adminCommission: 50, vendorPayable: 450, status: 'pending',
    },
    'orders/o6': {
      userId: 'cust2', status: 'pending', paymentMethod: 'COD', grandTotal: 100,
      priceCheck: { ok: false, clientTotal: 1, serverTotal: 100, mismatchedItems: [] },
    },
    'vendors/vendDebt': { ownerId: 'vendDebtU', shopName: 'Debt Shop', status: 'approved', isActive: true },
    'vendor_private/vendDebt': { vendorId: 'vendDebt', withdrawableBalance: -100, totalPaidOut: 0 },
    // Left to the catch-all until step E.
    'analytics_daily/2026-06-06': { date: '2026-06-06', orderCount: 1, revenue: 500 },
    'system_locks/l1': { locked: false },
    'settings/app': {
      deliveryCharge: 60, supportPhone: '0170',
      socialApi: { facebookPageId: '123', tiktokClientKey: 'abc' },
    },
    'settings/app_secrets': { socialApi: { facebookPageAccessToken: 'SECRET-TOKEN' } },
    'doctor_appointments/a1': { userId: 'cust1', bookedByUserId: 'cust1', patientName: 'X', phone: '01' },
  };
}

async function resetWorld() {
  await loadRules(RULES_FILE);
  await clearData();
  await seed(POST_MOVE ? withoutPrivateKeys(baseDocs()) : baseDocs());
}

module.exports = { resetWorld, RULES_FILE, OLD_RULES, KEEP_SECRETS, STEP_B_ROLLBACK, POST_MOVE };
