const admin = require("firebase-admin");

// -----------------------------------------------------------------------------
// AliExpress delivery-estimate parsing.
//
// Two strictly separate concerns live in this module:
//
// 1. discoverAliExpressDeliveryCandidates() — DEBUG-ONLY discovery. Recursively
//    scans the raw response for anything that LOOKS delivery/logistics/
//    shipping-related and returns it for logging. Its output is never used to
//    pick a saved value — a blind keyword scan across the whole response tree
//    could just as easily match a promotion-expiry date, seller processing
//    time, or a warehouse timestamp as it could the actual delivery date.
//
// 2. parseAliExpressDeliveryEstimate() — the only function whose output is
//    ever saved to Firestore. It reads EXCLUSIVELY from
//    DELIVERY_FIELD_ALLOWLIST below: explicit [knownContainer, fieldKey]
//    pairs, scoped to response objects that are already known to be
//    logistics/shipping objects (currently just logistics_info_dto /
//    logistics_info). A field is never read here unless it is both in an
//    explicitly-known container AND named in the allowlist.
//
// STATUS: only `logistics.delivery_time` (a day-count, not a date) is
// confirmed present for this project's AliExpress account — that was already
// being read before this module existed. No exact-date field has been
// confirmed yet. The exact/min/max/text allowlists below are intentionally
// EMPTY until a real path is confirmed from production
// "ALIEXPRESS_DEBUG raw logistics-like fields" log output (see index.js's
// fetchAliExpressProduct) — never from guessing. Add a confirmed path as a
// one-line addition to the relevant allowlist array; no other code changes
// needed.
// -----------------------------------------------------------------------------

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

// DEBUG-ONLY. Recursively walks a raw AliExpress response and collects every
// key whose name looks delivery/logistics/shipping/freight related, keyed by
// dotted path, with values truncated/stringified for safe logging. Do not
// use this output to select what gets saved — see module doc above.
function discoverAliExpressDeliveryCandidates(value, path = "", out = {}, seen = new Set()) {
  if (Object.keys(out).length >= 200) return out;
  if (Array.isArray(value)) {
    value.forEach((item, index) => discoverAliExpressDeliveryCandidates(item, `${path}[${index}]`, out, seen));
    return out;
  }
  if (!value || typeof value !== "object" || seen.has(value)) return out;
  seen.add(value);
  for (const [key, child] of Object.entries(value)) {
    const keyPath = path ? `${path}.${key}` : key;
    if (/deliver|logist|ship|freight|lead_?time|transit|\beta\b/i.test(key)) {
      if (child && typeof child === "object") {
        out[keyPath] = "[object — see nested keys below]";
      } else {
        const text = String(child);
        out[keyPath] = text.length > 300 ? `${text.slice(0, 300)}…(truncated)` : text;
      }
    }
    discoverAliExpressDeliveryCandidates(child, keyPath, out, seen);
  }
  return out;
}

const MONTH_NAMES = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

function monthIndexFromToken(token) {
  const key = textValue(token).toLowerCase().replace(/\./g, "").slice(0, 3);
  const index = MONTH_NAMES.indexOf(key);
  return index === -1 ? null : index;
}

// Anchors a parsed delivery date to UTC midnight. Delivery estimates are
// calendar dates, not moments-in-time — anchoring to UTC midnight avoids
// off-by-one-day errors for Bangladesh (UTC+6) clients: a positive local
// offset only ever advances the displayed calendar date relative to UTC,
// never rewinds it, so this is safe without any explicit timezone library.
function utcMidnight(year, monthIndex, day) {
  return new Date(Date.UTC(year, monthIndex, day));
}

// Resolves the year for a month/day-only AliExpress date string (e.g.
// "Aug 12"), since that format never includes a year. Delivery estimates are
// always in the future, so if the month/day already passed this year (more
// than a couple of days ago, to tolerate same-day timing jitter), it must
// mean next year.
function resolveYearForMonthDay(monthIndex, day, referenceDate) {
  const ref = referenceDate instanceof Date && !Number.isNaN(referenceDate.getTime()) ? referenceDate : new Date();
  const refMidnight = utcMidnight(ref.getUTCFullYear(), ref.getUTCMonth(), ref.getUTCDate());
  let year = ref.getUTCFullYear();
  let candidate = utcMidnight(year, monthIndex, day);
  const staleMs = 2 * 24 * 60 * 60 * 1000;
  if (candidate.getTime() < refMidnight.getTime() - staleMs) {
    year += 1;
    candidate = utcMidnight(year, monthIndex, day);
  }
  return candidate;
}

// Parses a single delivery-date token of unknown shape: a Date instance,
// epoch seconds/milliseconds, an ISO date string, or AliExpress's "Aug 12" /
// "Aug. 12" / "12 Aug" free-text style (no year). Only ever called on a
// value that came from an allowlisted field — never on arbitrary prose.
function parseDeliveryDateToken(raw, referenceDate) {
  if (raw === null || raw === undefined) return null;
  if (raw instanceof Date) return Number.isNaN(raw.getTime()) ? null : raw;

  if (typeof raw === "number" && Number.isFinite(raw)) {
    const ms = raw > 1e12 ? raw : raw * 1000; // >1e12 ~ already milliseconds; else seconds
    const date = new Date(ms);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  const text = textValue(raw);
  if (!text) return null;

  if (/^\d{10,13}$/.test(text)) {
    return parseDeliveryDateToken(Number(text), referenceDate);
  }

  const isoMatch = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (isoMatch) {
    const [, y, m, d] = isoMatch;
    const date = utcMidnight(Number(y), Number(m) - 1, Number(d));
    return Number.isNaN(date.getTime()) ? null : date;
  }

  const monthFirst = text.match(/^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?$/);
  const dayFirst = !monthFirst ? text.match(/^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?$/) : null;
  const match = monthFirst || dayFirst;
  if (match) {
    const [, first, second] = match;
    const monthToken = Number.isNaN(Number(first)) ? first : second;
    const dayToken = Number.isNaN(Number(first)) ? second : first;
    const monthIndex = monthIndexFromToken(monthToken);
    const day = Number(dayToken);
    if (monthIndex !== null && Number.isFinite(day) && day >= 1 && day <= 31) {
      return resolveYearForMonthDay(monthIndex, day, referenceDate);
    }
  }

  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

// Explicitly-known logistics/shipping response objects. A new named
// container may only be added here once its existence is confirmed from
// real AliExpress response logs — never guessed.
function resolveKnownContainers(result) {
  return {
    logistics: mapValue(result.logistics_info_dto || result.logistics_info),
  };
}

// Allowlist entries: [containerName, fieldKey]. containerName must be a key
// of resolveKnownContainers()'s return value. See module doc for the
// "confirmed from real logs only" rule.
const EXACT_DATE_FIELD_ALLOWLIST = [
  // e.g. ["logistics", "estimated_delivery_date"] — add once confirmed.
];
const MIN_DATE_FIELD_ALLOWLIST = [
  // e.g. ["logistics", "min_delivery_date"] — add once confirmed.
];
const MAX_DATE_FIELD_ALLOWLIST = [
  // e.g. ["logistics", "max_delivery_date"] — add once confirmed.
];
const TEXT_FIELD_ALLOWLIST = [
  // e.g. ["logistics", "delivery_date_desc"] — add once confirmed.
];
const SHIPPING_METHOD_FIELD_ALLOWLIST = [
  // e.g. ["logistics", "service_name"] — add once confirmed.
];
const DAYS_FIELD_ALLOWLIST = [
  ["logistics", "delivery_time"], // confirmed present (pre-existing behavior)
];

function findAllowlisted(containers, allowlist) {
  for (const [containerName, key] of allowlist) {
    const container = containers[containerName];
    if (!container) continue;
    const value = container[key];
    if (value !== undefined && value !== null && textValue(value).length) {
      return { key: `${containerName}.${key}`, value };
    }
  }
  return null;
}

/**
 * Parses an AliExpress `aliexpress.ds.product.get` raw API response into a
 * normalized delivery estimate, reading ONLY from the allowlists above.
 * Supports (once a real field is confirmed and allowlisted): an exact date,
 * a min/max date range, ISO date strings, unix timestamps (seconds or
 * milliseconds), and "Aug 12"-style text (with year resolution). A numeric
 * day-count (`delivery_time`) is the confirmed, always-available fallback.
 *
 * @param {object} apiResponse raw response from aliExpressSignedApiRequest
 * @param {{referenceDate?: Date}} options
 */
function parseAliExpressDeliveryEstimate(apiResponse, options = {}) {
  const referenceDate = options.referenceDate instanceof Date ? options.referenceDate : new Date();
  const root = mapValue(apiResponse);
  const result = mapValue(root.result || root.data || root);
  const containers = resolveKnownContainers(result);

  const exactMatch = findAllowlisted(containers, EXACT_DATE_FIELD_ALLOWLIST);
  const minMatch = findAllowlisted(containers, MIN_DATE_FIELD_ALLOWLIST);
  const maxMatch = findAllowlisted(containers, MAX_DATE_FIELD_ALLOWLIST);
  const textMatch = findAllowlisted(containers, TEXT_FIELD_ALLOWLIST);
  const daysMatch = findAllowlisted(containers, DAYS_FIELD_ALLOWLIST);
  const shippingMatch = findAllowlisted(containers, SHIPPING_METHOD_FIELD_ALLOWLIST);

  const estimatedDeliveryDate = exactMatch ? parseDeliveryDateToken(exactMatch.value, referenceDate) : null;
  const estimatedDeliveryMinDate = minMatch ? parseDeliveryDateToken(minMatch.value, referenceDate) : null;
  const estimatedDeliveryMaxDate = maxMatch ? parseDeliveryDateToken(maxMatch.value, referenceDate) : null;
  // Preserved exactly as AliExpress returned it — never mined for a date.
  const estimatedDeliveryText = textMatch ? textValue(textMatch.value) : "";

  let deliveryDays = null;
  let deliverySourceField = null;
  let deliverySyncStatus = "no_data";

  if (estimatedDeliveryDate) {
    deliveryDays = Math.max(0, Math.round((estimatedDeliveryDate.getTime() - referenceDate.getTime()) / 86400000));
    deliverySourceField = exactMatch.key;
    deliverySyncStatus = "exact_date";
  } else if (estimatedDeliveryMaxDate) {
    deliveryDays = Math.max(0, Math.round((estimatedDeliveryMaxDate.getTime() - referenceDate.getTime()) / 86400000));
    deliverySourceField = maxMatch.key;
    deliverySyncStatus = "date_range";
  } else if (daysMatch && Number.isFinite(Number(daysMatch.value))) {
    deliveryDays = Math.max(0, Math.trunc(Number(daysMatch.value)));
    deliverySourceField = daysMatch.key;
    deliverySyncStatus = "fallback_days";
  }

  return {
    estimatedDeliveryDate,
    estimatedDeliveryMinDate,
    estimatedDeliveryMaxDate,
    estimatedDeliveryText,
    deliveryDays,
    shippingMethod: shippingMatch ? textValue(shippingMatch.value) : "",
    deliverySource: "aliexpress_api",
    deliverySourceField,
    deliverySyncStatus,
  };
}

/**
 * Converts a parseAliExpressDeliveryEstimate() result into Firestore-ready
 * fields (Timestamps, not raw Dates). Only includes keys AliExpress actually
 * gave us this time — callers should spread this into an update/set payload
 * so a previously-saved exact date is never clobbered when AliExpress
 * temporarily returns no delivery data for a product: if no new exact date
 * was found, `estimatedDeliveryDate` is simply absent from the returned
 * object, leaving whatever is already in Firestore untouched.
 */
function buildAliExpressDeliveryFirestoreFields(estimate) {
  const est = estimate || {};
  const fields = {};
  if (est.estimatedDeliveryDate instanceof Date && !Number.isNaN(est.estimatedDeliveryDate.getTime())) {
    fields.estimatedDeliveryDate = admin.firestore.Timestamp.fromDate(est.estimatedDeliveryDate);
  }
  if (est.estimatedDeliveryMinDate instanceof Date && !Number.isNaN(est.estimatedDeliveryMinDate.getTime())) {
    fields.estimatedDeliveryMinDate = admin.firestore.Timestamp.fromDate(est.estimatedDeliveryMinDate);
  }
  if (est.estimatedDeliveryMaxDate instanceof Date && !Number.isNaN(est.estimatedDeliveryMaxDate.getTime())) {
    fields.estimatedDeliveryMaxDate = admin.firestore.Timestamp.fromDate(est.estimatedDeliveryMaxDate);
  }
  if (textValue(est.estimatedDeliveryText)) fields.estimatedDeliveryText = est.estimatedDeliveryText;
  if (textValue(est.shippingMethod)) fields.shippingMethod = est.shippingMethod;
  if (est.deliveryDays !== null && est.deliveryDays !== undefined && Number.isFinite(Number(est.deliveryDays))) {
    fields.deliveryDays = Math.max(0, Math.trunc(Number(est.deliveryDays)));
  }

  return {
    ...fields,
    deliverySource: "aliexpress_api",
    deliverySourceField: est.deliverySourceField || null,
    deliverySyncStatus: est.deliverySyncStatus || "no_data",
    deliveryLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

module.exports = {
  parseAliExpressDeliveryEstimate,
  buildAliExpressDeliveryFirestoreFields,
  discoverAliExpressDeliveryCandidates,
  // exported for tests only
  _internal: { parseDeliveryDateToken, resolveYearForMonthDay, utcMidnight },
};
