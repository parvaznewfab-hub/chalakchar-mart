'use strict';

// storage.rules for vendor / rider identity documents (14b step B).
// Runs with the Firestore AND Storage emulators (the rules read users/,
// vendors/ and deliveryPartners/ from Firestore): node tools/rules-test/run-storage.js
//
// "read" = download (alt=media) and metadata GET. The metadata response is
// what getDownloadURL() uses to hand out a token, so both must be refused.

const { describe, test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { resetWorld } = require('./fixtures');

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

async function upload(as, path) {
  const r = await fetch(`${ROOT}?name=${encodeURIComponent(path)}`, {
    method: 'POST', headers: { ...auth(as), 'Content-Type': 'image/jpeg' }, body: JPEG,
  });
  return r.status;
}
async function download(as, path) {
  return (await fetch(`${ROOT}/${encodeURIComponent(path)}?alt=media`, { headers: auth(as) })).status;
}
async function metadata(as, path) {
  return (await fetch(`${ROOT}/${encodeURIComponent(path)}`, { headers: auth(as) })).status;
}
async function remove(as, path) {
  return (await fetch(`${ROOT}/${encodeURIComponent(path)}`, { method: 'DELETE', headers: auth(as) })).status;
}
const ok = (s, what) => assert.ok(s >= 200 && s < 300, `expected ALLOWED ${what}, got ${s}`);
const no = (s, what) => assert.equal(s, 403, `expected DENIED ${what}, got ${s}`);
async function canRead(as, path) { ok(await download(as, path), `download ${as} ${path}`); ok(await metadata(as, path), `metadata ${as} ${path}`); }
async function cannotRead(as, path) { no(await download(as, path), `download ${as} ${path}`); no(await metadata(as, path), `metadata ${as} ${path}`); }

const V1 = 'vendors/vend1/documents/nid-front-1.jpeg';        // approved vendor 1 (owner vendU1)
const VNEW = 'vendors/vendNew/documents/nid-front-2.jpeg';    // pending applicant (doc id = uid)
const R1 = 'delivery_partner_documents/rider1/nid_front_rider1.jpg'; // approved rider
const R2 = 'delivery_partner_documents/rider2/nid_front_rider2.jpg'; // pending rider

beforeEach(async () => {
  await resetWorld(); // Firestore: users, vendors, deliveryPartners
  for (const p of [V1, VNEW, R1, R2]) ok(await upload('owner', p), `seed ${p}`);
});

describe('storage: vendor documents', () => {
  test('no login / customer / other vendor / rider: no download, no metadata (no new token)', async () => {
    for (const who of [null, 'cust1', 'vendU2', 'rider1']) await cannotRead(who, V1);
  });
  test('staff without vendor permission (analytics, order-assign, rider staff): refused', async () => {
    for (const who of ['analyst', 'assignStaff', 'riderStaff']) await cannotRead(who, V1);
  });
  test('owner, vendors.view, vendors.payouts, admin, superAdmin: allowed', async () => {
    for (const who of ['vendU1', 'vendStaff', 'payStaff', 'admin', 'boss']) await canRead(who, V1);
  });
  test('applicant uploads while pending; approved vendor cannot replace or delete', async () => {
    ok(await upload('vendNew', 'vendors/vendNew/documents/trade-license-3.jpeg'), 'applicant upload');
    ok(await remove('vendNew', VNEW), 'applicant delete own while pending');
    no(await upload('vendU1', 'vendors/vend1/documents/nid-front-9.jpeg'), 'approved vendor upload');
    no(await remove('vendU1', V1), 'approved vendor delete');
  });
  test('nobody else uploads into a vendor folder; staff cannot either; superAdmin may delete', async () => {
    no(await upload('cust1', 'vendors/vendNew/documents/x.jpeg'), 'customer into applicant folder');
    no(await upload('vendU2', 'vendors/vend1/documents/x.jpeg'), 'other vendor');
    no(await upload('admin', 'vendors/vend1/documents/x.jpeg'), 'admin upload');
    no(await remove('admin', V1), 'admin delete');
    ok(await remove('boss', V1), 'superAdmin delete');
  });
});

describe('storage: rider documents', () => {
  test('no login / customer / vendor / other rider: no download, no metadata', async () => {
    for (const who of [null, 'cust1', 'vendU1', 'rider3']) await cannotRead(who, R1);
  });
  test('staff without rider permission (analytics, order-assign, vendor staff): refused', async () => {
    for (const who of ['analyst', 'assignStaff', 'vendStaff']) await cannotRead(who, R1);
  });
  test('rider, delivery.view, admin, superAdmin: allowed', async () => {
    for (const who of ['rider1', 'riderStaff', 'admin', 'boss']) await canRead(who, R1);
  });
  test('rider uploads while applying (no doc / pending); approved rider cannot replace', async () => {
    ok(await upload('cust1', 'delivery_partner_documents/cust1/nid_front_cust1.jpg'), 'new applicant, no doc yet');
    ok(await upload('rider2', R2), 'pending rider re-upload');
    no(await upload('rider1', 'delivery_partner_documents/rider1/nid_front_rider1.jpg'), 'approved rider replace');
    no(await remove('rider1', R1), 'approved rider delete');
    no(await upload('cust2', 'delivery_partner_documents/cust1/x.jpg'), 'someone else');
  });
});
