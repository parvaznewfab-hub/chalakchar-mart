const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  parseDeliveryDayRange,
  extractFreightOptionsList,
  selectPreferredFreightOption,
  buildAliExpressFreightFirestoreFields,
} = require("../aliexpress/freightDeliveryEstimate");

describe("parseDeliveryDayRange", () => {
  test("standard range \"10-20day\"", () => {
    assert.deepEqual(parseDeliveryDayRange("10-20day"), { minDays: 10, maxDays: 20 });
  });

  test("standard range \"7-15day\"", () => {
    assert.deepEqual(parseDeliveryDayRange("7-15day"), { minDays: 7, maxDays: 15 });
  });

  test("wide range \"1-20day\"", () => {
    assert.deepEqual(parseDeliveryDayRange("1-20day"), { minDays: 1, maxDays: 20 });
  });

  test("single value \"20day\" is used for both min and max", () => {
    assert.deepEqual(parseDeliveryDayRange("20day"), { minDays: 20, maxDays: 20 });
  });

  test("plural form \"20 days\"", () => {
    assert.deepEqual(parseDeliveryDayRange("20 days"), { minDays: 20, maxDays: 20 });
  });

  test("spaces around dash and capitalization: \"10 - 20 Days\"", () => {
    assert.deepEqual(parseDeliveryDayRange("10 - 20 Days"), { minDays: 10, maxDays: 20 });
  });

  test("uppercase \"10-20DAY\"", () => {
    assert.deepEqual(parseDeliveryDayRange("10-20DAY"), { minDays: 10, maxDays: 20 });
  });

  test("reversed order is normalized (min <= max)", () => {
    assert.deepEqual(parseDeliveryDayRange("20-10day"), { minDays: 10, maxDays: 20 });
  });

  test("malformed text returns null", () => {
    assert.equal(parseDeliveryDayRange("fast shipping"), null);
    assert.equal(parseDeliveryDayRange("10 to 20 days"), null);
    assert.equal(parseDeliveryDayRange("10~20day"), null);
  });

  test("empty/missing values return null", () => {
    assert.equal(parseDeliveryDayRange(""), null);
    assert.equal(parseDeliveryDayRange(null), null);
    assert.equal(parseDeliveryDayRange(undefined), null);
  });
});

describe("extractFreightOptionsList / selectPreferredFreightOption", () => {
  const confirmedShapeResult = {
    aeop_freight_calculate_result_for_buyer_d_t_o_list: {
      aeop_freight_calculate_result_for_buyer_dto: [
        {
          service_name: "CAINIAO_STANDARD",
          estimated_delivery_time: "10-20day",
          freight: { amount: 0, currency_code: "USD" },
          tracking_available: "true",
          error_code: null,
        },
        {
          service_name: "AE_EXPEDITED",
          estimated_delivery_time: "7-15day",
          freight: { amount: 5.5, currency_code: "USD" },
          tracking_available: "true",
          error_code: null,
        },
      ],
    },
  };

  test("extracts the array from the confirmed real nested path", () => {
    const list = extractFreightOptionsList(confirmedShapeResult);
    assert.equal(list.length, 2);
    assert.equal(list[0].service_name, "CAINIAO_STANDARD");
  });

  test("picks the cheapest valid option (free CAINIAO_STANDARD over paid AE_EXPEDITED)", () => {
    const selected = selectPreferredFreightOption(confirmedShapeResult);
    assert.equal(selected.service_name, "CAINIAO_STANDARD");
    assert.equal(selected.estimated_delivery_time, "10-20day");
  });

  test("skips options with an error_code", () => {
    const result = {
      aeop_freight_calculate_result_for_buyer_d_t_o_list: {
        aeop_freight_calculate_result_for_buyer_dto: [
          { service_name: "BROKEN", estimated_delivery_time: "5-10day", freight: { amount: 0 }, error_code: "SOME_ERROR" },
          { service_name: "OK_OPTION", estimated_delivery_time: "10-20day", freight: { amount: 3 }, error_code: null },
        ],
      },
    };
    const selected = selectPreferredFreightOption(result);
    assert.equal(selected.service_name, "OK_OPTION");
  });

  test("skips options with a missing estimated_delivery_time", () => {
    const result = {
      aeop_freight_calculate_result_for_buyer_d_t_o_list: {
        aeop_freight_calculate_result_for_buyer_dto: [
          { service_name: "NO_ESTIMATE", freight: { amount: 0 } },
          { service_name: "HAS_ESTIMATE", estimated_delivery_time: "10-20day", freight: { amount: 3 } },
        ],
      },
    };
    const selected = selectPreferredFreightOption(result);
    assert.equal(selected.service_name, "HAS_ESTIMATE");
  });

  test("returns null when no valid option exists", () => {
    const result = {
      aeop_freight_calculate_result_for_buyer_d_t_o_list: {
        aeop_freight_calculate_result_for_buyer_dto: [
          { service_name: "BROKEN", error_code: "NOT_SUPPORTED" },
        ],
      },
    };
    assert.equal(selectPreferredFreightOption(result), null);
  });

  test("returns null for a completely empty/malformed response", () => {
    assert.equal(selectPreferredFreightOption({}), null);
    assert.equal(selectPreferredFreightOption(null), null);
  });
});

describe("buildAliExpressFreightFirestoreFields", () => {
  test("valid option with a parseable range produces the full field set", () => {
    const option = {
      service_name: "CAINIAO_STANDARD",
      estimated_delivery_time: "10-20day",
      freight: { amount: 0, currency_code: "USD" },
      tracking_available: "true",
    };
    const fields = buildAliExpressFreightFirestoreFields(option);
    assert.equal(fields.deliveryMinDays, 10);
    assert.equal(fields.deliveryMaxDays, 20);
    assert.equal(fields.deliveryDays, 20); // backward compatibility = max
    assert.equal(fields.deliveryServiceName, "CAINIAO_STANDARD");
    assert.equal(fields.deliveryFreightAmount, 0);
    assert.equal(fields.deliveryFreightCurrency, "USD");
    assert.equal(fields.deliveryTrackingAvailable, true);
    assert.equal(fields.deliverySource, "aliexpress.logistics.buyer.freight.calculate");
    assert.equal(fields.deliverySourceField, "estimated_delivery_time");
    assert.equal(fields.deliverySyncStatus, "api_range");
  });

  test("tracking_available \"false\" string converts to boolean false", () => {
    const fields = buildAliExpressFreightFirestoreFields({
      estimated_delivery_time: "5-10day",
      tracking_available: "false",
    });
    assert.equal(fields.deliveryTrackingAvailable, false);
  });

  test("a selected option with malformed estimated_delivery_time text does not include day-range keys, and status reflects it", () => {
    const fields = buildAliExpressFreightFirestoreFields({
      service_name: "WEIRD_SERVICE",
      estimated_delivery_time: "soon-ish",
      freight: { amount: 2, currency_code: "USD" },
    });
    assert.equal("deliveryMinDays" in fields, false);
    assert.equal("deliveryMaxDays" in fields, false);
    assert.equal("deliveryDays" in fields, false);
    assert.equal(fields.deliveryServiceName, "WEIRD_SERVICE");
    assert.equal(fields.deliverySyncStatus, "malformed");
  });

  test("never sets an exact estimatedDeliveryDate field — the API does not provide one", () => {
    const fields = buildAliExpressFreightFirestoreFields({
      estimated_delivery_time: "10-20day",
    });
    assert.equal("estimatedDeliveryDate" in fields, false);
    assert.equal("estimatedDeliveryMinDate" in fields, false);
    assert.equal("estimatedDeliveryMaxDate" in fields, false);
  });
});
