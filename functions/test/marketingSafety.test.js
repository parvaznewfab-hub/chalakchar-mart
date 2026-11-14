// Incident 2026-11-14: the chat question "Netac SSD 128GB price?" fell back
// to aliexpressSearchImport, which imported 5 medieval-costume products live
// (needsReview: true, autoPublish OFF) and the create trigger marketed them
// on 8 channels. These tests pin every guard added for it.
const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const {
  marketingBlockReason,
  isMarketingEligible,
  autoMarketingBlockReason,
  shouldAutoMarketProduct,
} = require("../marketing/eligibility");
const { searchImportPublishOptions } = require("../aliexpress/searchImportPublish");
const { isRelevantTitle, hasPartialCatalogMatch } = require("../messaging/productMatch");
const { handleCustomerMessage } = require("../messaging/handleCustomerMessage");

// The 5 products actually imported (live data), as the trigger saw them.
const costumeTitles = [
  "1 Pair Medieval PU Leather Skirt Hike Clips Vintage Double Ring Skirt Lifters Belt Hangers Viking Renaissance Faire LARP Fantasy",
  "Vintage Solid Faux Suede Drawstring Belt Bag, Simple Medieval Waist Pouch, Renaissance Pirate Elf Cosplay Costume Accessory",
  "Vintage Medieval PU Leather Belt with Drawstring Pouch Renaissance Long Tail Waist Belt Hanging Bag Pirate Witch LARP Cosplay Ha",
  "Medieval Viking PU Wrist Guards for LARP, Viking Warrior & Knight Arm Protectors for Role-Play, Themed Parties",
  "Cork Potion Bottle Cosplay Belt Accessories, Include 3 Potion Bottles with Holder Renaissance Witch Props Costume Accessories fo",
];
const importedCostume = {
  name: costumeTitles[0],
  isActive: true,
  isVisible: true,
  isPublished: true,
  approvalStatus: "approved",
  needsReview: true,
  autoMarketingDisabled: false,
  importedBy: "search_trigger",
};

describe("marketing eligibility (A1)", () => {
  test("the incident product is blocked: needsReview", () => {
    assert.equal(marketingBlockReason(importedCostume), "needs_review");
    assert.equal(shouldAutoMarketProduct(importedCostume), false);
  });

  test("not approved / not live / missing are blocked", () => {
    assert.equal(marketingBlockReason({ approvalStatus: "draft" }), "not_approved");
    assert.equal(marketingBlockReason({ approvalStatus: "pending" }), "not_approved");
    assert.equal(marketingBlockReason({ isActive: false }), "not_live");
    assert.equal(marketingBlockReason({ isPublished: false }), "not_live");
    assert.equal(marketingBlockReason(null), "product_missing");
  });

  test("a reviewed, approved, live product may be marketed; legacy products without approvalStatus too", () => {
    const ok = { isActive: true, approvalStatus: "approved", needsReview: false };
    assert.equal(isMarketingEligible(ok), true);
    assert.equal(isMarketingEligible({ name: "Vim 500ml" }), true);
  });

  test("automatic marketing also respects autoMarketingDisabled (every import sets it)", () => {
    const reviewedImport = { isActive: true, approvalStatus: "approved", needsReview: false, autoMarketingDisabled: true };
    assert.equal(isMarketingEligible(reviewedImport), true, "an admin may still queue it explicitly");
    assert.equal(autoMarketingBlockReason(reviewedImport), "auto_marketing_disabled");
  });
});

describe("search-import publish policy (A2)", () => {
  test("unpublished unless BOTH autoPublish and searchImportAutoPublish are on", () => {
    for (const settings of [{}, { autoPublish: false }, { autoPublish: true }, { searchImportAutoPublish: true }, { autoPublish: false, searchImportAutoPublish: true }]) {
      const { publish, options } = searchImportPublishOptions(settings);
      assert.equal(publish, false, JSON.stringify(settings));
      assert.deepEqual(options, { forceUnpublish: true, needsReview: true });
    }
    const on = searchImportPublishOptions({ autoPublish: true, searchImportAutoPublish: true });
    assert.equal(on.publish, true);
    assert.deepEqual(on.options, { forcePublish: true, needsReview: true }, "still needsReview, so never marketed");
  });
});

describe("search result relevance (A3)", () => {
  test("none of the 5 costume results is relevant to the SSD question", () => {
    for (const title of costumeTitles) {
      assert.equal(isRelevantTitle("Netac SSD 128GB price?", title), false, title);
      assert.equal(isRelevantTitle("128gb ssd", title), false, title);
    }
  });

  test("a real SSD listing is relevant, in English or Bangla", () => {
    const title = "Netac SSD 128GB 256GB 512GB SATA3 2.5 Inch Internal Solid State Drive";
    assert.equal(isRelevantTitle("Netac SSD 128GB", title), true);
    assert.equal(isRelevantTitle("১২৮ জিবি এসএসডি", title), true);
  });

  test("a number alone is not enough", () => {
    assert.equal(isRelevantTitle("128gb ssd", "128GB Micro SD memory card"), false);
  });
});

describe("chat fallback is skipped when the catalog partly matches (A3)", () => {
  const catalog = [
    { id: "ssd", name: "Netac SATA SSD Hard Drive 128GB 256GB 512GB", isActive: true, approvalStatus: "approved", price: 2851 },
  ];

  test("hasPartialCatalogMatch", () => {
    assert.equal(hasPartialCatalogMatch(catalog, "Netac SSD 1TB nvme"), true);
    assert.equal(hasPartialCatalogMatch(catalog, "wireless earbuds"), false);
    assert.equal(hasPartialCatalogMatch([{ ...catalog[0], isActive: false }], "Netac SSD 1TB nvme"), false);
  });

  function deps(triggered) {
    return {
      getRecentMessages: async () => [],
      writeMessage: async () => {},
      upsertConversation: async () => {},
      searchProducts: async () => catalog,
      callAI: async () => "AI reply",
      captionTemplate: "",
      triggerSearchImportFallback: (q) => triggered.push(q),
    };
  }

  test("'Netac SSD 128GB price?' is answered from the catalog; no import", async () => {
    const triggered = [];
    const result = await handleCustomerMessage(deps(triggered), { channel: "app", externalUserId: "u", text: "Netac SSD 128GB price?" });
    assert.deepEqual(triggered, []);
    assert.ok(result.productLinks?.length);
  });

  test("a close but not exact query (Netac NVMe 1TB) does not import either", async () => {
    const triggered = [];
    await handleCustomerMessage(deps(triggered), { channel: "app", externalUserId: "u", text: "Netac SSD 1TB nvme dam koto" });
    assert.deepEqual(triggered, []);
  });

  test("a real miss still relays only its product words", async () => {
    const triggered = [];
    await handleCustomerMessage(deps(triggered), { channel: "app", externalUserId: "u", text: "wireless earbuds er dam koto?" });
    assert.deepEqual(triggered, ["wireless earbuds"]);
  });
});
