const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { handleCustomerMessage, HANDOFF_HOLDING_MESSAGE } = require("../messaging/handleCustomerMessage");

const CAPTION_TEMPLATE = "🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}";
const FIXED_NOW = new Date("2026-01-01T00:00:00Z");

// Builds a fresh set of stub deps per test — plain in-memory objects, no
// Firestore fake needed since handleCustomerMessage takes all Firestore/AI
// access as injected functions.
function makeDeps(overrides = {}) {
  const writtenMessages = [];
  const conversationPatches = [];
  const adminNotifications = [];

  return {
    writtenMessages,
    conversationPatches,
    adminNotifications,
    getRecentMessages: async () => [],
    writeMessage: async (conversationId, message) => {
      writtenMessages.push({ conversationId, ...message });
    },
    upsertConversation: async (conversationId, patch) => {
      conversationPatches.push({ conversationId, ...patch });
    },
    searchProducts: async () => [],
    callAI: async () => "এটি আমাদের সাধারণ উত্তর।",
    captionTemplate: CAPTION_TEMPLATE,
    notifyAdmins: async (title, body, data) => {
      adminNotifications.push({ title, body, data });
    },
    now: () => FIXED_NOW,
    ...overrides,
  };
}

describe("handleCustomerMessage", () => {
  test("blank text with no media is a no-op — nothing written, no reply", async () => {
    const deps = makeDeps();
    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "   ",
    });
    assert.equal(result.replyText, "");
    assert.equal(deps.writtenMessages.length, 0);
  });

  test("duplicate providerMessageId short-circuits without writing or replying", async () => {
    const deps = makeDeps({ messageAlreadyProcessed: async () => true });
    const result = await handleCustomerMessage(deps, {
      channel: "whatsapp",
      externalUserId: "8801xxxxxxxxx",
      text: "hello",
      providerMessageId: "wamid.123",
    });
    assert.equal(result.duplicate, true);
    assert.equal(deps.writtenMessages.length, 0);
  });

  test("a product match replies with the caption template and does not call AI", async () => {
    let aiCalled = false;
    const deps = makeDeps({
      searchProducts: async () => [{ id: "p1", name: "Napa", price: 15, isActive: true }],
      callAI: async () => {
        aiCalled = true;
        return "should not be used";
      },
    });

    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "Napa",
    });

    assert.equal(aiCalled, false);
    assert.equal(result.replyText, "🛒 Napa\nPrice: ৳15\nOrder now: https://chalakcharmart.com/product/p1");
    assert.deepEqual(result.productLinks, ["https://chalakcharmart.com/product/p1"]);
    assert.equal(result.needsHuman, false);
  });

  test("no product match falls back to the AI general-question reply", async () => {
    const deps = makeDeps({
      searchProducts: async () => [],
      callAI: async ({ message }) => `AI reply to: ${message}`,
    });

    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "delivery time koto?",
    });

    assert.equal(result.replyText, "AI reply to: delivery time koto?");
    assert.equal(result.productLinks, null);
    assert.equal(result.needsHuman, false);
  });

  test("an explicit handoff keyword skips AI/product search and notifies admins", async () => {
    let searchCalled = false;
    let aiCalled = false;
    const deps = makeDeps({
      searchProducts: async () => {
        searchCalled = true;
        return [];
      },
      callAI: async () => {
        aiCalled = true;
        return "unused";
      },
    });

    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "manager er sathe kotha bolte chai",
    });

    assert.equal(searchCalled, false);
    assert.equal(aiCalled, false);
    assert.equal(result.replyText, HANDOFF_HOLDING_MESSAGE);
    assert.equal(result.needsHuman, true);
    assert.equal(deps.adminNotifications.length, 1);
    assert.equal(deps.adminNotifications[0].data.type, "needs_human");
  });

  test("a low-confidence AI reply is replaced with the holding message and flags needsHuman", async () => {
    const deps = makeDeps({
      callAI: async () => "I'm not sure about that.",
    });

    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "some obscure question",
    });

    assert.equal(result.replyText, HANDOFF_HOLDING_MESSAGE);
    assert.equal(result.needsHuman, true);
  });

  test("a third repeated question triggers handoff even without a keyword", async () => {
    const deps = makeDeps({
      getRecentMessages: async () => [
        { sender: "customer", text: "price koto?" },
        { sender: "bot", text: "কিছু বলা যায়নি" },
        { sender: "customer", text: "price koto?" },
      ],
    });

    const result = await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "price koto?",
    });

    assert.equal(result.needsHuman, true);
    assert.equal(result.replyText, HANDOFF_HOLDING_MESSAGE);
  });

  test("writes both the customer message and the bot reply to the conversation", async () => {
    const deps = makeDeps({
      searchProducts: async () => [{ id: "p1", name: "Napa", price: 15, isActive: true }],
    });

    await handleCustomerMessage(deps, { channel: "app", externalUserId: "uid1", text: "Napa" });

    assert.equal(deps.writtenMessages.length, 2);
    assert.equal(deps.writtenMessages[0].sender, "customer");
    assert.equal(deps.writtenMessages[0].text, "Napa");
    assert.equal(deps.writtenMessages[1].sender, "bot");
    assert.deepEqual(deps.writtenMessages[1].productLinks, ["https://chalakcharmart.com/product/p1"]);
  });

  test("upserts the conversation with channel, externalUserId, and needsHuman", async () => {
    const deps = makeDeps();

    await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      customerName: "Rahim",
      text: "hi",
    });

    assert.equal(deps.conversationPatches.length, 1);
    const patch = deps.conversationPatches[0];
    assert.equal(patch.conversationId, "app_uid1");
    assert.equal(patch.channel, "app");
    assert.equal(patch.externalUserId, "uid1");
    assert.equal(patch.customerName, "Rahim");
    assert.equal(patch.needsHuman, false);
    assert.equal(patch.unreadByAdmin, true);
  });

  test("conversationId follows the {channel}_{externalUserId} convention", async () => {
    const deps = makeDeps();
    const result = await handleCustomerMessage(deps, {
      channel: "whatsapp",
      externalUserId: "8801xxxxxxxxx",
      text: "hi",
    });
    assert.equal(result.conversationId, "whatsapp_8801xxxxxxxxx");
  });

  test("a genuine product-search miss triggers the AliExpress search-import fallback", async () => {
    const triggeredQueries = [];
    const deps = makeDeps({
      searchProducts: async () => [],
      triggerSearchImportFallback: (query) => triggeredQueries.push(query),
    });

    await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "wireless earbuds",
    });

    assert.deepEqual(triggeredQueries, ["wireless earbuds"]);
  });

  test("chit-chat with no product match does not trigger the search-import fallback", async () => {
    const triggeredQueries = [];
    const deps = makeDeps({
      searchProducts: async () => [],
      triggerSearchImportFallback: (query) => triggeredQueries.push(query),
    });

    await handleCustomerMessage(deps, { channel: "app", externalUserId: "uid1", text: "thanks" });

    assert.deepEqual(triggeredQueries, []);
  });

  test("a product match does not trigger the search-import fallback", async () => {
    const triggeredQueries = [];
    const deps = makeDeps({
      searchProducts: async () => [{ id: "p1", name: "Napa", price: 15, isActive: true }],
      triggerSearchImportFallback: (query) => triggeredQueries.push(query),
    });

    await handleCustomerMessage(deps, { channel: "app", externalUserId: "uid1", text: "Napa" });

    assert.deepEqual(triggeredQueries, []);
  });

  test("an explicit handoff keyword does not trigger the search-import fallback", async () => {
    const triggeredQueries = [];
    const deps = makeDeps({
      searchProducts: async () => [],
      triggerSearchImportFallback: (query) => triggeredQueries.push(query),
    });

    await handleCustomerMessage(deps, {
      channel: "app",
      externalUserId: "uid1",
      text: "manager er sathe kotha bolte chai",
    });

    assert.deepEqual(triggeredQueries, []);
  });

  test("works without deps.triggerSearchImportFallback (optional dep)", async () => {
    const deps = makeDeps({ searchProducts: async () => [] });

    const result = await handleCustomerMessage(deps, { channel: "app", externalUserId: "uid1", text: "wireless earbuds" });

    assert.equal(result.replyText, "এটি আমাদের সাধারণ উত্তর।");
  });
});
