const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { resolveAliExpressVariantImage } = require("../aliexpress/variantImage");

describe("resolveAliExpressVariantImage", () => {
  test("uses sku_image from the visual property (confirmed real field)", () => {
    const sku = {
      ae_sku_property_dtos: [
        { property_value_definition_name: "128g No Face ID", sku_image: "https://ae01.example.com/color.jpg" },
      ],
    };
    const result = resolveAliExpressVariantImage(sku, "https://ae01.example.com/primary.jpg");
    assert.equal(result.image, "https://ae01.example.com/color.jpg");
    assert.equal(result.imageUrl, "https://ae01.example.com/color.jpg");
  });

  test("when multiple properties exist, uses the first one that actually has an image", () => {
    const sku = {
      ae_sku_property_dtos: [
        { property_value_definition_name: "256GB" }, // storage property, no image
        { property_value_definition_name: "Red", sku_image: "https://ae01.example.com/red.jpg" },
      ],
    };
    const result = resolveAliExpressVariantImage(sku, "https://ae01.example.com/primary.jpg");
    assert.equal(result.image, "https://ae01.example.com/red.jpg");
  });

  test("falls back to the product primary image when no sku_image exists", () => {
    const sku = {
      ae_sku_property_dtos: [
        { property_value_definition_name: "256GB" },
      ],
    };
    const result = resolveAliExpressVariantImage(sku, "https://ae01.example.com/primary.jpg");
    assert.equal(result.image, "https://ae01.example.com/primary.jpg");
    assert.equal(result.imageUrl, "https://ae01.example.com/primary.jpg");
  });

  test("falls back to primary image when ae_sku_property_dtos is entirely missing", () => {
    const result = resolveAliExpressVariantImage({}, "https://ae01.example.com/primary.jpg");
    assert.equal(result.image, "https://ae01.example.com/primary.jpg");
  });

  test("returns an empty image when neither sku_image nor a primary image exists", () => {
    const result = resolveAliExpressVariantImage({}, "");
    assert.equal(result.image, "");
    assert.equal(result.imageUrl, "");
  });

  test("rejects a non-URL sku_image value (never returns a raw/invalid value)", () => {
    const sku = {
      ae_sku_property_dtos: [{ sku_image: "not-a-url" }],
    };
    const result = resolveAliExpressVariantImage(sku, "https://ae01.example.com/primary.jpg");
    assert.equal(result.image, "https://ae01.example.com/primary.jpg");
  });
});
