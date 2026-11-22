// Tiny Firestore-emulator client for rules tests. No npm dependencies:
// Node's built-in fetch talks to the emulator's REST API directly.
//
// - Requests signed as "owner" bypass rules (used for seeding).
// - Requests for a user carry an unsigned emulator ID token for that uid,
//   the same thing @firebase/rules-unit-testing sends.
'use strict';

const fs = require('node:fs');
const assert = require('node:assert/strict');

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-chalakchar-rules';
const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const ROOT = `http://${HOST}`;
const DB = `projects/${PROJECT}/databases/(default)`;
const DOCS = `${ROOT}/v1/${DB}/documents`;

const SERVER_TS = { __serverTimestamp: true };
const inc = (n) => ({ __increment: n });

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString('base64url');
}

function tokenFor(uid) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    sub: uid,
    user_id: uid,
    firebase: { sign_in_provider: 'password', identities: {} },
  };
  return `${b64url({ alg: 'none', typ: 'JWT' })}.${b64url(payload)}.`;
}

function headers(as) {
  const h = { 'Content-Type': 'application/json' };
  if (as === 'owner') h.Authorization = 'Bearer owner';
  else if (as) h.Authorization = `Bearer ${tokenFor(as)}`;
  return h;
}

function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === 'string') return { stringValue: v };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (v.__timestamp) return { timestampValue: v.__timestamp }; // exact value read back
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: toFields(v) } };
}

function isSentinel(v) {
  return v && typeof v === 'object' && (v.__serverTimestamp || v.__increment !== undefined);
}

function toFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (!isSentinel(v)) out[k] = toValue(v);
  }
  return out;
}

function fromValue(v) {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return { __timestamp: v.timestampValue };
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromValue);
  if ('mapValue' in v) return fromFields(v.mapValue.fields || {});
  return undefined;
}

function fromFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) out[k] = fromValue(v);
  return out;
}

// Expand {"a.b.c": 1} into nested maps; collect leaf paths and transforms.
function expand(data, { dotted }) {
  const nested = {};
  const leafPaths = [];
  const transforms = [];
  const walk = (obj, prefix, target) => {
    for (const [rawKey, v] of Object.entries(obj)) {
      const parts = dotted ? rawKey.split('.') : [rawKey];
      let t = target;
      for (const p of parts.slice(0, -1)) t = t[p] = t[p] || {};
      const key = parts[parts.length - 1];
      const path = [...prefix, ...parts].join('.');
      if (isSentinel(v)) {
        if (v.__serverTimestamp) transforms.push({ fieldPath: path, setToServerValue: 'REQUEST_TIME' });
        else transforms.push({ fieldPath: path, increment: toValue(v.__increment) });
      } else {
        t[key] = v;
        leafPaths.push(path);
      }
    }
  };
  walk(data, [], nested);
  return { nested, leafPaths, transforms };
}

function docName(path) {
  return `${DB}/documents/${path}`;
}

// Write ops for commit()
function setOp(path, data, { merge = false } = {}) {
  const { nested, leafPaths, transforms } = expand(data, { dotted: false });
  const w = { update: { name: docName(path), fields: toFields(nested) } };
  if (merge) w.updateMask = { fieldPaths: leafPaths };
  if (transforms.length) w.updateTransforms = transforms;
  return w;
}

function updateOp(path, data) {
  const { nested, leafPaths, transforms } = expand(data, { dotted: true });
  const w = {
    update: { name: docName(path), fields: toFields(nested) },
    updateMask: { fieldPaths: leafPaths },
    currentDocument: { exists: true },
  };
  if (transforms.length) w.updateTransforms = transforms;
  return w;
}

function createOp(path, data) {
  const w = setOp(path, data);
  w.currentDocument = { exists: false };
  return w;
}

async function call(as, method, url, body) {
  const res = await fetch(url, {
    method,
    headers: headers(as),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  // runQuery reports errors inside a 200 stream sometimes; normalise.
  if (Array.isArray(json) && json[0] && json[0].error) {
    return { status: json[0].error.code === 7 ? 403 : 400, json: json[0] };
  }
  return { status: res.status, json };
}

async function commit(as, writes) {
  return call(as, 'POST', `${DOCS}:commit`, { writes });
}

async function get(as, path) {
  const r = await call(as, 'GET', `${DOCS}/${path}`);
  if (r.status === 200) r.data = fromFields(r.json.fields);
  return r;
}

// filters: [[field, op, value]] with op in == array-contains in
async function query(as, collection, filters = []) {
  const ops = { '==': 'EQUAL', 'array-contains': 'ARRAY_CONTAINS', in: 'IN' };
  const f = filters.map(([field, op, value]) => ({
    fieldFilter: { field: { fieldPath: field }, op: ops[op], value: toValue(value) },
  }));
  // "parent/doc/sub" lists a subcollection: the query runs under its parent doc.
  const parts = collection.split('/');
  const collectionId = parts.pop();
  const parent = parts.length ? `${DOCS}/${parts.join('/')}` : DOCS;
  const structuredQuery = { from: [{ collectionId }] };
  if (f.length === 1) structuredQuery.where = f[0];
  if (f.length > 1) structuredQuery.where = { compositeFilter: { op: 'AND', filters: f } };
  const r = await call(as, 'POST', `${parent}:runQuery`, { structuredQuery });
  if (r.status === 200) r.docs = (r.json || []).filter((x) => x.document).map((x) => x.document);
  return r;
}

const db = (as) => ({
  get: (path) => get(as, path),
  query: (c, f) => query(as, c, f),
  set: (path, data, opts) => commit(as, [setOp(path, data, opts)]),
  create: (path, data) => commit(as, [createOp(path, data)]),
  update: (path, data) => commit(as, [updateOp(path, data)]),
  delete: (path) => commit(as, [{ delete: docName(path) }]),
  batch: (writes) => commit(as, writes),
});

async function loadRules(file) {
  const content = fs.readFileSync(file, 'utf8');
  const r = await call(null, 'PUT', `${ROOT}/emulator/v1/projects/${PROJECT}:securityRules`, {
    rules: { files: [{ name: 'firestore.rules', content }] },
  });
  assert.equal(r.status, 200, `rules failed to load: ${JSON.stringify(r.json).slice(0, 2000)}`);
}

async function clearData() {
  const r = await call(null, 'DELETE', `${ROOT}/emulator/v1/${DB}/documents`);
  assert.equal(r.status, 200, 'clear failed');
}

async function seed(docs) {
  const writes = Object.entries(docs).map(([path, data]) => setOp(path, data));
  const r = await commit('owner', writes);
  assert.equal(r.status, 200, `seed failed: ${JSON.stringify(r.json).slice(0, 500)}`);
}

function allowed(r, what = '') {
  assert.equal(r.status, 200, `expected ALLOWED ${what}, got ${r.status}: ${JSON.stringify(r.json).slice(0, 300)}`);
  return r;
}

function denied(r, what = '') {
  assert.equal(r.status, 403, `expected DENIED ${what}, got ${r.status}: ${JSON.stringify(r.json).slice(0, 300)}`);
  return r;
}

module.exports = {
  SERVER_TS, inc, db, loadRules, clearData, seed, allowed, denied,
  setOp, updateOp, createOp,
};
