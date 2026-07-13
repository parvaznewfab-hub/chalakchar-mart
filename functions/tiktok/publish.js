const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

const { textValue, mapValue, loadAppSettings, requireAdminAuth } = require("./util");
const { redactSecrets } = require("./logging");
const { contentVersionHash } = require("./crypto");
const { TIKTOK_API_BASE } = require("./config");
const { ensureFreshAccessToken } = require("./tokenRefresh");
const { JOBS_COLLECTION } = require("./dispatch");
const { fetchCreatorInfo } = require("./creatorInfo");
const { validateMediaForPublish, MediaValidationError } = require("./media");
const { patchTikTokAnalytics, TIKTOK_OUTCOME_ACCEPTED } = require("./analytics");

const VALID_PRIVACY_LEVELS = new Set([
  "PUBLIC_TO_EVERYONE",
  "MUTUAL_FOLLOW_FRIENDS",
  "FOLLOWER_OF_CREATOR",
  "SELF_ONLY",
]);

function db() {
  return admin.firestore();
}

function jobRef(jobId) {
  return db().collection(JOBS_COLLECTION).doc(jobId);
}

async function markJobFailed(jobId, { status, errorCategory, errorCode, errorMessage }) {
  await jobRef(jobId).set({
    status,
    errorCategory,
    errorCode,
    errorMessage: textValue(errorMessage).slice(0, 500),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function buildInitPayload({ mediaType, caption, imageUrl, privacyLevelEffective, allowComment, allowDuet, allowStitch }) {
  const postInfo = {
    title: caption,
    privacy_level: privacyLevelEffective,
    disable_comment: !allowComment,
  };

  if (mediaType === "video") {
    // Structurally supported, unexercised by this app's current data model
    // (no video field exists on products/outbox — see dispatch.js).
    postInfo.disable_duet = !allowDuet;
    postInfo.disable_stitch = !allowStitch;
    return {
      post_info: postInfo,
      source_info: { source: "PULL_FROM_URL", video_url: imageUrl },
      post_mode: "DIRECT_POST",
      media_type: "VIDEO",
    };
  }

  return {
    post_info: postInfo,
    source_info: { source: "PULL_FROM_URL", photo_cover_index: 0, photo_images: [imageUrl] },
    post_mode: "DIRECT_POST",
    media_type: "PHOTO",
  };
}

// Admin-only. Receives ONLY a jobId and the manual choices made on the
// review screen — never trusts caption, media URL, product ownership,
// connectionId, or job state as claimed by the client. Everything else is
// reloaded from Firestore / TikTok fresh, inside this function.
const tiktokConfirmPublish = onCall({ region: "asia-south1" }, async (request) => {
  const adminUid = await requireAdminAuth(request);

  const data = mapValue(request.data);
  const jobId = textValue(data.jobId);
  const privacyLevel = textValue(data.privacyLevel);
  const allowComment = data.allowComment === true;
  const allowDuet = data.allowDuet === true;
  const allowStitch = data.allowStitch === true;

  if (!jobId) throw new HttpsError("invalid-argument", "jobId is required.");
  if (!privacyLevel || !VALID_PRIVACY_LEVELS.has(privacyLevel)) {
    throw new HttpsError("invalid-argument", "A valid privacyLevel must be selected.");
  }

  // --- Locking: transactionally claim the job before doing any external
  // work. A second concurrent tap (double-click, two admins, a retried
  // client call) sees status !== "pending_creator_review" and is rejected
  // outright — this is the double-tap / concurrent-init guard.
  const ref = jobRef(jobId);
  const job = await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError("not-found", "Publish job not found.");

    const current = doc.data();
    if (current.status !== "pending_creator_review") {
      throw new HttpsError("failed-precondition", "This job is not awaiting confirmation (already processed or locked).");
    }

    tx.set(ref, {
      status: "confirming",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { id: doc.id, ...current };
  });

  try {
    // --- Reload authoritative product/outbox data fresh, never from the client.
    const outboxDoc = await db().collection("marketing_outbox").doc(job.productId).get();
    if (!outboxDoc.exists) {
      await markJobFailed(jobId, {
        status: "cancelled_product_removed",
        errorCategory: "permanent",
        errorCode: "PRODUCT_REMOVED",
        errorMessage: "marketing_outbox entry no longer exists.",
      });
      throw new HttpsError("failed-precondition", "This product is no longer available.");
    }

    const outbox = outboxDoc.data();
    const imageUrl = textValue(outbox.imageUrl);
    const caption = textValue(mapValue(outbox.captions).tiktok) || textValue(outbox.productName);
    const republishNonce = textValue(outbox.tiktokRepublishNonce, "0");
    const currentContentVersion = contentVersionHash(imageUrl, caption, republishNonce);

    if (currentContentVersion !== job.contentVersion) {
      await markJobFailed(jobId, {
        status: "cancelled_stale_content",
        errorCategory: "permanent",
        errorCode: "CONTENT_CHANGED",
        errorMessage: "Product content changed after this review job was created.",
      });
      throw new HttpsError(
        "failed-precondition",
        "This product's content has changed since this review was prepared. Refresh the queue for the current version."
      );
    }

    // --- Media validation, server-side only. Flutter never supplies a URL here.
    const settings = await loadAppSettings();
    try {
      await validateMediaForPublish(settings, { imageUrl, mediaType: job.mediaType });
    } catch (error) {
      if (error instanceof MediaValidationError) {
        await markJobFailed(jobId, {
          status: "failed_media",
          errorCategory: "media",
          errorCode: error.code,
          errorMessage: error.message,
        });
        throw new HttpsError("failed-precondition", error.message);
      }
      throw error;
    }

    // --- creator_info re-checked fresh, immediately before content/init —
    // independent of whatever the review screen fetched earlier.
    let creatorInfo;
    try {
      creatorInfo = await fetchCreatorInfo(job.connectionId);
    } catch (error) {
      console.error("TikTok creator_info re-check failed", redactSecrets(error));
      await markJobFailed(jobId, {
        status: "pending_creator_review", // transient — allow immediate retry
        errorCategory: "retryable",
        errorCode: "CREATOR_INFO_REFRESH_FAILED",
        errorMessage: "Could not re-verify TikTok account settings.",
      });
      throw new HttpsError("unavailable", "Could not verify current TikTok account settings. Please try again.");
    }

    const freshOptions = Array.isArray(creatorInfo.privacy_level_options) ? creatorInfo.privacy_level_options : [];
    if (!freshOptions.includes(privacyLevel)) {
      await markJobFailed(jobId, {
        status: "pending_creator_review",
        errorCategory: "permanent",
        errorCode: "PRIVACY_LEVEL_NOT_OFFERED",
        errorMessage: "Selected privacy level is no longer offered by the account.",
      });
      throw new HttpsError("failed-precondition", "The selected privacy option is no longer available for this account. Please review again.");
    }
    if (creatorInfo.comment_disabled && allowComment) {
      throw new HttpsError("failed-precondition", "Comments are disabled for this account; cannot enable them.");
    }
    if (job.mediaType === "video" && creatorInfo.duet_disabled && allowDuet) {
      throw new HttpsError("failed-precondition", "Duet is disabled for this account; cannot enable it.");
    }
    if (job.mediaType === "video" && creatorInfo.stitch_disabled && allowStitch) {
      throw new HttpsError("failed-precondition", "Stitch is disabled for this account; cannot enable it.");
    }

    // --- Audit gate enforced server-side too, not just shown in the UI:
    // an unaudited app is forced private regardless of what was selected.
    const auditStatus = textValue(mapValue(settings.socialApi).tiktokAuditStatus, "unaudited");
    const privacyLevelEffective = auditStatus === "audited" ? privacyLevel : "SELF_ONLY";

    const accessToken = await ensureFreshAccessToken(job.connectionId);
    const payload = buildInitPayload({
      mediaType: job.mediaType,
      caption,
      imageUrl,
      privacyLevelEffective,
      allowComment,
      allowDuet,
      allowStitch,
    });

    let initResponse;
    try {
      initResponse = await axios.post(
        `${TIKTOK_API_BASE}/v2/post/publish/content/init/`,
        payload,
        {
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json; charset=UTF-8",
          },
          timeout: 20000,
        }
      );
    } catch (error) {
      console.error("TikTok content/init failed", redactSecrets(error));
      const httpStatus = error.response && error.response.status;
      const retryable = !httpStatus || httpStatus >= 500 || httpStatus === 429;

      await markJobFailed(jobId, {
        status: retryable ? "pending_creator_review" : "failed_permanent",
        errorCategory: retryable ? "retryable" : "permanent",
        errorCode: "CONTENT_INIT_FAILED",
        errorMessage: "TikTok rejected the publish request.",
      });
      throw new HttpsError(retryable ? "unavailable" : "failed-precondition", "TikTok could not accept this post. Please try again.");
    }

    const publishId = textValue(initResponse.data && initResponse.data.data && initResponse.data.data.publish_id);
    if (!publishId) {
      await markJobFailed(jobId, {
        status: "pending_creator_review",
        errorCategory: "retryable",
        errorCode: "NO_PUBLISH_ID",
        errorMessage: "TikTok did not return a publish_id.",
      });
      throw new HttpsError("unavailable", "TikTok did not confirm the request. Please try again.");
    }

    // --- Accepted, NOT published. deliveryFinal stays false until the
    // webhook/Fetch Status resolver (resolve.js) confirms completion.
    // nextPollAt is seeded here so tiktokPublishJobsSweep picks this job up
    // on its very next 1-minute tick (the staged 30s/1m/2m/5m schedule is
    // driven from here onward by resolve.js's scheduleNextPoll).
    await ref.set({
      status: "accepted_processing",
      publishId,
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveryFinal: false,
      confirmedByUid: adminUid,
      confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      privacyLevelSelected: privacyLevel,
      privacyLevelEffective,
      interactionSettingsSelected: { allowComment, allowDuet, allowStitch },
      // Poll-attempt counter for THIS submission only — resubmissionAttemptCount
      // (seeded at job creation, never touched here) tracks the separate
      // "how many times has this job been resubmitted after a prior failure"
      // dimension; see resolve.js's resolveFailure for where that increments.
      pollAttemptCount: 0,
      pollScheduleStage: 0,
      nextPollAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30000),
      leaseOwner: null,
      leaseExpiresAt: null,
      errorCategory: null,
      errorCode: null,
      errorMessage: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Mirrors the shape Facebook/Instagram/WhatsApp already use in
    // channelResults, but with a status outside their "posted"/"queued"
    // success vocabulary — this must never be counted as delivered.
    await db().collection("marketing_outbox").doc(job.productId).set({
      channelResults: {
        tiktok: {
          status: "accepted_processing",
          jobId,
          publishId,
          deliveryFinal: false,
          at: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await patchTikTokAnalytics(job.productId, {
      outcome: TIKTOK_OUTCOME_ACCEPTED,
      publishId,
      attemptCount: 0,
    });

    return { accepted: true, jobId, publishId, status: "accepted_processing", deliveryFinal: false };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("tiktokConfirmPublish unexpected error", redactSecrets(error));
    await markJobFailed(jobId, {
      status: "pending_creator_review",
      errorCategory: "retryable",
      errorCode: "UNEXPECTED_ERROR",
      errorMessage: "Unexpected error while confirming publish.",
    });
    throw new HttpsError("internal", "Could not complete the TikTok publish confirmation. Please try again.");
  }
});

module.exports = { tiktokConfirmPublish };
