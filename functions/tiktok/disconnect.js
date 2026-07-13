const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const axios = require("axios");

const { requireAdminAuth, loadAppSettings, textValue } = require("./util");
const { redactSecrets } = require("./logging");
const { TIKTOK_CLIENT_SECRET, TIKTOK_REVOKE_URL, getTikTokClientKey } = require("./config");
const { CONNECTIONS_COLLECTION, getConnectionById, getActiveConnection } = require("./connectionStore");

function db() {
  return admin.firestore();
}

const tiktokDisconnect = onCall(
  { region: "asia-south1", secrets: [TIKTOK_CLIENT_SECRET] },
  async (request) => {
    const adminUid = await requireAdminAuth(request);

    const requestedId = textValue(request.data && request.data.connectionId);
    const connection = requestedId
      ? await getConnectionById(requestedId)
      : await getActiveConnection();

    if (!connection) {
      throw new HttpsError("not-found", "No TikTok connection to disconnect.");
    }

    const settings = await loadAppSettings();
    const clientKey = getTikTokClientKey(settings);

    // Best-effort: ask TikTok to revoke the token too. A failure here must
    // never block removing our own copy — the local token deletion below is
    // what actually matters for our security posture.
    try {
      await axios.post(
        TIKTOK_REVOKE_URL,
        new URLSearchParams({
          client_key: clientKey,
          client_secret: TIKTOK_CLIENT_SECRET.value(),
          token: connection.accessToken,
        }).toString(),
        { headers: { "Content-Type": "application/x-www-form-urlencoded" }, timeout: 15000 }
      );
    } catch (error) {
      logger.error("TikTok token revoke call failed (continuing with local disconnect)", redactSecrets(error));
    }

    // The connection document is kept (for audit history: who connected it,
    // when) but its token fields are deleted outright — this is the
    // "invalidate" requirement satisfied literally. The status-projection
    // trigger removes the sanitized doc automatically once it sees
    // status:"disconnected".
    //
    // Nothing else is touched here: tiktok_publish_jobs and delivery
    // analytics collections don't have any writer yet in this codebase
    // (Phase C/D), so there is nothing to mark or delete for them today.
    await db().collection(CONNECTIONS_COLLECTION).doc(connection.id).set({
      accessToken: admin.firestore.FieldValue.delete(),
      refreshToken: admin.firestore.FieldValue.delete(),
      status: "disconnected",
      disconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      disconnectedByAdminUid: adminUid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await db().collection("settings").doc("app").set({
      socialApi: {
        tiktokConnectionStatus: "not_connected",
        selectedTikTokConnectionId: admin.firestore.FieldValue.delete(),
      },
    }, { merge: true });

    return { disconnected: true };
  }
);

module.exports = { tiktokDisconnect };
