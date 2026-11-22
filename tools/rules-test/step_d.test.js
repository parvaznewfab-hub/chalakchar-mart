'use strict';

// 14b step D: server-only collections. Only Cloud Functions (admin SDK)
// read and write them; no app role may, superAdmin and admin included, and
// the catch-all must not open them to staff / analytics.view.
// Skipped when RULES_FILE points at an old copy or the step B rollback.

const { describe, test, beforeEach } = require('node:test');
const { db, denied, allowed } = require('./emu');
const { resetWorld, OLD_RULES, STEP_B_ROLLBACK } = require('./fixtures');

const opts = {
  skip: OLD_RULES || STEP_B_ROLLBACK ? 'step D suite (RULES_FILE is an old copy / the step B rollback)' : false,
};

beforeEach(resetWorld);

// Everyone the app knows: no login, customers (cust1 is the conversation's
// own customer), vendor, rider, staff with analytics.view, admin, superAdmin.
const everyone = [null, 'cust1', 'cust2', 'vendU1', 'rider1', 'analyst', 'vendStaff', 'riderStaff', 'admin', 'boss'];

const CLOSED = [
  { doc: 'conversations/app_cust1', collection: 'conversations' },
  { doc: 'conversations/app_cust1/messages/m1', collection: 'conversations/app_cust1/messages' },
  { doc: 'marketplace_connections/aliexpress', collection: 'marketplace_connections' },
  { doc: 'rateLimits/ip_203_0_113_5', collection: 'rateLimits' },
  { doc: 'whatsappProcessedMessages/wamid_1', collection: 'whatsappProcessedMessages' },
  { doc: 'delivery_logs/dl1', collection: 'delivery_logs' },
  { doc: 'searchImportLog/q1', collection: 'searchImportLog' },
];

describe('step D: server-only collections closed to every app role', opts, () => {
  for (const { doc, collection } of CLOSED) {
    test(`${collection}: nobody reads, lists, creates, updates or deletes`, async () => {
      for (const who of everyone) {
        denied(await db(who).get(doc), `get ${doc} as ${who}`);
        denied(await db(who).query(collection), `list ${collection} as ${who}`);
        denied(await db(who).set(doc, { x: 1 }, { merge: true }), `update ${doc} as ${who}`);
        denied(await db(who).create(`${collection}/new1`, { x: 1 }), `create in ${collection} as ${who}`);
        denied(await db(who).delete(doc), `delete ${doc} as ${who}`);
      }
    });
  }

  test('catch-all still works for collections without their own rule (unchanged in step D)', async () => {
    // analytics_daily and system_locks are deliberately left for step E.
    // (get, not list: in the emulator a list served only by the catch-all
    // fails on request.path; that was so before step D too.)
    allowed(await db('analyst').get('analytics_daily/2026-06-06'));
    allowed(await db('admin').get('system_locks/l1'));
    denied(await db('cust1').get('analytics_daily/2026-06-06'));
  });

  test('before step D the catch-all opened these to staff: the same get as analyst now fails', async () => {
    // Regression guard for the exclusion list: analyst (staff + analytics.view)
    // is exactly who the catch-all serves.
    for (const { doc } of CLOSED) denied(await db('analyst').get(doc), doc);
  });
});
