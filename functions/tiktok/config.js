const { defineSecret, defineString } = require("firebase-functions/params");
const { textValue, mapValue } = require("./util");

// Bound only to the functions that actually perform token exchange/refresh
// (see oauth.js, tokenRefresh.js). Never bound to every function.
const TIKTOK_CLIENT_SECRET = defineSecret("TIKTOK_CLIENT_SECRET");

// Deploy-time server config — NOT read from Firestore, NOT overridable by any
// client input (query string, request body, or settings/app). This is the
// single allowlisted OAuth callback destination. Set at deploy time, e.g.:
//   firebase deploy --only functions --set-params TIKTOK_REDIRECT_URI=https://asia-south1-<project>.cloudfunctions.net/tiktokOAuthCallback
const TIKTOK_REDIRECT_URI = defineString("TIKTOK_REDIRECT_URI", { default: "" });

const TIKTOK_API_BASE = "https://open.tiktokapis.com";
const TIKTOK_AUTHORIZE_URL = "https://www.tiktok.com/v2/auth/authorize/";
const TIKTOK_TOKEN_URL = `${TIKTOK_API_BASE}/v2/oauth/token/`;
const TIKTOK_REVOKE_URL = `${TIKTOK_API_BASE}/v2/oauth/revoke/`;

// user.info.basic: creator nickname/avatar for the consent screen (Phase B/C).
// video.publish: Direct Post content/init/ (Phase C).
const TIKTOK_OAUTH_SCOPES = "user.info.basic,video.publish";

function getTikTokClientKey(settings) {
  return textValue(mapValue(settings.socialApi).tiktokClientKey);
}

// Fail-closed: there is exactly one legitimate callback destination, fixed at
// deploy time. No fallback to Firestore, no per-request override of any kind.
function getAllowlistedRedirectUri() {
  const configured = textValue(TIKTOK_REDIRECT_URI.value());
  if (!configured) {
    throw new Error("TIKTOK_REDIRECT_URI_NOT_CONFIGURED");
  }
  return configured;
}

module.exports = {
  TIKTOK_CLIENT_SECRET,
  TIKTOK_REDIRECT_URI,
  TIKTOK_API_BASE,
  TIKTOK_AUTHORIZE_URL,
  TIKTOK_TOKEN_URL,
  TIKTOK_REVOKE_URL,
  TIKTOK_OAUTH_SCOPES,
  getTikTokClientKey,
  getAllowlistedRedirectUri,
};
