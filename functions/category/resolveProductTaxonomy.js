const { ensureCategoryExists } = require("./ensureCategoryExists");
const { ensureSubcategoryExists } = require("./ensureSubcategoryExists");
const { resolveTaxonomyRedirect } = require("./categoryAliasMap");

// Display name + flag applied whenever a product has no usable category
// input. Never invented/guessed (e.g. never forced into "Electronics" just
// because the product looks electronics-adjacent) — an admin reviews and
// re-files it manually via the Category Manager.
const UNCATEGORIZED_NAME = "Uncategorized";

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function uncategorizedResult() {
  return {
    categoryId: null,
    categoryName: UNCATEGORIZED_NAME,
    subcategoryId: null,
    createdCategory: false,
    createdSubcategory: false,
    needsCategoryReview: true,
  };
}

/**
 * Single entry point every product-writing path (Admin, Vendor, CSV, JSON,
 * AliExpress, n8n) should call before saving a product. Resolves category
 * and (optionally) subcategory through the shared resolvers and returns
 * exactly what the product document needs.
 *
 * Enforced invariant: `subcategoryId` is NEVER returned unless `categoryId`
 * was also resolved — a product can never carry a subcategoryId without its
 * parent categoryId. This is enforced here, in the one shared place, not
 * left to each caller to remember.
 *
 * If `rawCategoryName` is null/empty/whitespace-only, or it doesn't resolve
 * to a usable category (e.g. it normalizes to nothing), the resolver is
 * skipped entirely — no Firestore reads or writes happen — and the result
 * carries `categoryName: "Uncategorized"` with `needsCategoryReview: true`
 * so the product is never silently mis-filed or forced into an unrelated
 * category; an admin can find it (query `needsCategoryReview == true`) and
 * re-file it later. `categoryId`/`subcategoryId` stay null in this case.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} rawCategoryName
 * @param {string} [rawSubcategoryName]
 * @param {{ source?: string }} options - source: "admin"|"vendor"|"aliexpress"|"n8n"|"csv"|"json"
 * @returns {Promise<{
 *   categoryId: string|null,
 *   categoryName: string|null,
 *   subcategoryId: string|null,
 *   createdCategory: boolean,
 *   createdSubcategory: boolean,
 *   needsCategoryReview: boolean,
 * }>}
 */
async function resolveProductTaxonomy(db, rawCategoryName, rawSubcategoryName, options = {}) {
  // e.g. ("Mobile Parts", "Motherboard & Mainboard") -> ("Motherboard", "").
  // Only when a category was given, so a blank category still stays Uncategorized.
  if (textValue(rawCategoryName)) {
    ({ categoryName: rawCategoryName, subcategoryName: rawSubcategoryName } =
      resolveTaxonomyRedirect(rawCategoryName, rawSubcategoryName));
  }
  const categoryInput = textValue(rawCategoryName);
  if (!categoryInput) return uncategorizedResult(); // validation: skip the resolver completely

  const categoryResult = await ensureCategoryExists(db, categoryInput, options);
  if (!categoryResult) return uncategorizedResult();

  const result = {
    categoryId: categoryResult.categoryId,
    categoryName: categoryResult.categoryName,
    subcategoryId: null,
    createdCategory: categoryResult.createdCategory,
    createdSubcategory: false,
    needsCategoryReview: false,
  };

  const subcategoryInput = textValue(rawSubcategoryName);
  if (!subcategoryInput) return result;

  // Invariant: only ever attempted once a categoryId is in hand.
  const subcategoryResult = await ensureSubcategoryExists(
    db,
    result.categoryId,
    result.categoryName,
    subcategoryInput,
    options
  );
  if (subcategoryResult) {
    result.subcategoryId = subcategoryResult.subcategoryId;
    result.createdSubcategory = subcategoryResult.createdSubcategory;
  }

  return result;
}

module.exports = { resolveProductTaxonomy };
