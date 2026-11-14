const { describe, test } = require("node:test");
const assert = require("node:assert/strict");

const { searchImportLogDocId } = require("../aliexpress/searchImportLogId");

describe("searchImportLogDocId", () => {
  test("ASCII queries keep their existing slug ids", () => {
    assert.equal(searchImportLogDocId("Netac SSD 128GB price?"), "netac_ssd_128gb_price");
    assert.equal(searchImportLogDocId("  brass  garden hose "), "brass_garden_hose");
  });

  test("Bangla queries no longer all share the id 'query' (2026-11-14 incident)", () => {
    const a = searchImportLogDocId("১২৮ জিবি এসএসডি এর দাম কত? ডেলিভারি কতদিনে পাব?");
    const b = searchImportLogDocId("দাম কত");
    assert.notEqual(a, "query");
    assert.notEqual(a, b);
    assert.match(a, /^q_[0-9a-f]{12}$/);
  });

  test("mixed Bangla + ASCII doesn't collide with the plain ASCII query", () => {
    assert.notEqual(searchImportLogDocId("১২৮ জিবি ssd"), searchImportLogDocId("ssd"));
    assert.match(searchImportLogDocId("১২৮ জিবি ssd"), /^ssd_[0-9a-f]{12}$/);
  });

  test("same query, same id (dedupe still works)", () => {
    assert.equal(searchImportLogDocId("দাম কত"), searchImportLogDocId("  দাম   কত "));
  });
});
