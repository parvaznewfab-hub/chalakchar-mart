// Parses a WhatsApp Cloud API webhook POST body into normalized inbound
// message events. Pure/dependency-free so it's unit-testable against fixture
// payloads without a live webhook call.
//
// Shape (per Meta's Cloud API docs):
// {
//   object: "whatsapp_business_account",
//   entry: [{
//     id, changes: [{
//       field: "messages",
//       value: {
//         metadata: { phone_number_id, display_phone_number },
//         contacts: [{ profile: { name }, wa_id }],
//         messages: [{ from, id, timestamp, type, text: { body }, ... }],
//         statuses: [...] // delivery/read receipts — not customer messages, ignored
//       }
//     }]
//   }]
// }
//
// A single webhook call can (rarely) carry more than one message across
// entries/changes, so this always returns an array, never a single event.

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

/**
 * @param {object} body - the parsed (already-JSON) webhook request body
 * @returns {Array<{messageId: string, from: string, customerName: string|null, type: string, text: string, timestamp: string|null}>}
 */
function parseWhatsAppWebhookEvents(body) {
  const events = [];
  const entries = arrayValue(mapValue(body).entry);

  for (const entry of entries) {
    const changes = arrayValue(mapValue(entry).changes);

    for (const change of changes) {
      const value = mapValue(mapValue(change).value);
      const messages = arrayValue(value.messages);
      if (messages.length === 0) continue; // status-only updates (sent/delivered/read) — nothing to reply to

      const contacts = arrayValue(value.contacts);

      for (const message of messages) {
        const from = String(message?.from || "").trim();
        const contact = contacts.find((c) => String(c?.wa_id || "").trim() === from);
        const type = String(message?.type || "").trim();

        events.push({
          messageId: String(message?.id || "").trim(),
          from,
          customerName: contact?.profile?.name ? String(contact.profile.name).trim() : null,
          type,
          text: type === "text" ? String(message?.text?.body || "").trim() : "",
          timestamp: message?.timestamp ? String(message.timestamp) : null,
        });
      }
    }
  }

  return events;
}

module.exports = { parseWhatsAppWebhookEvents };
