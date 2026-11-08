const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  parseAliExpressDeliveryEstimate,
  buildAliExpressDeliveryFirestoreFields,
  discoverAliExpressDeliveryCandidates,
  _internal,
} = require("../aliexpress/deliveryEstimate");

const { parseDeliveryDateToken } = _internal;

// NOTE ON SCOPE: parseAliExpressDeliveryEstimate() only ever reads from an
// explicit allowlist scoped to the confirmed `logistics_info_dto` /
// `logistics_info` container (see module doc). As of this writing, no exact
// delivery-date field has been confirmed for this AliExpress account, so the
// exact/min/max/text allowlists are intentionally empty and only
// `logistics.delivery_time` (a day-count) is active. Tests below therefore
// cover:
//   - the underlying date-token parser directly, via `_internal`, for exact
//     ISO dates / unix timestamps / "Aug 12"-style text (proving the parsing
//     engine itself is correct and ready for when a field is allowlisted)
//   - parseAliExpressDeliveryEstimate() end-to-end against the fields that
//     ARE currently active (delivery_time fallback, missing data)
//   - buildAliExpressDeliveryFirestoreFields() for the "don't erase a valid
//     exact date" guarantee, using a synthetic estimate to simulate what
//     happens once an exact-date field is confirmed and allowlisted

describe("parseDeliveryDateToken (date-parsing primitives)", () => {
  const ref = new Date(Date.UTC(2026, 6, 24)); // 2026-07-24

  test("exact ISO delivery date", () => {
    const date = parseDeliveryDateToken("2026-08-12", ref);
    assert.equal(date.getUTCFullYear(), 2026);
    assert.equal(date.getUTCMonth(), 7); // August
    assert.equal(date.getUTCDate(), 12);
  });

  test("unix timestamp in seconds", () => {
    const seconds = Math.floor(Date.UTC(2026, 7, 12) / 1000);
    const date = parseDeliveryDateToken(seconds, ref);
    assert.equal(date.getUTCFullYear(), 2026);
    assert.equal(date.getUTCMonth(), 7);
    assert.equal(date.getUTCDate(), 12);
  });

  test("unix timestamp in milliseconds", () => {
    const ms = Date.UTC(2026, 7, 12);
    const date = parseDeliveryDateToken(ms, ref);
    assert.equal(date.getUTCFullYear(), 2026);
    assert.equal(date.getUTCMonth(), 7);
    assert.equal(date.getUTCDate(), 12);
  });

  test('"Aug 12" text resolves to the current year when still upcoming', () => {
    const date = parseDeliveryDateToken("Aug 12", ref);
    assert.equal(date.getUTCFullYear(), 2026);
    assert.equal(date.getUTCMonth(), 7);
    assert.equal(date.getUTCDate(), 12);
  });

  test('"Aug. 12" (with period) parses the same as "Aug 12"', () => {
    const date = parseDeliveryDateToken("Aug. 12", ref);
    assert.equal(date.getUTCMonth(), 7);
    assert.equal(date.getUTCDate(), 12);
  });

  test('"12 Aug" (day-first) parses correctly', () => {
    const date = parseDeliveryDateToken("12 Aug", ref);
    assert.equal(date.getUTCMonth(), 7);
    assert.equal(date.getUTCDate(), 12);
  });

  test('"Jan 5" rolls over to next year when the reference date is in December', () => {
    const decemberRef = new Date(Date.UTC(2026, 11, 20)); // 2026-12-20
    const date = parseDeliveryDateToken("Jan 5", decemberRef);
    assert.equal(date.getUTCFullYear(), 2027);
    assert.equal(date.getUTCMonth(), 0);
    assert.equal(date.getUTCDate(), 5);
  });

  test("invalid text returns null", () => {
    assert.equal(parseDeliveryDateToken("not a date", ref), null);
  });

  test("null/undefined returns null", () => {
    assert.equal(parseDeliveryDateToken(null, ref), null);
    assert.equal(parseDeliveryDateToken(undefined, ref), null);
  });
});

describe("parseAliExpressDeliveryEstimate (allowlisted fields only)", () => {
  test("only deliveryDays available (delivery_time = 19) — proves per-product values, not hardcoded", () => {
    const apiResponse = { result: { logistics_info_dto: { delivery_time: "19" } } };
    const estimate = parseAliExpressDeliveryEstimate(apiResponse);
    assert.equal(estimate.deliveryDays, 19);
    assert.equal(estimate.estimatedDeliveryDate, null);
    assert.equal(estimate.deliverySyncStatus, "fallback_days");
    assert.equal(estimate.deliverySourceField, "logistics.delivery_time");
  });

  test("a different product with delivery_time = 64 gets 64, not 7", () => {
    const apiResponse = { result: { logistics_info_dto: { delivery_time: "64" } } };
    const estimate = parseAliExpressDeliveryEstimate(apiResponse);
    assert.equal(estimate.deliveryDays, 64);
  });

  test("missing delivery data entirely", () => {
    const apiResponse = { result: { logistics_info_dto: {} } };
    const estimate = parseAliExpressDeliveryEstimate(apiResponse);
    assert.equal(estimate.deliveryDays, null);
    assert.equal(estimate.estimatedDeliveryDate, null);
    assert.equal(estimate.estimatedDeliveryText, "");
    assert.equal(estimate.deliverySyncStatus, "no_data");
    assert.equal(estimate.deliverySourceField, null);
  });

  test("unrelated nested fields (e.g. a promotion expiry date) are never picked up", () => {
    const apiResponse = {
      result: {
        logistics_info_dto: { delivery_time: 19 },
        promotion_info: { promotion_expiry_date: "2026-08-01", delivery_unrelated_note: "ignore me" },
      },
    };
    const estimate = parseAliExpressDeliveryEstimate(apiResponse);
    // Only the allowlisted logistics.delivery_time should ever be used —
    // nothing from promotion_info, even though it matches delivery-ish
    // keywords, should leak into the result.
    assert.equal(estimate.deliveryDays, 19);
    assert.equal(estimate.estimatedDeliveryDate, null);
  });
});

describe("discoverAliExpressDeliveryCandidates (debug-only, never used for parsing)", () => {
  test("finds keyword-matching paths for logging without affecting parseAliExpressDeliveryEstimate", () => {
    const result = {
      logistics_info_dto: { delivery_time: 19 },
      promotion_info: { promotion_expiry_date: "2026-08-01" },
    };
    const found = discoverAliExpressDeliveryCandidates(result);
    assert.ok("logistics_info_dto.delivery_time" in found);
    // Confirms the discovery scan is intentionally broad (would surface
    // unrelated fields too) — which is exactly why it must stay debug-only.
  });
});

describe("buildAliExpressDeliveryFirestoreFields (Firestore write-safety)", () => {
  test("a fresh valid exact date produces a Timestamp field ready to write (simulates an API date change during sync)", () => {
    const estimate = {
      estimatedDeliveryDate: new Date(Date.UTC(2026, 7, 12)),
      estimatedDeliveryMinDate: null,
      estimatedDeliveryMaxDate: null,
      estimatedDeliveryText: "",
      deliveryDays: 19,
      shippingMethod: "",
      deliverySourceField: "logistics.estimated_delivery_date",
      deliverySyncStatus: "exact_date",
    };
    const fields = buildAliExpressDeliveryFirestoreFields(estimate);
    assert.equal(fields.estimatedDeliveryDate.toDate().getUTCDate(), 12);
    assert.equal(fields.deliveryDays, 19);
    assert.equal(fields.deliverySyncStatus, "exact_date");
  });

  test("min/max date range produces both Timestamp fields", () => {
    const estimate = {
      estimatedDeliveryDate: null,
      estimatedDeliveryMinDate: new Date(Date.UTC(2026, 7, 10)),
      estimatedDeliveryMaxDate: new Date(Date.UTC(2026, 7, 12)),
      estimatedDeliveryText: "",
      deliveryDays: 19,
      shippingMethod: "",
      deliverySourceField: "logistics.max_delivery_date",
      deliverySyncStatus: "date_range",
    };
    const fields = buildAliExpressDeliveryFirestoreFields(estimate);
    assert.equal(fields.estimatedDeliveryMinDate.toDate().getUTCDate(), 10);
    assert.equal(fields.estimatedDeliveryMaxDate.toDate().getUTCDate(), 12);
  });

  test("original delivery text is preserved exactly, not reformatted", () => {
    const estimate = {
      estimatedDeliveryDate: null,
      estimatedDeliveryMinDate: null,
      estimatedDeliveryMaxDate: null,
      estimatedDeliveryText: "Delivery: Aug. 12 (estimated)",
      deliveryDays: null,
      shippingMethod: "",
      deliverySourceField: "logistics.delivery_date_desc",
      deliverySyncStatus: "no_data",
    };
    const fields = buildAliExpressDeliveryFirestoreFields(estimate);
    assert.equal(fields.estimatedDeliveryText, "Delivery: Aug. 12 (estimated)");
  });

  test("API temporarily returns no delivery data — no date keys are included, so an existing Firestore exact date is never erased", () => {
    const fields = buildAliExpressDeliveryFirestoreFields(null);
    assert.equal("estimatedDeliveryDate" in fields, false);
    assert.equal("estimatedDeliveryMinDate" in fields, false);
    assert.equal("estimatedDeliveryMaxDate" in fields, false);
    assert.equal("estimatedDeliveryText" in fields, false);
    assert.equal("deliveryDays" in fields, false);
    assert.equal(fields.deliverySyncStatus, "no_data");
    // deliveryLastSyncedAt/deliverySource/deliverySourceField/deliverySyncStatus
    // are always present (bookkeeping), but a caller spreading this object
    // into a Firestore .update() call will leave every date field it does
    // not mention completely untouched.
  });
});
