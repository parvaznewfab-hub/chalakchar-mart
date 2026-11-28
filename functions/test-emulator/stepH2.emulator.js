// Step H2: functions/products/productMarketingGuard.js against the FIRESTORE
// EMULATOR (demo project; users/ read for real). Run: node tools/rules-test/run-steph2.js
const test = require("node:test");
const assert = require("node:assert/strict");

const PROJECT = process.env.GCLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  throw new Error("Refusing to run: needs FIRESTORE_EMULATOR_HOST and a demo-* project (emulator only).");
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const G = require("../products/productMarketingGuard");
const { autoMarketingBlockReason } = require("../marketing/eligibility");

const live = (extra = {}) => ({ name: "P", approvalStatus: "approved", isActive: true, isVisible: true, isPublished: true, vendorId: "super_admin", ...extra });
const decide = (product, authType, authId) => G.newProductMarketingDecision({
  authType, authId, product, productBlockReason: autoMarketingBlockReason, deps: { db },
});

test.before(async () => {
  const b = db.batch();
  b.set(db.doc("users/boss"), { role: "superAdmin", roles: ["user", "superAdmin"], isActive: true, isBanned: false });
  b.set(db.doc("users/prodStaff"), { role: "staff", permissions: ["products.edit"], isActive: true, isBanned: false });
  b.set(db.doc("users/statusStaff"), { role: "staff", permissions: ["products.status"], isActive: true, isBanned: false });
  b.set(db.doc("users/bannedAdmin"), { role: "admin", isActive: true, isBanned: true });
  b.set(db.doc("users/cust1"), { role: "user", roles: ["user"], isActive: true, isBanned: false, vendorId: "" });
  b.set(db.doc("users/forger"), { role: "user", roles: ["user"], isActive: true, isBanned: false, vendorId: "vend1" });
  b.set(db.doc("users/vendU1"), { role: "vendor", roles: ["user", "vendor"], isActive: true, isBanned: false, vendorId: "vend1" });
  await b.commit();
});

test("shop product by super admin / products.edit staff / backend: marketed", async () => {
  assert.equal((await decide(live(), "app_user", "boss")).market, true);
  assert.equal((await decide(live(), "app_user", "prodStaff")).market, true);
  assert.equal((await decide(live(), "service_account")).market, true);
});

test("the pre-H2 attack: a customer's live 'approved' product is never marketed", async () => {
  assert.deepEqual(await decide(live({ vendorId: "cust1" }), "app_user", "cust1"), { market: false, reason: "vendor_product" });
  assert.deepEqual(await decide(live({ vendorId: "super_admin" }), "app_user", "cust1"), { market: false, reason: "writer_not_staff" });
  assert.deepEqual(await decide(live(), "app_user", "forger"), { market: false, reason: "writer_not_staff" });
});

test("products.status staff, a banned admin, an unknown writer: not marketed", async () => {
  assert.equal((await decide(live(), "app_user", "statusStaff")).reason, "writer_not_staff");
  assert.equal((await decide(live(), "app_user", "bannedAdmin")).reason, "writer_not_staff");
  assert.equal((await decide(live(), "app_user", "nobody")).reason, "writer_no_profile");
  assert.equal((await decide(live(), "unauthenticated")).reason, "writer_unauthenticated");
});

test("a vendor's product is never marketed automatically, not even an admin-approved one", async () => {
  const vendorProduct = live({ vendorId: "vend1", isMarketplace: true, vendorOwnerId: "vendU1" });
  assert.equal((await decide(vendorProduct, "app_user", "vendU1")).reason, "vendor_product");
  assert.equal((await decide(vendorProduct, "app_user", "boss")).reason, "vendor_product");
  assert.equal((await decide(vendorProduct, "service_account")).reason, "vendor_product");
});
