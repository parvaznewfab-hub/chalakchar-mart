const logger = require("firebase-functions/logger");

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

// -----------------------------------------------------------------------------
// Converts a resolveAliExpressDeliveryFields() result (deliveryFreightAmount/
// deliveryFreightCurrency, from aliexpress.logistics.buyer.freight.calculate)
// into a BDT amount safe to fold into applyImportPriceRule()'s
// additionalCostBDT — shared by both the import flow
// (buildMarketplaceProductPayload) and the sync flow (syncAliExpressProduct)
// in index.js, so there is only one implementation of "how much AliExpress
// shipping cost, if any, gets folded into price".
//
// Our fulfillment model pays AliExpress (product + shipping) then ships to
// the customer ourselves, so shipping is landed cost, not a pass-through —
// markup and the minimum-profit floor must both apply to it too.
//
// Only trusted when the freight call returned a currency this pipeline can
// convert with confidence: USD (matching every other price field in this
// pipeline, e.g. aliexpress.ds.product.get's target_currency) or no
// currency_code at all (freight.calculate omitted it — same USD assumption
// the rest of the pipeline already makes). Any other currency is logged and
// skipped rather than risking a silently wrong conversion — never guessed.
// -----------------------------------------------------------------------------
function resolveAliExpressShippingCostBDT(deliveryFields, importSettings, options = {}) {
  const fields = mapValue(deliveryFields);
  const freightAmountRaw = Number(fields.deliveryFreightAmount);
  const freightCurrency = textValue(fields.deliveryFreightCurrency).toUpperCase();

  if (!Number.isFinite(freightAmountRaw) || freightAmountRaw <= 0) {
    return { shippingCostBDT: 0, shippingCostOriginal: 0, shippingCostCurrency: "" };
  }

  if (freightCurrency && freightCurrency !== "USD") {
    logger.warn("AliExpress shipping cost skipped — unexpected freight currency, not folded into price", {
      sourceProductId: options.sourceProductId || null,
      freightCurrency,
      freightAmountRaw,
    });
    return { shippingCostBDT: 0, shippingCostOriginal: 0, shippingCostCurrency: "" };
  }

  return {
    shippingCostBDT: Math.max(0, freightAmountRaw * importSettings.exchangeRate),
    shippingCostOriginal: freightAmountRaw,
    shippingCostCurrency: freightCurrency || "USD",
  };
}

module.exports = { resolveAliExpressShippingCostBDT };
