const admin = require("firebase-admin");
const { normalizeCategoryKey, generateUniqueSlug } = require("./categoryNormalize");

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

// Same source-based defaults as the category tier — kept as an identical,
// separate copy (not imported from ensureCategoryExists.js) so the two
// tiers can diverge safely if a future requirement needs them to.
function defaultsForSource(source) {
  if (source === "vendor" || source === "aliexpress") {
    return { isActive: false, showOnHome: false, status: "pending" };
  }
  return { isActive: true, showOnHome: true, status: "active" };
}

/**
 * Ensures a subcategory document exists under the given parent category —
 * reuses an existing one when found, creates one with safe defaults
 * otherwise. Slug uniqueness is scoped to the parent categoryId only (two
 * different categories may each have an "Accessories" subcategory without
 * colliding). Never called with an empty/missing categoryId — see the
 * invariant enforced in resolveProductTaxonomy.js: a subcategory can never
 * exist without its parent category.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} categoryId
 * @param {string} categoryName
 * @param {string} rawName
 * @param {{ source?: string }} options
 * @returns {Promise<{ subcategoryId: string, subcategoryName: string, createdSubcategory: boolean }|null>}
 *          null when rawName or categoryId is empty.
 */
async function ensureSubcategoryExists(db, categoryId, categoryName, rawName, options = {}) {
  const name = textValue(rawName);
  const parentCategoryId = textValue(categoryId);
  if (!name || !parentCategoryId) return null;

  const normalizedName = normalizeCategoryKey(name);
  if (!normalizedName) return null;

  const subcategoriesRef = db.collection("subcategories");
  const source = textValue(options.source, "admin");

  return db.runTransaction(async (transaction) => {
    const existingQuery = await transaction.get(
      subcategoriesRef
        .where("categoryId", "==", parentCategoryId)
        .where("normalizedName", "==", normalizedName)
        .limit(10)
    );

    // Retired subcategories (mergedInto set by scripts/categoryMerge.js) are
    // never reused.
    const doc = existingQuery.docs.find((d) => !textValue(d.data().mergedInto));
    if (doc) {
      return {
        subcategoryId: doc.id,
        subcategoryName: textValue(doc.data().name, name),
        createdSubcategory: false,
      };
    }

    const slug = await generateUniqueSlug(name, async (candidate) => {
      const slugQuery = await transaction.get(
        subcategoriesRef
          .where("categoryId", "==", parentCategoryId)
          .where("slug", "==", candidate)
          .limit(1)
      );
      return !slugQuery.empty;
    });

    const defaults = defaultsForSource(source);
    const newRef = subcategoriesRef.doc();
    transaction.set(newRef, {
      categoryId: parentCategoryId,
      categoryName: textValue(categoryName),
      name,
      normalizedName,
      slug,
      priority: 0,
      isActive: defaults.isActive,
      isFeatured: false,
      showOnHome: defaults.showOnHome,
      status: defaults.status,
      autoCreated: true,
      source,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { subcategoryId: newRef.id, subcategoryName: name, createdSubcategory: true };
  });
}

module.exports = { ensureSubcategoryExists, defaultsForSource };
