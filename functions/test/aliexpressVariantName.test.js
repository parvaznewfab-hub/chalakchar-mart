const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  cleanAliExpressSkuFallbackText,
  resolveAliExpressVariantName,
} = require("../aliexpress/variantName");

describe("cleanAliExpressSkuFallbackText", () => {
  test("cleans the reported bug example exactly", () => {
    assert.equal(
      cleanAliExpressSkuFallbackText("14:200004890#11 128g No Face ID;200007763:201336100"),
      "11 128g No Face ID"
    );
  });

  test("pure internal id:id segment is discarded entirely", () => {
    assert.equal(cleanAliExpressSkuFallbackText("200007763:201336100"), "");
  });

  test("multiple semicolon-separated segments, all kept when readable", () => {
    assert.equal(
      cleanAliExpressSkuFallbackText("1:100#Red;2:200#64GB"),
      "Red / 64GB"
    );
  });

  test("plain text with no id/hash markers passes through unchanged", () => {
    assert.equal(cleanAliExpressSkuFallbackText("Blue"), "Blue");
  });

  test("empty/missing input returns empty string", () => {
    assert.equal(cleanAliExpressSkuFallbackText(""), "");
    assert.equal(cleanAliExpressSkuFallbackText(null), "");
    assert.equal(cleanAliExpressSkuFallbackText(undefined), "");
  });

  test("never leaves a raw property id in the output", () => {
    const result = cleanAliExpressSkuFallbackText("14:200004890#11 128g No Face ID;200007763:201336100");
    assert.equal(/\d+:\d+/.test(result), false);
  });
});

describe("resolveAliExpressVariantName", () => {
  test("readable attributes override sku_code even when sku_code is present", () => {
    const sku = {
      sku_code: "14:200004890#11 128g No Face ID;200007763:201336100",
      ae_sku_property_dtos: [
        { property_value_definition_name: "128GB No Face ID" },
      ],
    };
    assert.equal(resolveAliExpressVariantName(sku), "128GB No Face ID");
  });

  test("multiple readable attributes are joined with \" / \"", () => {
    const sku = {
      ae_sku_property_dtos: [
        { property_value_definition_name: "Red" },
        { property_value_name: "128GB" },
      ],
    };
    assert.equal(resolveAliExpressVariantName(sku), "Red / 128GB");
  });

  test("falls back through property_value_name, sku_property_value, property_value_display_name in order", () => {
    assert.equal(
      resolveAliExpressVariantName({ ae_sku_property_dtos: [{ property_value_name: "Blue" }] }),
      "Blue"
    );
    assert.equal(
      resolveAliExpressVariantName({ ae_sku_property_dtos: [{ sku_property_value: "Green" }] }),
      "Green"
    );
    assert.equal(
      resolveAliExpressVariantName({ ae_sku_property_dtos: [{ property_value_display_name: "Yellow" }] }),
      "Yellow"
    );
  });

  test("no readable attribute value falls back to cleaned raw sku_code (the reported bug case)", () => {
    const sku = {
      sku_code: "14:200004890#11 128g No Face ID;200007763:201336100",
      ae_sku_property_dtos: [{ property_value_id: 123 }], // no readable text fields
    };
    assert.equal(resolveAliExpressVariantName(sku), "11 128g No Face ID");
  });

  test("missing attributes entirely falls back safely through sku_name -> sku_attr -> sku_code", () => {
    assert.equal(resolveAliExpressVariantName({ sku_name: "Black" }), "Black");
    assert.equal(resolveAliExpressVariantName({ sku_attr: "14:1#Black" }), "Black");
    assert.equal(
      resolveAliExpressVariantName({ sku_code: "14:200004890#256GB" }),
      "256GB"
    );
  });

  test("completely empty sku with no usable fields returns empty string (caller applies its own \"Option N\" fallback)", () => {
    assert.equal(resolveAliExpressVariantName({}), "");
  });

  test("pure internal id segments never leak into the resolved name", () => {
    const sku = { sku_code: "200007763:201336100" };
    assert.equal(resolveAliExpressVariantName(sku), "");
  });
});
