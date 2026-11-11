const { normalizeCategoryKey } = require("./categoryNormalize");

// -----------------------------------------------------------------------------
// Isolated category alias table. Add new aliases here — nothing else needs
// to change. Keys are normalized (NFKC/trim/lowercase/whitespace-collapsed)
// input names; values are the canonical category name to use instead.
// -----------------------------------------------------------------------------
const CATEGORY_ALIASES = {
  "cell phone parts": "Mobile Parts",
  "cellphone parts": "Mobile Parts",
  "mobile phone parts": "Mobile Parts",
  "mobile phone accessories": "Accessories",
  // Motherboards are a top-level category with brand subcategories; the old
  // Mobile Parts › "Motherboard & Mainboard" subcategory is retired.
  "motherboards": "Motherboard",
  "mainboard": "Motherboard",
  "mainboards": "Motherboard",
  "main board": "Motherboard",
  "logic board": "Motherboard",
  "motherboard & mainboard": "Motherboard",
  "motherboard and mainboard": "Motherboard",
  "mobile motherboard": "Motherboard",
  "phone motherboard": "Motherboard",
};

// Subcategory names that are really a top-level category. When a product
// arrives with one of these as its subcategory, it is filed under the
// category instead, with no subcategory (so nothing is ever created under
// the retired Mobile Parts › "Motherboard & Mainboard").
const SUBCATEGORY_TO_CATEGORY = {
  "motherboard": "Motherboard",
  "motherboards": "Motherboard",
  "mainboard": "Motherboard",
  "main board": "Motherboard",
  "logic board": "Motherboard",
  "motherboard & mainboard": "Motherboard",
  "motherboard and mainboard": "Motherboard",
};

/**
 * Resolves a raw category name to its canonical form via the alias table.
 * Returns the original (trimmed) name unchanged if no alias matches.
 *
 * Deliberately async even though today's lookup is a synchronous in-memory
 * table — this keeps the call signature stable so a future Firestore-backed
 * alias configuration (e.g. an `categoryAliases` collection admin can edit)
 * can replace the implementation without touching ensureCategoryExists() or
 * any other caller.
 */
async function resolveCategoryAlias(rawName) {
  const text = String(rawName ?? "").trim();
  if (!text) return text;
  const key = normalizeCategoryKey(text);
  return CATEGORY_ALIASES[key] || text;
}

/**
 * Applies SUBCATEGORY_TO_CATEGORY: returns the category/subcategory pair to
 * resolve. Unchanged when the subcategory is not a redirected name.
 */
function resolveTaxonomyRedirect(rawCategoryName, rawSubcategoryName) {
  const sub = String(rawSubcategoryName ?? "").trim();
  const target = sub ? SUBCATEGORY_TO_CATEGORY[normalizeCategoryKey(sub)] : null;
  if (!target) return { categoryName: rawCategoryName, subcategoryName: rawSubcategoryName };
  return { categoryName: target, subcategoryName: "" };
}

module.exports = { CATEGORY_ALIASES, SUBCATEGORY_TO_CATEGORY, resolveCategoryAlias, resolveTaxonomyRedirect };
