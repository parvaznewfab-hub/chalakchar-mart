// Health features removed (Play Store Health apps declaration): medicine /
// health products are detected and hidden, never imported, never found by
// chat search, and the chat gives no medicine or doctor advice.
const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const { classifyHealthProduct, isHealthQuery } = require("../catalog/healthProduct");
const { rankProducts } = require("../messaging/productMatch");
const { handleCustomerMessage, HEALTH_NOT_OFFERED_MESSAGE } = require("../messaging/handleCustomerMessage");

// Live catalog rows (2026-11-14).
const bactin = { id: "46SbyNdhWk1lS9DsZhMl", name: "BACTIN", category: "Pharmacy", generic: "CIPROFLOXACIN HYDROCHLORIDE USP", strength: "500 MG", type: "TABLET" };
const orsaline = { id: "hcYlLXrkn9kgDj9Q30k6", name: "SMC Orsaline-N Oral Rehydration Solution", category: "Health & Wellness", strength: "pcs", type: "Oral Rehydration Solution" };
const horlicks = { name: "Horlicks Nutritional Drink Jar - Fresh & Delicious", category: "Baby food", strength: "250 gm", type: "Nutritional drink" };

describe("classifyHealthProduct", () => {
  test("live medicine and OTC products", () => {
    assert.equal(classifyHealthProduct(bactin).group, "rx");
    assert.equal(classifyHealthProduct(orsaline).group, "otc");
    assert.equal(classifyHealthProduct(horlicks).group, "unsure");
  });

  test("groceries with pack size in strength / generic are not medicine", () => {
    assert.equal(classifyHealthProduct({ name: "Fresh Refined Sugar", category: "Grocery", generic: "Sugar", strength: "1 kg", type: "Sugar", manufacturer: "Fresh" }).group, null);
    assert.equal(classifyHealthProduct({ name: "Vim Dishwashing Liquid", strength: "500 ml", type: "Dishwashing Liquid" }).group, null);
    assert.equal(classifyHealthProduct({ name: "Rooh Afza - Refreshing Herbal Drink Concentrate", category: "Beverages" }).group, null);
  });

  test("electronics that share medicine words are not medicine", () => {
    assert.equal(classifyHealthProduct({ name: "Samsung Galaxy Tab A7 tablet LCD display" }).group, null);
    assert.equal(classifyHealthProduct({ name: "Napa leather case for iPhone 12" }).group, null);
    assert.equal(classifyHealthProduct({ name: "Medieval Viking PU Wrist Guards Arm Protectors" }).group, null);
    assert.equal(classifyHealthProduct({ name: "Netac SATA SSD 128GB" }).group, null);
  });

  test("medical devices and supplements", () => {
    assert.equal(classifyHealthProduct({ name: "Digital Blood Pressure Machine" }).group, "otc");
    assert.equal(classifyHealthProduct({ name: "Vitamin C 1000 Supplement" }).group, "otc");
    assert.equal(classifyHealthProduct({ name: "Napa Extra 500mg tablet" }).group, "rx");
  });
});

describe("import denylist (isHealthQuery)", () => {
  test("health queries are refused", () => {
    for (const q of ["bactin", "ওষুধ", "doctor", "napa 500mg", "vitamin c", "blood pressure machine", "প্রেসক্রিপশন", "ভিটামিন", "medicine"]) {
      assert.equal(isHealthQuery(q), true, q);
    }
  });

  test("parts queries pass", () => {
    for (const q of ["Netac SSD 128GB", "tablet display", "ipad tablet battery", "iphone 12 display", "laptop charger 65w"]) {
      assert.equal(isHealthQuery(q), false, q);
    }
  });
});

describe("chat: no medicine or doctor advice", () => {
  const hidden = { ...bactin, isActive: false, isVisible: false, isPublished: false, hiddenReason: "health_removed", approvalStatus: "approved" };

  function deps(calls, overrides = {}) {
    return {
      getRecentMessages: async () => [],
      writeMessage: async () => {},
      upsertConversation: async () => {},
      searchProducts: async () => {
        calls.search += 1;
        return [hidden];
      },
      callAI: async () => {
        calls.ai += 1;
        return "AI";
      },
      triggerSearchImportFallback: (q) => calls.imports.push(q),
      captionTemplate: "",
      ...overrides,
    };
  }

  for (const text of ["bactin", "ওষুধ লাগবে", "doctor appointment", "জ্বরের জন্য কোন ওষুধ খাব?", "napa 500mg dam koto"]) {
    test(`"${text}" -> fixed reply, no search, no AI, no import`, async () => {
      const calls = { search: 0, ai: 0, imports: [] };
      const result = await handleCustomerMessage(deps(calls), { channel: "app", externalUserId: "u", text });
      assert.equal(result.replyText, HEALTH_NOT_OFFERED_MESSAGE);
      assert.equal(result.productLinks, null);
      assert.equal(result.needsHuman, false);
      assert.deepEqual(calls, { search: 0, ai: 0, imports: [] });
    });
  }

  test("the reply recommends no medicine", () => {
    assert.doesNotMatch(HEALTH_NOT_OFFERED_MESSAGE, /mg|ট্যাবলেট|সিরাপ|খান|খাবেন|dose/i);
  });

  test("hidden health products are never returned by chat search", () => {
    assert.deepEqual(rankProducts([hidden], "bactin", 5), []);
  });

  test("with healthEnabled on, the old flow comes back (flag is reversible)", async () => {
    const calls = { search: 0, ai: 0, imports: [] };
    const result = await handleCustomerMessage(deps(calls, { healthEnabled: true }), { channel: "app", externalUserId: "u", text: "doctor appointment" });
    assert.notEqual(result.replyText, HEALTH_NOT_OFFERED_MESSAGE);
    assert.equal(calls.search, 1);
  });

  test("parts questions are unaffected", async () => {
    const calls = { search: 0, ai: 0, imports: [] };
    const result = await handleCustomerMessage(
      deps(calls, { searchProducts: async () => [{ id: "ssd", name: "Netac SATA SSD 128GB", isActive: true, approvalStatus: "approved", price: 2851 }] }),
      { channel: "app", externalUserId: "u", text: "Netac SSD 128GB price?" }
    );
    assert.ok(result.productLinks?.length);
  });
});
