const { defineSecret, defineString } = require("firebase-functions/params");

// Shared by WhatsApp/Messenger — both are configured under the one main
// Meta Developer App (955752314186567), and Meta signs every webhook POST
// for both with that one App Secret.
// See developers.facebook.com/docs/graph-api/webhooks/getting-started#validate-payloads.
// Kept in Secret Manager (defineSecret), not settings/app — this is a
// signing key for verifying every inbound webhook, not an API access token
// like whatsappAccessToken/facebookPageAccessToken, so it warrants the same
// treatment functions/tiktok/config.js already gives TIKTOK_CLIENT_SECRET.
const META_APP_SECRET = defineSecret("META_APP_SECRET");

// Instagram messaging turned out NOT to share the main app — Meta's
// dashboard put the Instagram webhook subscription under a separate
// companion app ("ChalakChar Mart Social Automat-IG", App ID
// 2423413004818243), which signs its webhook POSTs with its own, distinct
// App Secret. Verifying instagramWebhook against META_APP_SECRET would
// reject every real Instagram delivery (the HMAC never matches a different
// app's secret) — see instagramWebhook in index.js.
const INSTAGRAM_APP_SECRET = defineSecret("INSTAGRAM_APP_SECRET");

// The string typed into a webhook's "Verify Token" field in the Meta App
// Dashboard — not a signing key, just a shared value Meta echoes back on the
// GET handshake to confirm whoever configured the callback URL also
// controls this deployment. This one we choose ourselves (it isn't
// Meta-issued per-app like the secrets above), so the same value is reused
// across all three products'/apps' dashboards. Deploy-time config, not
// Firestore-editable, matching TIKTOK_REDIRECT_URI's precedent in
// functions/tiktok/config.js.
const META_WEBHOOK_VERIFY_TOKEN = defineString("META_WEBHOOK_VERIFY_TOKEN", { default: "" });

module.exports = { META_APP_SECRET, INSTAGRAM_APP_SECRET, META_WEBHOOK_VERIFY_TOKEN };
