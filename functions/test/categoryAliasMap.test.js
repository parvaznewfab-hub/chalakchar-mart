const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { resolveCategoryAlias, resolveTaxonomyRedirect } = require("../category/categoryAliasMap");

describe("resolveCategoryAlias", () => {
  test("maps known aliases to their canonical category", async () => {
    assert.equal(await resolveCategoryAlias("Cell Phone Parts"), "Mobile Parts");
    assert.equal(await resolveCategoryAlias("Cellphone Parts"), "Mobile Parts");
    assert.equal(await resolveCategoryAlias("Mobile Phone Parts"), "Mobile Parts");
    assert.equal(await resolveCategoryAlias("Mobile Phone Accessories"), "Accessories");
  });

  test("alias matching is case/whitespace-insensitive", async () => {
    assert.equal(await resolveCategoryAlias("  cell phone PARTS  "), "Mobile Parts");
  });

  test("unknown names pass through unchanged (trimmed)", async () => {
    assert.equal(await resolveCategoryAlias("Electronics"), "Electronics");
    assert.equal(await resolveCategoryAlias("  Grocery  "), "Grocery");
  });

  test("empty input returns empty string", async () => {
    assert.equal(await resolveCategoryAlias(""), "");
    assert.equal(await resolveCategoryAlias(null), "");
  });

  test("motherboard/mainboard names alias to top-level Motherboard", async () => {
    assert.equal(await resolveCategoryAlias("Motherboard & Mainboard"), "Motherboard");
    assert.equal(await resolveCategoryAlias("Mainboard"), "Motherboard");
    assert.equal(await resolveCategoryAlias("Logic Board"), "Motherboard");
    assert.equal(await resolveCategoryAlias("Motherboard"), "Motherboard");
  });

  test("resolveTaxonomyRedirect turns a motherboard subcategory into the Motherboard category", () => {
    assert.deepEqual(resolveTaxonomyRedirect("Mobile Parts", "Motherboard & Mainboard"), { categoryName: "Motherboard", subcategoryName: "" });
    assert.deepEqual(resolveTaxonomyRedirect("Mobile Parts", "  mainboard "), { categoryName: "Motherboard", subcategoryName: "" });
    assert.deepEqual(resolveTaxonomyRedirect("Mobile Parts", "Display & Digitizer"), { categoryName: "Mobile Parts", subcategoryName: "Display & Digitizer" });
    assert.deepEqual(resolveTaxonomyRedirect("Motherboard", "iphone"), { categoryName: "Motherboard", subcategoryName: "iphone" });
  });
});
