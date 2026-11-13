const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { matchAliExpressVariant } = require("../aliexpress/variantMatch");

describe("matchAliExpressVariant", () => {
  test("matches by sourceSkuId (highest priority)", () => {
    const existing = { sourceSkuId: "123", skuId: "999", name: "Red" };
    const fresh = [
      { sourceSkuId: "999", name: "Wrong" },
      { sourceSkuId: "123", skuId: "999", name: "Red", image: "https://a/red.jpg" },
    ];
    const result = matchAliExpressVariant(existing, fresh);
    assert.equal(result.matched.image, "https://a/red.jpg");
    assert.equal(result.matchField, "sourceSkuId");
    assert.equal(result.ambiguous, false);
  });

  test("falls to skuId when sourceSkuId is absent", () => {
    const existing = { skuId: "sku-1", name: "Blue" };
    const fresh = [{ skuId: "sku-1", name: "Blue", image: "https://a/blue.jpg" }];
    const result = matchAliExpressVariant(existing, fresh);
    assert.equal(result.matchField, "skuId");
  });

  test("falls to variantId, then id, when higher-priority fields are absent", () => {
    const byVariantId = matchAliExpressVariant(
      { variantId: "v1" },
      [{ variantId: "v1", image: "https://a/1.jpg" }]
    );
    assert.equal(byVariantId.matchField, "variantId");

    const byId = matchAliExpressVariant(
      { id: "id1" },
      [{ id: "id1", image: "https://a/1.jpg" }]
    );
    assert.equal(byId.matchField, "id");
  });

  test("falls to exact cleaned name only when no id-like field is present", () => {
    const result = matchAliExpressVariant(
      { name: "  Red / 128GB  " },
      [{ name: "red / 128gb", image: "https://a/red-128.jpg" }]
    );
    assert.equal(result.matchField, "name");
    assert.equal(result.matched.image, "https://a/red-128.jpg");
  });

  test("does not fall through to a weaker field when a higher-priority field is present but unmatched", () => {
    // sourceSkuId is present on `existing` but doesn't exist in fresh at all —
    // must NOT fall through to try matching by name, even though the name matches.
    const existing = { sourceSkuId: "does-not-exist", name: "Red" };
    const fresh = [{ sourceSkuId: "something-else", name: "Red", image: "https://a/red.jpg" }];
    const result = matchAliExpressVariant(existing, fresh);
    assert.equal(result.matched, null);
    assert.equal(result.matchField, "sourceSkuId");
    assert.equal(result.ambiguous, false);
  });

  test("duplicate cleaned names are ambiguous and never guessed", () => {
    const existing = { name: "Red" };
    const fresh = [
      { name: "red", image: "https://a/1.jpg" },
      { name: "RED", image: "https://a/2.jpg" },
    ];
    const result = matchAliExpressVariant(existing, fresh);
    assert.equal(result.matched, null);
    assert.equal(result.ambiguous, true);
    assert.equal(result.matchField, "name");
  });

  test("never fuzzy/substring matches names", () => {
    const result = matchAliExpressVariant(
      { name: "Red" },
      [{ name: "Red / 128GB", image: "https://a/red-128.jpg" }]
    );
    assert.equal(result.matched, null);
  });

  test("no identifiers at all on either side returns no match", () => {
    const result = matchAliExpressVariant({}, [{ image: "https://a/1.jpg" }]);
    assert.equal(result.matched, null);
    assert.equal(result.matchField, null);
    assert.equal(result.ambiguous, false);
  });
});

describe("withSourceSkuIds", () => {
  const { withSourceSkuIds } = require("../aliexpress/variantMatch");

  test("copies skuId into sourceSkuId without mutating the input", () => {
    const fresh = [{ skuId: "1", name: "A" }];
    const out = withSourceSkuIds(fresh);
    assert.equal(out[0].sourceSkuId, "1");
    assert.equal("sourceSkuId" in fresh[0], false);
  });

  test("keeps an existing sourceSkuId, and leaves variants without skuId alone", () => {
    assert.equal(withSourceSkuIds([{ skuId: "1", sourceSkuId: "9" }])[0].sourceSkuId, "9");
    assert.equal("sourceSkuId" in withSourceSkuIds([{ name: "A" }])[0], false);
    assert.deepEqual(withSourceSkuIds(null), []);
  });

  test("saved sourceSkuId now matches a fresh variant that only had skuId", () => {
    const result = matchAliExpressVariant({ sourceSkuId: "77", name: "Red" }, withSourceSkuIds([{ skuId: "77", name: "Red" }]));
    assert.equal(result.matchField, "sourceSkuId");
    assert.ok(result.matched);
  });
});

describe("pickFreshVariantForSaved (SKU and name must agree)", () => {
  const { pickFreshVariantForSaved } = require("../aliexpress/variantMatch");
  const fresh = [
    { skuId: "A", name: "16 Pro 128g No Face", price: 276.76 },
    { skuId: "B", name: "16 128g No Face", price: 200 },
    { skuId: "C", name: "16 Pro 256g No Face", price: 297.16 },
  ];

  test("SKU match with the same name is used", () => {
    const pick = pickFreshVariantForSaved({ sourceSkuId: "B", name: "16 128g No Face" }, fresh);
    assert.equal(pick.how, "sku");
    assert.equal(pick.fresh.skuId, "B");
  });

  test("live case: saved SKU belongs to another variant -> use the unique same-name variant instead", () => {
    // Saved "16 128g No Face" carried the SKU of "16 Pro 128g No Face".
    const pick = pickFreshVariantForSaved({ sourceSkuId: "A", name: "16 128g No Face" }, fresh);
    assert.equal(pick.how, "name_sku_mismatch");
    assert.equal(pick.fresh.skuId, "B");
  });

  test("SKU points elsewhere and no variant has the saved name -> not used", () => {
    const pick = pickFreshVariantForSaved({ sourceSkuId: "A", name: "Renamed by admin" }, fresh);
    assert.equal(pick.how, "sku_name_mismatch");
    assert.equal(pick.fresh, null);
  });

  test("SKU gone but the name exists under a new SKU -> used; neither -> not_on_aliexpress", () => {
    assert.equal(pickFreshVariantForSaved({ sourceSkuId: "Z", name: "16 pro 256G  no face" }, fresh).how, "name_sku_changed");
    assert.equal(pickFreshVariantForSaved({ sourceSkuId: "Z", name: "Nothing like it" }, fresh).how, "not_on_aliexpress");
  });

  test("duplicate names are ambiguous, never guessed", () => {
    const dup = [...fresh, { skuId: "D", name: "16 128g No Face" }];
    assert.equal(pickFreshVariantForSaved({ sourceSkuId: "Z", name: "16 128g No Face" }, dup).how, "ambiguous");
  });
});
