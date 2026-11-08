const crypto = require("crypto");

// Shared X-Hub-Signature-256 verification for every Meta product webhook
// (WhatsApp now, Messenger/Instagram in later phases per spec §4/§5) — all
// signed the same way with the one Meta App Secret. Dependency-free/pure so
// it's unit-testable without Firestore, same convention as
// tiktok/webhookVerify.js.

class WebhookVerificationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "WebhookVerificationError";
    this.code = code;
  }
}

function constantTimeEqual(a, b) {
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  // Length differs → not equal. This branch itself leaks only "lengths
  // differ", never anything about content — same trade-off as tiktok/webhookVerify.js.
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Verifies Meta's `X-Hub-Signature-256: sha256=<hex-hmac>` header, HMAC-SHA256
 * over the raw (unparsed) request body, keyed with the Meta App Secret.
 * Throws WebhookVerificationError on any failure — the caller must reject
 * the request BEFORE any Firestore read/write, never processing an
 * unverified payload.
 *
 * @param {{ rawBody: Buffer|string, signatureHeader: string, appSecret: string }} params
 * @returns {true}
 */
function verifyMetaSignature({ rawBody, signatureHeader, appSecret }) {
  if (!appSecret) {
    throw new WebhookVerificationError("MISSING_SECRET", "No Meta app secret configured for verification.");
  }
  if (!signatureHeader) {
    throw new WebhookVerificationError("MISSING_SIGNATURE", "No X-Hub-Signature-256 header present.");
  }
  if (!rawBody || (Buffer.isBuffer(rawBody) && rawBody.length === 0)) {
    throw new WebhookVerificationError("MISSING_RAW_BODY", "Raw request body unavailable for verification.");
  }

  const prefix = "sha256=";
  if (!signatureHeader.startsWith(prefix)) {
    throw new WebhookVerificationError("MALFORMED_SIGNATURE", "X-Hub-Signature-256 header is missing the sha256= prefix.");
  }
  const providedSignature = signatureHeader.slice(prefix.length).trim();

  const rawBodyString = Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody);
  const expectedSignature = crypto.createHmac("sha256", appSecret).update(rawBodyString).digest("hex");

  if (!constantTimeEqual(expectedSignature, providedSignature)) {
    throw new WebhookVerificationError("INVALID_SIGNATURE", "Signature does not match the request body.");
  }

  return true;
}

module.exports = { verifyMetaSignature, WebhookVerificationError };
