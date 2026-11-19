const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const {
  PRIVATE_SOURCE_FIELDS,
  splitProductWrite,
  mergeProductWithSource,
  privateFieldsOn,
  importKeyId,
  orderSourceEntries,
  stripOrderItem,
} = require("../catalog/productSource");
const { productChanges } = require("../scripts/migrateProductSources");
const fs = require("fs");
const path = require("path");

const imported = {
  name: "Netac SSD",
  price: 2851,
  stock: 10,
  deliveryMinDays: 12,
  deliveryMaxDays: 22,
  source: "aliexpress",
  sourceProductId: "1005013221465261",
  sourceUrl: "https://www.aliexpress.com/item/1005013221465261.html",
  originalPrice: 9.3,
  exchangeRate: 123.5,
  markupPercent: 10,
  deliveryServiceName: "CAINIAO_FULFILLMENT_STD",
  variants: [
    { id: "v_0", name: "128GB", price: 2851, sourceSkuId: "12000060560295988", sourceAttributeName: "Capacity" },
    { id: "v_1", name: "256GB", price: 4481, sourceSkuId: "12000060560295989" },
  ],
};

describe("splitProductWrite", () => {
  test("supplier fields and variant SKUs go private, the rest stays public", () => {
    const { publicData, privateData } = splitProductWrite(imported);
    for (const f of ["source", "sourceProductId", "sourceUrl", "originalPrice", "exchangeRate", "markupPercent", "deliveryServiceName"]) {
      assert.ok(!(f in publicData), f);
      assert.ok(f in privateData, f);
    }
    assert.equal(publicData.price, 2851);
    assert.equal(publicData.deliveryMinDays, 12);
    assert.equal(publicData.variants.length, 2);
    assert.ok(publicData.variants.every((v) => !("sourceSkuId" in v)));
    assert.equal(publicData.variants[0].sourceAttributeName, "Capacity");
    assert.deepEqual(privateData.variantSkus, {
      v_0: { sourceSkuId: "12000060560295988" },
      v_1: { sourceSkuId: "12000060560295989" },
    });
  });

  test("variants without SKUs don't write (or wipe) variantSkus", () => {
    const { privateData } = splitProductWrite({ variants: [{ id: "v_0", stock: 3 }] });
    assert.ok(!("variantSkus" in privateData));
  });

  test("a public-only update stays public", () => {
    const { publicData, privateData } = splitProductWrite({ stock: 0, inStock: false });
    assert.deepEqual(privateData, {});
    assert.deepEqual(publicData, { stock: 0, inStock: false });
  });
});

describe("mergeProductWithSource", () => {
  test("round trip: split then merge gives the server the full product back", () => {
    const { publicData, privateData } = splitProductWrite(imported);
    const merged = mergeProductWithSource(publicData, privateData);
    assert.equal(merged.sourceProductId, imported.sourceProductId);
    assert.equal(merged.variants[1].sourceSkuId, "12000060560295989");
    assert.equal(merged.price, 2851);
  });

  test("before the migration (fields still on the product) it still works", () => {
    const merged = mergeProductWithSource(imported, null);
    assert.equal(merged.sourceProductId, imported.sourceProductId);
    assert.equal(merged.variants[0].sourceSkuId, "12000060560295988");
  });

  test("the source record wins over stale legacy values", () => {
    const merged = mergeProductWithSource(imported, { originalPrice: 11.5 });
    assert.equal(merged.originalPrice, 11.5);
  });
});

describe("privateFieldsOn", () => {
  test("finds top-level and variant fields", () => {
    const found = privateFieldsOn(imported);
    assert.ok(found.includes("sourceUrl"));
    assert.ok(found.includes("variants[].sourceSkuId"));
    assert.deepEqual(privateFieldsOn({ name: "x", price: 1, variants: [{ id: "v" }] }), []);
  });
});

describe("importKeyId", () => {
  test("same digest the old imp_aliexpress_ doc ids used", () => {
    // Live: imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165 is not derivable
    // here without its source id; check the shape and determinism instead.
    const a = importKeyId("aliexpress", "1005013221465261");
    assert.match(a, /^[0-9a-f]{32}$/);
    assert.equal(a, importKeyId("aliexpress", "1005013221465261"));
    assert.notEqual(a, importKeyId("aliexpress", "1005013221465262"));
  });
});

describe("orders", () => {
  test("order sourcing comes from product_sources, items are stripped", () => {
    const items = [
      { productId: "p1", variantId: "v_1", qty: 1, price: 4481, source: "aliexpress", sourceProductId: "100", aliExpressLink: "https://www.aliexpress.com/item/100.html" },
      { productId: "own", qty: 2, price: 50 },
    ];
    const sources = new Map([["p1", { source: "aliexpress", sourceProductId: "100", variantSkus: { v_1: { sourceSkuId: "sku-1" } } }]]);
    const entries = orderSourceEntries(items, sources);
    assert.equal(entries.length, 1);
    assert.deepEqual(entries[0], {
      index: 0, productId: "p1", variantId: "v_1", source: "aliexpress", sourceProductId: "100",
      sourceSkuId: "sku-1", aliExpressLink: "https://www.aliexpress.com/item/100.html",
    });
    const stripped = stripOrderItem(items[0]);
    assert.deepEqual(stripped, { productId: "p1", variantId: "v_1", qty: 1, price: 4481 });
  });

  test("a new-style order (no fields on the item) still gets its link", () => {
    const entries = orderSourceEntries([{ productId: "p1", qty: 1 }], new Map([["p1", { source: "aliexpress", sourceProductId: "77" }]]));
    assert.equal(entries[0].aliExpressLink, "https://www.aliexpress.com/item/77.html");
  });
});

describe("migration plan", () => {
  test("moves every private field, strips SKUs, marks imported, assigns slug", () => {
    const c = productChanges("imp_aliexpress_x", imported, null, "netac-ssd");
    assert.ok(c.deleteFields.includes("sourceUrl"));
    assert.ok(c.deleteFields.includes("originalPrice"));
    assert.ok(c.stripVariantSkus);
    assert.ok(c.strippedVariants.every((v) => !("sourceSkuId" in v)));
    assert.equal(c.setImported, true);
    assert.equal(c.slug, "netac-ssd");
    assert.equal(c.toSource.sourceProductId, imported.sourceProductId);
    assert.equal(c.importKey.id, importKeyId("aliexpress", imported.sourceProductId));
  });

  test("keeps newer values already in product_sources", () => {
    const c = productChanges("x", imported, { originalPrice: 11.5, variantSkus: { v_0: { sourceSkuId: "new" } } }, "");
    assert.ok(!("originalPrice" in c.toSource));
    assert.ok(!("v_0" in (c.toSource.variantSkus || {})));
    assert.ok("v_1" in c.toSource.variantSkus);
  });

  test("an existing urlSlug is never replaced", () => {
    const c = productChanges("x", { ...imported, urlSlug: "keep-me" }, null, "other");
    assert.equal(c.slug, "");
  });
});

describe("firestore.rules", () => {
  test("rules list the same private fields as the code", () => {
    const rules = fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
    const block = rules.slice(rules.indexOf("function privateSourceFields()"), rules.indexOf("function serverOwnedProductFields()"));
    const listed = [...block.matchAll(/'([A-Za-z]+)'/g)].map((m) => m[1]).sort();
    assert.deepEqual(listed, [...PRIVATE_SOURCE_FIELDS].sort());
  });
});
