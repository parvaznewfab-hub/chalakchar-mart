// Resolves the GET verification handshake every Meta product webhook
// (WhatsApp/Messenger/Instagram) requires before Meta will start POSTing
// events: a GET request with ?hub.mode=subscribe&hub.verify_token=...&hub.challenge=...,
// which must be echoed back verbatim only if the verify token matches what
// was configured in the Meta App Dashboard. Pure/dependency-free so it's
// unit-testable without an HTTP request object.

/**
 * @param {{ mode: string, verifyToken: string, challenge: string|number|undefined, expectedVerifyToken: string }} params
 * @returns {string|null} the challenge to echo back with a 200, or null if
 *          the caller should reject with 403 (mode isn't "subscribe", the
 *          verify token doesn't match, no verify token is configured at all,
 *          or there's no challenge to echo).
 */
function resolveVerificationChallenge({ mode, verifyToken, challenge, expectedVerifyToken }) {
  if (!expectedVerifyToken) return null;
  if (mode !== "subscribe") return null;
  if (!verifyToken || verifyToken !== expectedVerifyToken) return null;
  if (challenge === undefined || challenge === null || challenge === "") return null;
  return String(challenge);
}

module.exports = { resolveVerificationChallenge };
