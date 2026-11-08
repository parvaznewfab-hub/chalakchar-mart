const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { buildConversationId, truncatePreview } = require("../messaging/conversationId");

describe("buildConversationId", () => {
  test("joins channel and externalUserId with an underscore", () => {
    assert.equal(buildConversationId("whatsapp", "8801xxxxxxxxx"), "whatsapp_8801xxxxxxxxx");
  });

  test("app channel with a Firebase uid", () => {
    assert.equal(buildConversationId("app", "uid_abc123"), "app_uid_abc123");
  });

  test("replaces slashes in externalUserId (invalid in Firestore doc ids)", () => {
    assert.equal(buildConversationId("instagram", "178/xxxxxxxx"), "instagram_178_xxxxxxxx");
  });

  test("blank/undefined inputs degrade to empty segments rather than throwing", () => {
    assert.equal(buildConversationId("", ""), "_");
    assert.equal(buildConversationId(undefined, undefined), "_");
  });
});

describe("truncatePreview", () => {
  test("returns short text unchanged", () => {
    assert.equal(truncatePreview("hello there"), "hello there");
  });

  test("collapses internal whitespace/newlines", () => {
    assert.equal(truncatePreview("hello\n\n  there"), "hello there");
  });

  test("truncates with an ellipsis once over the max length", () => {
    const long = "a".repeat(200);
    const result = truncatePreview(long, 120);
    assert.equal(result.length, 120);
    assert.ok(result.endsWith("…"));
  });

  test("blank/undefined input returns empty string", () => {
    assert.equal(truncatePreview(""), "");
    assert.equal(truncatePreview(undefined), "");
  });
});
