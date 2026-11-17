// Customer notifications: Bangla text, link fields, marketing opt-out.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  allowsMarketing,
  isMarketingType,
  linkFields,
  categoryForType,
  templates,
} = require("../notifications/customerNotifications");

const BANGLA = /[ঀ-৿]/;

test("product notifications link to the product page", () => {
  assert.deepEqual(linkFields({ type: "new_product", productId: "abc 1" }), {
    type: "new_product",
    category: "new_product",
    productId: "abc 1",
    route: "/product/abc%201",
  });
});

test("search import links its first product", () => {
  const f = linkFields({ type: "search_import_done", productIds: ["p1", "p2"], query: "x" });
  assert.equal(f.productId, "p1");
  assert.equal(f.route, "/product/p1");
  assert.equal(f.category, "new_product");
});

test("order notifications carry the orderId, no route", () => {
  assert.deepEqual(linkFields({ type: "order_status", orderId: "o1", status: "confirmed" }), {
    type: "order_status",
    category: "order",
    orderId: "o1",
  });
  assert.equal(categoryForType("picked_up"), "order");
  assert.equal(categoryForType("order_delivered"), "order");
});

test("discounts are offers; unknown types are general", () => {
  assert.equal(categoryForType("wishlist_discount"), "offer");
  assert.equal(categoryForType("whatever"), "general");
  assert.deepEqual(linkFields({}), { category: "general" });
});

test("only an explicit marketing:false opts out", () => {
  assert.equal(allowsMarketing({}), true);
  assert.equal(allowsMarketing(undefined), true);
  assert.equal(allowsMarketing({ notificationPrefs: {} }), true);
  assert.equal(allowsMarketing({ notificationPrefs: { marketing: true } }), true);
  assert.equal(allowsMarketing({ notificationPrefs: { marketing: false } }), false);
});

test("order updates and search replies are never marketing", () => {
  for (const t of ["order_status", "picked_up", "order_delivered", "order", "search_import_done"]) {
    assert.equal(isMarketingType(t), false, t);
  }
  for (const t of ["new_product", "back_in_stock", "wishlist_discount"]) {
    assert.equal(isMarketingType(t), true, t);
  }
});

test("templates are Bangla and name the product", () => {
  const found = templates.searchImportFound(["Netac SSD 512GB", "Other"], "ssd");
  assert.match(found.title, BANGLA);
  assert.ok(found.body.includes("Netac SSD 512GB"));
  assert.ok(found.body.includes("আরও 1টি"));

  const noName = templates.searchImportFound([], "ssd");
  assert.ok(noName.body.includes('"ssd"'));

  const status = templates.orderStatus("ABCDEFGHIJK", "confirmed");
  assert.equal(status.body, "আপনার অর্ডার #ABCDEFGH এখন: নিশ্চিত করা হয়েছে।");
  assert.match(templates.orderPickedUp("o").title, BANGLA);
  assert.match(templates.orderDelivered("o").title, BANGLA);
  assert.ok(templates.backInStock("Fan").body.startsWith("Fan "));
  assert.ok(templates.wishlistDiscount("Fan", 15).body.includes("15% ছাড়"));
});
