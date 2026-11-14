const test = require("node:test");
const assert = require("node:assert");
const { taxonomyPromptBlock, matchAiTaxonomy } = require("../category/aiTaxonomy");

const taxonomy = [
  {
    id: "cat-mp",
    name: "Mobile Parts",
    subcategories: [
      { id: "sub-disp", name: "Display & Digitizer" },
      { id: "sub-usb", name: "USB Charging port board" },
    ],
  },
  { id: "cat-ca", name: "Computer Accessories", subcategories: [] },
];

test("exact category and subcategory match returns ids and canonical names", () => {
  assert.deepStrictEqual(matchAiTaxonomy(taxonomy, "Mobile Parts", "Display & Digitizer"), {
    matched: true,
    categoryId: "cat-mp",
    categoryName: "Mobile Parts",
    subcategoryId: "sub-disp",
    subcategoryName: "Display & Digitizer",
  });
});

test("matching ignores case, spacing and & vs and", () => {
  const m = matchAiTaxonomy(taxonomy, "  mobile parts ", "display and digitizer");
  assert.strictEqual(m.categoryId, "cat-mp");
  assert.strictEqual(m.subcategoryId, "sub-disp");
  assert.strictEqual(m.categoryName, "Mobile Parts");
});

test("unknown category clears both, even if the subcategory name exists elsewhere", () => {
  assert.deepStrictEqual(matchAiTaxonomy(taxonomy, "Electronics", "Display & Digitizer"), {
    matched: false,
    categoryId: "",
    categoryName: "",
    subcategoryId: "",
    subcategoryName: "",
  });
});

test("unknown subcategory under a known category keeps the category only", () => {
  const m = matchAiTaxonomy(taxonomy, "Computer Accessories", "Storage Devices");
  assert.strictEqual(m.matched, true);
  assert.strictEqual(m.categoryId, "cat-ca");
  assert.strictEqual(m.subcategoryId, "");
});

test("a subcategory of another category is not accepted", () => {
  const m = matchAiTaxonomy(taxonomy, "Computer Accessories", "USB Charging port board");
  assert.strictEqual(m.categoryId, "cat-ca");
  assert.strictEqual(m.subcategoryId, "");
});

test("prompt block lists every category with its subcategories", () => {
  const block = taxonomyPromptBlock(taxonomy);
  assert.match(block, /- Mobile Parts \(subcategories: Display & Digitizer \| USB Charging port board\)/);
  assert.match(block, /- Computer Accessories \(no subcategories\)/);
  assert.match(block, /Never invent/);
});

test("empty taxonomy tells the model to return empty strings", () => {
  assert.match(taxonomyPromptBlock([]), /return empty strings/);
});
