const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { parseMetaMessagingEvents } = require("../meta/parseMessagingEvents");

function textMessagePayload({ object = "page", senderId = "psid123", mid = "mid.1", text = "Napa ache?" } = {}) {
  return {
    object,
    entry: [
      {
        id: "page1",
        time: 1700000000000,
        messaging: [
          {
            sender: { id: senderId },
            recipient: { id: "page1" },
            timestamp: 1700000000,
            message: { mid, text },
          },
        ],
      },
    ],
  };
}

describe("parseMetaMessagingEvents", () => {
  test("extracts a single text message from a Messenger (object: page) payload", () => {
    const events = parseMetaMessagingEvents(textMessagePayload());
    assert.equal(events.length, 1);
    assert.deepEqual(events[0], {
      messageId: "mid.1",
      from: "psid123",
      customerName: null,
      type: "text",
      text: "Napa ache?",
      timestamp: "1700000000",
    });
  });

  test("extracts a single text message from an Instagram (object: instagram) payload", () => {
    const events = parseMetaMessagingEvents(textMessagePayload({ object: "instagram" }));
    assert.equal(events.length, 1);
    assert.equal(events[0].text, "Napa ache?");
  });

  test("read/delivery events (no message field) produce no events", () => {
    const payload = {
      object: "page",
      entry: [
        {
          id: "page1",
          messaging: [
            { sender: { id: "psid123" }, recipient: { id: "page1" }, timestamp: 1700000000, delivery: { mids: ["mid.1"] } },
            { sender: { id: "psid123" }, recipient: { id: "page1" }, timestamp: 1700000001, read: { watermark: 1700000000 } },
          ],
        },
      ],
    };
    assert.deepEqual(parseMetaMessagingEvents(payload), []);
  });

  test("echoes of our own sent message (is_echo: true) are skipped", () => {
    const payload = textMessagePayload();
    payload.entry[0].messaging[0].message.is_echo = true;
    assert.deepEqual(parseMetaMessagingEvents(payload), []);
  });

  test("attachment-only messages (no text) are still extracted with empty text", () => {
    const payload = textMessagePayload();
    payload.entry[0].messaging[0].message = {
      mid: "mid.2",
      attachments: [{ type: "image", payload: { url: "https://example.com/a.jpg" } }],
    };
    const events = parseMetaMessagingEvents(payload);
    assert.equal(events.length, 1);
    assert.equal(events[0].type, "attachment");
    assert.equal(events[0].text, "");
  });

  test("multiple messages across entries/messaging are all returned", () => {
    const payload = {
      object: "page",
      entry: [
        textMessagePayload({ mid: "mid.1", text: "hi" }).entry[0],
        textMessagePayload({ mid: "mid.2", text: "hello again", senderId: "psid456" }).entry[0],
      ],
    };
    const events = parseMetaMessagingEvents(payload);
    assert.equal(events.length, 2);
    assert.deepEqual(events.map((e) => e.messageId), ["mid.1", "mid.2"]);
  });

  test("malformed/empty body returns an empty array rather than throwing", () => {
    assert.deepEqual(parseMetaMessagingEvents({}), []);
    assert.deepEqual(parseMetaMessagingEvents(null), []);
    assert.deepEqual(parseMetaMessagingEvents(undefined), []);
    assert.deepEqual(parseMetaMessagingEvents({ entry: "not-an-array" }), []);
  });
});
