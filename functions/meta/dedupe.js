const admin = require("firebase-admin");

// Generic dedupe layer for inbound Meta product webhooks (Messenger,
// Instagram) — Meta retries webhook delivery on timeout, which can deliver
// the same message twice. Shared across products via a `collection`
// parameter rather than copy-pasted per product, since the claim logic
// itself doesn't vary — only WhatsApp keeps its own dedicated module
// (whatsapp/dedupe.js) since it predates this shared one. Atomic claim via
// Firestore's create() semantics (fails with ALREADY_EXISTS if the doc
// already exists) — no transaction needed, create() is already a
// compare-and-swap against non-existence. Same pattern as
// whatsapp/dedupe.js's claimWhatsAppMessageId / tiktok/webhookDedup.js's
// claimWebhookEvent.

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} collection - dedupe collection name, e.g.
 *        "messengerProcessedMessages" / "instagramProcessedMessages"
 * @param {string} messageId - the provider's message id (mid), globally
 *        unique per Meta
 * @returns {Promise<boolean>} true if this call newly claimed the id (process it),
 *          false if it was already claimed (skip — a duplicate delivery).
 */
async function claimMetaMessageId(db, collection, messageId) {
  if (!messageId) return true; // nothing to dedupe on — never block processing over a missing id

  const ref = db.collection(collection).doc(messageId);
  try {
    await ref.create({ messageId, processedAt: admin.firestore.FieldValue.serverTimestamp() });
    return true;
  } catch (error) {
    if (error.code === 6 /* gRPC ALREADY_EXISTS */) return false;
    throw error;
  }
}

module.exports = { claimMetaMessageId };
