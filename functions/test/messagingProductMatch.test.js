const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { scoreProductMatch, matchesQuery, rankProducts } = require("../messaging/productMatch");

describe("scoreProductMatch", () => {
  test("blank query scores 0", () => {
    assert.equal(scoreProductMatch({ name: "Paracetamol" }, ""), 0);
  });

  test("exact name match scores highest", () => {
    const exact = scoreProductMatch({ name: "Napa" }, "Napa");
    const partial = scoreProductMatch({ name: "Napa Extra" }, "Napa");
    assert.ok(exact > partial);
  });

  test("case-insensitive", () => {
    assert.equal(scoreProductMatch({ name: "Napa" }, "napa"), scoreProductMatch({ name: "NAPA" }, "NAPA"));
  });

  test("scores contributions from generic/manufacturer/brand/category/type/strength/vendorName", () => {
    const product = {
      name: "Something else",
      generic: "paracetamol",
      manufacturer: "square",
      brand: "napa",
      category: "medicine",
      type: "tablet",
      strength: "500mg",
      vendorName: "city pharmacy",
    };
    assert.ok(scoreProductMatch(product, "paracetamol") > 0);
    assert.ok(scoreProductMatch(product, "square") > 0);
    assert.ok(scoreProductMatch(product, "tablet") > 0);
    assert.ok(scoreProductMatch(product, "500mg") > 0);
    assert.ok(scoreProductMatch(product, "city pharmacy") > 0);
  });

  test("unrelated query scores 0", () => {
    assert.equal(scoreProductMatch({ name: "Napa" }, "bicycle"), 0);
  });

  test("shopName is accepted as a vendorName fallback", () => {
    assert.ok(scoreProductMatch({ name: "x", shopName: "Green Mart" }, "green mart") > 0);
  });
});

describe("matchesQuery", () => {
  test("blank query matches everything", () => {
    assert.equal(matchesQuery({ name: "Napa" }, ""), true);
  });

  test("every term must appear somewhere in the haystack", () => {
    const product = { name: "Napa Extra", category: "Medicine" };
    assert.equal(matchesQuery(product, "napa medicine"), true);
    assert.equal(matchesQuery(product, "napa bicycle"), false);
  });

  test("overview field is searched", () => {
    assert.equal(matchesQuery({ name: "x", overview: "great for fever" }, "fever"), true);
  });
});

describe("rankProducts", () => {
  const products = [
    { id: "p1", name: "Napa Extra", isActive: true },
    { id: "p2", name: "Napa", isActive: true },
    { id: "p3", name: "Bicycle", isActive: true },
    { id: "p4", name: "Napa", isActive: false },
  ];

  test("filters out non-matching and inactive products", () => {
    const ranked = rankProducts(products, "napa", 5);
    assert.deepEqual(ranked.map((p) => p.id), ["p2", "p1"]);
  });

  test("exact match outranks partial match", () => {
    const ranked = rankProducts(products, "napa", 5);
    assert.equal(ranked[0].id, "p2");
  });

  test("respects the limit", () => {
    const many = Array.from({ length: 10 }, (_, i) => ({ id: `x${i}`, name: "Napa", isActive: true }));
    assert.equal(rankProducts(many, "napa", 3).length, 3);
  });

  test("empty product list returns empty array", () => {
    assert.deepEqual(rankProducts([], "napa", 5), []);
  });

  test("null/undefined products in the list are skipped, not thrown on", () => {
    assert.deepEqual(rankProducts([null, undefined, { id: "p1", name: "Napa", isActive: true }], "napa", 5).map((p) => p.id), ["p1"]);
  });
});
