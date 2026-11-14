// The two live chat queries that used to get "দাম জানাতে পারব না":
// "Netac SSD 128GB price?" and "১২৮ জিবি এসএসডির দাম কত?".
const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const { normalizeChatQuery } = require("../messaging/queryNormalize");
const { rankProducts, matchesQuery } = require("../messaging/productMatch");
const { handleCustomerMessage } = require("../messaging/handleCustomerMessage");

// Shaped like imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165.
const netac = {
  id: "imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165",
  name: "Netac SATA SSD Hard Drive 128GB 256GB 512GB 1TB 2TB SATA3 2.5Inch Disks Laptop Internal Hard Drive HDD Hard Disk for PC Laptop",
  category: "Computer Accessories",
  source: "aliexpress",
  isActive: true,
  isVisible: true,
  isPublished: true,
  approvalStatus: "approved",
  price: 47546.14,
  deliveryMinDays: 9,
  deliveryMaxDays: 27,
  variants: [
    { name: "4TB Black / China Mainland", price: 47546.14, stock: 3 },
    { name: "512GB Black / China Mainland", price: 7606.24, stock: 636 },
    { name: "128GB Black / China Mainland", price: 2851.49, stock: 1337 },
  ],
};
const others = [
  { id: "lcd", name: "AMOLED Display For Samsung Galaxy A32 LCD Touch Screen", isActive: true, approvalStatus: "approved", price: 2230 },
  { id: "vim", name: "Vim Dishwashing Liquid Pouch - 500ml", isActive: true, approvalStatus: "approved", price: 50 },
  { id: "hidden", name: "Netac SSD 128GB old listing", isActive: true, approvalStatus: "draft", price: 1 },
];
const catalog = [netac, ...others];

function deps(overrides = {}) {
  return {
    getRecentMessages: async () => [],
    writeMessage: async () => {},
    upsertConversation: async () => {},
    searchProducts: async () => catalog,
    callAI: async () => {
      throw new Error("AI must not be called for a product hit");
    },
    captionTemplate: "{productName} ৳{price}",
    ...overrides,
  };
}

describe("chat product queries", () => {
  test("normalizes both queries to the same product terms", () => {
    assert.deepEqual(normalizeChatQuery("Netac SSD 128GB price?"), ["netac", "ssd", "128gb"]);
    assert.deepEqual(normalizeChatQuery("১২৮ জিবি এসএসডির দাম কত?"), ["128gb", "ssd"]);
    assert.deepEqual(normalizeChatQuery("দাম কত?"), []);
  });

  for (const query of ["Netac SSD 128GB price?", "১২৮ জিবি এসএসডির দাম কত?"]) {
    test(`"${query}" finds the Netac SSD and quotes the 128GB price, delivery and link`, async () => {
      assert.deepEqual(rankProducts(catalog, query, 5).map((p) => p.id), [netac.id]);

      const result = await handleCustomerMessage(deps(), { channel: "app", externalUserId: "u1", text: query });
      assert.match(result.replyText, /৳2,851 \(128GB Black\)/);
      assert.match(result.replyText, /আনুমানিক ডেলিভারি ৯–২৭ দিন/);
      assert.ok(result.replyText.includes(`https://chalakcharmart.com/product/${netac.id}`));
      // The text never names the origin/supplier (the product id inside the
      // URL is a Firestore doc id and is left as is).
      assert.doesNotMatch(result.replyText.replace(/https?:\/\/\S+/g, ""), /china|aliexpress/i);
      assert.equal(result.needsHuman, false);
    });
  }

  test("short chit-chat words don't match inside other words", () => {
    assert.equal(matchesQuery({ name: "High speed cable" }, "hi"), false);
    assert.equal(matchesQuery({ name: "Hi speed cable" }, "hi"), true);
  });

  test("a shop question with no product words goes to the AI", async () => {
    let asked = false;
    const result = await handleCustomerMessage(
      deps({
        callAI: async () => {
          asked = true;
          return "ডেলিভারি সাধারণত ২-৩ দিন।";
        },
      }),
      { channel: "app", externalUserId: "u2", text: "delivery time koto?" }
    );
    assert.equal(asked, true);
    assert.equal(result.productLinks, null);
  });
});
