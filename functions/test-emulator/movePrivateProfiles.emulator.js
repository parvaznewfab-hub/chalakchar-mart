// End-to-end test of scripts/movePrivateProfiles.js against the FIRESTORE
// EMULATOR ONLY (demo project). Run: node tools/rules-test/run-move-script.js
// Guards: refuses to run unless FIRESTORE_EMULATOR_HOST is set and the project
// id starts with "demo-"; HOME/USERPROFILE point at a temp dir so the backup
// never lands in the real ~/cc-backups.

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

const SCRIPT = path.join(__dirname, "..", "scripts", "movePrivateProfiles.js");
const LINK = "https://firebasestorage.googleapis.com/v0/b/x/o/vendors%2Fv1%2Fdocuments%2Fnid-front-1.jpeg?alt=media&token=SECRET-TOKEN";

function run(args, home) {
  const r = spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd: path.join(__dirname, ".."),
    env: { ...process.env, HOME: home, USERPROFILE: home, GCLOUD_PROJECT: PROJECT },
    encoding: "utf8",
  });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

async function clear() {
  for (const c of ["vendors", "vendor_private", "deliveryPartners", "delivery_partner_private"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed() {
  await db.doc("vendors/v1").set({
    shopName: "Shop", status: "approved", ownerId: "v1", phone: "01700000000", email: "a@b.c",
    address: "Road 1", note: "", payoutAccount: "bkash 017", nidFront: LINK, withdrawableBalance: 0,
  });
  await db.doc("vendors/v2").set({ shopName: "Clean", status: "approved", ownerId: "v2" });
  await db.doc("deliveryPartners/r1").set({
    name: "R", phone: "018", status: "approved", totalEarning: 100, codDue: 5,
    nidNumber: "1234567890", address: "House", nidFrontUrl: LINK, nidFrontPath: "delivery_partner_documents/r1/f.jpg",
  });
}

test("dry run: prints names and lengths only, writes nothing", async () => {
  await clear();
  await seed();
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "cc-move-"));
  const r = run([], home);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Dry run: 2 doc\(s\) would change/);
  assert.match(r.out, /phone\(11\)/);
  for (const secret of ["01700000000", "1234567890", "bkash 017", "SECRET-TOKEN", "House"]) {
    assert.ok(!r.out.includes(secret), `dry run printed a value: ${secret}`);
  }
  assert.equal((await db.doc("vendors/v1").get()).get("phone"), "01700000000");
  assert.equal((await db.doc("vendor_private/v1").get()).exists, false);
  assert.equal(fs.existsSync(path.join(home, "cc-backups")), false, "dry run must not write a backup");
});

test("--apply: private docs filled, public docs clean, backup outside repo, check passes", async () => {
  await clear();
  await seed();
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "cc-move-"));
  const r = run(["--apply"], home);
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /No private key left in vendors or deliveryPartners/);
  for (const secret of ["01700000000", "1234567890", "bkash 017", "SECRET-TOKEN"]) {
    assert.ok(!r.out.includes(secret), `--apply printed a value: ${secret}`);
  }

  const vPub = (await db.doc("vendors/v1").get()).data();
  const vPriv = (await db.doc("vendor_private/v1").get()).data();
  assert.deepEqual(Object.keys(vPub).sort(), ["ownerId", "shopName", "status"]);
  assert.equal(vPriv.phone, "01700000000");
  assert.equal(vPriv.payoutAccount, "bkash 017");
  assert.equal(vPriv.withdrawableBalance, 0);
  assert.equal(vPriv.nidFrontPath, "vendors/v1/documents/nid-front-1.jpeg");
  assert.equal(vPriv.nidFront, undefined, "the link (token) is not copied");

  const rPub = (await db.doc("deliveryPartners/r1").get()).data();
  const rPriv = (await db.doc("delivery_partner_private/r1").get()).data();
  assert.deepEqual(Object.keys(rPub).sort(), ["codDue", "name", "phone", "status", "totalEarning"]);
  assert.equal(rPriv.nidNumber, "1234567890");
  assert.equal(rPriv.nidFrontPath, "delivery_partner_documents/r1/f.jpg");
  assert.equal(rPriv.nidFrontUrl, undefined);

  assert.equal((await db.doc("vendor_private/v2").get()).exists, false, "clean vendor untouched");

  const backups = fs.readdirSync(path.join(home, "cc-backups"));
  assert.equal(backups.length, 1);
  const backup = JSON.parse(fs.readFileSync(path.join(home, "cc-backups", backups[0]), "utf8"));
  assert.equal(backup.length, 2);
  assert.equal(backup.find((b) => b.id === "v1").removed.phone, "01700000000");

  // Running again: nothing left to move.
  const again = run(["--apply"], home);
  assert.equal(again.code, 0, again.out);
  assert.match(again.out, /Nothing to move/);
});

test("conflict: a different value already in the private doc stops everything before any write", async () => {
  await clear();
  await seed();
  await db.doc("vendor_private/v1").set({ phone: "01799999999" });
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "cc-move-"));
  const r = run(["--apply"], home);
  assert.equal(r.code, 2, r.out);
  assert.match(r.out, /CONFLICT/);
  assert.equal((await db.doc("vendors/v1").get()).get("phone"), "01700000000", "public untouched");
  assert.equal((await db.doc("deliveryPartners/r1").get()).get("nidNumber"), "1234567890", "rider untouched too");
  assert.equal(fs.existsSync(path.join(home, "cc-backups")), false);
});
