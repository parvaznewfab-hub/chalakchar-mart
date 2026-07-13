const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const axios = require("axios");

const { textValue, loadAppSettings, requireAdminAuth } = require("./util");
const { sha256Hex, randomState } = require("./crypto");
const { redactSecrets } = require("./logging");
const {
  TIKTOK_CLIENT_SECRET,
  TIKTOK_AUTHORIZE_URL,
  TIKTOK_TOKEN_URL,
  TIKTOK_OAUTH_SCOPES,
  getTikTokClientKey,
  getAllowlistedRedirectUri,
} = require("./config");
const { upsertConnectionFromTokens } = require("./connectionStore");

const STATE_TTL_MS = 10 * 60 * 1000;
const STATES_COLLECTION = "tiktok_oauth_states";

function db() {
  return admin.firestore();
}

// Minimal, self-contained confirmation page — no external resources, no
// sensitive data of any kind (no tokens, no raw TikTok error payloads).
function renderResultPage(ok, message) {
  const tone = ok ? "#0E7A82" : "#B3402A";
  const heading = ok ? "TikTok account connected" : "Connection failed";
  return `<!doctype html>
<html><head><meta charset="utf-8"><title>${heading}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#F2F5F4;color:#121A1E;
    display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;}
  .card{background:#fff;border-radius:12px;padding:32px 28px;max-width:380px;text-align:center;
    box-shadow:0 8px 24px rgba(20,30,30,.08);}
  h1{font-size:1.15rem;margin:0 0 10px;color:${tone};}
  p{margin:0;color:#55646B;line-height:1.5;font-size:.95rem;}
</style></head>
<body><div class="card"><h1>${heading}</h1><p>${message}</p></div></body></html>`;
}

// Admin-only callable. Flutter never sees a client secret or raw token here —
// only the authorize URL to open in a browser.
const tiktokOAuthStart = onCall({ region: "asia-south1" }, async (request) => {
  const adminUid = await requireAdminAuth(request);

  const settings = await loadAppSettings();
  const clientKey = getTikTokClientKey(settings);

  if (!clientKey) {
    throw new HttpsError(
      "failed-precondition",
      "TikTok client key is not configured in settings/app.socialApi."
    );
  }

  // Fixed, deploy-time value — never sourced from Firestore, never
  // overridable by a query string or request body. See config.js.
  let redirectUri;
  try {
    redirectUri = getAllowlistedRedirectUri();
  } catch (_error) {
    throw new HttpsError("failed-precondition", "TikTok redirect URI is not configured on the backend.");
  }

  const state = randomState();
  const stateHash = sha256Hex(state);

  // Store only the hash — a Firestore export/backup never exposes the raw state.
  await db().collection(STATES_COLLECTION).doc(stateHash).set({
    requestedByAdminUid: adminUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + STATE_TTL_MS),
    used: false,
  });

  const authorizeUrl = new URL(TIKTOK_AUTHORIZE_URL);
  authorizeUrl.searchParams.set("client_key", clientKey);
  authorizeUrl.searchParams.set("scope", TIKTOK_OAUTH_SCOPES);
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("redirect_uri", redirectUri);
  authorizeUrl.searchParams.set("state", state);

  return { authorizeUrl: authorizeUrl.toString() };
});

// TikTok redirects the creator's browser here directly — never through Flutter.
const tiktokOAuthCallback = onRequest(
  { region: "asia-south1", secrets: [TIKTOK_CLIENT_SECRET] },
  async (req, res) => {
    const code = textValue(req.query.code);
    const state = textValue(req.query.state);

    if (!code || !state) {
      res.status(400).send(renderResultPage(false, "This TikTok connection link is incomplete. Please try connecting again from the admin panel."));
      return;
    }

    const stateHash = sha256Hex(state);
    const stateRef = db().collection(STATES_COLLECTION).doc(stateHash);

    try {
      // Single-use, atomic: validate + consume the state in one transaction
      // so a replayed callback within the TTL window still fails.
      const requestingAdminUid = await db().runTransaction(async (tx) => {
        const stateDoc = await tx.get(stateRef);
        if (!stateDoc.exists) throw new Error("STATE_NOT_FOUND");

        const stateData = stateDoc.data() || {};
        if (stateData.used === true) throw new Error("STATE_ALREADY_USED");
        if (stateData.expiresAt && stateData.expiresAt.toMillis() < Date.now()) {
          throw new Error("STATE_EXPIRED");
        }

        tx.update(stateRef, {
          used: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return stateData.requestedByAdminUid;
      });

      const settings = await loadAppSettings();
      const clientKey = getTikTokClientKey(settings);
      // Same fixed, allowlisted value used in tiktokOAuthStart — must match
      // exactly what TikTok was sent during authorize, per OAuth spec, and is
      // never accepted from the incoming request in any form.
      const redirectUri = getAllowlistedRedirectUri();

      // Authorization code is used exactly once here and never persisted anywhere.
      const tokenResponse = await axios.post(
        TIKTOK_TOKEN_URL,
        new URLSearchParams({
          client_key: clientKey,
          client_secret: TIKTOK_CLIENT_SECRET.value(),
          code,
          grant_type: "authorization_code",
          redirect_uri: redirectUri,
        }).toString(),
        {
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          timeout: 15000,
        }
      );

      const tokenData = tokenResponse.data || {};
      if (!tokenData.access_token || !tokenData.open_id) {
        throw new Error("TOKEN_EXCHANGE_INCOMPLETE");
      }

      const connectionId = sha256Hex(tokenData.open_id).slice(0, 32);
      const nowMs = Date.now();

      await upsertConnectionFromTokens(connectionId, {
        openId: tokenData.open_id,
        accessToken: tokenData.access_token,
        accessTokenExpiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + (Number(tokenData.expires_in) || 0) * 1000
        ),
        refreshToken: tokenData.refresh_token,
        refreshTokenExpiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + (Number(tokenData.refresh_expires_in) || 0) * 1000
        ),
        scope: textValue(tokenData.scope),
        adminUid: requestingAdminUid,
      });

      await db().collection("settings").doc("app").set({
        socialApi: {
          tiktokConnectionStatus: "connected",
          tiktokLastConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
          selectedTikTokConnectionId: connectionId,
        },
      }, { merge: true });

      res.status(200).send(renderResultPage(
        true,
        "You can close this tab and return to the admin panel — the connection status will update automatically."
      ));
    } catch (error) {
      logger.error("TikTok OAuth callback failed", redactSecrets(error));

      const knownStateErrors = ["STATE_NOT_FOUND", "STATE_ALREADY_USED", "STATE_EXPIRED"];
      const message = knownStateErrors.includes(error.message)
        ? "This connection link has expired or was already used. Please return to the admin panel and try connecting again."
        : "TikTok connection failed. Please return to the admin panel and try again.";

      try {
        await db().collection("settings").doc("app").set({
          socialApi: { tiktokConnectionStatus: "error" },
        }, { merge: true });
      } catch (_settingsWriteError) {
        // best-effort status update only
      }

      res.status(400).send(renderResultPage(false, message));
    }
  }
);

// Read-only, admin-only. Lets the settings page display the backend's fixed
// callback URL for TikTok Developer Portal setup guidance — this value is
// never accepted as input from Flutter, only ever shown.
const tiktokGetOAuthConfig = onCall({ region: "asia-south1" }, async (request) => {
  await requireAdminAuth(request);

  const settings = await loadAppSettings();
  const clientKeyConfigured = Boolean(getTikTokClientKey(settings));

  let redirectUri = "";
  try {
    redirectUri = getAllowlistedRedirectUri();
  } catch (_error) {
    redirectUri = "";
  }

  return { redirectUri, clientKeyConfigured };
});

module.exports = { tiktokOAuthStart, tiktokOAuthCallback, tiktokGetOAuthConfig };
