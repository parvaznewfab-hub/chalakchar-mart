const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { priceOf, productUrl, applyCaptionTemplate, formatProductReply } = require("../messaging/replyFormatting");

const TEMPLATE = "🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}";

describe("priceOf", () => {
  test("prefers first variant price over top-level price", () => {
    assert.equal(priceOf({ price: 100, variants: [{ price: 250 }] }), "250");
  });

  test("falls back to top-level price/piecePrice when no variants", () => {
    assert.equal(priceOf({ price: 120 }), "120");
    assert.equal(priceOf({ piecePrice: 90 }), "90");
  });

  test("returns empty string when no price is available anywhere", () => {
    assert.equal(priceOf({}), "");
  });
});

describe("productUrl", () => {
  test("builds the canonical chalakcharmart.com product URL", () => {
    assert.equal(productUrl("abc123"), "https://chalakcharmart.com/product/abc123");
  });

  test("URL-encodes the product id", () => {
    assert.equal(productUrl("a b"), "https://chalakcharmart.com/product/a%20b");
  });
});

describe("applyCaptionTemplate", () => {
  test("substitutes all placeholders, matching marketing_queue_service.dart's _applyTemplate", () => {
    const result = applyCaptionTemplate(TEMPLATE, { id: "p1", name: "Napa Extra", price: 15 });
    assert.equal(result, "🛒 Napa Extra\nPrice: ৳15\nOrder now: https://chalakcharmart.com/product/p1");
  });

  test("falls back to 'Product' when name is missing", () => {
    const result = applyCaptionTemplate("{productName}", { id: "p1" });
    assert.equal(result, "Product");
  });
});

describe("formatProductReply", () => {
  test("a single match uses the caption template directly", () => {
    const { replyText, productLinks } = formatProductReply([{ id: "p1", name: "Napa", price: 15 }], TEMPLATE);
    assert.equal(replyText, "🛒 Napa\nPrice: ৳15\nOrder now: https://chalakcharmart.com/product/p1");
    assert.deepEqual(productLinks, ["https://chalakcharmart.com/product/p1"]);
  });

  test("2-5 matches produce a numbered list, not the caption template", () => {
    const products = [
      { id: "p1", name: "Napa", price: 15 },
      { id: "p2", name: "Napa Extra", price: 20 },
    ];
    const { replyText, productLinks } = formatProductReply(products, TEMPLATE);
    assert.match(replyText, /1\. Napa/);
    assert.match(replyText, /2\. Napa Extra/);
    assert.deepEqual(productLinks, [
      "https://chalakcharmart.com/product/p1",
      "https://chalakcharmart.com/product/p2",
    ]);
  });

  test("more than 5 matches are capped at 5", () => {
    const products = Array.from({ length: 8 }, (_, i) => ({ id: `p${i}`, name: `Product ${i}` }));
    const { productLinks } = formatProductReply(products, TEMPLATE);
    assert.equal(productLinks.length, 5);
  });
});
