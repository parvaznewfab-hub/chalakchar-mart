const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

const { textValue, mapValue, loadAppSettings, requireAdminAuth } = require("./util");
const { redactSecrets } = require("./logging");
const { TIKTOK_API_BASE } = require("./config");
const { ensureFreshAccessToken } = require("./tokenRefresh");
const { JOBS_COLLECTION } = require("./dispatch");

function db() {
  return admin.firestore();
}

async function fetchCreatorInfo(connectionId) {
  const accessToken = await ensureFreshAccessToken(connectionId);

  const response = await axios.post(
    `${TIKTOK_API_BASE}/v2/post/publish/creator_info/query/`,
    {},
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=UTF-8",
      },
      timeout: 15000,
    }
  );

  return (response.data && response.data.data) || {};
}

// Admin-only. Called fresh every time the review screen opens for a job —
// never cached, never treated as authorization for a later publish call.
// tiktokConfirmPublish (publish.js) queries this again itself immediately
// before content/init, independent of whatever the review screen already saw.
const tiktokGetCreatorInfo = onCall({ region: "asia-south1" }, async (request) => {
  await requireAdminAuth(request);

  const jobId = textValue(request.data && request.data.jobId);
  if (!jobId) {
    throw new HttpsError("invalid-argument", "jobId is required.");
  }

  const jobDoc = await db().collection(JOBS_COLLECTION).doc(jobId).get();
  if (!jobDoc.exists) {
    throw new HttpsError("not-found", "Publish job not found.");
  }

  const job = jobDoc.data();
  if (job.status !== "pending_creator_review") {
    throw new HttpsError("failed-precondition", "This job is no longer pending review.");
  }

  let raw;
  try {
    raw = await fetchCreatorInfo(job.connectionId);
  } catch (error) {
    console.error("TikTok creator_info query failed", redactSecrets(error));
    throw new HttpsError("unavailable", "Could not load TikTok account information right now.");
  }

  const settings = await loadAppSettings();
  const auditStatus = textValue(mapValue(settings.socialApi).tiktokAuditStatus, "unaudited");

  // Only TikTok-approved review metadata — never a token, never anything
  // from the raw response beyond these specific fields.
  return {
    displayName: textValue(raw.creator_nickname),
    avatarUrl: textValue(raw.creator_avatar_url),
    privacyLevelOptions: Array.isArray(raw.privacy_level_options) ? raw.privacy_level_options : [],
    commentDisabled: Boolean(raw.comment_disabled),
    duetDisabled: Boolean(raw.duet_disabled),
    stitchDisabled: Boolean(raw.stitch_disabled),
    maxVideoPostDurationSec: Number(raw.max_video_post_duration_sec) || null,
    mediaType: job.mediaType,
    auditRestricted: auditStatus !== "audited",
  };
});

module.exports = { tiktokGetCreatorInfo, fetchCreatorInfo };
