// -----------------------------------------------------------------------------
// Rate limiting for aliexpressSearchImport — the one AliExpress-import HTTP
// endpoint reachable by anonymous shoppers (idToken is optional, see
// search_page.dart). The 24h searchImportLog dedupe only protects against
// the SAME query text repeating; it does nothing against an abuser cycling
// through many DIFFERENT query strings, each of which is a fresh
// AliExpress-affiliate-API + up to 5 fetchAliExpressProduct calls. This
// module is the layer that caps request volume regardless of query text.
//
// Fixed-window counters, one Firestore doc per (kind, identity) pair in the
// `rateLimits` collection. Two window sizes are layered: a short burst window
// (default 5 per 10 minutes) and the original per-hour window. Each counter
// is incremented inside a transaction, the same transactional-claim shape
// already used by claimSearchImportSlot in index.js. Deliberately dependency-light (db passed in, no admin.firestore
// import needed) so it's unit-testable against the project's existing
// FakeFirestore without a real emulator.
// -----------------------------------------------------------------------------

const WINDOW_MS = 60 * 60 * 1000; // 1 hour — matches the "per hour" limits this guards.
const BURST_WINDOW_MS = 10 * 60 * 1000; // 10 minutes — the default short burst window.

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

/**
 * Extracts the real caller IP from a Cloud Functions v2 (Cloud Run-backed)
 * onRequest request. `req.ip` is NOT reliable here — this project's
 * onRequest handlers are plain handlers, not an Express app with
 * `trust proxy` set, so req.ip resolves to a Cloud Run-internal address.
 * Per Google's own Cloud Functions (2nd gen) docs, the FIRST entry of
 * X-Forwarded-For is the real client IP, appended by Google's front end
 * before the request ever reaches the function — a caller cannot override
 * it by sending their own X-Forwarded-For, so unlike a self-hosted proxy
 * setup, this is safe to trust without additional validation.
 *
 * Falls back to "unknown" (e.g. local emulator testing, where there is no
 * Google front end in front of the function to set this header) rather than
 * throwing — a missing IP should degrade to "everyone shares one bucket",
 * never crash the request.
 */
function extractClientIp(req) {
  const header = textValue(req?.get ? req.get("x-forwarded-for") : req?.headers?.["x-forwarded-for"]);
  if (!header) return "unknown";
  return textValue(header.split(",")[0]);
}

/**
 * Sanitizes an arbitrary identity string (IP address or Firebase uid) into
 * safe Firestore doc-ID characters. Mirrors index.js's importSafeId, kept as
 * a local copy so this module has no dependency on index.js.
 */
function sanitizeRateLimitIdentity(value, fallback = "unknown") {
  const normalized = textValue(value, fallback)
    .toLowerCase()
    .replace(/[^a-z0-9_.-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  return normalized || fallback;
}

/**
 * Checks and (if allowed) consumes one request against a fixed-window
 * limit for `key`. The window is one hour unless `windowMs` is given. `now`
 * is injectable for tests; defaults to the real clock in production.
 *
 * Only writes to Firestore when the request is allowed (a reset or an
 * increment) — a denied request doesn't need to change stored state, since
 * retryAfterSeconds is computed from the window's existing start time.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {{ key: string, limitPerHour: number, windowMs?: number, now?: number }} params
 *   limitPerHour is the limit per window; the name predates windowMs.
 * @returns {Promise<{ allowed: boolean, remaining: number, limit: number, retryAfterSeconds: number }>}
 */
async function checkRateLimit(db, { key, limitPerHour, windowMs = WINDOW_MS, now = Date.now() }) {
  const limit = Math.max(1, Math.trunc(Number(limitPerHour) || 1));
  const windowLength = Math.max(1000, Math.trunc(Number(windowMs) || WINDOW_MS));
  const docId = sanitizeRateLimitIdentity(key);
  const ref = db.collection("rateLimits").doc(docId);

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.exists ? snap.data() || {} : null;

    const windowExpired = !data || (now - Number(data.windowStart || 0)) >= windowLength;

    if (windowExpired) {
      transaction.set(ref, { count: 1, windowStart: now });
      return { allowed: true, remaining: limit - 1, limit, retryAfterSeconds: 0 };
    }

    const count = Number(data.count || 0);
    if (count < limit) {
      transaction.set(ref, { count: count + 1, windowStart: data.windowStart });
      return { allowed: true, remaining: limit - (count + 1), limit, retryAfterSeconds: 0 };
    }

    const retryAfterSeconds = Math.max(1, Math.ceil((Number(data.windowStart) + windowLength - now) / 1000));
    return { allowed: false, remaining: 0, limit, retryAfterSeconds };
  });
}

/**
 * Normalizes the raw `settings/app` importSettings map into rate-limit
 * config, with the same defaults regardless of caller — pure function, no
 * Firestore access, so index.js's settings reader can stay a thin fetch +
 * delegate and this defaulting logic is covered by tests directly.
 *
 * @param {object} rawImportSettings - mapValue(settingsDoc.data().importSettings)
 */
function parseRateLimitSettings(rawImportSettings) {
  const settings = rawImportSettings || {};
  const toBool = (value, fallback) => (typeof value === "boolean" ? value : fallback);
  const toPositiveInt = (value, fallback) => {
    const n = Math.trunc(Number(value));
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  return {
    enabled: toBool(settings.searchImportRateLimitEnabled, true),
    ipLimitPerHour: toPositiveInt(settings.searchImportIpLimitPerHour, 12),
    uidLimitPerHour: toPositiveInt(settings.searchImportUidLimitPerHour, 25),
    // Short burst window, applied per IP and per uid on top of the hourly caps.
    burstLimit: toPositiveInt(settings.searchImportBurstLimit, 5),
    burstWindowMs: toPositiveInt(settings.searchImportBurstWindowMinutes, 10) * 60 * 1000,
  };
}

/**
 * Orchestrates the rate-limit layers for one aliexpressSearchImport request,
 * in this order:
 *   1. IP burst (only when burstLimit is set)
 *   2. IP hourly
 *   3. uid burst (signed-in callers, only when burstLimit is set)
 *   4. uid hourly (signed-in callers)
 * IP is the only signal for the anonymous majority of callers, since idToken
 * is optional on this endpoint. Any one layer denying is enough to deny the
 * request; these are independent ceilings, not a compound threshold.
 *
 * Checking stops at the first denial, so a rejected request never consumes
 * quota from the layers after it.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {{ ip: string, uid?: string|null, ipLimitPerHour: number, uidLimitPerHour: number,
 *           burstLimit?: number, burstWindowMs?: number, now?: number }} params
 * @returns {Promise<null|{ scope: "ip_burst"|"ip"|"uid_burst"|"uid", limit: number, retryAfterSeconds: number }>}
 *          null when the request is allowed.
 */
async function evaluateSearchImportRateLimit(db, {
  ip,
  uid,
  ipLimitPerHour,
  uidLimitPerHour,
  burstLimit,
  burstWindowMs = BURST_WINDOW_MS,
  now = Date.now(),
}) {
  const hasBurst = Number(burstLimit) > 0;
  const layers = [];
  if (hasBurst) layers.push({ scope: "ip_burst", key: `ipburst_${ip}`, limit: burstLimit, windowMs: burstWindowMs });
  layers.push({ scope: "ip", key: `ip_${ip}`, limit: ipLimitPerHour, windowMs: WINDOW_MS });
  if (uid) {
    if (hasBurst) layers.push({ scope: "uid_burst", key: `uidburst_${uid}`, limit: burstLimit, windowMs: burstWindowMs });
    layers.push({ scope: "uid", key: `uid_${uid}`, limit: uidLimitPerHour, windowMs: WINDOW_MS });
  }

  for (const layer of layers) {
    const result = await checkRateLimit(db, { key: layer.key, limitPerHour: layer.limit, windowMs: layer.windowMs, now });
    if (!result.allowed) {
      return { scope: layer.scope, limit: result.limit, retryAfterSeconds: result.retryAfterSeconds };
    }
  }

  return null;
}

module.exports = {
  WINDOW_MS,
  BURST_WINDOW_MS,
  extractClientIp,
  sanitizeRateLimitIdentity,
  checkRateLimit,
  parseRateLimitSettings,
  evaluateSearchImportRateLimit,
};
