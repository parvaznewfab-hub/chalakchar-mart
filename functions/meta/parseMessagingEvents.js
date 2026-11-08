// Parses a Messenger or Instagram webhook POST body into normalized inbound
// message events. Both products webhook through the same Meta "Send/Receive
// API" entry[].messaging[] shape (unlike WhatsApp's distinct Cloud API
// shape in whatsapp/parseInboundMessage.js), so this one parser is shared by
// both messengerWebhook and instagramWebhook per the omnichannel messaging
// pipeline's "shared Meta modules" convention. Pure/dependency-free so it's
// unit-testable against fixture payloads without a live webhook call.
//
// Shape (per Meta's Messenger/Instagram Platform docs):
// {
//   object: "page" | "instagram",
//   entry: [{
//     id, time,
//     messaging: [{
//       sender: { id }, recipient: { id }, timestamp,
//       message: { mid, text, attachments: [...], is_echo? },
//       // read/delivery/postback events carry no `message` field — ignored
//     }]
//   }]
// }
//
// A single webhook call can carry more than one message across
// entries/messaging items, so this always returns an array, never a single
// event. There is no customer display name in this payload (unlike
// WhatsApp's `contacts[].profile.name`) — a name lookup would need a
// separate Graph API call, out of scope here — so customerName is always null.

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

/**
 * @param {object} body - the parsed (already-JSON) webhook request body
 * @returns {Array<{messageId: string, from: string, customerName: null, type: string, text: string, timestamp: string|null}>}
 */
function parseMetaMessagingEvents(body) {
  const events = [];
  const entries = arrayValue(mapValue(body).entry);

  for (const entry of entries) {
    const messagingItems = arrayValue(mapValue(entry).messaging);

    for (const item of messagingItems) {
      const messaging = mapValue(item);
      const message = mapValue(messaging.message);
      if (Object.keys(message).length === 0) continue; // read/delivery/postback-only events — nothing to reply to
      if (message.is_echo === true) continue; // our own outbound message, echoed back — never treat as inbound

      const text = String(message.text || "").trim();
      const hasAttachment = arrayValue(message.attachments).length > 0;

      events.push({
        messageId: String(message.mid || "").trim(),
        from: String(messaging.sender?.id || "").trim(),
        customerName: null,
        type: text ? "text" : (hasAttachment ? "attachment" : "unknown"),
        text,
        timestamp: messaging.timestamp !== undefined ? String(messaging.timestamp) : null,
      });
    }
  }

  return events;
}

module.exports = { parseMetaMessagingEvents };
