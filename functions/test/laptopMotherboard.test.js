// Audit #10: laptop boards go to Motherboard › Laptop Motherboard, from the
// title (whatever category the supplier sent) and from alias names.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const { matchTaxonomyOverride } = require("../category/aliExpressCategoryKeywords");
const { resolveTaxonomyRedirect } = require("../category/categoryAliasMap");

const LAPTOP = { categoryName: "Motherboard", subcategoryName: "Laptop Motherboard" };

test("laptop board titles are forced to Motherboard › Laptop Motherboard", () => {
  assert.deepEqual(matchTaxonomyOverride("KoCoQin Laptop motherboard For HP Probook 15-D 250 G2 HM76 SLJ8E Mainboard"), LAPTOP);
  assert.deepEqual(matchTaxonomyOverride("Mainboard for Lenovo ThinkPad T480 i5-8350U"), LAPTOP);
  assert.deepEqual(matchTaxonomyOverride("MacBook Pro A1708 logic board 2017"), LAPTOP);
});

test("phone boards and other laptop parts are not", () => {
  assert.equal(matchTaxonomyOverride("Fully Tested Motherboard For iPhone 12 Pro Max"), null);
  assert.equal(matchTaxonomyOverride("Laptop keyboard for HP Probook 450 G5"), null);
  assert.equal(matchTaxonomyOverride("Netac SSD 128GB for laptop"), null);
});

test("alias names as category or subcategory land in the same place", () => {
  assert.deepEqual(resolveTaxonomyRedirect("Laptop Mainboard", ""), LAPTOP);
  assert.deepEqual(resolveTaxonomyRedirect("Computer Parts", "laptop motherboard"), LAPTOP);
  assert.deepEqual(resolveTaxonomyRedirect("Mobile Parts", "Motherboard & Mainboard"), { categoryName: "Motherboard", subcategoryName: "" });
});
