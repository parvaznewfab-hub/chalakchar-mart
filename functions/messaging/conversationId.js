// Shared conversation-id/text helpers for the omnichannel messaging pipeline
// (see the Unified Omnichannel Messaging Pipeline spec). Kept dependency-free
// so it's unit-testable without Firestore, same convention as
// aliexpress/searchImportRateLimit.js's sanitizeRateLimitIdentity.

/**
 * Builds the Firestore doc id for `conversations/{conversationId}`:
 * `{channel}_{externalUserId}`. Firestore doc ids can't contain "/", so any
 * slash in externalUserId (unlikely, but phone numbers/PSIDs are provider
 * data we don't fully control) is replaced rather than rejected.
 */
function buildConversationId(channel, externalUserId) {
  const safeChannel = String(channel || "").trim();
  const safeUser = String(externalUserId || "").trim().replace(/\//g, "_");
  return `${safeChannel}_${safeUser}`;
}

/**
 * Truncates a message body down to `max` chars for use as
 * conversations/{id}.lastMessagePreview, so the admin inbox list view never
 * renders a full multi-paragraph AI reply inline.
 */
function truncatePreview(text, max = 120) {
  const clean = String(text || "").trim().replace(/\s+/g, " ");
  if (clean.length <= max) return clean;
  return `${clean.slice(0, Math.max(0, max - 1)).trim()}…`;
}

module.exports = { buildConversationId, truncatePreview };
