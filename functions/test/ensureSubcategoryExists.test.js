const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { FakeFirestore } = require("./helpers/fakeFirestore");
const { ensureSubcategoryExists } = require("../category/ensureSubcategoryExists");

describe("ensureSubcategoryExists", () => {
  test("existing subcategory under the same category is reused", async () => {
    const db = new FakeFirestore();
    db._seed("subcategories", "sub_1", {
      categoryId: "cat_1",
      name: "Mobile Parts",
      normalizedName: "mobile parts",
      slug: "mobile-parts",
    });

    const result = await ensureSubcategoryExists(db, "cat_1", "Electronics", "mobile parts", { source: "admin" });
    assert.equal(result.subcategoryId, "sub_1");
    assert.equal(result.createdSubcategory, false);
  });

  test("same subcategory name under a DIFFERENT category is a separate document", async () => {
    const db = new FakeFirestore();
    db._seed("subcategories", "sub_1", {
      categoryId: "cat_1",
      name: "Accessories",
      normalizedName: "accessories",
      slug: "accessories",
    });

    const result = await ensureSubcategoryExists(db, "cat_2", "Fashion", "Accessories", { source: "admin" });
    assert.notEqual(result.subcategoryId, "sub_1");
    assert.equal(result.createdSubcategory, true);
    assert.equal(Object.keys(db._collections.subcategories).length, 2);
  });

  test("missing subcategory is created exactly once, scoped to its category", async () => {
    const db = new FakeFirestore();
    const result = await ensureSubcategoryExists(db, "cat_1", "Electronics", "Mobile Parts", { source: "admin" });
    const stored = db._collections.subcategories[result.subcategoryId];
    assert.equal(stored.categoryId, "cat_1");
    assert.equal(stored.categoryName, "Electronics");
    assert.equal(stored.name, "Mobile Parts");
    assert.equal(stored.normalizedName, "mobile parts");
    assert.equal(stored.slug, "mobile-parts");
  });

  test("slug collision is scoped per category (numeric suffix only within the same parent)", async () => {
    const db = new FakeFirestore();
    db._seed("subcategories", "existing", { categoryId: "cat_1", name: "Old", normalizedName: "old", slug: "accessories" });

    const sameParent = await ensureSubcategoryExists(db, "cat_1", "Electronics", "Accessories", { source: "admin" });
    assert.equal(db._collections.subcategories[sameParent.subcategoryId].slug, "accessories-2");

    const otherParent = await ensureSubcategoryExists(db, "cat_2", "Fashion", "Accessories", { source: "admin" });
    assert.equal(db._collections.subcategories[otherParent.subcategoryId].slug, "accessories"); // free in cat_2
  });

  test("vendor source defaults to inactive/hidden/pending, same as category tier", async () => {
    const db = new FakeFirestore();
    const result = await ensureSubcategoryExists(db, "cat_1", "Electronics", "Mobile Parts", { source: "vendor" });
    const stored = db._collections.subcategories[result.subcategoryId];
    assert.equal(stored.isActive, false);
    assert.equal(stored.showOnHome, false);
    assert.equal(stored.status, "pending");
  });

  test("missing categoryId returns null — never creates an orphaned subcategory", async () => {
    const db = new FakeFirestore();
    const result = await ensureSubcategoryExists(db, "", "Electronics", "Mobile Parts", { source: "admin" });
    assert.equal(result, null);
    assert.equal(Object.keys(db._collections.subcategories || {}).length, 0);
  });

  test("missing/empty name returns null", async () => {
    const db = new FakeFirestore();
    assert.equal(await ensureSubcategoryExists(db, "cat_1", "Electronics", "", { source: "admin" }), null);
    assert.equal(await ensureSubcategoryExists(db, "cat_1", "Electronics", "   ", { source: "admin" }), null);
  });

  test("a retired (mergedInto) subcategory is not reused; a new one is created", async () => {
    const db = new FakeFirestore();
    db._seed("subcategories", "retired", {
      categoryId: "cat_1", name: "Motherboard & Mainboard", normalizedName: "motherboard & mainboard",
      slug: "motherboard-mainboard", mergedInto: "mb",
    });

    const result = await ensureSubcategoryExists(db, "cat_1", "Mobile Parts", "Motherboard & Mainboard", { source: "admin" });
    assert.notEqual(result.subcategoryId, "retired");
    assert.equal(result.createdSubcategory, true);
  });
});
