// Restricts the AI product optimizer's category/subcategory suggestion to
// the store's own ACTIVE taxonomy. The model is given the list in its
// prompt, and its answer is matched back against that list here: anything
// that doesn't match comes back empty, so a free-text guess like
// "Electronics" / "Storage Devices" never reaches a product.

function matchKey(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * Active categories with their active subcategories, ordered by priority
 * then name. Retired subcategories (mergedInto set) are left out.
 * @returns {Promise<Array<{id:string,name:string,subcategories:Array<{id:string,name:string}>}>>}
 */
async function loadActiveTaxonomy(db) {
  const [categorySnap, subcategorySnap] = await Promise.all([
    db.collection("categories").where("isActive", "==", true).get(),
    db.collection("subcategories").where("isActive", "==", true).get(),
  ]);
  const byPriority = (a, b) =>
    (Number(a.priority) || 0) - (Number(b.priority) || 0) ||
    a.name.toLowerCase().localeCompare(b.name.toLowerCase());

  const categories = categorySnap.docs
    .map((d) => ({ id: d.id, name: String(d.data().name || "").trim(), priority: d.data().priority }))
    .filter((c) => c.name)
    .sort(byPriority);
  const subs = subcategorySnap.docs
    .map((d) => ({ id: d.id, ...d.data(), name: String(d.data().name || "").trim() }))
    .filter((s) => s.name && !String(s.mergedInto || "").trim());

  return categories.map((c) => ({
    id: c.id,
    name: c.name,
    subcategories: subs
      .filter((s) => s.categoryId === c.id)
      .sort(byPriority)
      .map((s) => ({ id: s.id, name: s.name })),
  }));
}

/** Prompt lines listing the allowed category › subcategory names. */
function taxonomyPromptBlock(taxonomy) {
  if (!taxonomy.length) {
    return "Allowed categories: (none) — return empty strings for suggestedCategory and suggestedSubCategory.";
  }
  const lines = taxonomy.map((c) =>
    c.subcategories.length
      ? `- ${c.name} (subcategories: ${c.subcategories.map((s) => s.name).join(" | ")})`
      : `- ${c.name} (no subcategories)`
  );
  return [
    "Allowed categories (use these exact names only):",
    ...lines,
    "- suggestedCategory MUST be copied exactly from the list above, or \"\" if none fits the product.",
    "- suggestedSubCategory MUST be one of that category's listed subcategories, copied exactly, or \"\" if none fits.",
    "- Never invent a new category or subcategory name.",
  ].join("\n");
}

/**
 * Matches the model's raw answer back to the taxonomy (case/punctuation
 * insensitive, "&" == "and"). An unknown category clears both; an unknown
 * subcategory under a known category clears only the subcategory.
 */
function matchAiTaxonomy(taxonomy, rawCategory, rawSubcategory) {
  const category = taxonomy.find((c) => matchKey(c.name) === matchKey(rawCategory)) || null;
  const subKey = matchKey(rawSubcategory);
  const subcategory =
    category && subKey ? category.subcategories.find((s) => matchKey(s.name) === subKey) || null : null;
  return {
    matched: Boolean(category),
    categoryId: category ? category.id : "",
    categoryName: category ? category.name : "",
    subcategoryId: subcategory ? subcategory.id : "",
    subcategoryName: subcategory ? subcategory.name : "",
  };
}

module.exports = { loadActiveTaxonomy, taxonomyPromptBlock, matchAiTaxonomy, matchKey };
