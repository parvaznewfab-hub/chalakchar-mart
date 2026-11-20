// End-to-end test of scripts/clearPublicOwnerName.js against the FIRESTORE
// EMULATOR ONLY (demo project). Run: node tools/rules-test/run-move-script.js
// Same guards as movePrivateProfiles.emulator.js.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const PROJECT = process.env.GCLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  throw new Error("Refusing to run: needs FIRESTORE_EMULATOR_HOST and a demo-* project (emulator only).");
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

const SCRIPT = path.join(__dirname, "..", "scripts", "clearPublicOwnerName.js");
const MOVE = path.join(__dirname, "..", "scripts", "movePrivateProfiles.js");
const OLD = "Old Shop Name As Owner";
const NEW = "Real Owner";

function run(args, home, script = SCRIPT) {
  const r = spawnSync(process.execPath, [script, ...args], {
    cwd: path.join(__dirname, ".."),
    env: { ...process.env, HOME: home, USERPROFILE: home, GCLOUD_PROJECT: PROJECT },
    encoding: "utf8",
  });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

const home = () => fs.mkdtempSync(path.join(os.tmpdir(), "cc-owner-"));
const backups = (h) => (fs.existsSync(path.join(h, "cc-backups")) ? fs.readdirSync(path.join(h, "cc-backups")) : []);

async function reset(privateData) {
  for (const c of ["vendors", "vendor_private", "deliveryPartners", "delivery_partner_private"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await db.doc("vendors/v1").set({ shopName: "Shop", ownerName: OLD, phone: "01700000000", status: "approved" });
  if (privateData) await db.doc("vendor_private/v1").set(privateData);
}

test("private has no ownerName (or no doc): refuses, deletes nothing, no backup", async () => {
  for (const priv of [null, { phone: "01700000000" }]) {
    await reset(priv);
    const h = home();
    const r = run(["v1", "--apply"], h);
    assert.equal(r.code, 2, r.out);
    assert.match(r.out, /REFUSED/);
    assert.equal((await db.doc("vendors/v1").get()).get("ownerName"), OLD);
    assert.deepEqual(backups(h), []);
  }
});

test("private ownerName blank: refuses, deletes nothing", async () => {
  await reset({ ownerName: "   " });
  const h = home();
  const r = run(["v1", "--apply"], h);
  assert.equal(r.code, 2, r.out);
  assert.equal((await db.doc("vendors/v1").get()).get("ownerName"), OLD);
  assert.deepEqual(backups(h), []);
});

test("dry run: says what it would do, prints no value, writes nothing", async () => {
  await reset({ ownerName: NEW });
  const h = home();
  const r = run(["v1"], h);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Dry run: would delete vendors\/v1\.ownerName/);
  assert.ok(!r.out.includes(OLD) && !r.out.includes(NEW), "printed a value");
  assert.equal((await db.doc("vendors/v1").get()).get("ownerName"), OLD);
  assert.deepEqual(backups(h), []);
});

test("--apply: deletes only vendors.ownerName, keeps backup; second run does nothing; move script then has no conflict", async () => {
  await reset({ ownerName: NEW });
  const before = (await db.doc("vendors/v1").get()).data();
  const h = home();
  const r = run(["v1", "--apply"], h);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Done\./);
  assert.ok(!r.out.includes(OLD) && !r.out.includes(NEW), "printed a value");

  const after = (await db.doc("vendors/v1").get()).data();
  const expected = { ...before };
  delete expected.ownerName;
  assert.deepEqual(after, expected, "only ownerName removed");
  assert.equal((await db.doc("vendor_private/v1").get()).get("ownerName"), NEW);

  const files = backups(h);
  assert.equal(files.length, 1);
  const backup = JSON.parse(fs.readFileSync(path.join(h, "cc-backups", files[0]), "utf8"));
  assert.deepEqual(backup, [{ collection: "vendors", id: "v1", removed: { ownerName: OLD } }]);

  const again = run(["v1", "--apply"], h);
  assert.equal(again.code, 0, again.out);
  assert.match(again.out, /Nothing to do/);
  assert.equal(backups(h).length, 1, "no second backup");

  const move = run([], h, MOVE);
  assert.equal(move.code, 0, move.out);
  assert.ok(!/CONFLICT/.test(move.out), move.out);
});

test("usage: needs exactly one vendor id; missing vendor doc refuses", async () => {
  const h = home();
  assert.equal(run([], h).code, 1);
  assert.equal(run(["a", "b"], h).code, 1);
  await reset({ ownerName: NEW });
  assert.equal(run(["nope", "--apply"], h).code, 1);
});
