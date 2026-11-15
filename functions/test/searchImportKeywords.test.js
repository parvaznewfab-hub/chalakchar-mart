// Search-box queries in Bangla reach AliExpress as English product words.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const { searchImportKeywords } = require("../aliexpress/searchImportKeywords");

test("English queries are sent unchanged", () => {
  assert.equal(searchImportKeywords("Netac SSD 128GB"), "Netac SSD 128GB");
  assert.equal(searchImportKeywords("  iphone 12 battery "), "iphone 12 battery");
});

test("Bangla queries become English product words", () => {
  assert.equal(searchImportKeywords("১২৮ জিবি এসএসডির দাম কত?"), "128gb ssd");
  assert.equal(searchImportKeywords("স্যামসাং এ২৩ ডিসপ্লে"), "samsung 23 display");
  assert.equal(searchImportKeywords("iPhone 12 এর ব্যাটারি"), "iphone 12 battery");
});

test("nothing translatable left -> no import", () => {
  assert.equal(searchImportKeywords("ভালো জুতা"), null);
  assert.equal(searchImportKeywords("দাম কত?"), null);
  assert.equal(searchImportKeywords("১২৮"), null);
  assert.equal(searchImportKeywords(""), null);
});
