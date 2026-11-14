const { test, describe, before } = require("node:test");
const assert = require("node:assert/strict");

const { verifyIncomingVariants } = require("../aliexpress/importVariantGuard");
const { carryVariantLabelFields, sourceLabelFieldsFromSku } = require("../aliexpress/variantLabelFields");

// Raw aliexpress.ds.product.get shape (trimmed): two SKUs whose first
// property is the seller's "Color" — holding phone models, as seen live.
function rawAliExpress() {
  const sku = (id, model, price, stock) => ({
    sku_id: id,
    offer_sale_price: String(price),
    sku_price: String(price + 2),
    sku_available_stock: stock,
    ae_sku_property_dtos: {
      ae_sku_property_d_t_o: [
        { sku_property_name: "Color", sku_property_value: model, property_value_definition_name: model },
        { sku_property_name: "Ships From", sku_property_value: "China Mainland" },
      ],
    },
  });
  return {
    result: {
      ae_item_base_info_dto: { product_id: "1005006207341627", subject: "Mainboard Flex Cable For Huawei Nova" },
      ae_multimedia_info_dto: { image_urls: "https://ae01.alicdn.com/kf/main.jpg" },
      ae_item_sku_info_dtos: { ae_item_sku_info_d_t_o: [sku("111", "Nova 3i", 3.5, 10), sku("222", "Nova 3", 3.9, 4)] },
    },
  };
}

let internals;
before(() => {
  process.env.CHALAKCHAR_LOCAL_TEST = "1";
  internals = require("../index.js").__localImportInternals;
  assert.ok(internals, "index.js exposes import internals when CHALAKCHAR_LOCAL_TEST=1");
});

// buildMarketplaceProductPayload re-prices each variant with a spread
// ({ ...item, price, mrp }) before importVariants — reproduced here.
const reprice = (variants) => variants.map((v) => ({ ...v, price: 500, mrp: 600 }));

describe("label fields helpers", () => {
  test("sourceLabelFieldsFromSku stores AliExpress's name as-is", () => {
    assert.deepEqual(sourceLabelFieldsFromSku(rawAliExpress().result.ae_item_sku_info_dtos.ae_item_sku_info_d_t_o[0]), { sourceAttributeName: "Color" });
    assert.deepEqual(sourceLabelFieldsFromSku({ sku_attr: "14:1#Black" }), {});
  });
  test("carryVariantLabelFields keeps only non-empty fields", () => {
    assert.deepEqual(carryVariantLabelFields({ sourceAttributeName: "Color", attributeName: " " }), { sourceAttributeName: "Color" });
    assert.deepEqual(carryVariantLabelFields(null), {});
  });
});

describe("n8n -> importAliExpressProduct: ID-only body", () => {
  test("variants are saved with sourceAttributeName and no attributeName", () => {
    const product = internals.normalizeAliExpressProduct(rawAliExpress(), "1005006207341627");
    assert.deepEqual(product.variants.map((v) => [v.skuId, v.sourceAttributeName]), [["111", "Color"], ["222", "Color"]]);

    const saved = internals.importVariants(reprice(product.variants), { unit: "Default", price: 500, mrp: 600, stock: 0 });
    for (const v of saved) {
      assert.equal(v.sourceAttributeName, "Color");
      assert.equal("attributeName" in v, false, "AliExpress data never becomes a manual label");
    }
  });
});

describe("n8n -> importAliExpressProduct: full-data body", () => {
  test("sourceAttributeName is added from the matching AliExpress SKU (verified and repaired)", () => {
    const fresh = internals.normalizeAliExpressProduct(rawAliExpress(), "1005006207341627").variants;
    const incoming = [
      { skuId: "111", name: "Nova 3i / China Mainland", price: 3.5, stock: 10 }, // agrees
      { skuId: "111", name: "Nova 3 / China Mainland", price: 3.5, stock: 10 }, // n8n paired wrong SKU
    ];
    const guard = verifyIncomingVariants(incoming, fresh);
    assert.equal(guard.verified, 1);
    assert.equal(guard.repaired.length, 1);

    const saved = internals.importVariants(reprice(guard.variants), { unit: "Default", price: 500, mrp: 600, stock: 0 });
    assert.deepEqual(saved.map((v) => [v.name, v.sourceSkuId, v.sourceAttributeName]), [
      ["Nova 3i / China Mainland", "111", "Color"],
      ["Nova 3 / China Mainland", "222", "Color"],
    ]);
  });

  test("a manual attributeName sent by n8n is carried; an existing sourceAttributeName is not overwritten", () => {
    const fresh = internals.normalizeAliExpressProduct(rawAliExpress(), "1005006207341627").variants;
    const guard = verifyIncomingVariants(
      [{ skuId: "111", name: "Nova 3i / China Mainland", price: 3.5, stock: 1, attributeName: "Model", sourceAttributeName: "Phone Model" }],
      fresh
    );
    const [saved] = internals.importVariants(reprice(guard.variants), { unit: "Default", price: 500, mrp: 600, stock: 0 });
    assert.equal(saved.attributeName, "Model");
    assert.equal(saved.sourceAttributeName, "Phone Model");
  });
});
