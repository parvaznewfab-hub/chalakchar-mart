const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");

const { textValue, mapValue } = require("./util");
const { redactSecrets } = require("./logging");
const { sha256Hex } = require("./crypto");
const { TIKTOK_API_BASE, TIKTOK_CLIENT_SECRET } = require("./config");
const { ensureFreshAccessToken } = require("./tokenRefresh");
const { JOBS_COLLECTION } = require("./dispatch");
const { patchTikTokAnalytics, TIKTOK_OUTCOME_PUBLIC, TIKTOK_OUTCOME_PRIVATE, TIKTOK_OUTCOME_FAILED } = require("./analytics");
const { verifyWebhookSignature, WebhookVerificationError, SIGNATURE_HEADER } = require("./webhookVerify");
const { claimWebhookEvent } = require("./webhookDedup");

const POLL_STAGES_MS = [30_000, 60_000, 120_000, 300_000]; // 30s, 1m, 2m, 5m, then...
const LONG_POLL_INTERVAL_MS = 15 * 60 * 1000; // ...every 15m
const STALE_PROCESSING_MS = 2 * 60 * 60 * 1000; // 2h — TikTok documents no processing time limit, this is our own operational ceiling
const MAX_POLL_ATTEMPTS = 5;
const MAX_RESUBMISSION_ATTEMPTS = 5;
const LEASE_DURATION_MS = 90 * 1000; // a single Fetch Status + Firestore write cycle should never take this long
const MAX_JITTER_MS = 5000;

function db() {
  return admin.firestore();
}

function jitter() {
  return Math.floor(Math.random() * MAX_JITTER_MS);
}

function jobRefFor(job) {
  return db().collection(JOBS_COLLECTION).doc(job.id || job.jobId);
}

// Every write that ends a processing attempt (success, failure, reschedule)
// goes through here so the lease is always released in the same place —
// there is exactly one line of code that clears leaseOwner/leaseExpiresAt,
// not one per call site.
async function writeJobUpdate(job, patch) {
  await jobRefFor(job).set({
    ...patch,
    leaseOwner: null,
    leaseExpiresAt: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

function outboxChannelPatch(job, status, extra = {}) {
  return db().collection("marketing_outbox").doc(job.productId).set({
    channelResults: {
      tiktok: {
        status,
        jobId: job.jobId || job.id,
        deliveryFinal: true,
        at: admin.firestore.FieldValue.serverTimestamp(),
        ...extra,
      },
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

// Transactional claim, callable from both the webhook and the sweep — this
// is the single choke point that prevents two overlapping invocations
// (a slow sweep tick still running when the next one fires, or the webhook
// firing mid-sweep) from processing the same job concurrently. An expired
// lease (owner crashed mid-processing) is claimable again automatically —
// no manual intervention, no permanently stuck job.
async function claimJobForProcessing(jobId) {
  const ref = db().collection(JOBS_COLLECTION).doc(jobId);
  const leaseOwner = crypto.randomBytes(8).toString("hex");
  const nowMs = Date.now();

  return db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return null;

    const data = doc.data();
    if (data.status !== "accepted_processing") return null;

    const leaseExpiresAtMs = data.leaseExpiresAt && data.leaseExpiresAt.toMillis ? data.leaseExpiresAt.toMillis() : 0;
    if (leaseExpiresAtMs > nowMs) return null; // actively leased by another invocation

    tx.set(ref, {
      leaseOwner,
      leaseExpiresAt: admin.firestore.Timestamp.fromMillis(nowMs + LEASE_DURATION_MS),
    }, { merge: true });

    return { id: doc.id, ...data, leaseOwner };
  });
}

async function resolveSuccess(job) {
  const isPublic = job.privacyLevelEffective && job.privacyLevelEffective !== "SELF_ONLY";
  const finalStatus = isPublic ? "published_public" : "published_private_audit_restricted";

  await writeJobUpdate(job, {
    status: finalStatus,
    deliveryFinal: true,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await outboxChannelPatch(job, finalStatus, { publishId: job.publishId });

  // The ONLY place a TikTok post can be counted as real public reach.
  // published_private_audit_restricted explicitly does NOT set
  // tiktokPublishedPublic — see analytics.js.
  await patchTikTokAnalytics(job.productId, {
    outcome: isPublic ? TIKTOK_OUTCOME_PUBLIC : TIKTOK_OUTCOME_PRIVATE,
    publishId: job.publishId,
    attemptCount: job.pollAttemptCount || 0,
  });
}

// Best-effort mapping from TikTok's Fetch Status fail_reason text to our 5
// categories. TikTok's exact fail_reason taxonomy isn't fully enumerated in
// public docs — verify this classifier against real sandbox failures during
// pre-launch testing and extend it, rather than trusting it as exhaustive.
function classifyFailReason(reason) {
  const r = (reason || "").toLowerCase();
  if (r.includes("spam_risk") || r.includes("rate_limit") || r.includes("too_many") || r.includes("cap")) return "quota";
  if (r.includes("token") || r.includes("auth") || r.includes("scope")) return "oauth";
  if (r.includes("media") || r.includes("format") || r.includes("duration") || r.includes("size") || r.includes("download")) return "media";
  if (r.includes("internal") || r.includes("timeout") || r.includes("unavailable")) return "retryable";
  return "permanent"; // conservative default: unknown reasons do not auto-retry indefinitely
}

// A FAILED publish_id is a dead end — TikTok will never complete that
// specific submission. "Retryable" here does NOT mean re-polling or
// auto-resubmitting; it means the job goes back to pending_creator_review so
// the admin reviews and taps Publish again through the normal consent flow —
// fresh creator_info, no privacy preselected, nothing carried over. The old
// publishId is cleared so it can never be polled as if it were still active.
async function resolveFailure(job, failReason) {
  const category = classifyFailReason(failReason);
  const resubmissionAttemptCount = (job.resubmissionAttemptCount || 0) + 1;
  const backToReview = category === "retryable" && resubmissionAttemptCount <= MAX_RESUBMISSION_ATTEMPTS;

  const attemptRecord = {
    publishId: job.publishId || null,
    failedAt: admin.firestore.Timestamp.now(), // FieldValue.serverTimestamp() is not allowed inside arrayUnion elements
    errorCategory: category,
    errorCode: "PUBLISH_FAILED",
    errorMessage: textValue(failReason, "TikTok reported a failure.").slice(0, 300),
  };

  if (backToReview) {
    await jobRefFor(job).set({
      status: "pending_creator_review",
      deliveryFinal: false,
      resubmissionAttemptCount,
      previousAttempts: admin.firestore.FieldValue.arrayUnion(attemptRecord),
      // Clear everything tied to the dead submission — a stale publishId
      // must never be polled again, and clearing the consent fields makes it
      // structurally impossible to skip a fresh creator_info + fresh manual
      // choice on the next confirm (tiktokConfirmPublish always re-derives
      // these from scratch regardless, this is defense in depth).
      publishId: null,
      acceptedAt: null,
      confirmedByUid: null,
      confirmedAt: null,
      privacyLevelSelected: null,
      privacyLevelEffective: null,
      interactionSettingsSelected: null,
      pollAttemptCount: 0,
      pollScheduleStage: 0,
      nextPollAt: null,
      lastPollAt: null,
      leaseOwner: null,
      leaseExpiresAt: null,
      errorCategory: category,
      errorCode: "PUBLISH_FAILED",
      errorMessage: attemptRecord.errorMessage,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return;
  }

  const terminalStatus = category === "quota" ? "failed_quota"
    : category === "oauth" ? "failed_oauth"
    : category === "media" ? "failed_media"
    : "failed_permanent";

  await writeJobUpdate(job, {
    status: terminalStatus,
    deliveryFinal: true,
    resubmissionAttemptCount,
    previousAttempts: admin.firestore.FieldValue.arrayUnion(attemptRecord),
    errorCategory: category,
    errorCode: "PUBLISH_FAILED",
    errorMessage: attemptRecord.errorMessage,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await outboxChannelPatch(job, terminalStatus);

  await patchTikTokAnalytics(job.productId, {
    outcome: TIKTOK_OUTCOME_FAILED,
    publishId: job.publishId,
    attemptCount: job.pollAttemptCount || 0,
  });
}

async function goToDeadLetter(job, errorCode, errorMessage) {
  await writeJobUpdate(job, {
    status: "dead_letter",
    deliveryFinal: true,
    errorCategory: "retryable",
    errorCode,
    errorMessage,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await outboxChannelPatch(job, "dead_letter");
  await patchTikTokAnalytics(job.productId, {
    outcome: TIKTOK_OUTCOME_FAILED,
    publishId: job.publishId,
    attemptCount: job.pollAttemptCount || 0,
  });
}

async function scheduleNextPoll(job, { delayOverrideMs, resetAttempt } = {}) {
  const acceptedAtMs = job.acceptedAt && job.acceptedAt.toMillis ? job.acceptedAt.toMillis() : Date.now();
  const elapsed = Date.now() - acceptedAtMs;

  if (elapsed > STALE_PROCESSING_MS) {
    const pollAttemptCount = (job.pollAttemptCount || 0) + 1;
    if (pollAttemptCount >= MAX_POLL_ATTEMPTS) {
      await goToDeadLetter(job, "STALE_PROCESSING_TIMEOUT", "TikTok never confirmed completion within the operational time limit.");
      return;
    }
    await writeJobUpdate(job, {
      pollAttemptCount,
      errorCategory: "retryable",
      errorCode: "STALE_PROCESSING_TIMEOUT",
      nextPollAt: admin.firestore.Timestamp.fromMillis(Date.now() + LONG_POLL_INTERVAL_MS + jitter()),
    });
    return;
  }

  const stage = resetAttempt ? job.pollScheduleStage || 0 : (job.pollScheduleStage || 0) + 1;
  const baseDelay = delayOverrideMs != null
    ? delayOverrideMs
    : (stage < POLL_STAGES_MS.length ? POLL_STAGES_MS[stage] : LONG_POLL_INTERVAL_MS);

  await writeJobUpdate(job, {
    pollScheduleStage: stage,
    lastPollAt: admin.firestore.FieldValue.serverTimestamp(),
    nextPollAt: admin.firestore.Timestamp.fromMillis(Date.now() + baseDelay + jitter()),
  });
}

async function handleStatusFetchTransportFailure(job, error) {
  console.error("TikTok Fetch Status call failed", redactSecrets(error));

  // 429 is backpressure, not a failure of ours — respect Retry-After and do
  // not burn a poll attempt on it.
  if (error.response && error.response.status === 429) {
    const retryAfterHeader = error.response.headers && error.response.headers["retry-after"];
    const retryAfterMs = parseRetryAfter(retryAfterHeader);
    await writeJobUpdate(job, {
      nextPollAt: admin.firestore.Timestamp.fromMillis(Date.now() + retryAfterMs + jitter()),
    });
    return;
  }

  const pollAttemptCount = (job.pollAttemptCount || 0) + 1;
  if (pollAttemptCount >= MAX_POLL_ATTEMPTS) {
    await goToDeadLetter(job, "STATUS_FETCH_FAILED", "Could not reach TikTok to confirm delivery status after repeated attempts.");
    return;
  }

  await writeJobUpdate(job, {
    pollAttemptCount,
    errorCategory: "retryable",
    errorCode: "STATUS_FETCH_FAILED",
    nextPollAt: admin.firestore.Timestamp.fromMillis(Date.now() + LONG_POLL_INTERVAL_MS + jitter()),
  });
}

function parseRetryAfter(headerValue) {
  if (!headerValue) return 30_000;
  const asSeconds = Number(headerValue);
  if (Number.isFinite(asSeconds)) return Math.max(1000, asSeconds * 1000);
  const asDate = Date.parse(headerValue);
  if (Number.isFinite(asDate)) return Math.max(1000, asDate - Date.now());
  return 30_000;
}

async function handleOAuthResolutionFailure(job, error) {
  console.error("TikTok token unavailable during status resolution", redactSecrets(error));

  await writeJobUpdate(job, {
    status: "failed_oauth",
    deliveryFinal: true,
    errorCategory: "oauth",
    errorCode: "TOKEN_UNAVAILABLE",
    errorMessage: "TikTok connection is no longer valid; reconnect required.",
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await outboxChannelPatch(job, "failed_oauth");
  await patchTikTokAnalytics(job.productId, {
    outcome: TIKTOK_OUTCOME_FAILED,
    publishId: job.publishId,
    attemptCount: job.pollAttemptCount || 0,
  });
}

// The single authoritative resolver. Claims the job (see claimJobForProcessing)
// before doing anything else, so overlapping sweep ticks / webhook calls can
// never process the same job at once; releases the lease via writeJobUpdate
// on every exit path. Called both by the webhook (as a low-latency trigger,
// AFTER signature verification) and by the scheduled sweep — both converge
// here, so duplicate/out-of-order calls are safe: a job that's already
// terminal, or already leased, is simply skipped.
async function fetchAndResolveStatus(jobId) {
  const job = await claimJobForProcessing(jobId);
  if (!job) return; // not eligible, already terminal, or currently leased elsewhere

  if (!job.publishId) {
    // Shouldn't happen for a job in accepted_processing, but fail safe
    // rather than leave the lease held indefinitely.
    await writeJobUpdate(job, {});
    return;
  }

  let accessToken;
  try {
    accessToken = await ensureFreshAccessToken(job.connectionId);
  } catch (error) {
    await handleOAuthResolutionFailure(job, error);
    return;
  }

  let response;
  try {
    response = await axios.post(
      `${TIKTOK_API_BASE}/v2/post/publish/status/fetch/`,
      { publish_id: job.publishId },
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json; charset=UTF-8",
        },
        timeout: 15000,
      }
    );
  } catch (error) {
    await handleStatusFetchTransportFailure(job, error);
    return;
  }

  const data = (response.data && response.data.data) || {};
  const status = textValue(data.status);

  if (status === "PUBLISH_COMPLETE") {
    await resolveSuccess(job);
    return;
  }

  if (status === "FAILED") {
    await resolveFailure(job, textValue(data.fail_reason));
    return;
  }

  // PROCESSING_DOWNLOAD / PROCESSING_UPLOAD / SEND_TO_USER_INBOX — still in flight.
  await scheduleNextPoll(job);
}

// TikTok's webhook payload IS now signature-verified below, but is still
// never trusted as authoritative for job state — it is used only to decide
// which job(s) to re-check, and the re-check always goes through our own
// authenticated fetchAndResolveStatus() above, which is the single source
// of truth regardless of what the (now-verified) webhook body claims.
const tiktokWebhook = onRequest(
  { region: "asia-south1", secrets: [TIKTOK_CLIENT_SECRET] },
  async (req, res) => {
    let verified;
    try {
      verified = verifyWebhookSignature({
        rawBody: req.rawBody,
        signatureHeader: req.headers[SIGNATURE_HEADER],
        clientSecret: TIKTOK_CLIENT_SECRET.value(),
      });
    } catch (error) {
      // Reject BEFORE any Firestore read/write. No signature, no processing.
      console.error("TikTok webhook signature rejected", {
        code: error instanceof WebhookVerificationError ? error.code : "UNKNOWN",
      });
      res.status(401).send("invalid signature");
      return;
    }

    try {
      const isNewEvent = await claimWebhookEvent(verified.signature);
      if (!isNewEvent) {
        res.status(200).send("duplicate");
        return;
      }

      const body = mapValue(req.body);
      const openId = textValue(body.user_openid);

      if (!openId) {
        res.status(200).send("ignored");
        return;
      }

      const connectionId = sha256Hex(openId).slice(0, 32);
      const snap = await db()
        .collection(JOBS_COLLECTION)
        .where("connectionId", "==", connectionId)
        .where("status", "==", "accepted_processing")
        .limit(10)
        .get();

      for (const doc of snap.docs) {
        await fetchAndResolveStatus(doc.id);
      }

      res.status(200).send("ok");
    } catch (error) {
      console.error("TikTok webhook handling failed", redactSecrets(error));
      // Ack 200 regardless — the 1-minute sweep is the safety net for this
      // job either way, and an error response just spends TikTok's 72h
      // retry budget on a webhook we've already effectively handled.
      res.status(200).send("ok");
    }
  }
);

module.exports = { tiktokWebhook, fetchAndResolveStatus, claimJobForProcessing };
