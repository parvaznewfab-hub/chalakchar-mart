// -----------------------------------------------------------------------------
// HTTP handlers for productSeo, pageSeo, homeSeo and sitemap
// (functions/index.js wires them to onRequest). Status rules:
//
//   page exists, shop shows it ........ 200 + index
//   exists but hidden / empty category  200 + noindex (link still opens)
//   does not exist .................... 404 + noindex
//   Firestore error or slow read ...... 503 + Retry-After, never noindex
//
// `deps`: { db, logger, relatedHtml?(product), reviews?(productId, name) }.
// -----------------------------------------------------------------------------

const { cleanText, seoSlug } = require("./html");
const {
  activeCategoryNames, isProductIndexable, isCategoryIndexable, findActiveCategoryBySlug,
} = require("./indexable");
const { createCatalog, SeoUnavailableError } = require("./catalog");
const pages = require("./pages");

const RETRY_AFTER_SECONDS = "120";

// The date the policy texts last changed (lib/pages/user/policy_texts.dart);
// the sitemap's lastmod for those pages. functions/test/seoPolicyTexts.test.js
// fails when the Dart file has a newer commit than this.
const POLICY_LAST_MODIFIED = "2026-11-27";

function sendHtml(res, status, html, { cache, robotsHeader } = {}) {
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Cache-Control", cache || "public, max-age=300, s-maxage=600");
  if (robotsHeader) res.set("X-Robots-Tag", robotsHeader);
  return res.status(status).send(html);
}

function sendUnavailable(res, path, logger, error) {
  logger.warn("SEO page unavailable (503)", { path, message: error?.message || String(error) });
  res.set("Retry-After", RETRY_AFTER_SECONDS);
  return sendHtml(res, 503, pages.renderUnavailablePage(path), { cache: "no-store" });
}

/** Any failure while answering: 503 (data) or 500 (bug); never noindex. */
function sendFailure(res, path, logger, error) {
  if (error instanceof SeoUnavailableError) return sendUnavailable(res, path, logger, error);
  logger.error("SEO page render failed", { path, message: error?.message || String(error), stack: error?.stack });
  return sendHtml(res, 500, pages.renderUnavailablePage(path), { cache: "no-store" });
}

function requestPath(req) {
  let raw = String(req.path || req.url || "/").split("?")[0].split("#")[0];
  try {
    raw = decodeURIComponent(raw);
  } catch (_) {
    // keep as is
  }
  return raw.replace(/\/+$/, "") || "/";
}

// -----------------------------------------------------------------------------

/** /product/ID (also /ID and /productSeo/product/ID from the function URL). */
async function productSeo(req, res, deps) {
  const path = requestPath(req);
  const { logger } = deps;
  try {
    const parts = path.split("/").map((p) => p.trim()).filter(Boolean)
      .filter((p) => p !== "product" && p !== "productSeo");
    const productId = cleanText(parts[parts.length - 1]);
    if (!productId) {
      return sendHtml(res, 404, pages.renderNotFoundPage(path, "product"), { robotsHeader: "noindex" });
    }
    const catalog = createCatalog(deps.db, deps);
    const [product, categories] = await Promise.all([catalog.product(productId), catalog.categories()]);
    if (!product) {
      logger.warn("Product SEO not found", { path, productId });
      return sendHtml(res, 404, pages.renderNotFoundPage(path, "product"), { cache: "no-store", robotsHeader: "noindex" });
    }
    const active = activeCategoryNames(categories);
    const indexable = isProductIndexable(product, active);
    const category = categories.find((c) => cleanText(c.name).toLowerCase() === cleanText(product.category).toLowerCase()) || null;
    let subcategory = null;
    if (cleanText(product.subcategoryId)) {
      const subs = await catalog.subcategories();
      subcategory = subs.find((s) => s.id === product.subcategoryId) || null;
    }
    const name = cleanText(product.name, "Product");
    const [relatedHtml, reviews] = await Promise.all([
      indexable && deps.relatedHtml ? deps.relatedHtml(product).catch(() => "") : "",
      deps.reviews ? deps.reviews(product.id, name).catch(() => []) : [],
    ]);
    const html = pages.renderProductPage({ product, category, subcategory, indexable, relatedHtml, reviews });
    return sendHtml(res, 200, html, {
      cache: "public, max-age=300, s-maxage=600",
      robotsHeader: indexable ? null : "noindex, nofollow",
    });
  } catch (error) {
    return sendFailure(res, path, logger, error);
  }
}

/** /category/*, /about-us, /privacy-policy, /terms-conditions, /return-policy, /data-deletion. */
async function pageSeo(req, res, deps) {
  const path = requestPath(req);
  const { logger } = deps;
  try {
    const catalog = createCatalog(deps.db, deps);
    if (pages.POLICY_PAGE_SEO[path]) {
      const contacts = await catalog.contacts();
      return sendHtml(res, 200, pages.renderPolicyPage(path, contacts), { cache: "public, max-age=600, s-maxage=3600" });
    }

    const match = path.match(/^\/category\/([^/]+)$/);
    const slug = match ? seoSlug(match[1]) : "";
    if (!slug) {
      return sendHtml(res, 404, pages.renderNotFoundPage(path), { robotsHeader: "noindex" });
    }

    const categories = await catalog.categories();
    const category = findActiveCategoryBySlug(categories, slug);
    if (!category) {
      // Unknown or switched off: the app still opens (it shows its own
      // "not found"), but search engines must not index it.
      return sendHtml(res, 404, pages.renderNotFoundPage(path), { robotsHeader: "noindex" });
    }

    const active = activeCategoryNames(categories);
    const [candidates, subcategories] = await Promise.all([
      catalog.categoryProducts(category.name),
      catalog.subcategories(),
    ]);
    const products = candidates.filter((p) => isProductIndexable(p, active));
    const indexable = isCategoryIndexable(category, products.length);
    const html = pages.renderCategoryPage({ category, products, subcategories, indexable });
    return sendHtml(res, 200, html, {
      cache: "public, max-age=600, s-maxage=1800",
      robotsHeader: indexable ? null : "noindex",
    });
  } catch (error) {
    return sendFailure(res, path, logger, error);
  }
}

/**
 * Home HTML with category and newest-product links. Note: Firebase Hosting
 * serves the static build/web/index.html for "/" before any rewrite, so
 * this runs only when called directly (or if "/" is routed here later).
 */
async function homeSeo(req, res, deps) {
  const { logger } = deps;
  try {
    const catalog = createCatalog(deps.db, deps);
    const [categories, products] = await Promise.all([catalog.categories(), catalog.listedProducts()]);
    const html = pages.renderHomePage({ categories, products, activeCategoriesLower: activeCategoryNames(categories) });
    return sendHtml(res, 200, html, { cache: "public, max-age=600, s-maxage=1800" });
  } catch (error) {
    return sendFailure(res, "/", logger, error);
  }
}

/** /sitemap.xml */
async function sitemap(req, res, deps) {
  const { logger } = deps;
  try {
    const catalog = createCatalog(deps.db, deps);
    const [categories, products] = await Promise.all([catalog.categories(), catalog.listedProducts()]);
    const xml = pages.renderSitemap({
      categories,
      products,
      activeCategoriesLower: activeCategoryNames(categories),
      policyLastModified: new Date(`${POLICY_LAST_MODIFIED}T00:00:00Z`),
    });
    res.set("Content-Type", "application/xml; charset=utf-8");
    res.set("Cache-Control", "public, max-age=3600, s-maxage=3600");
    return res.status(200).send(xml);
  } catch (error) {
    const unavailable = error instanceof SeoUnavailableError;
    (unavailable ? logger.warn : logger.error)("Sitemap failed", { message: error?.message || String(error) });
    if (unavailable) res.set("Retry-After", RETRY_AFTER_SECONDS);
    res.set("Content-Type", "text/plain; charset=utf-8");
    res.set("Cache-Control", "no-store");
    return res.status(unavailable ? 503 : 500).send("Sitemap temporarily unavailable");
  }
}

module.exports = {
  productSeo,
  pageSeo,
  homeSeo,
  sitemap,
  requestPath,
  POLICY_LAST_MODIFIED,
  RETRY_AFTER_SECONDS,
};
