const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { FakeFirestore } = require("./helpers/fakeFirestore");
const { resolveProductTaxonomy } = require("../category/resolveProductTaxonomy");

describe("resolveProductTaxonomy", () => {
  test("resolves both category and subcategory together", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "Electronics", "Mobile Parts", { source: "admin" });

    assert.ok(result.categoryId);
    assert.equal(result.categoryName, "Electronics");
    assert.ok(result.subcategoryId);
    assert.equal(result.createdCategory, true);
    assert.equal(result.createdSubcategory, true);

    const storedSub = db._collections.subcategories[result.subcategoryId];
    assert.equal(storedSub.categoryId, result.categoryId);
  });

  test("invariant: subcategoryId is never set without categoryId — empty category input skips everything and flags for review", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "", "Mobile Parts", { source: "admin" });

    assert.equal(result.categoryId, null);
    assert.equal(result.categoryName, "Uncategorized");
    assert.equal(result.subcategoryId, null);
    assert.equal(result.createdCategory, false);
    assert.equal(result.createdSubcategory, false);
    assert.equal(result.needsCategoryReview, true);
    assert.equal(Object.keys(db._collections.categories || {}).length, 0);
    assert.equal(Object.keys(db._collections.subcategories || {}).length, 0);
  });

  test("whitespace-only category input is validated, skips the resolver completely, and flags Uncategorized/needsCategoryReview", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "   ", "", { source: "admin" });
    assert.deepEqual(result, {
      categoryId: null,
      categoryName: "Uncategorized",
      subcategoryId: null,
      createdCategory: false,
      createdSubcategory: false,
      needsCategoryReview: true,
    });
  });

  test("resolved category never carries needsCategoryReview", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "Electronics", "", { source: "aliexpress" });
    assert.equal(result.needsCategoryReview, false);
    assert.equal(result.categoryName, "Electronics");
  });

  test("category resolves but no subcategory input given — subcategoryId stays null", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "Grocery", "", { source: "admin" });
    assert.ok(result.categoryId);
    assert.equal(result.subcategoryId, null);
    assert.equal(result.createdSubcategory, false);
  });

  test("n8n-as-a-source-value source follows admin (visible) defaults", async () => {
    const db = new FakeFirestore();
    const result = await resolveProductTaxonomy(db, "Category n8n", "", { source: "n8n" });
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.isActive, true);
    assert.equal(stored.showOnHome, true);
  });

  test("vendor and aliexpress sources produce a hidden/pending category and subcategory", async () => {
    const db = new FakeFirestore();
    for (const source of ["vendor", "aliexpress"]) {
      const result = await resolveProductTaxonomy(db, `New ${source} Category`, `New ${source} Sub`, { source });

      const storedCat = db._collections.categories[result.categoryId];
      const storedSub = db._collections.subcategories[result.subcategoryId];
      assert.equal(storedCat.isActive, false, `${source} category should be hidden`);
      assert.equal(storedCat.status, "pending");
      assert.equal(storedSub.isActive, false, `${source} subcategory should be hidden`);
      assert.equal(storedSub.status, "pending");
    }
  });

  test("a second call with an equivalent (differently-cased/spaced) name reuses the same taxonomy, not duplicates", async () => {
    const db = new FakeFirestore();
    const first = await resolveProductTaxonomy(db, "Electronics", "Mobile Parts", { source: "admin" });
    const second = await resolveProductTaxonomy(db, " electronics ", "mobile   parts", { source: "admin" });

    assert.equal(first.categoryId, second.categoryId);
    assert.equal(first.subcategoryId, second.subcategoryId);
    assert.equal(second.createdCategory, false);
    assert.equal(second.createdSubcategory, false);
    assert.equal(Object.keys(db._collections.categories).length, 1);
    assert.equal(Object.keys(db._collections.subcategories).length, 1);
  });
});
