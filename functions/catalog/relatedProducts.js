// -----------------------------------------------------------------------------
// The product page's two related rows, for productSeo's HTML links. Same
// rules as lib/utils/related_products.dart (the Flutter page):
//   1) shared model key; < 2 -> shared series, titled "{series} সিরিজের আরও
//      পার্টস"; < 2 -> none.
//   2) same subcategory (else category), nearest price, max 12, not in row 1.
// Never the product itself; only shop-visible products; in stock first.
// -----------------------------------------------------------------------------

const { modelFieldsForName } = require("./deviceModel");

const ROW_MAX = 12;
const MODEL_ROW_MIN = 2;

const text = (v) => String(v ?? "").trim();

function modelKeysOf(p) {
  return Array.isArray(p.modelKeys) && p.modelKeys.length ? p.modelKeys : modelFieldsForName(p.name).modelKeys;
}

function modelSeriesOf(p) {
  return Array.isArray(p.modelSeries) && p.modelSeries.length ? p.modelSeries : modelFieldsForName(p.name).modelSeries;
}

/** Brands named by the model keys: "iphone 12" -> iphone, "samsung a52s" -> samsung. */
function brandsOf(p) {
  return new Set(modelKeysOf(p).map((k) => k.split(" ")[0]));
}

function displayModelName(key) {
  return key.split(" ").map((w) => {
    if (w === "iphone") return "iPhone";
    if (/^[a-z]{1,2}$/.test(w) || /^[a-z]\d/.test(w)) return w.toUpperCase();
    if (!w || /^\d/.test(w)) return w;
    return w[0].toUpperCase() + w.slice(1);
  }).join(" ");
}

/**
 * @param {object} opts
 * @param {object} opts.current product with .id
 * @param {object[]} opts.exactCandidates / seriesCandidates / similarCandidates (with .id)
 * @param {(p: object) => boolean} opts.isVisible shop visibility
 * @param {(p: object) => number} opts.price display price
 * @param {(p: object) => number} opts.stock
 * @returns {{ modelRow: {title: string, products: object[]} | null, similar: object[] }}
 */
function pickRelatedRows({ current, exactCandidates = [], seriesCandidates = [], similarCandidates = [], isVisible, price, stock }) {
  const clean = (list, exclude = new Set()) => {
    const seen = new Set([text(current.id), ...exclude]);
    return list.filter((p) => {
      const id = text(p.id);
      if (seen.has(id)) return false;
      seen.add(id);
      return isVisible(p);
    });
  };
  const inStockFirst = (list) => [...list.filter((p) => stock(p) > 0), ...list.filter((p) => stock(p) <= 0)];

  let modelRow = null;
  const keys = new Set(modelKeysOf(current));
  if (keys.size) {
    const exact = clean(exactCandidates).filter((p) => modelKeysOf(p).some((k) => keys.has(k)));
    if (exact.length >= MODEL_ROW_MIN) {
      modelRow = { title: "এই মডেলের আরও পার্টস", products: inStockFirst(exact).slice(0, ROW_MAX) };
    } else {
      const series = modelSeriesOf(current);
      const set = new Set(series);
      const inSeries = clean(seriesCandidates).filter((p) => modelSeriesOf(p).some((s) => set.has(s)));
      if (inSeries.length >= MODEL_ROW_MIN) {
        const shared = series.filter((s) => inSeries.some((p) => modelSeriesOf(p).includes(s)));
        const label = shared.slice(0, 2).map(displayModelName).join(" / ");
        modelRow = { title: `${label} সিরিজের আরও পার্টস`, products: inStockFirst(inSeries).slice(0, ROW_MAX) };
      }
    }
  }

  const subcategoryId = text(current.subcategoryId);
  const category = text(current.category).toLowerCase();
  const target = price(current);
  const exclude = new Set((modelRow?.products || []).map((p) => text(p.id)));
  // Same brand first (iPhone page: iPhone displays before Samsung), then
  // nearest price; in stock before out of stock above both.
  const brands = brandsOf(current);
  const sameBrand = (p) => (brands.size && [...brandsOf(p)].some((b) => brands.has(b)) ? 0 : 1);
  const similar = clean(similarCandidates, exclude)
    .filter((p) => (subcategoryId ? text(p.subcategoryId) === subcategoryId : text(p.category).toLowerCase() === category))
    .sort((a, b) => sameBrand(a) - sameBrand(b) || Math.abs(price(a) - target) - Math.abs(price(b) - target));

  return { modelRow, similar: inStockFirst(similar).slice(0, ROW_MAX) };
}

module.exports = { pickRelatedRows, displayModelName, modelKeysOf, modelSeriesOf, brandsOf };
