const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { planAttributeNames } = require("../scripts/backfillVariantAttributeName");

// Shape of an aliexpressProductDetails `product`: normalized variants plus
// the untouched raw response.
function fresh(skus) {
  return {
    variants: skus.map((s) => ({ id: s.sku_id, skuId: s.sku_id, name: s.name })),
    rawAliExpress: {
      result: {
        ae_item_sku_info_dtos: {
          ae_item_sku_info_d_t_o: skus.map((s) => ({
            sku_id: s.sku_id,
            ae_sku_property_dtos: { ae_sku_property_d_t_o: s.props },
          })),
        },
      },
    },
  };
}

const capacity = (v) => [
  { sku_property_name: "Capacity", sku_property_value: v },
  { sku_property_name: "Ships From", sku_property_value: "China" },
];

describe("planAttributeNames", () => {
  test("sets sourceAttributeName via SKU id match", () => {
    const plan = planAttributeNames(
      [
        { name: "1TB / China", sourceSkuId: "11" },
        { name: "2TB / China", sourceSkuId: "12" },
      ],
      fresh([
        { sku_id: "11", name: "1TB / China", props: capacity("1TB") },
        { sku_id: "12", name: "2TB / China", props: capacity("2TB") },
      ])
    );
    assert.deepEqual(plan.changes.map((c) => [c.index, c.sourceAttributeName]), [[0, "Capacity"], [1, "Capacity"]]);
    assert.deepEqual(plan.labels, ["Capacity"]);
    assert.equal(plan.unresolved.length, 0);
  });

  test("never overwrites an existing sourceAttributeName", () => {
    const plan = planAttributeNames(
      [{ name: "1TB / China", sourceSkuId: "11", sourceAttributeName: "Storage", attributeName: "Manual" }],
      fresh([{ sku_id: "11", name: "1TB / China", props: capacity("1TB") }])
    );
    assert.equal(plan.changes.length, 0);
    assert.equal(plan.alreadySet, 1);
  });

  test("variant gone from AliExpress is reported, not guessed", () => {
    const plan = planAttributeNames(
      [{ name: "8TB", sourceSkuId: "99" }],
      fresh([{ sku_id: "11", name: "1TB / China", props: capacity("1TB") }])
    );
    assert.equal(plan.changes.length, 0);
    assert.equal(plan.unresolved[0].reason, "not_on_aliexpress");
  });

  test("AliExpress sent no property names -> unresolved", () => {
    const plan = planAttributeNames(
      [{ name: "Red", sourceSkuId: "1" }],
      fresh([{ sku_id: "1", name: "Red", props: [{ sku_property_value: "Red" }] }])
    );
    assert.equal(plan.unresolved[0].reason, "no_attribute_name_from_aliexpress");
  });

  test("uses the deployed endpoint's sourceAttributeName when present", () => {
    const plan = planAttributeNames(
      [{ name: "Black / XL", sourceSkuId: "5" }],
      { variants: [{ skuId: "5", name: "Black / XL", sourceAttributeName: "Color" }] }
    );
    assert.equal(plan.changes[0].sourceAttributeName, "Color");
  });
});

describe("variantLabelMap (report-only --assume-* overrides)", () => {
  const { variantLabelMap } = require("../scripts/backfillVariantAttributeName");
  const docs = [
    { id: "cat-mb", data: { name: "Motherboard" } },
    { id: "cat-mp", data: { name: "Mobile Parts", variantLabel: "Part" } },
  ];

  test("reads live variantLabel values", () => {
    assert.deepEqual([...variantLabelMap(docs, [])], [["cat-mp", "Part"]]);
  });

  test("assumptions match by name (case-insensitive) or id and override", () => {
    const map = variantLabelMap(docs, ["motherboard=Model", "cat-mp=Type"]);
    assert.equal(map.get("cat-mb"), "Model");
    assert.equal(map.get("cat-mp"), "Type");
  });

  test("names containing '=' or '&' still parse; unknown names fail loudly", () => {
    const amp = [{ id: "s1", data: { name: "Display & Digitizer" } }];
    assert.equal(variantLabelMap(amp, ["Display & Digitizer=Type"]).get("s1"), "Type");
    assert.throws(() => variantLabelMap(docs, ["Motherbord=Model"]), /no category\/subcategory matches/);
  });
});
