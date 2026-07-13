const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const { mapValue, textValue, requireAdminAuth, loadAppSettings } = require("./util");
const { contentVersionHash, jobIdFor } = require("./crypto");
const { getActiveConnection } = require("./connectionStore");

const JOBS_COLLECTION = "tiktok_publish_jobs";

function db() {
  return admin.firestore();
}

function channelResult(status, extra = {}) {
  return { status, at: admin.firestore.FieldValue.serverTimestamp(), ...extra };
}

// This app's product/marketing-outbox model only ever stores a single
// `imageUrl` field (see functions/index.js productMarketingPayload) — there
// is no video field anywhere in the data model. mediaType therefore always
// resolves to "photo" today; the "video" path exists structurally (crypto
// key shape, media.js, publish.js payload builder) but is unexercised.
function resolveMediaType(_outbox) {
  return "photo";
}

// Called from the existing dispatcher's run("tiktok", postTikTokContent) —
// the ONLY thing this does is prepare a job for human review. It never
// calls any TikTok publish endpoint, so it is safe for the dispatcher to
// call unconditionally, exactly like the Facebook/Instagram/WhatsApp
// handlers beside it.
async function postTikTokContent(settings, outbox) {
  const socialApi = mapValue(settings.socialApi);

  if (socialApi.tiktokEnabled === false) {
    return channelResult("skipped_disabled");
  }

  const connection = await getActiveConnection();
  if (!connection) {
    return channelResult("skipped_missing_credentials");
  }

  const imageUrl = textValue(outbox.imageUrl);
  if (!imageUrl) {
    return channelResult("skipped_missing_image_url");
  }

  const caption = textValue(mapValue(outbox.captions).tiktok) || textValue(outbox.productName);
  const mediaType = resolveMediaType(outbox);
  const republishNonce = textValue(outbox.tiktokRepublishNonce, "0");
  const contentVersion = contentVersionHash(imageUrl, caption, republishNonce);
  const jobId = jobIdFor(outbox.productId, contentVersion, connection.id, mediaType);
  const jobRef = db().collection(JOBS_COLLECTION).doc(jobId);

  const auditStatus = textValue(socialApi.tiktokAuditStatus, "unaudited");
  const blockUntilAudited = socialApi.tiktokBlockUntilAudited === true && auditStatus !== "audited";

  // Deterministic doc ID already prevents duplicates for this exact
  // identity; the transaction additionally guarantees a job that has moved
  // past review (or further) is never silently reset by a later dispatch
  // retry of the same outbox item (e.g. Instagram retrying while TikTok's
  // leg already has an admin-confirmed job in flight).
  const outcome = await db().runTransaction(async (tx) => {
    const existing = await tx.get(jobRef);
    if (existing.exists) {
      return { created: false, status: existing.data().status };
    }

    const status = blockUntilAudited ? "blocked_pending_audit" : "pending_creator_review";

    tx.set(jobRef, {
      jobId,
      productId: outbox.productId,
      queueId: outbox.productId,
      contentVersion,
      connectionId: connection.id,
      mediaType,
      status,
      deliveryFinal: false,
      // Polling/transport-retry counter — reset to 0 each time a NEW
      // publishId begins processing (see publish.js). Distinct from...
      pollAttemptCount: 0,
      // ...this: how many times the whole confirm→init→failed cycle has
      // repeated for this job identity. Only resolve.js's retryable-FAILED
      // branch increments this; publish.js never touches it after creation.
      resubmissionAttemptCount: 0,
      maxAttempts: 5,
      previousAttempts: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { created: true, status };
  });

  return channelResult(outcome.status, { jobId, deliveryFinal: false });
}

// Admin-only. Legitimate republish path: bumps a nonce on the outbox doc so
// contentVersion (and therefore the job identity) changes even though the
// image/caption text are unchanged, then immediately creates the new job —
// rather than waiting for some other product edit to naturally re-dispatch.
const tiktokForceRepublish = onCall({ region: "asia-south1" }, async (request) => {
  await requireAdminAuth(request);

  const productId = textValue(request.data && request.data.productId);
  if (!productId) {
    throw new HttpsError("invalid-argument", "productId is required.");
  }

  const outboxRef = db().collection("marketing_outbox").doc(productId);
  const outboxDoc = await outboxRef.get();
  if (!outboxDoc.exists) {
    throw new HttpsError("not-found", "No marketing_outbox entry for this product.");
  }

  const outbox = outboxDoc.data();
  const currentNonce = Number(outbox.tiktokRepublishNonce || 0);
  const nextNonce = currentNonce + 1;

  await outboxRef.set({ tiktokRepublishNonce: nextNonce }, { merge: true });

  const settings = await loadAppSettings();
  const result = await postTikTokContent(settings, { ...outbox, productId, tiktokRepublishNonce: String(nextNonce) });

  return { jobId: result.jobId || null, status: result.status };
});

module.exports = { postTikTokContent, tiktokForceRepublish, JOBS_COLLECTION };
