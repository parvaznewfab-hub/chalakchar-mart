// -----------------------------------------------------------------------------
// ChalakChar Cash (users.points) on orders, and the order total check
// (14b step G). Written only by Cloud Functions; the client never writes
// users.points or orders.cashCheck (firestore.rules).
//
//   orders/{orderId}.cashCheck       result of the check, written once
//   users/{uid}.points               decreased by the redeemed Cash, and
//                                    increased again (once) on cancel/return
//   wallet_logs/cash_redeem_{id}     debit  log for the customer's wallet page
//   wallet_logs/cash_refund_{id}     credit log for the refund
//
// Cash is redeemed only when ALL of these hold; otherwise nothing is taken
// and cashCheck.ok = false (admin sees a red warning before confirming):
//   - settings/app.enableAbdCash is not false
//   - claimed <= settings/app.maxAbdCashRedeem (taka per order, default 100)
//   - claimed <= the customer's points
//   - claimed <= server subtotal - coupon
// The total check runs on EVERY order:
//   grandTotal == serverSubtotal - coupon - Cash + delivery   (not below 0)
// serverSubtotal is priced from products/ (priceOrder), never from the
// client's item prices. Coupon and delivery charge are still the client's
// numbers (checking them is step I).
//
// Pure (no Firestore), unit tested; cashTriggers.js does the reads/writes.
// -----------------------------------------------------------------------------

const DEFAULT_MAX_CASH_PER_ORDER = 100;
const MONEY_EPSILON = 0.01;

function toNumber(value, fallback = 0) {
  if (value === null || value === undefined || value === "") return fallback;
  const n = typeof value === "number" ? value : Number(String(value).trim());
  return Number.isFinite(n) ? n : fallback;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function has(obj, key) {
  return obj && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, key);
}

// settings/app -> { enabled, maxPerOrder }
function cashSettings(appSettings) {
  const s = appSettings || {};
  // enableChalakCharCash wins over the older enableAbdCash key (same as
  // AppSettingsService and lib/utils/chalakchar_cash.dart).
  const flag = has(s, "enableChalakCharCash") ? s.enableChalakCharCash : s.enableAbdCash;
  const enabled = flag !== false;
  const raw = has(s, "maxAbdCashRedeem") ? s.maxAbdCashRedeem : DEFAULT_MAX_CASH_PER_ORDER;
  const max = toNumber(raw, DEFAULT_MAX_CASH_PER_ORDER);
  return { enabled, maxPerOrder: max < 0 ? 0 : max };
}

function clientGrandTotal(order) {
  const o = order || {};
  if (has(o, "grandTotal")) return toNumber(o.grandTotal, NaN);
  if (has(o, "finalTotal")) return toNumber(o.finalTotal, NaN);
  return toNumber(o.total, NaN);
}

// { order, serverSubtotal, points, appSettings } -> cashCheck (without timestamps)
function checkOrderCash({ order, serverSubtotal, points, appSettings }) {
  const o = order || {};
  const { enabled, maxPerOrder } = cashSettings(appSettings);
  const claimedRaw = has(o, "chalakCharCashUsed") ? o.chalakCharCashUsed : 0;
  const claimed = toNumber(claimedRaw, NaN);
  const pd = o.paymentDiscounts && typeof o.paymentDiscounts === "object" ? o.paymentDiscounts : {};
  const pdClaim = has(pd, "chalakCharCashUsed") ? toNumber(pd.chalakCharCashUsed, NaN) : null;
  const coupon = toNumber(o.couponDiscount);
  const delivery = toNumber(o.deliveryCharge);
  const available = toNumber(points);
  const subtotal = round2(toNumber(serverSubtotal));

  let reason = null;
  if (!Number.isFinite(claimed) || claimed < 0) reason = "invalid_amount";
  else if (pdClaim !== null && (!Number.isFinite(pdClaim) || Math.abs(pdClaim - claimed) > MONEY_EPSILON)) reason = "claim_mismatch";
  else if (claimed > 0 && !enabled) reason = "cash_disabled";
  else if (claimed > maxPerOrder + MONEY_EPSILON) reason = "over_limit";
  else if (claimed > available + MONEY_EPSILON) reason = "not_enough_points";
  else if (claimed > subtotal - coupon + MONEY_EPSILON) reason = "over_order_value";

  const claimedSafe = Number.isFinite(claimed) && claimed > 0 ? round2(claimed) : 0;
  const ok = reason === null;

  const serverGrandRaw = round2(subtotal - coupon - claimedSafe + delivery);
  const serverGrandTotal = serverGrandRaw < 0 ? 0 : serverGrandRaw;
  const clientTotal = clientGrandTotal(o);
  const totalOk = Number.isFinite(clientTotal) && Math.abs(clientTotal - serverGrandTotal) <= MONEY_EPSILON;

  return {
    ok,
    reason,
    claimed: Number.isFinite(claimed) ? round2(claimed) : 0,
    deducted: ok ? claimedSafe : 0,
    available: round2(available),
    enabled,
    maxPerOrder,
    totalOk,
    clientGrandTotal: Number.isFinite(clientTotal) ? round2(clientTotal) : null,
    serverGrandTotal,
    serverSubtotal: subtotal,
    couponDiscount: round2(coupon),
    deliveryCharge: round2(delivery),
  };
}

// Status that gives the redeemed Cash back. Same reading of status as the
// ledger (targetForOrder): cancelled, returned / refunded.
function isRefundStatus(order) {
  const s = String((order && order.status) || "").trim().toLowerCase();
  return s === "cancelled" || s === "returned" || s === "refunded";
}

// cashCheck already on the order -> amount to give back now (0 = nothing).
function refundDue(cashCheck) {
  if (!cashCheck || typeof cashCheck !== "object") return 0;
  if (cashCheck.refundedAt || cashCheck.refunded === true) return 0;
  const d = toNumber(cashCheck.deducted);
  return d > 0 ? round2(d) : 0;
}

const redeemLogId = (orderId) => `cash_redeem_${orderId}`;
const refundLogId = (orderId) => `cash_refund_${orderId}`;

module.exports = {
  DEFAULT_MAX_CASH_PER_ORDER,
  cashSettings,
  checkOrderCash,
  isRefundStatus,
  refundDue,
  redeemLogId,
  refundLogId,
};
