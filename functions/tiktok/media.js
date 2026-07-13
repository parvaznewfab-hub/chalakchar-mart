const { mapValue, textValue } = require("./util");
const { safeHead, SsrfBlockedError } = require("./network");

const MAX_PHOTO_BYTES = 20 * 1024 * 1024; // 20MB — conservative; verify against current TikTok limits before production
const MAX_VIDEO_BYTES = 4 * 1024 * 1024 * 1024; // 4GB — same caveat; video path is not exercised by this app's data model today
const SUPPORTED_PHOTO_TYPES = ["image/jpeg", "image/jpg", "image/png", "image/webp"];
const SUPPORTED_VIDEO_TYPES = ["video/mp4", "video/quicktime"];

class MediaValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "MediaValidationError";
    this.code = code;
  }
}

function getMediaDomainAllowlist(settings) {
  const raw = textValue(mapValue(settings.socialApi).tiktokMediaDomainAllowlist);
  return raw
    .split(",")
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
}

// Allowlist entries are "host" or "host/required/path/prefix". Subdomains of
// an entry host are allowed (exact match or a "." + entry suffix) — this
// still requires an admin to explicitly list the domain that was verified
// with TikTok's PULL_FROM_URL ownership check in the Developer Portal; it
// does not implicitly trust unrelated hosts.
function matchesAllowlistEntry(hostname, pathname, entry) {
  const slashIndex = entry.indexOf("/");
  const entryHost = slashIndex === -1 ? entry : entry.slice(0, slashIndex);
  const requiredPathPrefix = slashIndex === -1 ? null : entry.slice(slashIndex);

  const hostOk = hostname === entryHost || hostname.endsWith(`.${entryHost}`);
  if (!hostOk) return false;
  if (!requiredPathPrefix) return true;
  return pathname.startsWith(requiredPathPrefix);
}

// Structural checks only — this cannot confirm TikTok's own PULL_FROM_URL
// domain-verification state (that lives in the TikTok Developer Portal, not
// queryable via API). This function instead ensures we never even attempt to
// hand TikTok, or fetch ourselves, a URL outside the operator's own
// explicitly configured allowlist — and never touches the network before
// that allowlist check passes.
async function validateMediaForPublish(settings, { imageUrl, mediaType }) {
  let parsed;
  try {
    parsed = new URL(imageUrl);
  } catch (_error) {
    throw new MediaValidationError("MEDIA_INVALID_URL", "The product image URL is not a valid URL.");
  }

  if (parsed.protocol !== "https:") {
    throw new MediaValidationError("MEDIA_INVALID_URL", "The product image URL must use HTTPS.");
  }
  if (parsed.username || parsed.password) {
    throw new MediaValidationError("MEDIA_INVALID_URL", "The product image URL must not contain embedded credentials.");
  }

  const allowlist = getMediaDomainAllowlist(settings);

  // FAIL CLOSED. An unset or empty allowlist blocks publishing — it never
  // silently permits it. This is a configuration error, not "no policy."
  if (allowlist.length === 0) {
    throw new MediaValidationError(
      "MEDIA_ALLOWLIST_NOT_CONFIGURED",
      "settings/app.socialApi.tiktokMediaDomainAllowlist is not configured. Publishing is blocked until an operator sets at least one verified domain."
    );
  }

  const hostname = parsed.hostname.toLowerCase();
  const matched = allowlist.some((entry) => matchesAllowlistEntry(hostname, parsed.pathname, entry));

  if (!matched) {
    throw new MediaValidationError(
      "MEDIA_DOMAIN_NOT_ALLOWLISTED",
      `"${hostname}${parsed.pathname}" does not match any entry in tiktokMediaDomainAllowlist.`
    );
  }

  // Only now — after protocol, credentials, and allowlist all pass — does
  // any network request happen. SSRF hardening (DNS pinning, private/
  // reserved-IP rejection, no redirects, no forwarded auth) lives in
  // network.js's safeHead().
  let response;
  try {
    response = await safeHead(imageUrl);
  } catch (error) {
    if (error instanceof SsrfBlockedError) {
      throw new MediaValidationError("MEDIA_UNSAFE_HOST", error.message);
    }
    throw new MediaValidationError("MEDIA_UNREACHABLE", "The product image URL could not be reached.");
  }

  const contentType = textValue(response.headers["content-type"]).toLowerCase().split(";")[0].trim();
  const contentLength = Number(response.headers["content-length"] || 0);

  const supportedTypes = mediaType === "video" ? SUPPORTED_VIDEO_TYPES : SUPPORTED_PHOTO_TYPES;
  if (!supportedTypes.includes(contentType)) {
    throw new MediaValidationError(
      "MEDIA_UNSUPPORTED_TYPE",
      `Unsupported content-type "${contentType || "unknown"}" for a ${mediaType} post.`
    );
  }

  const maxBytes = mediaType === "video" ? MAX_VIDEO_BYTES : MAX_PHOTO_BYTES;
  if (contentLength > 0 && contentLength > maxBytes) {
    throw new MediaValidationError("MEDIA_TOO_LARGE", `Media file exceeds the ${maxBytes} byte limit.`);
  }

  return { ok: true, contentType, sizeBytes: contentLength || null };
}

module.exports = { validateMediaForPublish, MediaValidationError, getMediaDomainAllowlist, matchesAllowlistEntry };
