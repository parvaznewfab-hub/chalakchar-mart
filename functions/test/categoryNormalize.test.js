const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeCategoryKey,
  slugifyCategoryName,
  generateUniqueSlug,
} = require("../category/categoryNormalize");

describe("normalizeCategoryKey", () => {
  test("all case/spacing variants of a name normalize to the same key", () => {
    const variants = ["Electronics", "electronics", "ELECTRONICS", " Electronics ", "Electronics  "];
    const keys = variants.map(normalizeCategoryKey);
    for (const key of keys) assert.equal(key, keys[0]);
    assert.equal(keys[0], "electronics");
  });

  test("collapses repeated internal whitespace", () => {
    assert.equal(normalizeCategoryKey("Mobile   Parts"), "mobile parts");
  });

  test("empty/whitespace-only input returns empty string", () => {
    assert.equal(normalizeCategoryKey(""), "");
    assert.equal(normalizeCategoryKey("   "), "");
    assert.equal(normalizeCategoryKey(null), "");
    assert.equal(normalizeCategoryKey(undefined), "");
  });
});

describe("slugifyCategoryName", () => {
  test("converts to kebab-case", () => {
    assert.equal(slugifyCategoryName("Mobile Parts"), "mobile-parts");
  });

  test("strips non-alphanumeric characters", () => {
    assert.equal(slugifyCategoryName("Mobile & Parts!"), "mobile-parts");
  });

  test("empty input returns empty string", () => {
    assert.equal(slugifyCategoryName(""), "");
  });
});

describe("generateUniqueSlug", () => {
  test("uses the base slug when free", async () => {
    const slug = await generateUniqueSlug("Mobile Parts", async () => false);
    assert.equal(slug, "mobile-parts");
  });

  test("appends -2, -3 on collision", async () => {
    const taken = new Set(["mobile-parts", "mobile-parts-2"]);
    const slug = await generateUniqueSlug("Mobile Parts", async (candidate) => taken.has(candidate));
    assert.equal(slug, "mobile-parts-3");
  });

  test("throws after exhausting max attempts rather than looping forever", async () => {
    await assert.rejects(
      () => generateUniqueSlug("X", async () => true, { maxAttempts: 3 }),
      /exhausted/
    );
  });
});
