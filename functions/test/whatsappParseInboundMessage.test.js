const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { parseWhatsAppWebhookEvents } = require("../whatsapp/parseInboundMessage");

function textMessagePayload({ from = "8801xxxxxxxxx", id = "wamid.123", body = "Napa ache?", name = "Rahim" } = {}) {
  return {
    object: "whatsapp_business_account",
    entry: [
      {
        id: "entry1",
        changes: [
          {
            field: "messages",
            value: {
              metadata: { phone_number_id: "1234567890", display_phone_number: "8801xxxxxxxxx" },
              contacts: [{ profile: { name }, wa_id: from }],
              messages: [
                { from, id, timestamp: "1700000000", type: "text", text: { body } },
              ],
            },
          },
        ],
      },
    ],
  };
}

describe("parseWhatsAppWebhookEvents", () => {
  test("extracts a single text message with sender name", () => {
    const events = parseWhatsAppWebhookEvents(textMessagePayload());
    assert.equal(events.length, 1);
    assert.deepEqual(events[0], {
      messageId: "wamid.123",
      from: "8801xxxxxxxxx",
      customerName: "Rahim",
      type: "text",
      text: "Napa ache?",
      timestamp: "1700000000",
    });
  });

  test("status-only updates (sent/delivered/read) produce no events", () => {
    const payload = {
      object: "whatsapp_business_account",
      entry: [
        {
          id: "entry1",
          changes: [
            {
              field: "messages",
              value: {
                metadata: { phone_number_id: "123" },
                statuses: [{ id: "wamid.999", status: "delivered", recipient_id: "8801xxxxxxxxx" }],
              },
            },
          ],
        },
      ],
    };
    assert.deepEqual(parseWhatsAppWebhookEvents(payload), []);
  });

  test("non-text messages (image/audio) are still extracted but with empty text", () => {
    const payload = textMessagePayload();
    payload.entry[0].changes[0].value.messages[0] = {
      from: "8801xxxxxxxxx",
      id: "wamid.456",
      timestamp: "1700000001",
      type: "image",
      image: { id: "media123", mime_type: "image/jpeg" },
    };
    const events = parseWhatsAppWebhookEvents(payload);
    assert.equal(events.length, 1);
    assert.equal(events[0].type, "image");
    assert.equal(events[0].text, "");
  });

  test("missing contact profile falls back to null customerName", () => {
    const payload = textMessagePayload();
    payload.entry[0].changes[0].value.contacts = [];
    const events = parseWhatsAppWebhookEvents(payload);
    assert.equal(events[0].customerName, null);
  });

  test("multiple messages across entries/changes are all returned", () => {
    const payload = {
      object: "whatsapp_business_account",
      entry: [
        textMessagePayload({ id: "wamid.1", body: "hi" }).entry[0],
        textMessagePayload({ id: "wamid.2", body: "hello again", from: "8802xxxxxxxxx" }).entry[0],
      ],
    };
    const events = parseWhatsAppWebhookEvents(payload);
    assert.equal(events.length, 2);
    assert.deepEqual(events.map((e) => e.messageId), ["wamid.1", "wamid.2"]);
  });

  test("malformed/empty body returns an empty array rather than throwing", () => {
    assert.deepEqual(parseWhatsAppWebhookEvents({}), []);
    assert.deepEqual(parseWhatsAppWebhookEvents(null), []);
    assert.deepEqual(parseWhatsAppWebhookEvents(undefined), []);
    assert.deepEqual(parseWhatsAppWebhookEvents({ entry: "not-an-array" }), []);
  });
});
