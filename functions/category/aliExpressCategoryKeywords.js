// -----------------------------------------------------------------------------
// Fast, free, deterministic first pass at guessing a category for an
// AliExpress-imported product whose response had no usable category_name
// (common for mobile-parts/repair-accessory/generic-gadget listings — see
// normalizeAliExpressProduct() in index.js). Checked against the product
// title/name only.
//
// Style follows functions/scripts/backfillMobilePartsSubcategory.js's
// classifyByTitle(): explicit regex rules, first match wins, never a fuzzy
// guess. Rule order matters — more specific rules (e.g. Mobile Parts'
// display/motherboard terms) are listed before broader ones (e.g. generic
// Electronics) so a phone-screen listing doesn't get bucketed into
// Electronics ahead of Mobile Parts.
//
// Every `name` below is deliberately an EXACT existing (or previously-real)
// store category name, so ensureCategoryExists()'s normalized-name lookup
// reuses the real category doc instead of creating a near-duplicate. Add
// new rules here as new AliExpress product types show up in the
// needsCategoryReview queue — no other code changes needed.
// -----------------------------------------------------------------------------

const CATEGORY_KEYWORD_RULES = [
  {
    name: "Mobile Parts",
    pattern: /\b(motherboard|main\s?board|logic\s?board|digitizer|flex\s?cable|phone\s?screen|lcd\s?assembly|spudger|pry\s?(tool|bar)|prying\s?tool|opening\s?tool)\b/i,
  },
  {
    // Phone repair TOOL kits (e.g. "10 Pcs Abs Plastic Spudger Disassembling
    // Tools For Phone Cell Laptop Repair") phrase the tool word and the
    // phone/repair word in either order and rarely adjacent, so a plain
    // word-boundary alternation (like the rule above) can miss them unless
    // "spudger" or another exact term happens to be present. These three
    // independent lookaheads instead require disassembly/repair language,
    // "tool(s)", AND a phone-ish word to ALL appear somewhere in the title
    // (any order) — specific enough to avoid false positives from unrelated
    // "repair kit" listings (car, furniture, etc.), which never mention a
    // phone/cell/mobile word at all.
    name: "Mobile Parts",
    pattern: /(?=.*\b(disassembl\w*|repair)\b)(?=.*\btools?\b)(?=.*\b(phone|cell\s?phone|smartphone|mobile)\b)/i,
  },
  {
    name: "Mobile Accessories",
    pattern: /\b(phone\s?case|screen\s?protector|tempered\s?glass|phone\s?charger|phone\s?holder|popsocket|sim\s?tray|phone\s?stand)\b/i,
  },
  {
    name: "Watches",
    pattern: /\b(watch|wristwatch|smart\s?watch)\b/i,
  },
  {
    name: "Electronics",
    pattern: /\b(speaker|earbud|earphone|headphone|headset|bluetooth|power\s?bank|usb\s?cable|charger|adapter|camera|drone|router|led\s?light|projector|amoled|\boled\b)\b/i,
  },
  {
    // Checked before Automotive — a bare "car" is too ambiguous (RC Car
    // toys, baby car seats) to safely claim here; Automotive below only
    // matches multi-word car-specific phrases for that reason.
    name: "Toys",
    pattern: /\b(toy|action\s?figure|puzzle|lego|rc\s?car|building\s?block)\b/i,
  },
  {
    name: "Automotive",
    pattern: /\b(car\s?(charger|holder|mount|accessor\w*|seat\s?cover)|motorcycle|automobile|vehicle|\btire\b|\btyre\b|dash\s?cam)\b/i,
  },
  {
    name: "Jewellery",
    pattern: /\b(necklace|bracelet|earring|pendant|jewellery|jewelry)\b/i,
  },
  {
    name: "Kitchen Items",
    pattern: /\b(kitchen|cookware|utensil|knife\s?set|cutting\s?board|frying\s?pan)\b/i,
  },
  {
    name: "Sports",
    pattern: /\b(fitness|gym|yoga|dumbbell|treadmill|resistance\s?band)\b/i,
  },
  {
    name: "Home & Living",
    pattern: /\b(home\s?decor|curtain|bed\s?sheet|pillow|furniture|storage\s?box)\b/i,
  },
  {
    name: "Books",
    pattern: /\b(book|novel|notebook|diary)\b/i,
  },
  {
    name: "Kids & Baby",
    pattern: /\b(kids?|baby|toddler|infant|stroller|diaper)\b/i,
  },
];

/**
 * Returns the canonical category name for the first matching rule, or null
 * if the title matches none. Never invents a category — a miss here just
 * means the caller should fall through to the AI-assisted step.
 */
function matchCategoryByKeyword(title) {
  const text = String(title || "");
  for (const rule of CATEGORY_KEYWORD_RULES) {
    if (rule.pattern.test(text)) return rule.name;
  }
  return null;
}

module.exports = { CATEGORY_KEYWORD_RULES, matchCategoryByKeyword };
