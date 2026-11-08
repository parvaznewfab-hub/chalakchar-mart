const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { resolveAliExpressShippingCostBDT } = require("../aliexpress/shippingCost");

const importSettings = { exchangeRate: 125 };

describe("resolveAliExpressShippingCostBDT", () => {
  test("converts a USD freight amount to BDT using the configured exchange rate", () => {
    const result = resolveAliExpressShippingCostBDT(
      { deliveryFreightAmount: 14.02, deliveryFreightCurrency: "USD" },
      importSettings
    );
    assert.equal(result.shippingCostOriginal, 14.02);
    assert.equal(result.shippingCostCurrency, "USD");
    assert.equal(result.shippingCostBDT, 14.02 * 125);
  });

  test("treats a missing currency_code as USD (matches the rest of the pipeline's assumption)", () => {
    const result = resolveAliExpressShippingCostBDT({ deliveryFreightAmount: 5 }, importSettings);
    assert.equal(result.shippingCostCurrency, "USD");
    assert.equal(result.shippingCostBDT, 5 * 125);
  });

  test("skips folding in an unrecognized currency rather than guessing a conversion", () => {
    const result = resolveAliExpressShippingCostBDT(
      { deliveryFreightAmount: 100, deliveryFreightCurrency: "EUR" },
      importSettings
    );
    assert.deepEqual(result, { shippingCostBDT: 0, shippingCostOriginal: 0, shippingCostCurrency: "" });
  });

  test("returns zero when there is no freight amount at all", () => {
    const result = resolveAliExpressShippingCostBDT({}, importSettings);
    assert.deepEqual(result, { shippingCostBDT: 0, shippingCostOriginal: 0, shippingCostCurrency: "" });
  });

  test("returns zero for a non-finite or non-positive freight amount", () => {
    assert.equal(
      resolveAliExpressShippingCostBDT({ deliveryFreightAmount: 0, deliveryFreightCurrency: "USD" }, importSettings)
        .shippingCostBDT,
      0
    );
    assert.equal(
      resolveAliExpressShippingCostBDT({ deliveryFreightAmount: -5, deliveryFreightCurrency: "USD" }, importSettings)
        .shippingCostBDT,
      0
    );
    assert.equal(
      resolveAliExpressShippingCostBDT({ deliveryFreightAmount: "not-a-number" }, importSettings).shippingCostBDT,
      0
    );
  });

  test("is case-insensitive on currency code", () => {
    const result = resolveAliExpressShippingCostBDT(
      { deliveryFreightAmount: 10, deliveryFreightCurrency: "usd" },
      importSettings
    );
    assert.equal(result.shippingCostCurrency, "USD");
    assert.equal(result.shippingCostBDT, 10 * 125);
  });
});
