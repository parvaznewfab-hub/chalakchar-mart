const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const axios = require("axios");

const { loadAppSettings } = require("./util");
const { redactSecrets } = require("./logging");
const { TIKTOK_CLIENT_SECRET, TIKTOK_TOKEN_URL, getTikTokClientKey } = require("./config");
const { CONNECTIONS_COLLECTION, markConnectionStatus } = require("./connectionStore");

function db() {
  return admin.firestore();
}

async function refreshConnectionToken(connectionDoc, clientKey) {
  const data = connectionDoc.data();

  const response = await axios.post(
    TIKTOK_TOKEN_URL,
    new URLSearchParams({
      client_key: clientKey,
      client_secret: TIKTOK_CLIENT_SECRET.value(),
      grant_type: "refresh_token",
      refresh_token: data.refreshToken,
    }).toString(),
    {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      timeout: 15000,
    }
  );

  const tokenData = response.data || {};
  if (!tokenData.access_token) {
    throw new Error("REFRESH_RESPONSE_INCOMPLETE");
  }

  const nowMs = Date.now();

  // TikTok rotates the refresh token on every use — the old one becomes invalid,
  // so it must be overwritten, not just the access token.
  await connectionDoc.ref.set({
    accessToken: tokenData.access_token,
    accessTokenExpiresAt: admin.firestore.Timestamp.fromMillis(
      nowMs + (Number(tokenData.expires_in) || 0) * 1000
    ),
    refreshToken: tokenData.refresh_token || data.refreshToken,
    refreshTokenExpiresAt: tokenData.refresh_expires_in
      ? admin.firestore.Timestamp.fromMillis(nowMs + Number(tokenData.refresh_expires_in) * 1000)
      : data.refreshTokenExpiresAt,
    status: "active",
    lastRefreshAt: admin.firestore.FieldValue.serverTimestamp(),
    lastRefreshError: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

// Proactive: refreshes anything expiring within the next 6h, well ahead of the
// 24h access-token lifetime. A just-in-time check (ensureFreshAccessToken) is
// the defense-in-depth backstop used by Phase C/D, not a replacement for this.
const tiktokTokenRefreshSweep = onSchedule(
  { schedule: "every 6 hours", region: "asia-south1", secrets: [TIKTOK_CLIENT_SECRET] },
  async () => {
    const settings = await loadAppSettings();
    const clientKey = getTikTokClientKey(settings);

    if (!clientKey) {
      logger.info("TikTok token refresh sweep skipped: no client key configured");
      return;
    }

    const soon = admin.firestore.Timestamp.fromMillis(Date.now() + 6 * 60 * 60 * 1000);
    const snap = await db()
      .collection(CONNECTIONS_COLLECTION)
      .where("status", "==", "active")
      .where("accessTokenExpiresAt", "<=", soon)
      .get();

    for (const doc of snap.docs) {
      try {
        await refreshConnectionToken(doc, clientKey);
      } catch (error) {
        const apiError = error.response && error.response.data && error.response.data.error;
        const message = apiError || error.message || String(error);

        logger.error("TikTok token refresh failed", {
          connectionId: doc.id,
          ...redactSecrets({ message }),
        });

        const isRevoked = String(message).includes("invalid_grant");
        await markConnectionStatus(doc.id, isRevoked ? "revoked" : "error", message);

        if (isRevoked) {
          await db().collection("settings").doc("app").set({
            socialApi: { tiktokConnectionStatus: "revoked" },
          }, { merge: true });
        }
      }
    }
  }
);

// Just-in-time check, used by later phases before every publish-affecting call.
// Not wired into any export yet — Phase A only establishes the foundation.
async function ensureFreshAccessToken(connectionId) {
  const ref = db().collection(CONNECTIONS_COLLECTION).doc(connectionId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error("TIKTOK_CONNECTION_NOT_FOUND");

  const data = doc.data();
  const expiresInMs = data.accessTokenExpiresAt ? data.accessTokenExpiresAt.toMillis() - Date.now() : -1;

  if (expiresInMs > 10 * 60 * 1000) {
    return data.accessToken;
  }

  const settings = await loadAppSettings();
  const clientKey = getTikTokClientKey(settings);
  await refreshConnectionToken(doc, clientKey);

  const refreshed = await ref.get();
  return refreshed.data().accessToken;
}

module.exports = { tiktokTokenRefreshSweep, ensureFreshAccessToken, refreshConnectionToken };
