const admin = require("firebase-admin");

// -----------------------------------------------------------------------------
// AliExpress freight/shipping-estimate parsing (aliexpress.logistics.buyer.
// freight.calculate). Confirmed real response shape (verified against a live
// call for this project's account, not guessed):
//
//   result.aeop_freight_calculate_result_for_buyer_d_t_o_list
//     .aeop_freight_calculate_result_for_buyer_dto[]
//       { service_name, estimated_delivery_time, freight: { amount,
//         currency_code }, tracking_available, error_code }
//
// estimated_delivery_time is a day-RANGE string like "10-20day", never an
// exact calendar date — so this module only ever produces day counts
// (deliveryMinDays/deliveryMaxDays), never a fabricated estimatedDeliveryDate.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

/**
 * Parses AliExpress's day-range text ("10-20day", "7-15day", "20day",
 * "20 days", "10 - 20 Days") into { minDays, maxDays }. Whitespace-insensitive
 * and case-insensitive; a single number is used for both min and max.
 * Returns null for anything malformed, empty, or missing.
 */
function parseDeliveryDayRange(rawText) {
  const text = textValue(rawText);
  if (!text) return null;

  const compact = text.replace(/\s+/g, "");
  const match = compact.match(/^(\d+)(?:-(\d+))?days?$/i);
  if (!match) return null;

  const first = Number(match[1]);
  const second = match[2] !== undefined ? Number(match[2]) : first;
  if (!Number.isFinite(first) || !Number.isFinite(second)) return null;

  return {
    minDays: Math.max(0, Math.min(first, second)),
    maxDays: Math.max(0, Math.max(first, second)),
  };
}

/**
 * Extracts the shipping-options array from the raw freight.calculate result,
 * using the confirmed real nested path first, with one defensive fallback
 * for a flatter shape (never a blind whole-tree scan).
 */
function extractFreightOptionsList(result) {
  const root = mapValue(result);
  const outer = mapValue(root.aeop_freight_calculate_result_for_buyer_d_t_o_list);
  if (Array.isArray(outer.aeop_freight_calculate_result_for_buyer_dto)) {
    return outer.aeop_freight_calculate_result_for_buyer_dto;
  }
  if (Array.isArray(root.aeop_freight_calculate_result_for_buyer_d_t_o_list)) {
    return root.aeop_freight_calculate_result_for_buyer_d_t_o_list;
  }
  return [];
}

/**
 * Picks the preferred shipping option: valid (no error_code, has an
 * estimated_delivery_time) and cheapest by freight.amount. Returns null if
 * no valid option exists.
 */
function selectPreferredFreightOption(result) {
  const options = extractFreightOptionsList(result).map((raw) => mapValue(raw));

  const valid = options.filter((item) => {
    const errorCode = item.error_code;
    const hasError = errorCode !== undefined && errorCode !== null &&
      String(errorCode).trim() !== "" && String(errorCode) !== "0";
    return !hasError && textValue(item.estimated_delivery_time).length > 0;
  });
  if (!valid.length) return null;

  const amountOf = (item) => {
    const amount = Number(mapValue(item.freight).amount);
    return Number.isFinite(amount) ? amount : Number.POSITIVE_INFINITY;
  };

  return [...valid].sort((a, b) => amountOf(a) - amountOf(b))[0];
}

/**
 * Converts a selected freight option into Firestore-ready fields. Only
 * called once a valid option has already been selected — deliverySource/
 * deliverySourceField always reflect that this endpoint was actually
 * called. deliverySyncStatus is "api_range" when the day-range text parsed
 * successfully, or "malformed" if a valid option was selected but its
 * estimated_delivery_time text didn't match any known shape (still logged,
 * never silently dropped).
 */
function buildAliExpressFreightFirestoreFields(selectedOption) {
  const option = mapValue(selectedOption);
  const range = parseDeliveryDayRange(option.estimated_delivery_time);
  const fields = {};

  if (range) {
    fields.deliveryMinDays = range.minDays;
    fields.deliveryMaxDays = range.maxDays;
    fields.deliveryDays = range.maxDays; // backward compatibility
  }
  if (textValue(option.service_name)) fields.deliveryServiceName = textValue(option.service_name);

  const freight = mapValue(option.freight);
  const freightAmount = Number(freight.amount);
  if (Number.isFinite(freightAmount)) fields.deliveryFreightAmount = freightAmount;
  if (textValue(freight.currency_code)) fields.deliveryFreightCurrency = textValue(freight.currency_code);

  if (option.tracking_available !== undefined && option.tracking_available !== null) {
    fields.deliveryTrackingAvailable = String(option.tracking_available).toLowerCase() === "true";
  }

  return {
    ...fields,
    deliverySource: "aliexpress.logistics.buyer.freight.calculate",
    deliverySourceField: "estimated_delivery_time",
    deliverySyncStatus: range ? "api_range" : "malformed",
    deliveryLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

module.exports = {
  parseDeliveryDayRange,
  extractFreightOptionsList,
  selectPreferredFreightOption,
  buildAliExpressFreightFirestoreFields,
};
