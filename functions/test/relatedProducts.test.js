const test = require("node:test");
const assert = require("node:assert/strict");
const { pickRelatedRows, displayModelName } = require("../catalog/relatedProducts");

const P = (id, name, extra = {}) => ({ id, name, category: "Mobile Parts", subcategoryId: "display", price: 2000, stock: 5, ...extra });
const base = { isVisible: (p) => p.hidden !== true, price: (p) => p.price, stock: (p) => p.stock };

test("iPhone 12 Display: Pro Max parts are not in the 'this model' row", () => {
  const current = P("d12", "iPhone 12 12 Pro LCD Display");
  const all = [current, P("b12", "Motherboard For iPhone 12 64g"), P("d12all", "Screen for IPhone 12/12Pro/12ProMax"),
    P("b12pm", "Motherboard For iPhone 12 Pro Max"), P("b12pm2", "Board For iPhone 12 Pro Max")];
  const { modelRow, similar } = pickRelatedRows({ ...base, current, exactCandidates: all, seriesCandidates: all, similarCandidates: all });
  assert.equal(modelRow.title, "এই মডেলের আরও পার্টস");
  assert.deepEqual(modelRow.products.map((p) => p.id).sort(), ["b12", "d12all"]);
  // Row 2 never repeats row 1 or the product itself.
  assert.deepEqual(similar.map((p) => p.id).sort(), ["b12pm", "b12pm2"]);
});

test("series fallback title, hidden below 2, hidden/out-of-stock rules", () => {
  const current = P("pm", "Motherboard For iPhone 12 Pro Max");
  const series = [P("a", "For iPhone 12 64g", { stock: 0 }), P("b", "For iPhone 12 Mini"), P("h", "For iPhone 12 Pro", { hidden: true })];
  const { modelRow } = pickRelatedRows({ ...base, current, exactCandidates: [], seriesCandidates: series });
  assert.equal(modelRow.title, "iPhone 12 সিরিজের আরও পার্টস");
  assert.deepEqual(modelRow.products.map((p) => p.id), ["b", "a"]);
  const none = pickRelatedRows({ ...base, current, exactCandidates: [], seriesCandidates: [series[0]] });
  assert.equal(none.modelRow, null);
});

test("displayModelName", () => {
  assert.equal(displayModelName("iphone 12"), "iPhone 12");
  assert.equal(displayModelName("huawei p30"), "Huawei P30");
  assert.equal(displayModelName("samsung a52"), "Samsung A52");
});

test("similar row: same brand first, then nearest price; in stock first; no brand -> price only", () => {
  const S = (id, name, price, stock = 5) => P(id, name, { price, stock });
  const current = S("c", "iPhone 12 12 Pro LCD Display", 2400);
  const all = [S("sam", "LCD For Samsung Galaxy A14", 2390), S("ip8", "LCD for iPhone 8 SE 2020", 2100),
    S("ip11", "LCD for iPhone XR 11", 2600), S("hot", "FOR Hotwav Cyber 7 LCD", 2400), S("ipOut", "LCD for iPhone 6 Plus", 2400, 0)];
  const ids = (cur) => pickRelatedRows({ ...base, current: cur, similarCandidates: all }).similar.map((p) => p.id);
  assert.deepEqual(ids(current), ["ip11", "ip8", "hot", "sam", "ipOut"]);
  assert.deepEqual(ids(S("s", "Netac SSD 1TB", 2400)).slice(0, 2), ["hot", "sam"]);
});
