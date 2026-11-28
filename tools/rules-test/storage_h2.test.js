'use strict';

// Step H2: product images in Storage. Runs with the Firestore AND Storage
// emulators (storage.rules reads users/ and vendors/):
//   firebase emulators:exec --only firestore,storage --project demo-chalakchar-rules \
//     "node --test tools/rules-test/storage_h2.test.js"
// The Storage emulator loads storage.rules from firebase.json. While that
// file is byte-identical to the live ruleset 2ce1afb0 (sha256 7ae2db76...)
// the attacks are expected to SUCCEED; any other storage.rules = fixed.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { db, allowed } = require('./emu');
const { resetWorld } = require('./fixtures');

const STORAGE_RULES = path.resolve(__dirname, '..', '..', 'storage.rules');
const LIVE_SHA = '7ae2db7616de21ca';
const GAP_OPEN = crypto.createHash('sha256').update(fs.readFileSync(STORAGE_RULES)).digest('hex').startsWith(LIVE_SHA);
const tag = GAP_OPEN ? '[2ce1afb0: gap open]' : '[fixed: closed]';

const HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:9199';
const BUCKET = `${process.env.GCLOUD_PROJECT || 'demo-chalakchar-rules'}.appspot.com`;
const ROOT = `http://${HOST}/v0/b/${BUCKET}/o`;
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 0xff, 0xd9]);

function tokenFor(uid) {
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const project = process.env.GCLOUD_PROJECT || 'demo-chalakchar-rules';
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${project}`, aud: project, iat: now, exp: now + 3600,
    auth_time: now, sub: uid, user_id: uid, firebase: { sign_in_provider: 'password', identities: {} },
  })}.`;
}
const auth = (as) => (as === 'owner' ? { Authorization: 'Bearer owner' } : as ? { Authorization: `Firebase ${tokenFor(as)}` } : {});
async function upload(as, p) {
  const r = await fetch(`${ROOT}?name=${encodeURIComponent(p)}`, {
    method: 'POST', headers: { ...auth(as), 'Content-Type': 'image/jpeg' }, body: JPEG,
  });
  return r.status;
}
const ok = (s, what) => assert.ok(s >= 200 && s < 300, `expected ALLOWED ${what}, got ${s}`);
const no = (s, what) => assert.equal(s, 403, `expected DENIED ${what}, got ${s}`);
const attack = GAP_OPEN ? ok : no;

beforeEach(async () => {
  await resetWorld();
  ok(await upload('owner', 'products/shop.jpg'), 'seed shop image');
  ok(await upload('owner', 'product_images/shop2.jpg'), 'seed shop image 2');
});

describe('storage step H2: product images', () => {
  test('a plain customer may not upload product images (both rule sets)', async () => {
    no(await upload('cust2', 'products/new.jpg'), 'products/');
  });

  test(`${tag} a customer who set own users.vendorId counts as a vendor and overwrites a shop product image`, async () => {
    allowed(await db('cust1').update('users/cust1', { vendorId: 'cust1' }));
    attack(await upload('cust1', 'products/shop.jpg'), 'overwrite products/shop.jpg');
    attack(await upload('cust1', 'product_images/shop2.jpg'), 'overwrite product_images/shop2.jpg');
  });

  test(`${tag} an approved vendor overwrites a shop product image`, async () => {
    attack(await upload('vendU1', 'products/shop.jpg'));
  });

  test(`${tag} a plain customer stores public files under vendor_products/{own uid}/`, async () => {
    attack(await upload('cust2', 'vendor_products/cust2/a.jpg'));
  });

  test('nobody uploads into another vendor\'s vendor_products folder (both rule sets)', async () => {
    no(await upload('cust1', 'vendor_products/vend1/a.jpg'), 'customer');
  });

  test('the approved vendor uploads into own vendor_products folder (both rule sets)', async () => {
    ok(await upload('vendU1', 'vendor_products/vend1/a.jpg'));
  });
});
