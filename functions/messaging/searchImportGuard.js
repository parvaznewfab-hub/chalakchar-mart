// Guards the AliExpress search-miss fallback (see handleCustomerMessage.js)
// against firing on casual chat chit-chat that happens to find no local
// product match — "hi", "ok", "thanks" are all zero-match text just like a
// real product search, but unlike lib/pages/user/search_page.dart's search
// box (where every non-empty query is a deliberate product search), chat
// text is mostly small talk. This is a denylist of exact chit-chat phrases
// rather than a word-count/length threshold, since a genuine product miss
// can be a single word too (e.g. "iphone", "napa"). Pure/dependency-free so
// it's unit-testable, same convention as handoffDetection.js.

const CHITCHAT_PHRASES = new Set([
  "hi", "hii", "hiii", "hello", "hey", "heya", "yo",
  "ok", "okay", "k", "kk", "thik ache", "thik asche", "acha", "achha",
  "thanks", "thank you", "thnx", "tnx", "ty", "dhonnobad",
  "bye", "bye bye", "good morning", "good evening", "good night", "gn", "gm",
  "hmm", "hm", "yes", "no", "na", "ha", "hae", "jj",
  "হাই", "হ্যালো", "হ্যাল্লো", "ওকে", "আচ্ছা", "আচ্ছা ঠিক আছে", "ঠিক আছে",
  "ধন্যবাদ", "হ্যাঁ", "না", "গুড মর্নিং", "শুভ সকাল", "বাই",
]);

function normalize(text) {
  return String(text || "")
    .trim()
    .toLowerCase()
    .replace(/\p{Extended_Pictographic}/gu, "")
    .replace(/[?!.,~]+/g, "")
    .trim();
}

/**
 * True if `text` looks like a genuine product-search miss worth relaying to
 * AliExpress (per shouldTriggerSearchImportFallback's callers, only ever
 * checked once local product search has already come back empty). False for
 * blank text, a bare 1-char scrap, or a known chit-chat/greeting phrase.
 */
function shouldTriggerSearchImportFallback(text) {
  const normalized = normalize(text);
  if (normalized.length < 2) return false;
  if (CHITCHAT_PHRASES.has(normalized)) return false;
  return true;
}

module.exports = { shouldTriggerSearchImportFallback, CHITCHAT_PHRASES };
