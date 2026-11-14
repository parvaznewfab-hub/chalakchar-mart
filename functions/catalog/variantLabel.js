// -----------------------------------------------------------------------------
// Storefront variant label ("Capacity" in "Capacity: 4TB").
//
// JS mirror of resolveVariantAttributeLabel / cleanVariantDisplayName in
// lib/utils/variant_selector_model.dart + variant_display_name.dart, used by
// backend scripts (backfill dry-run reports). Both sides are checked against
// test/fixtures/variant_label_cases.json — change them together.
//
// Order:
//   1. product.variantAttributeName (manual, admin-set)
//   2. subcategory.variantLabel (admin default, e.g. "Model")
//   3. category.variantLabel
//   4. "Color"    — only if MOST values are real colours ("Rose Gold",
//                   "Light Blue"; not "TFT Black Frame")
//   5. "Capacity" — MOST values start with a storage size ("4TB Black")
//   6. "Size"     — every value is a clothing size (S, M, XL, 3XL)
//   7. "Option"
// AliExpress's own name (variants[].sourceAttributeName) and per-variant
// attributeName are deliberately not used: sellers misuse "Color" for
// models/storage/frames.
// -----------------------------------------------------------------------------

const COLOURS = new Set([
  "black", "white", "red", "blue", "green", "yellow", "pink", "purple", "violet",
  "orange", "brown", "grey", "gray", "silver", "gold", "golden", "beige", "ivory",
  "cream", "khaki", "navy", "teal", "cyan", "turquoise", "aqua", "magenta",
  "maroon", "burgundy", "wine", "coffee", "chocolate", "tan", "camel", "champagne",
  "bronze", "copper", "rose", "lavender", "lilac", "mint", "olive", "coral",
  "peach", "apricot", "lemon", "transparent", "clear", "multicolor",
  "multicolour", "colorful", "colourful", "rainbow", "graphite", "titanium",
]);
const COLOUR_MODIFIERS = new Set([
  "light", "dark", "deep", "pale", "bright", "matte", "matt", "glossy",
  "metallic", "sky", "royal", "army", "hot", "baby", "neon", "pastel", "space",
  "midnight", "starlight", "jet", "pure", "off", "and",
]);
// Starts with a storage size: "512GB", "1 TB", "4TB Black" (not "256g").
const STORAGE_PREFIX = /^\d+(\.\d+)?\s?(GB|TB|MB)(?![A-Za-z])/i;
const SIZE = /^(XXS|XS|S|M|L|XL|XXL|XXXL|[2-6]XL)$/i;
const DISPLAY_SEPARATORS = ["|", " / "];

/** Mirror of cleanVariantDisplayName (Dart): drop ships-from suffixes. */
function cleanVariantDisplayName(raw) {
  const text = String(raw ?? "").trim();
  if (!text) return text;
  for (const sep of DISPLAY_SEPARATORS) {
    const i = text.indexOf(sep);
    if (i > 0) {
      const head = text.slice(0, i).trim();
      if (head) return head;
    }
  }
  return text;
}

function isColourValue(value) {
  const tokens = String(value ?? "").toLowerCase().split(/[\s\-&+,/]+/).filter(Boolean);
  if (!tokens.length) return false;
  let colours = 0;
  for (const t of tokens) {
    if (COLOURS.has(t)) colours += 1;
    else if (!COLOUR_MODIFIERS.has(t)) return false;
  }
  return colours > 0;
}

/**
 * @param {string} productAttributeName product.variantAttributeName
 * @param {string[]} values cleaned display values (cleanVariantDisplayName)
 * @param {{ subcategoryLabel?: string, categoryLabel?: string }} defaults
 *   the product's subcategory/category `variantLabel`
 */
function resolveVariantAttributeLabel(productAttributeName, values, defaults = {}) {
  for (const explicit of [productAttributeName, defaults.subcategoryLabel, defaults.categoryLabel]) {
    const label = String(explicit ?? "").trim();
    if (label) return label;
  }

  const list = [...new Set((values || []).map((v) => String(v ?? "").trim()).filter(Boolean))];
  if (!list.length) return "Option";
  if (list.filter(isColourValue).length * 2 > list.length) return "Color";
  if (list.filter((v) => STORAGE_PREFIX.test(v)).length * 2 > list.length) return "Capacity";
  if (list.every((v) => SIZE.test(v))) return "Size";
  return "Option";
}

/**
 * Label for a whole product document.
 * @param {object} product
 * @param {{ subcategoryLabel?: string, categoryLabel?: string }} defaults
 */
function labelForProduct(product, defaults = {}) {
  const p = product || {};
  const variants = Array.isArray(p.variants) ? p.variants : [];
  const values = variants
    .filter((v) => v && typeof v === "object")
    .map((v) => cleanVariantDisplayName(v.name ?? v.unit ?? v.variantName));
  return resolveVariantAttributeLabel(p.variantAttributeName, values, defaults);
}

module.exports = { resolveVariantAttributeLabel, cleanVariantDisplayName, isColourValue, labelForProduct };
