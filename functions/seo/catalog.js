// -----------------------------------------------------------------------------
// Firestore reads for the SEO pages and the sitemap.
//
// Every read goes through `guard`: a Firestore error or a read slower than
// the deadline becomes SeoUnavailableError, which the handlers answer with
// 503 + Retry-After. A temporary backend problem must never look like
// "page not found" (404) or "do not index" to a crawler.
// -----------------------------------------------------------------------------

const { cleanText } = require("./html");

const DEFAULT_DEADLINE_MS = 8000;

class SeoUnavailableError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = "SeoUnavailableError";
    if (cause) this.cause = cause;
  }
}

/** [promise], or SeoUnavailableError on failure or after [ms]. */
function guard(promise, label, ms = DEFAULT_DEADLINE_MS) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new SeoUnavailableError(`${label}: timed out after ${ms} ms`)), ms);
  });
  return Promise.race([Promise.resolve(promise), timeout])
    .catch((error) => {
      if (error instanceof SeoUnavailableError) throw error;
      throw new SeoUnavailableError(`${label}: ${error?.message || error}`, error);
    })
    .finally(() => clearTimeout(timer));
}

const rows = (snap) => snap.docs.map((d) => ({ ...(d.data() || {}), id: d.id }));

// Fields the list pages and the sitemap use (visibility rule, link text,
// display price, dates): about 1/5 of the full product documents.
const LIST_FIELDS = [
  "name", "category", "subcategoryId",
  "isActive", "approvalStatus", "isVisible", "isPublished", "hiddenReason",
  "price", "piecePrice", "oldPrice", "mrp", "unit", "variants",
  "createdAt", "updatedAt",
];
const listOnly = (query) => (typeof query.select === "function" ? query.select(...LIST_FIELDS) : query);

function createCatalog(db, { deadlineMs = DEFAULT_DEADLINE_MS } = {}) {
  const g = (promise, label) => guard(promise, label, deadlineMs);
  return {
    /** All category docs (small collection). */
    categories: () => g(db.collection("categories").get().then(rows), "categories"),

    subcategories: () => g(db.collection("subcategories").get().then(rows), "subcategories"),

    /** Active products of one category (the shop rule filters the rest). */
    categoryProducts: (categoryName) =>
      g(listOnly(db.collection("products")
        .where("category", "==", categoryName)
        .where("isActive", "==", true))
        .get().then(rows), "categoryProducts"),

    /** Active + approved products: the candidates for sitemap and home. */
    listedProducts: () =>
      g(listOnly(db.collection("products")
        .where("isActive", "==", true)
        .where("approvalStatus", "==", "approved"))
        .get().then(rows), "listedProducts"),

    /**
     * Product by document id, else by an id/productId/sku field (some old
     * admin imports). null when it does not exist.
     */
    product: (productId) => g((async () => {
      const doc = await db.collection("products").doc(productId).get();
      if (doc.exists) return { ...(doc.data() || {}), id: doc.id };
      for (const field of ["id", "productId", "sku"]) {
        const snap = await db.collection("products").where(field, "==", productId).limit(1).get();
        if (!snap.empty) return { ...(snap.docs[0].data() || {}), id: snap.docs[0].id };
      }
      return null;
    })(), "product"),

    /** Contact phone/email shown in the policy texts (settings/app). */
    contacts: () => g(db.collection("settings").doc("app").get().then((doc) => {
      const data = (doc.exists && doc.data()) || {};
      return {
        phone: cleanText(data.supportPhone),
        email: cleanText(data.email || data.supportEmail),
      };
    }), "contacts"),
  };
}

module.exports = { createCatalog, guard, SeoUnavailableError, DEFAULT_DEADLINE_MS, LIST_FIELDS };
