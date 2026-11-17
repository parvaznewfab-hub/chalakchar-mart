'use strict';

const path = require('node:path');
const { loadRules, clearData, seed } = require('./emu');

const REPO = path.resolve(__dirname, '..', '..');
const RULES_FILE = path.resolve(REPO, process.env.RULES_FILE || 'firestore.rules');
const OLD_RULES = /rules-backup/.test(RULES_FILE);
// The rollback file = old rules with only settings/app_secrets locked.
const KEEP_SECRETS = /keep-secrets/.test(RULES_FILE);

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
};

function baseDocs() {
  return {
    ...users,
    'vendors/vend1': {
      ownerId: 'vendU1', userId: 'vendU1', shopName: 'Shop One', phone: '01700000001',
      nidFront: 'https://example.invalid/nid?token=x', status: 'approved', isActive: true, isVerified: true,
    },
    'vendors/vend2': { ownerId: 'vendU2', userId: 'vendU2', shopName: 'Shop Two', status: 'approved', isActive: true, isVerified: true },
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
  await seed(baseDocs());
}

module.exports = { resetWorld, RULES_FILE, OLD_RULES, KEEP_SECRETS };
