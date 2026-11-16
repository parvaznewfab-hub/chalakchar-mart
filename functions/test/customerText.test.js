// Customer-facing text never names the supplier or the origin country.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  mentionsSupplier,
  isHiddenSpecification,
  stripSupplierSentences,
  withoutSupplierKeywords,
} = require("../catalog/customerText");

test("sentences naming the supplier or China are dropped (same cases as the Dart test)", () => {
  assert.equal(
    stripSupplierSentences("Fast 2.5 inch SSD. We mainly ship via AliExpress standard shipping. Items cannot be tracked after they leave China! 3 year warranty."),
    "Fast 2.5 inch SSD. 3 year warranty."
  );
  assert.equal(stripSupplierSentences("Netac SSD 128GB"), "Netac SSD 128GB");
});

test("origin specs hidden, keywords filtered", () => {
  assert.equal(isHiddenSpecification("Origin", "Mainland China"), true);
  assert.equal(isHiddenSpecification("Brand Name", "Netac"), false);
  assert.deepEqual(withoutSupplierKeywords(["ssd", "aliexpress", "china", "netac"]), ["ssd", "netac"]);
  assert.equal(mentionsSupplier("Machinery"), false, "whole words only");
});

// Shared with test/customer_text_test.dart (Dart mirror).
{
  const fixture = require(require("path").join(__dirname, "..", "..", "test", "fixtures", "seller_text_cases.json"));
  const { cleanCustomerText, cleanCustomerHtml } = require("../catalog/customerText");
  for (const c of fixture.text) {
    test(`cleanCustomerText: ${c.label}`, () => assert.equal(cleanCustomerText(c.in), c.out));
  }
  for (const c of fixture.html) {
    test(`cleanCustomerHtml: ${c.label}`, () => assert.equal(cleanCustomerHtml(c.in), c.out));
  }
}
