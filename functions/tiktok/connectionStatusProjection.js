const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const STATUS_COLLECTION = "tiktok_connection_status";
const TOKEN_EXPIRING_WINDOW_MS = 24 * 60 * 60 * 1000; // 24h

// Single place that decides the 6-value status Flutter is allowed to see.
// Keeping this derivation in one trigger (rather than repeated at every
// write site in oauth.js / tokenRefresh.js / disconnect.js) means the
// projection can never drift from whatever tiktok_connections actually says.
function deriveConnectionStatus(data) {
  if (!data || data.status === "disconnected") return null;

  if (data.status === "revoked") return "authorization_revoked";
  if (data.status === "error") return "reconnect_required";

  const refreshExpiresAt = data.refreshTokenExpiresAt ? data.refreshTokenExpiresAt.toMillis() : null;
  if (refreshExpiresAt !== null && refreshExpiresAt < Date.now()) {
    return "reconnect_required";
  }

  const accessExpiresAt = data.accessTokenExpiresAt ? data.accessTokenExpiresAt.toMillis() : null;
  if (accessExpiresAt !== null && accessExpiresAt - Date.now() < TOKEN_EXPIRING_WINDOW_MS) {
    return "token_expiring";
  }

  return data.status === "active" ? "connected" : "reconnect_required";
}

const tiktokConnectionStatusProjection = onDocumentWritten(
  { document: "tiktok_connections/{connectionId}", region: "asia-south1" },
  async (event) => {
    const connectionId = event.params.connectionId;
    const statusRef = admin.firestore().collection(STATUS_COLLECTION).doc(connectionId);
    const after = event.data && event.data.after && event.data.after.exists
      ? event.data.after.data()
      : null;

    const connectionStatus = deriveConnectionStatus(after);

    if (!connectionStatus) {
      // Document deleted, or explicitly disconnected — no sanitized
      // projection should exist for it.
      await statusRef.delete().catch(() => {});
      return;
    }

    // Deliberately does NOT include openId, accessToken, refreshToken, or
    // anything from the token exchange — only what Flutter is allowed to see.
    // displayName/username are populated once creator_info integration lands
    // (Phase C+); this trigger never calls TikTok's API.
    await statusRef.set({
      connectionId,
      connectionStatus,
      reconnectRequired: connectionStatus === "authorization_revoked" || connectionStatus === "reconnect_required",
      lastConnectedAt: after.connectedAt || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: false });

    logger.info("TikTok connection status projection updated", { connectionId, connectionStatus });
  }
);

module.exports = { tiktokConnectionStatusProjection, deriveConnectionStatus };
