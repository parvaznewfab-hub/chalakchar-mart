// Step H2: functions/products/productMarketingGuard.js (pure parts).
const test = require("node:test");
const assert = require("node:assert/strict");
const G = require("../products/productMarketingGuard");
const { autoMarketingBlockReason } = require("../marketing/eligibility");

const live = (extra = {}) => ({ name: "P", approvalStatus: "approved", isActive: true, isVisible: true, isPublished: true, vendorId: "super_admin", ...extra });
const fakeDb = (users) => ({
  collection: () => ({ doc: (id) => ({ get: async () => ({ exists: id in users, data: () => users[id] }) }) }),
});

test("isVendorProduct: marketplace flag or any non-shop vendorId", () => {
  assert.equal(G.isVendorProduct(live()), false);
  assert.equal(G.isVendorProduct(live({ vendorId: "" })), false);
  assert.equal(G.isVendorProduct(live({ vendorId: undefined })), false);
  assert.equal(G.isVendorProduct(live({ vendorId: "vend1" })), true);
  assert.equal(G.isVendorProduct(live({ isMarketplace: true })), true);
  assert.equal(G.isVendorProduct(live({ vendorId: "cust1-uid" })), true);
});

test("isProductStaff: admin roles or products.edit; never blocked", () => {
  assert.equal(G.isProductStaff({ role: "admin" }), true);
  assert.equal(G.isProductStaff({ role: "user", roles: ["superAdmin"] }), true);
  assert.equal(G.isProductStaff({ role: "staff", permissions: ["products.edit"] }), true);
  assert.equal(G.isProductStaff({ role: "staff", permissions: { "products.edit": true } }), true);
  assert.equal(G.isProductStaff({ role: "staff", permissions: ["products.status"] }), false);
  assert.equal(G.isProductStaff({ role: "user" }), false);
  assert.equal(G.isProductStaff({ role: "vendor", vendorId: "vend1" }), false);
  assert.equal(G.isProductStaff({ role: "admin", isBanned: true }), false);
});

test("writerBlockReason: backend writers yes; app users only when staff", async () => {
  const deps = { db: fakeDb({ admin: { role: "admin" }, cust: { role: "user" }, vend: { role: "vendor", vendorId: "vend1" } }) };
  assert.equal(await G.writerBlockReason({ authType: "service_account", deps }), null);
  assert.equal(await G.writerBlockReason({ authType: "system", deps }), null);
  assert.equal(await G.writerBlockReason({ authType: "app_user", authId: "admin", deps }), null);
  assert.equal(await G.writerBlockReason({ authType: "app_user", authId: "cust", deps }), "writer_not_staff");
  assert.equal(await G.writerBlockReason({ authType: "app_user", authId: "vend", deps }), "writer_not_staff");
  assert.equal(await G.writerBlockReason({ authType: "app_user", authId: "ghost", deps }), "writer_no_profile");
  assert.equal(await G.writerBlockReason({ authType: "app_user", authId: "", deps }), "writer_no_uid");
  assert.equal(await G.writerBlockReason({ authType: "unauthenticated", deps }), "writer_unauthenticated");
  assert.equal(await G.writerBlockReason({ authType: "api_key", deps }), "writer_api_key");
  assert.equal(await G.writerBlockReason({ authType: undefined, deps }), "writer_unknown");
});

test("newProductMarketingDecision: vendor product never; product state; writer", async () => {
  const deps = { db: fakeDb({ admin: { role: "admin" }, cust: { role: "user" } }) };
  const decide = (product, authType, authId) => G.newProductMarketingDecision({
    authType, authId, product, productBlockReason: autoMarketingBlockReason, deps,
  });
  assert.deepEqual(await decide(live(), "app_user", "admin"), { market: true, reason: null });
  assert.deepEqual(await decide(live(), "service_account"), { market: true, reason: null });
  // the attack before step H2: a customer's own "approved" product
  assert.deepEqual(await decide(live({ vendorId: "cust" }), "app_user", "cust"), { market: false, reason: "vendor_product" });
  assert.deepEqual(await decide(live(), "app_user", "cust"), { market: false, reason: "writer_not_staff" });
  // approved vendor product, even when written by an admin
  assert.deepEqual(await decide(live({ vendorId: "vend1", isMarketplace: true }), "app_user", "admin"), { market: false, reason: "vendor_product" });
  // product state still decides first for shop products
  assert.deepEqual(await decide(live({ needsReview: true }), "service_account"), { market: false, reason: "needs_review" });
  assert.deepEqual(await decide(live({ autoMarketingDisabled: true }), "service_account"), { market: false, reason: "auto_marketing_disabled" });
  assert.deepEqual(await decide(live({ approvalStatus: "pending" }), "app_user", "admin"), { market: false, reason: "not_approved" });
});
