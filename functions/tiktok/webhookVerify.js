const crypto = require("crypto");

const SIGNATURE_HEADER = "tiktok-signature";

// TikTok does not publish a mandated tolerance window on
// developers.tiktok.com/doc/webhooks-verification — it only says to compute
// the age and "decide whether the difference is tolerable." 5 minutes is our
// own conservative choice, not an official value.
const REPLAY_TOLERANCE_SECONDS = 5 * 60;

class WebhookVerificationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "WebhookVerificationError";
    this.code = code;
  }
}

function parseSignatureHeader(headerValue) {
  const parsed = {};
  for (const part of String(headerValue || "").split(",")) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    parsed[part.slice(0, eq).trim()] = part.slice(eq + 1).trim();
  }
  if (!parsed.t || !parsed.s) {
    throw new WebhookVerificationError("MALFORMED_SIGNATURE", "Signature header missing t or s component.");
  }
  return { timestamp: parsed.t, signature: parsed.s };
}

function constantTimeEqual(a, b) {
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  // Length differs → not equal. This branch itself leaks only "lengths
  // differ", never anything about content — the same trade-off every
  // constant-time-compare implementation (incl. Node's own) makes.
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

// Implements the algorithm documented at
// developers.tiktok.com/doc/webhooks-verification:
//   header:  "Tiktok-Signature: t=<unix-seconds>,s=<hex-hmac>"
//   key:     the app's client_secret
//   payload: "{timestamp}.{raw json body}"
//   hash:    HMAC-SHA256, compared as hex
//
// Must run BEFORE any Firestore read/write — this function throws on any
// failure and the caller (resolve.js) rejects the request immediately on
// catch, never reaching a database call for an unverified request.
function verifyWebhookSignature({ rawBody, signatureHeader, clientSecret }) {
  if (!signatureHeader) {
    throw new WebhookVerificationError("MISSING_SIGNATURE", "No signature header present.");
  }
  if (!rawBody || (Buffer.isBuffer(rawBody) && rawBody.length === 0)) {
    throw new WebhookVerificationError("MISSING_RAW_BODY", "Raw request body unavailable for verification.");
  }
  if (!clientSecret) {
    throw new WebhookVerificationError("MISSING_SECRET", "No client secret configured for verification.");
  }

  const { timestamp, signature } = parseSignatureHeader(signatureHeader);

  const timestampNum = Number(timestamp);
  if (!Number.isFinite(timestampNum) || timestampNum <= 0) {
    throw new WebhookVerificationError("MALFORMED_TIMESTAMP", "Signature timestamp is not a valid number.");
  }

  const ageSeconds = Math.abs(Math.floor(Date.now() / 1000) - timestampNum);
  if (ageSeconds > REPLAY_TOLERANCE_SECONDS) {
    throw new WebhookVerificationError(
      "STALE_SIGNATURE",
      `Signature timestamp is ${ageSeconds}s old, outside the ${REPLAY_TOLERANCE_SECONDS}s tolerance window.`
    );
  }

  const rawBodyString = Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody);
  const signedPayload = `${timestamp}.${rawBodyString}`;
  const expectedSignature = crypto.createHmac("sha256", clientSecret).update(signedPayload).digest("hex");

  if (!constantTimeEqual(expectedSignature, signature)) {
    throw new WebhookVerificationError("INVALID_SIGNATURE", "Signature does not match the request body.");
  }

  return { timestamp: timestampNum, signature };
}

module.exports = { verifyWebhookSignature, WebhookVerificationError, SIGNATURE_HEADER, REPLAY_TOLERANCE_SECONDS };
