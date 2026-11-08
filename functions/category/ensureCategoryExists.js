const admin = require("firebase-admin");
const { normalizeCategoryKey, generateUniqueSlug } = require("./categoryNormalize");
const { resolveCategoryAlias } = require("./categoryAliasMap");

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

// Defaults by source context. Vendor-originated categories are never
// automatically visible — admin must approve via the existing Category
// Manager Pro Active/Show on Homepage toggles. AliExpress-originated
// categories (Feature A discovery, Feature B search-import, and the n8n
// import webhook all pass source: "aliexpress") are equally unreviewed — an
// AI/keyword-matched category name nobody chose should not appear on the
// homepage before an admin has looked at it, same reasoning as
// needsReview on the product itself. Every other source (admin, csv, json,
// n8n-as-a-source-value-of-its-own) follows the admin defaults.
function defaultsForSource(source) {
  if (source === "vendor" || source === "aliexpress") {
    return { isActive: false, showOnHome: false, status: "pending" };
  }
  return { isActive: true, showOnHome: true, status: "active" };
}

/**
 * Ensures a category document exists for the given raw name — reuses an
 * existing one when found, creates one with safe defaults otherwise. Never
 * overwrites an existing category's manually-managed fields (image,
 * priority, description, isFeatured, isActive, showOnHome) — an existing
 * category is only ever returned, never touched.
 *
 * Concurrency-safe: name-dedup check, slug-uniqueness check, and the create
 * write all happen inside one Firestore transaction, so two simultaneous
 * callers creating the same category converge on a single document.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} rawName
 * @param {{ source?: string }} options - source: "admin"|"vendor"|"aliexpress"|"n8n"|"csv"|"json"
 * @returns {Promise<{ categoryId: string, categoryName: string, createdCategory: boolean }|null>}
 *          null when rawName is empty/whitespace-only — caller must not call
 *          this with a blank category name.
 */
async function ensureCategoryExists(db, rawName, options = {}) {
  const trimmedInput = textValue(rawName);
  if (!trimmedInput) return null;

  const canonicalName = textValue(await resolveCategoryAlias(trimmedInput), trimmedInput);
  const normalizedName = normalizeCategoryKey(canonicalName);
  if (!normalizedName) return null;

  const categoriesRef = db.collection("categories");
  const source = textValue(options.source, "admin");

  return db.runTransaction(async (transaction) => {
    const existingQuery = await transaction.get(
      categoriesRef.where("normalizedName", "==", normalizedName).limit(1)
    );

    if (!existingQuery.empty) {
      const doc = existingQuery.docs[0];
      return {
        categoryId: doc.id,
        categoryName: textValue(doc.data().name, canonicalName),
        createdCategory: false,
      };
    }

    const slug = await generateUniqueSlug(canonicalName, async (candidate) => {
      const slugQuery = await transaction.get(
        categoriesRef.where("slug", "==", candidate).limit(1)
      );
      return !slugQuery.empty;
    });

    const defaults = defaultsForSource(source);
    const newRef = categoriesRef.doc();
    transaction.set(newRef, {
      name: canonicalName,
      normalizedName,
      slug,
      priority: 0,
      description: "",
      image: "",
      imageUrl: "",
      isActive: defaults.isActive,
      isFeatured: false,
      showOnHome: defaults.showOnHome,
      status: defaults.status,
      autoCreated: true,
      source,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { categoryId: newRef.id, categoryName: canonicalName, createdCategory: true };
  });
}

module.exports = { ensureCategoryExists, defaultsForSource };
