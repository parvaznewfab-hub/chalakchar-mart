// 14b step C: getIdentityDocumentUrl against the FIRESTORE + STORAGE
// EMULATORS (demo project). Run: node tools/rules-test/run-identity-doc.js
// Real Firestore reads (users, vendor_private, delivery_partner_private) and a
// real Storage existence check; only the signing step is replaced, because
// signing needs the live service account (iam.serviceAccounts.signBlob).

const test = require("node:test");
const assert = require("node:assert/strict");

const PROJECT = process.env.GCLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  throw new Error("Refusing to run: needs the Firestore + Storage emulators and a demo-* project.");
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` });
const db = admin.firestore();
const realBucket = admin.storage().bucket();
const { getIdentityDocumentUrl } = require("../identity/identityDocumentUrl");

const signed = [];
const logs = [];
const bucket = {
  file: (p) => {
    const f = realBucket.file(p);
    return {
      exists: () => f.exists(),
      getSignedUrl: async (opts) => { signed.push({ p, opts }); return [`https://signed.test/${encodeURIComponent(p)}`]; },
    };
  },
};
const deps = { db, bucket, logger: { info: (m, f) => logs.push(f) }, now: () => Date.now() };

test.before(async () => {
  await Promise.all([
    db.doc("users/admin1").set({ role: "admin" }),
    db.doc("users/vstaff").set({ role: "staff", permissions: ["vendors.view"] }),
    db.doc("users/rstaff").set({ role: "staff", permissions: { "delivery.view": true } }),
    db.doc("users/analyst").set({ role: "staff", permissions: ["analytics.view"] }),
    db.doc("users/banned").set({ role: "superAdmin", isBanned: true }),
    db.doc("users/vend1").set({ role: "vendor", vendorId: "v1" }),
    db.doc("vendor_private/v1").set({
      nidFrontPath: "vendors/v1/documents/nid-front-1.jpeg",
      nidBackPath: "vendors/v2/documents/nid-back-1.jpeg", // points at someone else's folder
      tradeLicensePath: "vendors/v1/documents/missing.jpeg", // no such file
      phone: "01700000000",
    }),
    db.doc("delivery_partner_private/r1").set({ nidFrontPath: "delivery_partner_documents/r1/front.jpg", nidNumber: "123" }),
  ]);
  for (const p of ["vendors/v1/documents/nid-front-1.jpeg", "vendors/v2/documents/nid-back-1.jpeg", "delivery_partner_documents/r1/front.jpg"]) {
    await realBucket.file(p).save(Buffer.from("img"), { contentType: "image/jpeg" });
  }
});

const call = (uid, data) => getIdentityDocumentUrl(uid ? { uid } : null, data, deps);
const V = { kind: "vendor", ownerId: "v1", which: "nidFront" };
const R = { kind: "rider", ownerId: "r1", which: "nidFront" };

test("admin: vendor and rider documents open; signed for 5 minutes, path from the private doc", async () => {
  signed.length = 0;
  const v = await call("admin1", { ...V, path: "delivery_partner_documents/r1/front.jpg" });
  assert.match(v.url, /^https:\/\/signed\.test\//);
  assert.equal(signed[0].p, "vendors/v1/documents/nid-front-1.jpeg");
  assert.equal(signed[0].opts.expires - Date.parse(v.expiresAt), 0);
  assert.ok(Date.parse(v.expiresAt) - Date.now() <= 5 * 60 * 1000);
  await call("admin1", R);
  assert.equal(signed[1].p, "delivery_partner_documents/r1/front.jpg");
});

test("staff: vendors.view opens vendor documents only; delivery.view rider only; analyst neither", async () => {
  assert.ok((await call("vstaff", V)).url);
  await assert.rejects(call("vstaff", R), { code: "permission-denied" });
  assert.ok((await call("rstaff", R)).url);
  await assert.rejects(call("rstaff", V), { code: "permission-denied" });
  await assert.rejects(call("analyst", V), { code: "permission-denied" });
});

test("vendor themselves, banned superAdmin, unknown user, no login: refused", async () => {
  await assert.rejects(call("vend1", V), { code: "permission-denied" });
  await assert.rejects(call("banned", V), { code: "permission-denied" });
  await assert.rejects(call("ghost", V), { code: "permission-denied" });
  await assert.rejects(call(null, V), { code: "unauthenticated" });
});

test("path outside the owner's folder, missing file, nothing on file, unknown owner: no URL", async () => {
  const before = signed.length;
  await assert.rejects(call("admin1", { ...V, which: "nidBack" }), { code: "failed-precondition" });
  await assert.rejects(call("admin1", { ...V, which: "tradeLicense" }), { code: "not-found" });
  await assert.rejects(call("admin1", { ...R, which: "nidBack" }), { code: "not-found" });
  await assert.rejects(call("admin1", { ...V, ownerId: "nobody" }), { code: "not-found" });
  assert.equal(signed.length, before);
});

test("log lines: who, when, whose, which kind only", () => {
  assert.ok(logs.length >= 4);
  for (const f of logs) assert.deepEqual(Object.keys(f).sort(), ["at", "kind", "ownerId", "viewerUid", "which"]);
  const all = JSON.stringify(logs);
  for (const s of ["vendors/", "delivery_partner_documents", "signed.test", "01700000000", "123\""]) assert.ok(!all.includes(s), s);
});

// ---- scripts/revokeIdentityDocTokens.js ----

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function runRevoke(args, home) {
  const r = spawnSync(process.execPath, [path.join(__dirname, "..", "scripts", "revokeIdentityDocTokens.js"), ...args], {
    cwd: path.join(__dirname, ".."),
    env: { ...process.env, HOME: home, USERPROFILE: home, GCLOUD_PROJECT: PROJECT, STORAGE_BUCKET: realBucket.name },
    encoding: "utf8",
  });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

const TOKEN = "SECRET-DOWNLOAD-TOKEN-1";
const tokensOf = async (p) => ((await realBucket.file(p).getMetadata())[0].metadata || {}).firebaseStorageDownloadTokens;

// NOTE: the Storage EMULATOR never deletes firebaseStorageDownloadTokens
// (it keeps the key even for metadata: null; probed 2026-11-20), so the real
// removal can only be seen on live GCS. Here we check everything else, and
// that the script's own re-read catches a token that is still there (exit 3).
test("revoke script: dry run changes nothing; --apply touches only the right files, never prints a token, and its check catches a kept token", async () => {
  const p = "vendors/v1/documents/nid-front-1.jpeg";
  const r = "delivery_partner_documents/r1/front.jpg";
  const other = "vendors/v2/documents/nid-back-1.jpeg"; // only referenced from outside its owner's folder
  for (const f of [p, r, other]) await realBucket.file(f).setMetadata({ metadata: { firebaseStorageDownloadTokens: TOKEN } });
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "cc-revoke-"));

  const dry = runRevoke([], home);
  assert.equal(dry.code, 0, dry.out);
  assert.match(dry.out, /Dry run: 2 file\(s\)/);
  assert.match(dry.out, /SKIPPED \(path outside the owner's folder\): vendor\/v1\/nidBack/);
  assert.equal(await tokensOf(p), TOKEN);
  assert.equal(fs.existsSync(path.join(home, "cc-backups")), false);

  const run = runRevoke(["--apply"], home);
  assert.ok(!run.out.includes(TOKEN), "a token was printed");
  assert.match(run.out, /removed: vendor v1… nidFront/);
  assert.match(run.out, /removed: rider r1… nidFront/);
  assert.ok(!/removed: vendor v1… nidBack/.test(run.out), "file outside the folder was touched");
  // Emulator keeps the key -> the script must say so and fail (exit 3).
  assert.equal(run.code, 3, run.out);
  assert.match(run.out, /FAILED CHECK: 2 file\(s\) still have a token/);
  assert.equal((await realBucket.file(p).exists())[0], true, "file kept");
  const [rec] = fs.readdirSync(path.join(home, "cc-backups"));
  const saved = fs.readFileSync(path.join(home, "cc-backups", rec), "utf8");
  assert.ok(!saved.includes(TOKEN), "record has no token");
  assert.deepEqual(JSON.parse(saved).map((s) => `${s.kind}/${s.which}/${s.tokens}`).sort(), ["rider/nidFront/1", "vendor/nidFront/1"]);
});
