const admin = require("firebase-admin");

const OUTCOME_ACCEPTED = "accepted_processing";
const OUTCOME_PUBLIC = "published_public";
const OUTCOME_PRIVATE = "published_private_audit_restricted";
const OUTCOME_FAILED = "failed";

// Deliberately separate from functions/index.js's writeCampaignAnalytics —
// importing it here would create a circular require (index.js already
// requires this module's siblings). This only ever patches the tiktok-*
// fields, additive, on the same campaign_analytics/{productId} doc the main
// pipeline already writes the base fields to.
//
// Each outcome is its own boolean field, not a single status string — this
// is the point: published_private_audit_restricted must be structurally
// impossible to mistake for tiktokPublishedPublic in any downstream query,
// dashboard, or "posts delivered" aggregate. Only tiktokPublishedPublic may
// ever be counted as real public marketing reach.
async function patchTikTokAnalytics(productId, { outcome, publishId, attemptCount }) {
  await admin.firestore().collection("campaign_analytics").doc(productId).set({
    tiktokAcceptedProcessing: outcome === OUTCOME_ACCEPTED,
    tiktokPublishedPublic: outcome === OUTCOME_PUBLIC,
    tiktokPublishedPrivateAuditRestricted: outcome === OUTCOME_PRIVATE,
    tiktokFailed: outcome === OUTCOME_FAILED,
    tiktokLastOutcome: outcome,
    tiktokPublishId: publishId || null,
    tiktokAttemptCount: attemptCount || 0,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

module.exports = {
  patchTikTokAnalytics,
  TIKTOK_OUTCOME_ACCEPTED: OUTCOME_ACCEPTED,
  TIKTOK_OUTCOME_PUBLIC: OUTCOME_PUBLIC,
  TIKTOK_OUTCOME_PRIVATE: OUTCOME_PRIVATE,
  TIKTOK_OUTCOME_FAILED: OUTCOME_FAILED,
};
