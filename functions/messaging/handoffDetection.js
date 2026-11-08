// Human-handoff detection for the omnichannel messaging pipeline (spec §6).
// Dependency-free/pure so it's unit-testable without Firestore or a live AI
// call — same convention as productMatch.js/replyFormatting.js.

// Bengali (Banglish + script) and English phrases that signal the customer
// wants a person, not the bot. Matched as case-insensitive substrings against
// the raw message, so partial phrasing ("ekjon agent lagbe") still matches.
const HANDOFF_KEYWORDS = [
  "kotha bolte chai",
  "manager",
  "manager chai",
  "human",
  "real person",
  "talk to someone",
  "talk to a human",
  "customer care",
  "complaint",
  "complain",
  "agent",
  "এজেন্ট",
  "ম্যানেজার",
  "কথা বলতে চাই",
  "মানুষের সাথে কথা",
  "অভিযোগ",
  "কমপ্লেইন",
];

function normalize(text) {
  return String(text || "").trim().toLowerCase();
}

/** True if `text` contains any explicit human-request/complaint phrase. */
function containsHandoffKeyword(text) {
  const normalized = normalize(text);
  if (!normalized) return false;
  return HANDOFF_KEYWORDS.some((keyword) => normalized.includes(keyword));
}

// Collapse whitespace/punctuation so "product ache?", "product ache??" and
// "product  ache" all count as the same repeated question.
function normalizeForRepeatCheck(text) {
  return normalize(text).replace(/[?!.,]+/g, "").replace(/\s+/g, " ").trim();
}

/**
 * True once the same customer question has appeared `threshold` times
 * (including the current message) without resolution, per spec §6's "asked
 * 3+ times" trigger. `recentMessages` is the conversation history BEFORE the
 * current message is written, oldest-or-newest-first doesn't matter here —
 * every prior customer message is scanned.
 */
function hasRepeatedUnresolvedQuestion(recentMessages, currentText, threshold = 3) {
  const target = normalizeForRepeatCheck(currentText);
  if (!target) return false;

  const priorMatches = (recentMessages || []).filter(
    (m) => m && m.sender === "customer" && normalizeForRepeatCheck(m.text) === target
  ).length;

  // +1 counts the current message itself as one of the "asked N times".
  return priorMatches + 1 >= threshold;
}

// Substrings an AI reply uses when it isn't confident enough to answer on
// its own — a signal to hand off rather than surface a hedge to the customer.
const UNCERTAINTY_SIGNALS = [
  "i'm not sure",
  "i am not sure",
  "i don't know",
  "i do not know",
  "i cannot help",
  "i can't help",
  "not certain",
  "দুঃখিত, আমি নিশ্চিত না",
  "নিশ্চিত না",
  "জানি না",
];

/** True if a blank/empty AI reply, or one containing an uncertainty phrase. */
function isLowConfidenceReply(replyText) {
  const normalized = normalize(replyText);
  if (!normalized) return true;
  return UNCERTAINTY_SIGNALS.some((signal) => normalized.includes(signal));
}

module.exports = {
  HANDOFF_KEYWORDS,
  containsHandoffKeyword,
  normalizeForRepeatCheck,
  hasRepeatedUnresolvedQuestion,
  isLowConfidenceReply,
};
