const admin = require("firebase-admin");
const crypto = require("crypto");

const EVENTS_COLLECTION = "tiktok_webhook_events";

// Correctness does NOT depend on this dedup layer — fetchAndResolveStatus()
// is already idempotent (re-checking an already-terminal or already-leased
// job is a safe no-op). This exists purely to avoid redundant Fetch Status
// calls when TikTok's "at least once" delivery sends the same event twice
// in quick succession. 24h comfortably covers realistic duplicate windows;
// anything older than that has long since been resolved by the sweep anyway.
const DEDUP_TTL_MS = 24 * 60 * 60 * 1000;

function db() {
  return admin.firestore();
}

// Atomic claim via Firestore's create() semantics (fails with ALREADY_EXISTS
// if the doc is already there) — no transaction needed, create() is already
// a compare-and-swap against non-existence.
async function claimWebhookEvent(signature) {
  const id = crypto.createHash("sha256").update(signature).digest("hex").slice(0, 40);
  const ref = db().collection(EVENTS_COLLECTION).doc(id);

  try {
    await ref.create({
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + DEDUP_TTL_MS),
    });
    return true; // newly claimed — not a duplicate
  } catch (error) {
    if (error.code === 6 /* gRPC ALREADY_EXISTS */) return false;
    throw error;
  }
}

module.exports = { claimWebhookEvent, EVENTS_COLLECTION };
