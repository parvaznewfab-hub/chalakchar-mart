const admin = require("firebase-admin");

const CONNECTIONS_COLLECTION = "tiktok_connections";

function db() {
  return admin.firestore();
}

async function getActiveConnection() {
  const snap = await db()
    .collection(CONNECTIONS_COLLECTION)
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (snap.empty) return null;
  const doc = snap.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function getConnectionById(connectionId) {
  const doc = await db().collection(CONNECTIONS_COLLECTION).doc(connectionId).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

async function upsertConnectionFromTokens(connectionId, {
  openId,
  accessToken,
  accessTokenExpiresAt,
  refreshToken,
  refreshTokenExpiresAt,
  scope,
  adminUid,
}) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const ref = db().collection(CONNECTIONS_COLLECTION).doc(connectionId);
  const existing = await ref.get();

  const payload = {
    openId,
    accessToken,
    accessTokenExpiresAt,
    refreshToken,
    refreshTokenExpiresAt,
    scope,
    status: "active",
    lastRefreshError: null,
    updatedAt: now,
  };

  if (!existing.exists) {
    payload.connectedByAdminUid = adminUid;
    payload.connectedAt = now;
  } else {
    payload.lastRefreshAt = now;
  }

  await ref.set(payload, { merge: true });
  return ref.id;
}

async function markConnectionStatus(connectionId, status, error) {
  await db().collection(CONNECTIONS_COLLECTION).doc(connectionId).set({
    status,
    lastRefreshError: error ? String(error).slice(0, 500) : null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

module.exports = {
  CONNECTIONS_COLLECTION,
  getActiveConnection,
  getConnectionById,
  upsertConnectionFromTokens,
  markConnectionStatus,
};
