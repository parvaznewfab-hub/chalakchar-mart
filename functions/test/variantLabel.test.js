const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");

const {
  resolveVariantAttributeLabel,
  cleanVariantDisplayName,
  isColourValue,
  labelForProduct,
} = require("../catalog/variantLabel");

// Same fixture as test/variant_label_parity_test.dart (Flutter side).
const { cases } = require(path.join(__dirname, "..", "..", "test", "fixtures", "variant_label_cases.json"));

describe("variant label parity fixture", () => {
  for (const c of cases) {
    test(c.label, () => {
      assert.equal(
        resolveVariantAttributeLabel(c.productAttributeName, c.names.map(cleanVariantDisplayName), {
          subcategoryLabel: c.subcategoryLabel,
          categoryLabel: c.categoryLabel,
        }),
        c.expect
      );
    });
  }
});

describe("labelForProduct", () => {
  test("uses the manual product label, ignores sourceAttributeName", () => {
    assert.equal(labelForProduct({ variants: [
      { name: "Nova 3i", sourceAttributeName: "Color" },
      { name: "Nova 3", sourceAttributeName: "Color" },
    ] }), "Option");
    assert.equal(labelForProduct({ variantAttributeName: "Model", variants: [{ name: "Nova 3i" }] }), "Model");
  });

  test("isColourValue", () => {
    assert.equal(isColourValue("Rose Gold"), true);
    assert.equal(isColourValue("Black Frame"), false);
    assert.equal(isColourValue("Light"), false);
  });
});
