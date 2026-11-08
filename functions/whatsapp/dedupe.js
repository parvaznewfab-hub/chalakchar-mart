const admin = require("firebase-admin");

// Dedupe layer for inbound WhatsApp messages — WhatsApp/Meta retries webhook
// delivery on timeout, which can deliver the same message twice (spec §5).
// Atomic claim via Firestore's create() semantics (fails with ALREADY_EXISTS
// if the doc already exists) — no transaction needed, create() is already a
// compare-and-swap against non-existence. Same pattern as
// functions/tiktok/webhookDedup.js's claimWebhookEvent.
const DEDUPE_COLLECTION = "whatsappProcessedMessages";

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} messageId - WhatsApp's message.id (globally unique per Meta)
 * @returns {Promise<boolean>} true if this call newly claimed the id (process it),
 *          false if it was already claimed (skip — a duplicate delivery).
 */
async function claimWhatsAppMessageId(db, messageId) {
  if (!messageId) return true; // nothing to dedupe on — never block processing over a missing id

  const ref = db.collection(DEDUPE_COLLECTION).doc(messageId);
  try {
    await ref.create({ messageId, processedAt: admin.firestore.FieldValue.serverTimestamp() });
    return true;
  } catch (error) {
    if (error.code === 6 /* gRPC ALREADY_EXISTS */) return false;
    throw error;
  }
}

module.exports = { claimWhatsAppMessageId, DEDUPE_COLLECTION };
