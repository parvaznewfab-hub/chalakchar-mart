const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { buildMergePlan, mergeKey, classifyBrand, parseArgs, renderMarkdown } = require("../scripts/categoryMerge");

const ts = (iso) => ({ toMillis: () => Date.parse(iso) });
const writeFor = (plan, path) => plan.writes.find((w) => `${w.collection}/${w.id}` === path);

function fixture() {
  return {
    categories: [
      // Motherboard: admin doc with products vs. older Category Manager doc holding "iphone".
      { id: "mbAdmin", name: "Motherboard", source: "admin", isActive: true, normalizedName: "motherboard", createdAt: ts("2026-11-11") },
      { id: "mbOld", name: "Motherboard", isActive: true, createdAt: ts("2026-07-25") },
      // Electronics: old manual doc (empty) vs. aliexpress doc with products + image.
      { id: "elOld", name: "Electronics", isActive: false, createdAt: ts("2026-05-27") },
      { id: "elAli", name: "Electronics", source: "aliexpress", isActive: false, image: "e.jpg", imageUrl: "e.jpg", description: "From AE", normalizedName: "electronics", createdAt: ts("2026-07-28") },
      // "&" vs "and" are the same group.
      { id: "hc1", name: "Home & Cleaning", createdAt: ts("2026-06-21") },
      { id: "hc2", name: "Home and Cleaning", source: "aliexpress", normalizedName: "home and cleaning", createdAt: ts("2026-08-09") },
      // Stale key from a rename.
      { id: "ma", name: "Mobile Accessories", source: "admin", isActive: true, normalizedName: "computer accessories" },
      { id: "mp", name: "Mobile Parts", source: "admin", isActive: true, normalizedName: "mobile parts" },
      // Already merged on an earlier run: ignored.
      { id: "gone", name: "Motherboard", isActive: false, mergedInto: "mbAdmin" },
    ],
    subcategories: [
      { id: "iphone", name: "iphone", categoryId: "mbOld", normalizedName: "iphone" },
      { id: "flbc", name: "Motherboard & Mainboard", categoryId: "mp", normalizedName: "motherboard & mainboard" },
      { id: "disp", name: "Display & Digitizer", categoryId: "mp", normalizedName: "display & digitizer" },
    ],
    products: [
      { id: "e1", category: "Electronics", categoryId: "elAli" },
      { id: "e2", category: "Electronics", categoryId: "elAli" },
      // In Motherboard but still pointing at Mobile Parts' subcategory.
      { id: "mb1", name: "Mainboard For iPhone 17 Pro Max", category: "Motherboard", categoryId: "mbAdmin", subcategoryId: "flbc" },
      // Under Mobile Parts › Motherboard & Mainboard: retired.
      { id: "r1", name: "Fully Tested Motherboard For iPhone 12", category: "Mobile Parts", categoryId: "mp", subcategoryId: "flbc" },
      { id: "r2", name: "Mainboard For Samsung Galaxy S21", category: "Mobile Parts", categoryId: "mp", subcategoryId: "flbc" },
      { id: "r3", name: "Unlocked Logic Board 128GB", category: "Mobile Parts", categoryId: "mp", subcategoryId: "flbc" },
      { id: "r4", name: "Board for Galaxy S9 with Face ID", category: "Mobile Parts", categoryId: "mp", subcategoryId: "flbc" },
      { id: "r5", name: "Mainboard For Samsung A52", category: "Mobile Parts", categoryId: "mp", subcategoryId: "flbc" },
      // Unrelated Mobile Parts subcategory: untouched.
      { id: "d1", name: "LCD for iPhone", category: "Mobile Parts", categoryId: "mp", subcategoryId: "disp" },
    ],
    banners: [{ id: "b1", categoryId: "elAli", clickValue: "elAli" }],
  };
}

const OPTIONS = {
  remapSubcategory: { flbc: "iphone" },
  retireSubcategories: [{ subId: "flbc", toCategoryId: "mbAdmin" }],
};

describe("categoryMerge helpers", () => {
  test("mergeKey folds case, whitespace, NFKC and & / and", () => {
    assert.equal(mergeKey("  Home   &  Cleaning "), "home and cleaning");
    assert.equal(mergeKey("Home and Cleaning"), "home and cleaning");
    assert.equal(mergeKey("ＥＬＥＣＴＲＯＮＩＣＳ"), "electronics");
    assert.equal(mergeKey(""), "");
  });

  test("classifyBrand picks one brand, or null when none / several", () => {
    assert.equal(classifyBrand("Fully Tested Mainboard For iPhone 17 Pro Max"), "iphone");
    assert.equal(classifyBrand("Compatible With 12 Mini With Face ID Cleaned iCloud"), "iphone");
    assert.equal(classifyBrand("Mainboard for Samsung Galaxy S21"), "samsung");
    assert.equal(classifyBrand("Redmi Note 12 main board"), "xiaomi");
    assert.equal(classifyBrand("Unlocked Logic Board 128GB"), null);
    assert.equal(classifyBrand("Board for Galaxy S9 with Face ID"), null);
  });

  test("parseArgs reads --apply, --remap-subcategory and --retire-subcategory", () => {
    const a = parseArgs(["--out=x", "--remap-subcategory=A:B", "--retire-subcategory=S:C", "--create-brand-subcategories=samsung, xiaomi", "--mark-manual=Z"]);
    assert.deepEqual(a.createBrandSubcategories, ["samsung", "xiaomi"]);
    assert.deepEqual(a.markManual, ["Z"]);
    assert.equal(a.apply, false);
    assert.deepEqual(a.remapSubcategory, { A: "B" });
    assert.deepEqual(a.retireSubcategories, [{ subId: "S", toCategoryId: "C" }]);
    assert.equal(parseArgs(["--apply"]).apply, true);
  });
});

describe("buildMergePlan", () => {
  test("canonical prefers admin, then no source, then active, products, age", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    const canon = Object.fromEntries(plan.groups.map((g) => [g.key, g.canonical.id]));
    assert.equal(canon.motherboard, "mbAdmin");
    assert.equal(canon.electronics, "elOld"); // no source beats aliexpress despite 0 products
    assert.equal(canon["home and cleaning"], "hc1");
    assert.equal(plan.groups.length, 3); // "gone" is ignored
  });

  test("losers are hidden with mergedInto and lose normalizedName; nothing is deleted", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    const w = writeFor(plan, "categories/mbOld");
    assert.deepEqual(w.set, { isActive: false, showOnHome: false, mergedInto: "mbAdmin" });
    assert.deepEqual(w.deleteFields, ["normalizedName"]);
    assert.ok(plan.writes.every((x) => !x.deleteFields.includes("name")));
  });

  test("canonical gets missing image/imageUrl/description copied from a loser", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    const w = writeFor(plan, "categories/elOld");
    assert.equal(w.set.image, "e.jpg");
    assert.equal(w.set.imageUrl, "e.jpg");
    assert.equal(w.set.description, "From AE");
    assert.equal(w.set.normalizedName, "electronics");
  });

  test("canonical's own fields are never overwritten", () => {
    const data = fixture();
    data.categories.find((c) => c.id === "elOld").image = "mine.jpg";
    const plan = buildMergePlan(data, OPTIONS);
    const w = writeFor(plan, "categories/elOld");
    assert.equal(w.set.image, undefined);
    assert.equal(w.set.imageUrl, "e.jpg");
  });

  test("products, subcategories and banners move to the canonical", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    assert.deepEqual(writeFor(plan, "products/e1").set, { categoryId: "elOld", category: "Electronics" });
    assert.deepEqual(writeFor(plan, "subcategories/iphone").set, { categoryId: "mbAdmin", categoryName: "Motherboard" });
    assert.deepEqual(writeFor(plan, "banners/b1").set, { categoryId: "elOld", clickValue: "elOld" });
  });

  test("stale normalizedName is repaired with the production key (no & folding)", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    assert.equal(writeFor(plan, "categories/ma").set.normalizedName, "mobile accessories");
    assert.equal(writeFor(plan, "categories/hc1").set.normalizedName, "home & cleaning");
    assert.equal(writeFor(plan, "subcategories/disp"), undefined); // already correct
  });

  test("products already in the target with the retired subcategory are remapped", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    assert.deepEqual(writeFor(plan, "products/mb1").set, { subcategoryId: "iphone" });
  });

  test("without a remap, an invalid subcategoryId is cleared", () => {
    const plan = buildMergePlan(fixture(), { retireSubcategories: OPTIONS.retireSubcategories });
    const w = writeFor(plan, "products/mb1");
    assert.deepEqual(w.deleteFields, ["subcategoryId"]);
  });

  test("without approval, a missing brand subcategory is only proposed, never created", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    assert.equal(plan.creates.length, 0);
    assert.deepEqual(plan.proposedNewSubcategories, ["samsung"]);
    for (const id of ["r2", "r5"]) {
      const w = writeFor(plan, `products/${id}`);
      assert.deepEqual(w.set, { categoryId: "mbAdmin", category: "Motherboard" });
      assert.deepEqual(w.deleteFields, ["subcategoryId"]);
    }
    assert.equal(plan.totals.retiredSubcategoryBrandPendingCreation, 2);
    // Existing "iphone" is still assigned.
    assert.equal(writeFor(plan, "products/r1").set.subcategoryId, "iphone");
  });

  test("--mark-manual sets autoCreated:false, following a merge", () => {
    const data = fixture();
    data.categories.find((c) => c.id === "mbAdmin").autoCreated = true;
    const plan = buildMergePlan(data, { ...OPTIONS, markManual: ["mbOld"] });
    assert.equal(writeFor(plan, "categories/mbAdmin").set.autoCreated, false);
    data.categories.find((c) => c.id === "mbAdmin").autoCreated = false;
    assert.equal(writeFor(buildMergePlan(data, { markManual: ["mbAdmin"] }), "categories/mbAdmin")?.set.autoCreated, undefined);
  });

  test("approved brands (--create-brand-subcategories) are created once and assigned", () => {
    const plan = buildMergePlan(fixture(), { ...OPTIONS, createBrandSubcategories: ["Samsung"] });
    // Existing "iphone" (moved under mbAdmin by the merge) is reused.
    assert.deepEqual(writeFor(plan, "products/r1").set, { categoryId: "mbAdmin", category: "Motherboard", subcategoryId: "iphone" });
    // A new "samsung" subcategory is created once and shared.
    assert.equal(plan.creates.length, 1);
    const samsung = plan.creates[0];
    assert.equal(samsung.data.name, "samsung");
    assert.equal(samsung.data.categoryId, "mbAdmin");
    assert.equal(samsung.data.normalizedName, "samsung");
    assert.equal(writeFor(plan, "products/r2").set.subcategoryId, samsung.placeholder);
    assert.equal(writeFor(plan, "products/r5").set.subcategoryId, samsung.placeholder);
    // Unclear brand: moved, no subcategory.
    for (const id of ["r3", "r4"]) {
      const w = writeFor(plan, `products/${id}`);
      assert.deepEqual(w.set, { categoryId: "mbAdmin", category: "Motherboard" });
      assert.deepEqual(w.deleteFields, ["subcategoryId"]);
    }
    assert.equal(plan.totals.retiredSubcategoryBrandUnclear, 2);
  });

  test("the retired subcategory is hidden, not deleted, and other subcategories are untouched", () => {
    const plan = buildMergePlan(fixture(), OPTIONS);
    const w = writeFor(plan, "subcategories/flbc");
    assert.deepEqual(w.set, { isActive: false, showOnHome: false, mergedInto: "mbAdmin" });
    assert.deepEqual(w.deleteFields, ["normalizedName"]);
    assert.equal(writeFor(plan, "products/d1"), undefined);
  });

  test("retiring into a merged-away category targets its canonical", () => {
    const plan = buildMergePlan(fixture(), { retireSubcategories: [{ subId: "flbc", toCategoryId: "mbOld" }] });
    assert.equal(writeFor(plan, "products/r1").set.categoryId, "mbAdmin");
  });

  test("subcategory name collisions under the canonical are reported", () => {
    const data = fixture();
    data.subcategories.push({ id: "iphone2", name: "iPhone", categoryId: "mbAdmin" });
    const plan = buildMergePlan(data, OPTIONS);
    assert.equal(plan.collisions.length, 1);
    assert.equal(plan.collisions[0].moving, "iphone");
  });

  test("a second run over already-merged data plans no merges", () => {
    const data = fixture();
    const plan = buildMergePlan(data, OPTIONS);
    // Apply the plan in memory.
    const all = { categories: data.categories, subcategories: data.subcategories, products: data.products, banners: data.banners };
    for (const c of plan.creates) all[c.collection].push({ id: c.placeholder, ...c.data });
    for (const w of plan.writes) {
      const doc = all[w.collection].find((d) => d.id === w.id);
      Object.assign(doc, w.set);
      for (const f of w.deleteFields) delete doc[f];
    }
    const again = buildMergePlan(all, { createBrandSubcategories: ["samsung"] });
    assert.equal(again.groups.length, 0);
    assert.equal(again.invalidSubcategory.length, 0);
    assert.equal(again.writes.length, 0);
  });

  test("renderMarkdown lists each retired product with its brand", () => {
    const data = fixture();
    const plan = buildMergePlan(data, { ...OPTIONS, createBrandSubcategories: ["samsung"] });
    const md = renderMarkdown(plan, new Map(data.categories.map((c) => [c.id, c])), new Map(data.subcategories.map((s) => [s.id, s])));
    assert.match(md, /\| r2 \| Mainboard For Samsung Galaxy S21 \| Mobile Parts \| "samsung" \(NEW\) \|/);
    assert.match(md, /\| r3 \| .* \| \*\*unclear\*\* \(no subcategory\) \|/);
    const pending = buildMergePlan(data, OPTIONS);
    const md2 = renderMarkdown(pending, new Map(data.categories.map((c) => [c.id, c])), new Map(data.subcategories.map((s) => [s.id, s])));
    assert.match(md2, /"samsung" PROPOSED — not created/);
    assert.match(md2, /--create-brand-subcategories=samsung/);
  });
});
