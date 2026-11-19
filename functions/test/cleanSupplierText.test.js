const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { stripSupplierText, stripSupplierHtml, supplierTextChanges } = require("../scripts/cleanSupplierText");

describe("stripSupplierText", () => {
  test("removes only the supplier sentence; other lines stay byte-identical", () => {
    const before = [
      "🔈More specifications about the product:",
      "4. Strictly tested before delivery,100% working well.",
      "5. Delivery within 1-2 working days after payment confirmation. (Most products and countries support delivery from AliExpress official warehouse.)",
      "",
      "Package includes: Screen *1",
    ].join("\n");
    const after = stripSupplierText(before);
    assert.equal(after, [
      "🔈More specifications about the product:",
      "4. Strictly tested before delivery,100% working well.",
      "5. Delivery within 1-2 working days after payment confirmation.",
      "",
      "Package includes: Screen *1",
    ].join("\n"));
  });

  test("a heading whose whole section was the supplier sentence goes too", () => {
    const before = "Notice:\n1. Test first.\n\nShipping Method\nWe mainly shipping via Aliexpress standard and priority shipping.\n\nAbout the motherboard";
    assert.equal(stripSupplierText(before), "Notice:\n1. Test first.\n\nAbout the motherboard");
  });

  test("text without supplier words is returned unchanged", () => {
    const s = "Material: AAA display.\nResolution: Standard.";
    assert.equal(stripSupplierText(s), s);
  });
});

describe("stripSupplierHtml", () => {
  test("cleans text runs, keeps tags and images", () => {
    const html = '<p>Great screen.</p><p>Ships from AliExpress official warehouse.</p><img src="https://x/y.webp">';
    assert.equal(stripSupplierHtml(html), '<p>Great screen.</p><p></p><img src="https://x/y.webp">');
  });
});

describe("supplierTextChanges", () => {
  test("keywords, tags and suggestedCategory", () => {
    const changes = supplierTextChanges({
      category: "Motherboard",
      suggestedCategory: "AliExpress",
      seoTags: ["iphone 11 motherboard", "aliexpress"],
      searchKeywords: ["aliexpress motherboard", "logic board"],
      description: "Good board.",
    });
    assert.deepEqual(changes, {
      seoTags: ["iphone 11 motherboard"],
      searchKeywords: ["logic board"],
      suggestedCategory: "Motherboard",
    });
  });

  test("a clean product has no changes", () => {
    assert.deepEqual(supplierTextChanges({ name: "Vim Bar", description: "Cleans dishes.", seoTags: ["dish"] }), {});
  });
});
