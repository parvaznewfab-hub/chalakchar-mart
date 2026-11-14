const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { priceOf, productUrl, applyCaptionTemplate, formatProductReply, deliveryLine } = require("../messaging/replyFormatting");

const TEMPLATE = "🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}";

describe("priceOf", () => {
  test("prefers the cheapest in-stock variant over the first variant and the top-level price", () => {
    assert.equal(priceOf({ price: 100, variants: [{ price: 250 }] }), "250");
    assert.equal(priceOf({ price: 47546, variants: [{ price: 47546, stock: 3 }, { price: 2851.49, stock: 9 }] }), "2851");
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
  test("a single match shows name, price and link", () => {
    const { replyText, productLinks } = formatProductReply([{ id: "p1", name: "Napa", price: 15 }], TEMPLATE);
    assert.equal(replyText, "এই প্রোডাক্টটি পাওয়া যাচ্ছে:\n\nNapa\n💰 দাম: ৳15\n🔗 https://chalakcharmart.com/product/p1");
    assert.deepEqual(productLinks, ["https://chalakcharmart.com/product/p1"]);
  });

  test("quotes the variant the customer named, with its price, never the origin", () => {
    const product = {
      id: "ssd",
      name: "Netac SATA SSD",
      source: "aliexpress",
      deliveryMinDays: 9,
      deliveryMaxDays: 27,
      variants: [
        { name: "4TB Black / China Mainland", price: 47546.14, stock: 3 },
        { name: "128GB Black / China Mainland", price: 2851.49, stock: 1337 },
      ],
    };
    const { replyText } = formatProductReply([product], TEMPLATE, "Netac SSD 128GB price?");
    assert.match(replyText, /💰 দাম: ৳2,851 \(128GB Black\)/);
    assert.match(replyText, /🚚 বিদেশ থেকে আমদানি, আনুমানিক ডেলিভারি ৯–২৭ দিন/);
    assert.match(replyText, /🔗 https:\/\/chalakcharmart\.com\/product\/ssd/);
    assert.doesNotMatch(replyText.replace(/https?:\/\/\S+/g, ""), /china|aliexpress/i);
    // No size in the question: the "from" price.
    assert.match(formatProductReply([product], TEMPLATE, "netac ssd").replyText, /৳2,851 থেকে/);
  });

  test("deliveryLine: local products show a plain estimate, unknown shows nothing", () => {
    assert.equal(deliveryLine({ deliveryDays: 2 }), "🚚 আনুমানিক ডেলিভারি ২ দিন");
    assert.equal(deliveryLine({}), "");
    assert.equal(deliveryLine({ source: "aliexpress" }), "🚚 বিদেশ থেকে আমদানি করা পণ্য");
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
