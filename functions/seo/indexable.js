// -----------------------------------------------------------------------------
// The one rule for "may search engines index this page", shared by the SEO
// pages (productSeo, pageSeo, homeSeo) and the sitemap, so the sitemap never
// lists a URL whose page says noindex.
//
// isProductIndexable is the shop's own rule, copied exactly from
// lib/utils/shop_visibility.dart isShopVisibleProduct (change both together):
// active, approved, not invisible/unpublished, no hiddenReason, and its
// category is a switched-on category. needsReview is a marketing gate, not a
// shop filter, so it is not checked.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

const { cleanText, seoSlug } = require("./html");

/** A category the shop treats as switched on (CategoryModel.isActive). */
function isCategoryActive(category) {
  return Boolean(category) && category.isActive === true;
}

/** Lower-cased names of the switched-on categories in [categories]. */
function activeCategoryNames(categories) {
  return new Set(
    (categories || [])
      .filter(isCategoryActive)
      .map((c) => cleanText(c.name).toLowerCase())
      .filter(Boolean)
  );
}

/** isShopVisibleProduct: the product shoppers see in the shop. */
function isProductIndexable(product, activeCategoriesLower) {
  if (!product) return false;
  if (product.isActive !== true) return false;
  if (product.approvalStatus !== "approved") return false;
  if (product.isVisible === false || product.isPublished === false) return false;
  if (cleanText(product.hiddenReason)) return false;
  return activeCategoriesLower.has(cleanText(product.category).toLowerCase());
}

/** Switched on and at least one product the shop shows in it. */
function isCategoryIndexable(category, visibleProductCount) {
  return isCategoryActive(category) && Number(visibleProductCount) > 0;
}

/** A subcategory the shop lists (SubcategoryModel.isActive). */
function isSubcategoryActive(sub) {
  return Boolean(sub) && sub.isActive === true && !cleanText(sub.mergedInto) && Boolean(cleanText(sub.categoryId));
}

function subcategorySlug(sub) {
  return cleanText(sub.slug) || seoSlug(sub.name);
}

/**
 * The switched-on category for URL [slug], as the category page picks it:
 * active categories by priority, first whose name has that slug. null when
 * none (unknown or switched off).
 */
function findActiveCategoryBySlug(categories, slug) {
  if (!slug) return null;
  const active = (categories || [])
    .filter(isCategoryActive)
    .sort((a, b) => (Number(a.priority) || 0) - (Number(b.priority) || 0));
  return active.find((c) => seoSlug(c.name) === slug) || null;
}

module.exports = {
  isCategoryActive,
  activeCategoryNames,
  isProductIndexable,
  isCategoryIndexable,
  isSubcategoryActive,
  subcategorySlug,
  findActiveCategoryBySlug,
};
