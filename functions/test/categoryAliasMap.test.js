const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { resolveCategoryAlias } = require("../category/categoryAliasMap");

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
});
