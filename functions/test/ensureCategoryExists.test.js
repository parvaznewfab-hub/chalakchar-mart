const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { FakeFirestore } = require("./helpers/fakeFirestore");
const { ensureCategoryExists } = require("../category/ensureCategoryExists");

describe("ensureCategoryExists", () => {
  test("existing exact category is reused (no write)", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "cat_1", { name: "Electronics", normalizedName: "electronics", slug: "electronics" });

    const result = await ensureCategoryExists(db, "Electronics", { source: "admin" });
    assert.equal(result.categoryId, "cat_1");
    assert.equal(result.createdCategory, false);
    assert.equal(Object.keys(db._collections.categories).length, 1); // no new doc
  });

  test("case-insensitive category is reused", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "cat_1", { name: "Electronics", normalizedName: "electronics", slug: "electronics" });

    const result = await ensureCategoryExists(db, "ELECTRONICS", { source: "admin" });
    assert.equal(result.categoryId, "cat_1");
    assert.equal(result.createdCategory, false);
  });

  test("whitespace-normalized category is reused", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "cat_1", { name: "Electronics", normalizedName: "electronics", slug: "electronics" });

    const result = await ensureCategoryExists(db, "  Electronics  ", { source: "admin" });
    assert.equal(result.categoryId, "cat_1");
  });

  test("missing category is created exactly once", async () => {
    const db = new FakeFirestore();
    const result = await ensureCategoryExists(db, "Grocery", { source: "admin" });

    assert.equal(result.createdCategory, true);
    assert.ok(result.categoryId);
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.name, "Grocery");
    assert.equal(stored.normalizedName, "grocery");
    assert.equal(stored.slug, "grocery");
  });

  test("existing category's manually-managed fields are never overwritten", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "cat_1", {
      name: "Electronics",
      normalizedName: "electronics",
      slug: "electronics",
      image: "https://example.com/custom.jpg",
      imageUrl: "https://example.com/custom.jpg",
      priority: 42,
      description: "Hand-written description",
      isFeatured: true,
      isActive: false,
      showOnHome: false,
    });

    await ensureCategoryExists(db, "electronics", { source: "admin" });

    const stored = db._collections.categories.cat_1;
    assert.equal(stored.image, "https://example.com/custom.jpg");
    assert.equal(stored.priority, 42);
    assert.equal(stored.description, "Hand-written description");
    assert.equal(stored.isFeatured, true);
    assert.equal(stored.isActive, false);
    assert.equal(stored.showOnHome, false);
  });

  test("new category defaults to active and showOnHome for admin/manual import sources", async () => {
    const db = new FakeFirestore();
    for (const source of ["admin", "n8n", "csv", "json"]) {
      const result = await ensureCategoryExists(db, `Category ${source}`, { source });
      const stored = db._collections.categories[result.categoryId];
      assert.equal(stored.isActive, true, `${source} should default active`);
      assert.equal(stored.showOnHome, true, `${source} should default showOnHome`);
      assert.equal(stored.status, "active");
      assert.equal(stored.autoCreated, true);
      assert.equal(stored.source, source);
    }
  });

  test("new vendor-sourced category defaults to inactive/hidden/pending", async () => {
    const db = new FakeFirestore();
    const result = await ensureCategoryExists(db, "Vendor Category", { source: "vendor" });
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.isActive, false);
    assert.equal(stored.showOnHome, false);
    assert.equal(stored.status, "pending");
  });

  test("new aliexpress-sourced category defaults to inactive/hidden/pending", async () => {
    const db = new FakeFirestore();
    const result = await ensureCategoryExists(db, "Automotive", { source: "aliexpress" });
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.isActive, false);
    assert.equal(stored.showOnHome, false);
    assert.equal(stored.status, "pending");
    assert.equal(stored.autoCreated, true);
    assert.equal(stored.source, "aliexpress");
  });

  test("alias mapping is applied before dedup/creation", async () => {
    const db = new FakeFirestore();
    const result = await ensureCategoryExists(db, "Cell Phone Parts", { source: "admin" });
    assert.equal(result.categoryName, "Mobile Parts");
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.name, "Mobile Parts");
    assert.equal(stored.normalizedName, "mobile parts");
  });

  test("a second alias submission reuses the same category, not a duplicate", async () => {
    const db = new FakeFirestore();
    const first = await ensureCategoryExists(db, "Cell Phone Parts", { source: "admin" });
    const second = await ensureCategoryExists(db, "Cellphone Parts", { source: "admin" });
    assert.equal(first.categoryId, second.categoryId);
    assert.equal(Object.keys(db._collections.categories).length, 1);
  });

  test("slug collision is resolved with a numeric suffix", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "existing_1", { name: "Mobile Parts Old", normalizedName: "mobile parts old", slug: "mobile-parts" });

    const result = await ensureCategoryExists(db, "Mobile Parts", { source: "admin" });
    const stored = db._collections.categories[result.categoryId];
    assert.equal(stored.slug, "mobile-parts-2");
  });

  test("null/empty/whitespace-only category name returns null (resolver skipped)", async () => {
    const db = new FakeFirestore();
    assert.equal(await ensureCategoryExists(db, "", { source: "admin" }), null);
    assert.equal(await ensureCategoryExists(db, "   ", { source: "admin" }), null);
    assert.equal(await ensureCategoryExists(db, null, { source: "admin" }), null);
    assert.equal(Object.keys(db._collections.categories || {}).length, 0);
  });

  test("a merged-away doc is never reused; the live doc with the same key wins", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "old", { name: "Motherboard", normalizedName: "motherboard", slug: "motherboard", mergedInto: "live" });
    db._seed("categories", "live", { name: "Motherboard", normalizedName: "motherboard", slug: "motherboard-2" });

    const result = await ensureCategoryExists(db, "Motherboard", { source: "aliexpress" });
    assert.equal(result.categoryId, "live");
    assert.equal(result.createdCategory, false);
  });

  test("a merged-away doc that still carries the key is followed to its mergedInto target", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "old", { name: "Electronics", normalizedName: "electronics", mergedInto: "canon" });
    db._seed("categories", "canon", { name: "Electronics" }); // no normalizedName yet

    const result = await ensureCategoryExists(db, "electronics", { source: "aliexpress" });
    assert.equal(result.categoryId, "canon");
    assert.equal(result.createdCategory, false);
    assert.equal(Object.keys(db._collections.categories).length, 2);
  });

  test("before any merge (no mergedInto anywhere) lookup behaves as before", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "a", { name: "Home & Cleaning", normalizedName: "home & cleaning" });

    const result = await ensureCategoryExists(db, "home &  cleaning", { source: "aliexpress" });
    assert.equal(result.categoryId, "a");
    assert.equal(result.createdCategory, false);
  });

  test("motherboard aliases resolve to the existing Motherboard category", async () => {
    const db = new FakeFirestore();
    db._seed("categories", "mb", { name: "Motherboard", normalizedName: "motherboard" });

    for (const name of ["Mainboard", "Motherboard & Mainboard", "logic board"]) {
      const result = await ensureCategoryExists(db, name, { source: "aliexpress" });
      assert.equal(result.categoryId, "mb", name);
    }
  });
});
