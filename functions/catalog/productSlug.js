"use strict";
// -----------------------------------------------------------------------------
// SEO-friendly product URL slugs: /product/{urlSlug}.
//
// A slug is built only from the product's name: lowercase ASCII, hyphenated,
// at most SLUG_MAX characters, cut at a word boundary. Bangla is spelled out
// in Latin letters, Bangla units become standard abbreviations, marketing
// filler ("Fully Tested", "100% Original", ...) and every source/supplier word
// ("aliexpress", "china", ...) are dropped. Nothing from the Firestore doc id
// or the supplier ever goes into a slug.
//
// Collisions (another product already owns the slug) are resolved in order:
//   1. a longer cut of the name (up to SLUG_MAX_EXTENDED), so two titles that
//      only differ after 60 characters keep the words that tell them apart;
//   2. the product's size ("strength": "1 ltr" -> "1-ltr", "400 ml" -> "400ml");
//   3. a short suffix that is fixed per product (hash of the doc id), only when
//      the size is missing or identical.
// See docs/plans/product-url-slugs.md. Once saved, urlSlug never changes when
// the name changes (a link must keep working).
// -----------------------------------------------------------------------------

const crypto = require("crypto");

const SLUG_MAX = 60;
const SLUG_MAX_EXTENDED = 80;
const SUFFIX_LENGTH = 4;

const SOURCE_WORDS = new Set([
  "aliexpress", "ali", "express", "alibaba", "alicdn", "imp", "china", "chinese",
  "taobao", "1688", "cainiao", "dropship", "dropshipping",
]);

// Words a slug must not start or end on (a cut often lands right after them).
const EDGE_WORDS = new Set(["for", "with", "and", "or", "of", "no", "the", "a", "an", "to", "in", "without", "plus"]);

// Marketing filler, matched on the original text before any other rewrite.
const FILLER = [
  /\b100\s*%\s*(working|original)\b/gi,
  /\bfully\s+tested\b/gi,
  /\b(fast|free)\s+shipping\b/gi,
  /\bhot\s+sale\b/gi,
  /\bnew\s+arrivals?\b/gi,
  /\bhigh\s+quality\b/gi,
  /\bbrand\s+new\b/gi,
  /\boriginal\b/gi,
  /\bgenuine\b/gi,
  /\bA{2,}\+*/g,
];

// --- Bangla -> Latin ---------------------------------------------------------

const BN_CONSONANTS = {
  "ক": "k", "খ": "kh", "গ": "g", "ঘ": "gh", "ঙ": "ng",
  "চ": "ch", "ছ": "chh", "জ": "j", "ঝ": "jh", "ঞ": "n",
  "ট": "t", "ঠ": "th", "ড": "d", "ঢ": "dh", "ণ": "n",
  "ত": "t", "থ": "th", "দ": "d", "ধ": "dh", "ন": "n",
  "প": "p", "ফ": "f", "ব": "b", "ভ": "bh", "ম": "m",
  "য": "j", "র": "r", "ল": "l", "শ": "sh", "ষ": "sh",
  "স": "s", "হ": "h", "ড়": "r", "ঢ়": "rh", "য়": "y",
  "ৎ": "t",
};
const BN_VOWELS = {
  "অ": "o", "আ": "a", "ই": "i", "ঈ": "i", "উ": "u",
  "ঊ": "u", "ঋ": "ri", "এ": "e", "ঐ": "oi", "ও": "o", "ঔ": "ou",
};
const BN_VOWEL_SIGNS = {
  "া": "a", "ি": "i", "ী": "i", "ু": "u", "ূ": "u",
  "ৃ": "ri", "ে": "e", "ৈ": "oi", "ো": "o", "ৌ": "ou",
};
const BN_MARKS = { "ং": "ng", "ঃ": "h", "ঁ": "n" };
const BN_HASANT = "্";

// Bangla units -> standard abbreviations, when written after a number or as
// their own word ("৫০০ মিলি", "৫০০মিলি", "১ কেজি").
const BN_UNITS = [
  ["কেজি", "kg"], // কেজি
  ["গ্রাম", "g"], // গ্রাম
  ["মিলি", "ml"], // মিলি
  ["লিটার", "l"], // লিটার
  ["পিস", "pcs"], // পিস
];
const BN_WORD_CHAR = "\\u0980-\\u09FF";

function bnUnits(s) {
  // Bangla digits first, so "৫কেজি" reads as a number then a unit.
  let out = s.replace(/[০-৯]/g, (d) => String(d.charCodeAt(0) - 0x09E6));
  for (const [bn, abbr] of BN_UNITS) {
    out = out.replace(new RegExp(`(^|[^${BN_WORD_CHAR}])${bn}(?![${BN_WORD_CHAR}])`, "g"), `$1 ${abbr} `);
  }
  return out;
}

function isBnLetter(c) {
  return Boolean(c) && /[ঀ-৿]/.test(c);
}

function bnToLatin(input) {
  const s = bnUnits(String(input || "").normalize("NFC")
    .replace(/ড়/g, "ড়")
    .replace(/ঢ়/g, "ঢ়")
    .replace(/য়/g, "য়"));
  const ch = [...s];
  let out = "";
  for (let i = 0; i < ch.length; i++) {
    const c = ch[i];
    const next = ch[i + 1];
    if (BN_CONSONANTS[c]) {
      out += BN_CONSONANTS[c];
      if (next === BN_HASANT) { i++; continue; } // conjunct: no inherent vowel
      if (BN_VOWEL_SIGNS[next]) continue; // the sign supplies the vowel
      if (BN_MARKS[next]) { out += "o"; continue; }
      if (isBnLetter(next)) out += "o"; // inherent vowel inside a word
      // word-final inherent vowel is silent
    } else if (BN_VOWELS[c]) out += BN_VOWELS[c];
    else if (BN_VOWEL_SIGNS[c]) out += BN_VOWEL_SIGNS[c];
    else if (BN_MARKS[c]) out += BN_MARKS[c];
    else if (/[০-৯]/.test(c)) out += String(c.charCodeAt(0) - 0x09E6);
    else if (c === BN_HASANT || c === "‌" || c === "‍" || c === "়") continue;
    else out += c;
  }
  return out;
}

// --- slug --------------------------------------------------------------------

function words(name) {
  let s = String(name || "");
  for (const re of FILLER) s = s.replace(re, " ");
  s = bnToLatin(s);
  s = s.normalize("NFKD").replace(/[̀-ͯ]/g, "");
  s = s
    .replace(/(\d)\s*(''|"|”|″|\binch(es)?\b)/gi, "$1 inch ")
    .replace(/&/g, " and ")
    // "+" is "plus" only as part of a model name: "S21+", "Note 10+".
    // Anything else ("iPhone 11+Face ID") is just a separator.
    .replace(/([A-Za-z0-9])\+(?=$|[\s/,;:)\]|-])/g, "$1 plus ")
    .replace(/\+/g, " ")
    .replace(/%/g, " percent ")
    .replace(/(\d)\.(\d)/g, "$1-$2")
    .replace(/['’`"]/g, "");
  return s.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w && !SOURCE_WORDS.has(w));
}

function trimEdges(list) {
  const ws = [...list];
  while (ws.length > 1 && EDGE_WORDS.has(ws[0])) ws.shift();
  while (ws.length > 1 && EDGE_WORDS.has(ws[ws.length - 1])) ws.pop();
  return ws;
}

function joinWithin(list, max) {
  let out = "";
  for (const w of list) {
    const next = out ? `${out}-${w}` : w;
    if (next.length > max) {
      if (!out) out = w.slice(0, max);
      break;
    }
    out = next;
  }
  return out;
}

/** The slug for [name], at most [max] characters ("product" if nothing is left). */
function baseSlug(name, max = SLUG_MAX) {
  const cut = joinWithin(words(name), max).split("-").filter(Boolean);
  return trimEdges(cut).join("-") || "product";
}

const SIZE_UNITS = [
  [/^(kg|kgs|kilo|kilogram|kilograms)$/, "kg"],
  [/^(g|gm|gms|gr|gram|grams)$/, "g"],
  [/^(mg)$/, "mg"],
  [/^(ml|mls)$/, "ml"],
  [/^(l|lt|ltr|ltrs|liter|liters|litre|litres)$/, "-ltr"],
  [/^(pc|pcs|piece|pieces)$/, "pcs"],
];

/**
 * The product's size as a slug part: "1 ltr" -> "1-ltr", "400 ml" -> "400ml",
 * "500gm" -> "500g", "১ কেজি" -> "1kg". "" when [strength] holds no amount.
 */
function sizeSlug(strength) {
  const s = bnToLatin(String(strength || "")).toLowerCase();
  const m = s.match(/(\d+(?:[.,]\d+)?)\s*([a-z]+)/);
  if (m) {
    const amount = m[1].replace(/[.,]/g, "-");
    for (const [re, unit] of SIZE_UNITS) {
      if (re.test(m[2])) return `${amount}${unit}`; // liters read "1-ltr", the rest "400ml"
    }
  }
  if (!/\d/.test(s)) return "";
  const fallback = s.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return fallback.slice(0, 20).replace(/-+$/, "");
}

/** A short suffix that is always the same for one product (hash of its doc id). */
function stableSuffix(docId, length = SUFFIX_LENGTH) {
  const hex = crypto.createHash("sha256").update(`slug:${docId}`).digest("hex");
  return BigInt(`0x${hex.slice(0, 16)}`).toString(36).padStart(length, "0").slice(0, length);
}

function withPart(base, part) {
  const room = SLUG_MAX - part.length - 1;
  const trimmed = trimEdges(joinWithin(base.split("-"), Math.max(room, 10)).split("-")).join("-");
  return `${trimmed}-${part}`;
}

/**
 * Slugs to try for one product, best first. The first one nobody owns wins
 * (see pickSlugInTransaction in productSlugStore.js).
 * [product]: { name, strength }; [docId]: Firestore id (only feeds the suffix).
 * [options.titleTaken]: another product already has this exact name, so the
 * name alone is not offered (a title collision always gets the size).
 */
function slugCandidates(product, docId, { titleTaken = false } = {}) {
  const name = product?.name || product?.title || "";
  const base = baseSlug(name);
  const out = [];
  if (!titleTaken) {
    out.push(base);
    for (let max = SLUG_MAX + 4; max <= SLUG_MAX_EXTENDED; max += 4) out.push(baseSlug(name, max));
  }
  const size = sizeSlug(product?.strength);
  if (size) out.push(withPart(base, size));
  const tail = size ? `${size}-` : "";
  for (let len = SUFFIX_LENGTH; len <= SUFFIX_LENGTH + 4; len++) out.push(withPart(base, `${tail}${stableSuffix(docId, len)}`));
  return [...new Set(out)];
}

/**
 * Backfill planner: a slug for every product, all unique and none in [taken].
 * Products whose names give the same slug are treated as a group, so every
 * member of the group gets a distinguishing part (not just the later ones):
 * the longer cut if that separates them, else their size, else the suffix.
 * [products]: [{ id, name, strength }]. Returns Map id -> { slug, reason }.
 */
function planSlugs(products, taken = new Set()) {
  const used = new Set(taken);
  const result = new Map();
  const groups = new Map();
  for (const p of products) {
    const b = baseSlug(p.name);
    if (!groups.has(b)) groups.set(b, []);
    groups.get(b).push(p);
  }

  const claim = (p, slug, reason) => {
    if (used.has(slug)) return false;
    used.add(slug);
    result.set(p.id, { slug, reason });
    return true;
  };

  // Stable order: the group's slug, then doc id.
  const ordered = [...groups.entries()].sort(([a], [b]) => a.localeCompare(b));
  for (const [base, members] of ordered) {
    members.sort((a, b) => a.id.localeCompare(b.id));
    if (members.length === 1) {
      const p = members[0];
      if (claim(p, base, "name")) continue;
      slugCandidates(p, p.id).slice(1).some((s) => claim(p, s, "collision"));
      continue;
    }

    // 1. A longer cut that tells every member apart.
    let done = false;
    for (let max = SLUG_MAX + 4; max <= SLUG_MAX_EXTENDED && !done; max += 4) {
      const slugs = members.map((p) => baseSlug(p.name, max));
      if (new Set(slugs).size === slugs.length && slugs.every((s) => !used.has(s))) {
        members.forEach((p, i) => claim(p, slugs[i], "longer cut"));
        done = true;
      }
    }
    if (done) continue;

    // 2. Every member's size, when all are present and different.
    const sizes = members.map((p) => sizeSlug(p.strength));
    if (sizes.every(Boolean) && new Set(sizes).size === sizes.length) {
      const slugs = members.map((p, i) => withPart(base, sizes[i]));
      if (new Set(slugs).size === slugs.length && slugs.every((s) => !used.has(s))) {
        members.forEach((p, i) => claim(p, slugs[i], "size"));
        continue;
      }
    }

    // 3. The first words where the names differ ("with face id" / "without
    //    face id" ~90 characters in), when that tells every member apart.
    const lists = members.map((p) => words(p.name));
    let common = 0;
    while (lists.every((l) => common < l.length && l[common] === lists[0][common])) common++;
    // Only trailing filler is trimmed here: a leading "with"/"without" is
    // often the very difference.
    const diffs = lists.map((l) => {
      const ws = l.slice(common, common + 3);
      while (ws.length > 1 && EDGE_WORDS.has(ws[ws.length - 1])) ws.pop();
      return ws.join("-");
    });
    // Two names where one only has an extra word ("... Touch Screen
    // Digitizer For Samsung" vs "... Touch Screen For Samsung"): the one with
    // the word gets it ("-digitizer"), the other keeps the plain slug.
    if (members.length === 2) {
      const [a, b] = lists;
      const extraIn = a[common + 1] !== undefined && a[common + 1] === b[common] ? 0
        : b[common + 1] !== undefined && b[common + 1] === a[common] ? 1 : -1;
      if (extraIn >= 0) {
        const word = lists[extraIn][common];
        const slugs = members.map((p, i) => (i === extraIn ? withPart(base, word) : base));
        if (!EDGE_WORDS.has(word) && slugs[0] !== slugs[1] && slugs.every((s) => !used.has(s))) {
          members.forEach((p, i) => claim(p, slugs[i], i === extraIn ? "extra word" : "name"));
          continue;
        }
      }
    }
    const extraWordOnly = lists.some((a) => lists.some((b) => a !== b && a[common + 1] !== undefined && a[common + 1] === b[common]));
    if (!extraWordOnly && diffs.every(Boolean) && new Set(diffs).size === diffs.length) {
      const slugs = members.map((p, i) => withPart(base, diffs[i]));
      if (new Set(slugs).size === slugs.length && slugs.every((s) => !used.has(s))) {
        members.forEach((p, i) => claim(p, slugs[i], "differing words"));
        continue;
      }
    }

    // 4. Size where it is unique within the group, else the fixed suffix.
    members.forEach((p, i) => {
      const size = sizes[i];
      const sizeUnique = size && sizes.filter((s) => s === size).length === 1;
      if (sizeUnique && claim(p, withPart(base, size), "size")) return;
      const tail = size ? `${size}-` : "";
      for (let len = SUFFIX_LENGTH; len <= SUFFIX_LENGTH + 4; len++) {
        if (claim(p, withPart(base, `${tail}${stableSuffix(p.id, len)}`), size ? "size + suffix" : "suffix")) return;
      }
    });
  }
  return result;
}

module.exports = {
  SLUG_MAX,
  SLUG_MAX_EXTENDED,
  baseSlug,
  bnToLatin,
  sizeSlug,
  stableSuffix,
  slugCandidates,
  planSlugs,
};
