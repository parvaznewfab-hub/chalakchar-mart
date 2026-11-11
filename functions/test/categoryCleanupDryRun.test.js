const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { buildCleanupPlan, renderMarkdown } = require("../scripts/categoryCleanupDryRun");

const ts = (iso) => ({ toMillis: () => Date.parse(iso) });

function fixture() {
  return {
    categories: [
      { id: "mA", name: "Mobile Accessories", isActive: true, showOnHome: true, image: "a.jpg", createdAt: ts("2025-01-01"), normalizedName: "mobile accessories" },
      { id: "mB", name: "Mobile accessories ", isActive: false, showOnHome: false, createdAt: ts("2024-01-01"), normalizedName: "mobile accessories" },
      { id: "mC", name: "MOBILE ACCESSORIES", isActive: false, showOnHome: false },
      { id: "auto1", name: "Automotive", isActive: false, showOnHome: false },
      { id: "auto2", name: "Automotive", isActive: false, showOnHome: false, image: "car.jpg" },
      { id: "cook", name: "Cooking", isActive: true, showOnHome: false },
      { id: "toys", name: "Toys", isActive: false, showOnHome: false },
    ],
    subcategories: [
      { id: "s1", name: "Chargers", categoryId: "mA" },
      { id: "s2", name: "chargers", categoryId: "mB" },
      { id: "s3", name: "Cables", categoryId: "mB" },
    ],
    products: [
      { id: "p1", category: "Mobile Accessories", categoryId: "mA" },
      { id: "p2", category: "Mobile Accessories", categoryId: "mA" },
      { id: "p3", category: "Mobile accessories", categoryId: "mB" },
      { id: "p4", category: "mobile accessories" }, // name only, different case
      { id: "p5", category: "Cooking" }, // name only, exact
      { id: "p6", category: "Other" }, // skipped
      { id: "p7", category: "" }, // skipped
      { id: "p8", category: "Gadgets" }, // unknown name
      { id: "p9", category: "Cooking", categoryId: "deleted" }, // dangling
    ],
    banners: [
      { id: "b1", categoryId: "mB", clickActionType: "category", clickValue: "mB" },
      { id: "b2", categoryId: "cook" },
    ],
  };
}

describe("buildCleanupPlan (pure, no Firestore)", () => {
  const plan = buildCleanupPlan(fixture());

  test("groups case/space variants and picks the canonical with the most products", () => {
    const group = plan.mergeGroups.find((g) => g.key === "mobile accessories");
    assert.equal(group.canonical.id, "mA");
    assert.deepEqual(group.losers.map((l) => l.id).sort(), ["mB", "mC"]);
  });

  test("ties on product count fall back to image, then createdAt, then id", () => {
    const group = plan.mergeGroups.find((g) => g.key === "automotive");
    assert.equal(group.canonical.id, "auto2"); // has image
  });

  test("merge repoints products, subcategories and banners, and flags name collisions", () => {
    const w = plan.mergeGroups.find((g) => g.key === "mobile accessories").writes;
    assert.deepEqual(w.products.map((p) => [p.productId, p.set.categoryId, p.set.category]), [
      ["p3", "mA", "Mobile Accessories"],
    ]);
    assert.equal(w.products[0].categoryTextChanges, true);
    const s2 = w.subcategories.find((s) => s.subcategoryId === "s2");
    assert.equal(s2.nameCollidesUnderCanonical, true);
    assert.equal(w.subcategories.find((s) => s.subcategoryId === "s3").nameCollidesUnderCanonical, false);
    assert.deepEqual(w.banners, [{ bannerId: "b1", from: "mB", fields: ["categoryId", "clickValue"], set: { categoryId: "mA" } }]);
  });

  test("merged-away docs are hidden, point at the canonical, and lose normalizedName", () => {
    const mb = plan.mergeGroups[0].writes.mergedAway.find((m) => m.categoryId === "mB");
    assert.deepEqual(mb.set, { isActive: false, showOnHome: false, mergedInto: "mA" });
    assert.deepEqual(mb.deleteFields, ["normalizedName"]);
  });

  test("canonical docs missing normalizedName get it backfilled", () => {
    const ids = plan.canonicalFixes.map((f) => f.categoryId);
    assert.ok(ids.includes("cook"));
    assert.ok(!ids.includes("mA")); // already correct
  });

  test("name-only products: assigned to canonical, Other/empty skipped, unknown reported", () => {
    assert.deepEqual(plan.nameOnly.assign.map((a) => [a.productId, a.set.categoryId]), [
      ["p4", "mA"],
      ["p5", "cook"],
    ]);
    assert.equal(plan.nameOnly.assign.find((a) => a.productId === "p5").categoryTextChanges, false);
    assert.deepEqual(plan.nameOnly.skippedForManualFix.map((p) => p.productId), ["p6", "p7"]);
    assert.deepEqual(plan.nameOnly.unknownName.map((p) => p.productId), ["p8"]);
    assert.deepEqual(plan.danglingCategoryId.map((p) => p.productId), ["p9"]);
  });

  test("empty categories are split into merged-away and unique", () => {
    assert.deepEqual(plan.emptyCategories.uniqueAndEmpty.map((c) => c.id), ["auto2", "toys"]);
    assert.deepEqual(plan.emptyCategories.mergedAway.map((c) => c.id).sort(), ["auto1", "mB", "mC"]);
  });

  test("homepage tiles and SEO slugs are reported", () => {
    assert.deepEqual(plan.homepage.categoryTilesBefore, ["Mobile Accessories"]);
    assert.deepEqual(plan.homepage.categoryTilesAfter, ["Mobile Accessories"]);
    assert.deepEqual(plan.seo.slugChanges, []);
    const ids = plan.homepage.productsWhoseCategoryTextChanges.map((p) => p.productId);
    assert.deepEqual(ids.sort(), ["p3", "p4"]);
  });

  test("markdown renders without throwing", () => {
    assert.match(renderMarkdown(plan), /No Firestore writes were made/);
  });
});
