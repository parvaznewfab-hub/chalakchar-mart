// -----------------------------------------------------------------------------
// AI-assisted category suggestion — the fallback step when an AliExpress
// import has no category_name AND matchCategoryByKeyword() (see
// aliExpressCategoryKeywords.js) found nothing. Only ever called on a
// keyword-match MISS, to keep the common case free/instant/deterministic.
//
// Pure/testable logic lives here (prompt building, response parsing); the
// actual OpenAI network call stays in index.js next to every other
// openai.chat.completions.create() usage in this project, so this module
// has no dependency on the openai package or OPENAI_API_KEY.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

/**
 * Builds the prompt asking the model to either pick one of our real,
 * existing store categories, or — only if none genuinely fit — propose a
 * short new one. Candidate names are the caller's full current category
 * list (active or not — matches this project's "reuse an existing category
 * regardless of active state" policy, same as ensureCategoryExists()).
 */
function buildCategorySuggestionPrompt({ title, candidateNames }) {
  const cleanTitle = textValue(title);
  const names = Array.isArray(candidateNames) ? candidateNames.map((n) => textValue(n)).filter(Boolean) : [];

  return `A product imported from AliExpress needs a store category. Our store's existing categories are:
${names.length ? names.map((n) => `- ${n}`).join("\n") : "(none yet)"}

Product title: ${cleanTitle}

Return ONLY valid JSON, no markdown, in this exact shape:
{
  "matchedCategory": "one of the existing category names above that genuinely fits this product, or null if none reasonably fit",
  "suggestedNewCategory": "a short (2-3 word) new category name for this product, used only if matchedCategory is null"
}

Rules:
- Only set matchedCategory to a name that appears EXACTLY in the list above (byte-for-byte) — never invent, rename, or slightly alter one of the existing names.
- Do not force a weak match — if nothing in the list is a genuine fit, set matchedCategory to null and provide suggestedNewCategory instead.
- suggestedNewCategory must be a general ecommerce category (e.g. "Electronics", "Home Decor"), never the product's own name or brand.`;
}

/**
 * Parses the model's JSON response, validating matchedCategory against the
 * real candidate list (case/whitespace-insensitive) so a hallucinated or
 * near-miss name is never trusted — falls through to suggestedNewCategory
 * (or null) instead of silently accepting an invented existing-category name.
 */
function parseCategorySuggestionResponse(rawJsonText, candidateNames) {
  const names = Array.isArray(candidateNames) ? candidateNames.map((n) => textValue(n)) : [];
  const byNormalized = new Map(names.map((n) => [n.trim().toLowerCase(), n]));

  let parsed;
  try {
    parsed = JSON.parse(textValue(rawJsonText, "{}"));
  } catch (_) {
    return { matchedCategory: null, suggestedNewCategory: "" };
  }

  const matchedRaw = textValue(parsed.matchedCategory).trim().toLowerCase();
  const matchedCategory = matchedRaw && byNormalized.has(matchedRaw) ? byNormalized.get(matchedRaw) : null;
  const suggestedNewCategory = matchedCategory ? "" : textValue(parsed.suggestedNewCategory).slice(0, 40);

  return { matchedCategory, suggestedNewCategory };
}

module.exports = { buildCategorySuggestionPrompt, parseCategorySuggestionResponse };
