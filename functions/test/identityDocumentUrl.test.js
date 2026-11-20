const test = require("node:test");
const assert = require("node:assert/strict");
const {
  KINDS, RequestError, userCanSeeDocuments, parseRequest, pathInsideOwnerFolder, getIdentityDocumentUrl,
} = require("../identity/identityDocumentUrl");

// ---- permissions ----

test("admin / superAdmin (role or roles) always; banned or inactive never", () => {
  const perms = KINDS.vendor.permissions;
  assert.ok(userCanSeeDocuments({ role: "admin" }, perms));
  assert.ok(userCanSeeDocuments({ role: "superAdmin" }, perms));
  assert.ok(userCanSeeDocuments({ role: "user", roles: ["user", "super_admin"] }, perms));
  assert.equal(userCanSeeDocuments({ role: "admin", isBanned: true }, perms), false);
  assert.equal(userCanSeeDocuments({ role: "superAdmin", isActive: false }, perms), false);
  assert.equal(userCanSeeDocuments(null, perms), false);
});

test("staff: vendor documents need a vendors.* permission, rider documents a delivery.* one", () => {
  for (const p of ["vendors.view", "vendors.edit", "vendors.approve", "vendors.payouts"]) {
    assert.ok(userCanSeeDocuments({ role: "staff", permissions: [p] }, KINDS.vendor.permissions), p);
    assert.ok(userCanSeeDocuments({ role: "staff", permissions: { [p]: true } }, KINDS.vendor.permissions), `${p} map`);
    assert.equal(userCanSeeDocuments({ role: "staff", permissions: [p] }, KINDS.rider.permissions), false, `${p} on rider`);
  }
  for (const p of ["delivery.view", "delivery.approve", "delivery.block"]) {
    assert.ok(userCanSeeDocuments({ role: "staff", permissions: [p] }, KINDS.rider.permissions), p);
    assert.equal(userCanSeeDocuments({ role: "staff", permissions: [p] }, KINDS.vendor.permissions), false);
  }
  // Not enough: other permissions, a false map entry, vendors.documents alone, customers, vendors, riders.
  assert.equal(userCanSeeDocuments({ role: "staff", permissions: ["orders.view", "analytics.view"] }, KINDS.vendor.permissions), false);
  assert.equal(userCanSeeDocuments({ role: "staff", permissions: { "vendors.view": false } }, KINDS.vendor.permissions), false);
  assert.equal(userCanSeeDocuments({ role: "staff", permissions: ["vendors.documents"] }, KINDS.vendor.permissions), false);
  for (const role of ["user", "vendor", "deliveryPartner", "staff"]) {
    assert.equal(userCanSeeDocuments({ role }, KINDS.vendor.permissions), false, role);
    assert.equal(userCanSeeDocuments({ role }, KINDS.rider.permissions), false, role);
  }
});

// ---- request + path ----

test("request: only the known kinds and documents; ownerId must look like an id", () => {
  assert.equal(parseRequest({ kind: "vendor", ownerId: "abc_D-1", which: "tradeLicense" }).which, "tradeLicense");
  assert.equal(parseRequest({ kind: "rider", ownerId: "u1", which: "nidBack" }).kind, "rider");
  for (const bad of [
    {}, { kind: "users", ownerId: "a", which: "nidFront" }, { kind: "rider", ownerId: "a", which: "tradeLicense" },
    { kind: "vendor", ownerId: "../x", which: "nidFront" }, { kind: "vendor", ownerId: "a/b", which: "nidFront" },
    { kind: "vendor", ownerId: "", which: "nidFront" }, { kind: "vendor", ownerId: "a", which: "nidFrontPath" },
    { kind: "vendor", ownerId: "a", which: "__proto__" }, { kind: "constructor", ownerId: "a", which: "nidFront" },
  ]) {
    assert.throws(() => parseRequest(bad), (e) => e instanceof RequestError && e.code === "invalid-argument", JSON.stringify(bad));
  }
});

test("stored path must be inside the owner's own folder", () => {
  const v = KINDS.vendor;
  const r = KINDS.rider;
  assert.ok(pathInsideOwnerFolder(v, "v1", "vendors/v1/documents/nid-front-1.jpeg"));
  assert.ok(pathInsideOwnerFolder(r, "r1", "delivery_partner_documents/r1/nid_front.jpg"));
  for (const bad of [
    "", "vendors/v2/documents/a.jpg", "vendors/v1/documents/", "vendors/v1/a.jpg", "vendors/v1/documents/../../x",
    "products/p.jpg", "vendors/v1/documents//a.jpg", "vendors/v10/documents/a.jpg", "https://firebasestorage.googleapis.com/x",
  ]) {
    assert.equal(pathInsideOwnerFolder(v, "v1", bad), false, bad);
  }
  assert.equal(pathInsideOwnerFolder(r, "r1", "vendors/r1/documents/a.jpg"), false);
});

// ---- the whole call, with fakes ----

function fakeDeps({ users = {}, priv = {}, files = ["vendors/v1/documents/nid-front-1.jpeg"] } = {}) {
  const logs = [];
  const signed = [];
  const db = {
    collection: (c) => ({
      doc: (id) => ({
        get: async () => {
          const data = c === "users" ? users[id] : priv[`${c}/${id}`];
          return { exists: !!data, data: () => data, get: (k) => (data ? data[k] : undefined) };
        },
      }),
    }),
  };
  const bucket = {
    file: (p) => ({
      exists: async () => [files.includes(p)],
      getSignedUrl: async (opts) => { signed.push({ p, opts }); return [`https://signed.example/${p}?X-Goog-Expires=300`]; },
    }),
  };
  return { deps: { db, bucket, logger: { info: (m, f) => logs.push({ m, f }) }, now: () => 1_000_000 }, logs, signed };
}

const VENDOR_PRIV = { "vendor_private/v1": { nidFrontPath: "vendors/v1/documents/nid-front-1.jpeg", phone: "017" } };

test("allowed: 5-minute V4 read URL for the path from the private doc; log has no path, URL or value", async () => {
  const { deps, logs, signed } = fakeDeps({ users: { a1: { role: "admin" } }, priv: VENDOR_PRIV });
  const res = await getIdentityDocumentUrl({ uid: "a1" }, { kind: "vendor", ownerId: "v1", which: "nidFront", path: "evil/x" }, deps);
  assert.equal(signed.length, 1);
  assert.equal(signed[0].p, "vendors/v1/documents/nid-front-1.jpeg", "client path ignored");
  assert.deepEqual(signed[0].opts, { version: "v4", action: "read", expires: 1_000_000 + 5 * 60 * 1000 });
  assert.equal(res.expiresAt, new Date(1_000_000 + 300_000).toISOString());
  assert.match(res.url, /^https:\/\/signed\.example\//);
  assert.equal(logs.length, 1);
  assert.deepEqual(Object.keys(logs[0].f).sort(), ["at", "kind", "viewerUid", "which"]);
  const logged = JSON.stringify(logs);
  for (const secret of ["vendors/v1/documents", "signed.example", "017", "v1\""]) assert.ok(!logged.includes(secret), secret);
});

test("refused: no login, no permission, banned admin; nothing signed, nothing logged", async () => {
  const users = { c1: { role: "user" }, s1: { role: "staff", permissions: ["delivery.view"] }, b1: { role: "admin", isBanned: true } };
  for (const [auth, code] of [[null, "unauthenticated"], [{ uid: "nobody" }, "permission-denied"],
    [{ uid: "c1" }, "permission-denied"], [{ uid: "s1" }, "permission-denied"], [{ uid: "b1" }, "permission-denied"]]) {
    const { deps, logs, signed } = fakeDeps({ users, priv: VENDOR_PRIV });
    await assert.rejects(getIdentityDocumentUrl(auth, { kind: "vendor", ownerId: "v1", which: "nidFront" }, deps),
      (e) => e.code === code, JSON.stringify(auth));
    assert.equal(signed.length + logs.length, 0);
  }
});

test("not on file, missing file, or a stored path outside the owner's folder: no URL", async () => {
  const users = { a1: { role: "admin" } };
  const cases = [
    [{}, "not-found"], // no private doc
    [{ "vendor_private/v1": { nidFrontPath: "" } }, "not-found"],
    [{ "vendor_private/v1": { nidFrontPath: "vendors/v1/documents/gone.jpeg" } }, "not-found"],
    [{ "vendor_private/v1": { nidFrontPath: "vendors/v2/documents/nid-front-1.jpeg" } }, "failed-precondition"],
    [{ "vendor_private/v1": { nidFrontPath: "products/x.jpg" } }, "failed-precondition"],
  ];
  for (const [priv, code] of cases) {
    const { deps, signed } = fakeDeps({ users, priv, files: ["vendors/v1/documents/nid-front-1.jpeg", "vendors/v2/documents/nid-front-1.jpeg", "products/x.jpg"] });
    await assert.rejects(getIdentityDocumentUrl({ uid: "a1" }, { kind: "vendor", ownerId: "v1", which: "nidFront" }, deps),
      (e) => e.code === code, JSON.stringify(priv));
    assert.equal(signed.length, 0);
  }
});
