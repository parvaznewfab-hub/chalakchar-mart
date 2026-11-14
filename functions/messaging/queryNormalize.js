// -----------------------------------------------------------------------------
// Turns a chat message into product-search terms.
//
// Customers write "Netac SSD 128GB price?" or "১২৮ জিবি এসএসডির দাম কত?".
// Matching the raw words failed both: "price?", "দাম", "কত" never appear in a
// product, and the Bangla words don't match English product names. Here:
//   - Bangla digits -> ASCII (১২৮ -> 128);
//   - punctuation dropped (but "2.5" keeps its dot);
//   - Bangla / Banglish product words -> the English the catalog uses
//     (এসএসডি -> ssd, জিবি -> gb), also with a case ending (এসএসডির -> ssd);
//   - question / filler words dropped (price, দাম, কত, dam, koto, ...);
//   - a number and its unit joined (128 gb -> 128gb), as product names write it.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

const BANGLA_DIGITS = { "০": "0", "১": "1", "২": "2", "৩": "3", "৪": "4", "৫": "5", "৬": "6", "৭": "7", "৮": "8", "৯": "9" };

// Bangla (and common Banglish) spellings -> catalog words. Multi-word values
// are allowed ("hard disk").
const TERM_MAP = new Map(Object.entries({
  "এসএসডি": "ssd", "এস.এস.ডি": "ssd",
  "জিবি": "gb", "টিবি": "tb", "এমবি": "mb", "এমএএইচ": "mah",
  "র‍্যাম": "ram", "র্যাম": "ram", "রেম": "ram",
  "হার্ডডিস্ক": "hard disk", "হার্ড": "hard", "ডিস্ক": "disk", "ড্রাইভ": "drive",
  "ল্যাপটপ": "laptop", "ল্যাপটপের": "laptop", "কম্পিউটার": "computer",
  "মোবাইল": "mobile", "ফোন": "phone", "আইফোন": "iphone", "স্যামসাং": "samsung", "শাওমি": "xiaomi",
  "রিয়েলমি": "realme", "অপো": "oppo", "ভিভো": "vivo", "নেটাক": "netac",
  "ডিসপ্লে": "display", "স্ক্রিন": "screen", "স্ক্রীন": "screen", "এলসিডি": "lcd", "ওএলইডি": "oled",
  "ব্যাটারি": "battery", "ব্যাটারী": "battery", "চার্জার": "charger", "ক্যাবল": "cable", "কেবল": "cable",
  "মাদারবোর্ড": "motherboard", "বোর্ড": "board", "কিবোর্ড": "keyboard", "কীবোর্ড": "keyboard",
  "মাউস": "mouse", "ক্যামেরা": "camera", "স্পিকার": "speaker", "হেডফোন": "headphone",
  "কভার": "cover", "কেস": "case", "গ্লাস": "glass", "ফ্লেক্স": "flex",
  "ইঞ্চি": "inch", "ওয়াট": "w",
}));

// Words that ask about a product rather than name it.
const STOPWORDS = new Set([
  // English
  "price", "prices", "pricing", "cost", "rate", "how", "much", "what", "whats", "is", "are", "the", "of", "a", "an",
  "for", "do", "does", "you", "have", "has", "available", "availability", "please", "pls", "plz", "want", "need",
  "i", "me", "my", "it", "this", "that", "in", "stock", "buy", "can", "get", "tell", "about", "show", "any", "and",
  "or", "with", "to", "there", "bdt", "tk", "taka",
  // Shop questions ("delivery time koto?") go to the AI, not product search;
  // "Netac SSD delivery time?" still searches "netac ssd".
  "delivery", "deliver", "shipping", "ship", "time", "days", "day", "order", "payment", "pay", "cash", "cod",
  "return", "refund", "warranty", "guarantee", "kobe", "kokhon", "kotodin", "lagbe", "address", "location",
  "ডেলিভারি", "ডেলিভারী", "সময়", "দিনে", "কবে", "কখন", "কতদিন", "অর্ডার", "পেমেন্ট", "রিটার্ন", "ওয়ারেন্টি", "ঠিকানা",
  // Banglish
  "dam", "daam", "koto", "kot", "ache", "ase", "achhe", "ki", "er", "bhai", "vai", "apu", "den", "din",
  "chai", "lagbe", "jante", "janan", "janaben", "ekta", "kemon", "hobe",
  // Bangla
  "দাম", "দামে", "কত", "কতো", "আছে", "আছেকি", "কি", "কী", "ভাই", "আপু", "প্লিজ", "টাকা", "চাই", "লাগবে", "দেন",
  "দিন", "জানাবেন", "জানান", "জানতে", "চাচ্ছি", "এর", "টা", "টি", "একটা", "একটি", "কেমন", "হবে", "আমার", "আমি",
  "এই", "ওই", "সেই", "এবং", "ও", "আর", "কোন", "কোনো", "দয়া", "করে", "পাওয়া", "যাবে", "যায়", "স্টক", "প্রাইস",
]);

// Case endings / classifiers that can follow a Bangla word (longest first).
const BANGLA_SUFFIXES = ["গুলোর", "গুলো", "টার", "টির", "েরটা", "ের", "এর", "য়ের", "র", "টা", "টি", "তে", "কে"];

const UNITS = "gb|tb|mb|mah|w|hz|inch|mm|cm|v";

const BANGLA_RE = /[ঀ-৿]/;

function toAsciiDigits(value) {
  return String(value ?? "").replace(/[০-৯]/g, (d) => BANGLA_DIGITS[d]);
}

/** Bangla word -> catalog word(s), trying it as written, then without a case ending. */
function mapBanglaWord(word) {
  if (TERM_MAP.has(word)) return TERM_MAP.get(word);
  for (const suffix of BANGLA_SUFFIXES) {
    if (word.length > suffix.length + 1 && word.endsWith(suffix)) {
      const stem = word.slice(0, -suffix.length);
      if (TERM_MAP.has(stem)) return TERM_MAP.get(stem);
      if (STOPWORDS.has(stem)) return "";
    }
  }
  return word;
}

/**
 * Search terms for [message]: lowercase, deduplicated, in order.
 * Returns [] when nothing product-like is left (e.g. "দাম কত?").
 */
function normalizeChatQuery(message) {
  let s = toAsciiDigits(message).toLowerCase();
  // Keep decimal points (2.5), drop every other punctuation mark.
  s = s.replace(/(\d)\.(\d)/g, "$1\u0000$2");
  s = s.replace(/[^\p{L}\p{M}\p{N}\u0000‌‍\s]+/gu, " ");
  s = s.replace(/\u0000/g, ".");

  const words = [];
  for (const raw of s.split(/\s+/).filter(Boolean)) {
    // "128জিবি" -> "128" + "জিবি"
    const parts = raw.split(/(?<=\d)(?=[ঀ-৿])|(?<=[ঀ-৿])(?=\d)/u);
    for (const part of parts) {
      const mapped = BANGLA_RE.test(part) ? mapBanglaWord(part) : part;
      for (const w of String(mapped).split(/\s+/).filter(Boolean)) {
        if (!STOPWORDS.has(w)) words.push(w);
      }
    }
  }

  // "128 gb" -> "128gb"
  const joined = words.join(" ").replace(new RegExp(`\\b(\\d+(?:\\.\\d+)?) (${UNITS})\\b`, "g"), "$1$2");
  return [...new Set(joined.split(" ").filter(Boolean))];
}

module.exports = { normalizeChatQuery, toAsciiDigits };
