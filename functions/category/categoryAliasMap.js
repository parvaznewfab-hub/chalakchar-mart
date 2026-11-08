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

module.exports = { CATEGORY_ALIASES, resolveCategoryAlias };
