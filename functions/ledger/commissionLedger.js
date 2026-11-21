// -----------------------------------------------------------------------------
// Vendor commission ledger, written only by Cloud Functions (ledger-1).
//
//   commission_ledger/{orderId}_{vendorId}   one doc per vendor per order
//   vendor_private/{vendorId}                totals and balances (increments)
//   orders/{orderId}.priceCheck              client vs server totals
//
// Nothing here trusts the client's prices, quantities or vendor ids: every
// item is priced again from products/{productId} (variant price when the
// item names a variant), attributed to the product's own vendorId, and any
// difference is recorded (priceCheck, priceMismatch / needsReview).
//
// This file is pure (no Firestore) so it can be unit tested; the triggers
// in ledgerTriggers.js read and write inside transactions.
// -----------------------------------------------------------------------------

const DEFAULT_COMMISSION_PERCENT = 10;
const HOUSE_VENDOR = "super_admin";
const MONEY_EPSILON = 0.005;

function toNumber(value, fallback = 0) {
  if (value === null || value === undefined || value === "") return fallback;
  const n = typeof value === "number" ? value : Number(String(value).trim());
  return Number.isFinite(n) ? n : fallback;
}

function text(value) {
  return value === null || value === undefined ? "" : String(value).trim();
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function vendorOfProduct(product) {
  const v = text(product && product.vendorId);
  return v || HOUSE_VENDOR;
}

// Same rule as vendorCommissionPercent() in lib/utils/private_profile_fields.dart:
// commissionPercent, else commissionRate; 0 stays 0; 10 only when never set.
function commissionPercentOf(vendorPrivate) {
  const data = vendorPrivate || {};
  for (const key of ["commissionPercent", "commissionRate"]) {
    const raw = data[key];
    if (raw === null || raw === undefined || raw === "") continue;
    const n = toNumber(raw, NaN);
    if (Number.isFinite(n) && n >= 0 && n <= 100) return n;
  }
  return DEFAULT_COMMISSION_PERCENT;
}

// The variant an order item refers to: by variant id, then by unit name
// (name / unit / variantName, as ProductService.selectedVariant), then the
// first variant. null when the product has no variants.
function variantForItem(product, item) {
  const variants = Array.isArray(product && product.variants)
    ? product.variants.filter((v) => v && typeof v === "object")
    : [];
  if (!variants.length) return null;
  const id = text(item.variantId);
  if (id && id !== "default") {
    const byId = variants.find((v) => text(v.id) === id || text(v.variantId) === id);
    if (byId) return byId;
  }
  const unit = text(item.unit).toLowerCase();
  if (unit) {
    for (const key of ["name", "unit", "variantName"]) {
      const hit = variants.find((v) => text(v[key]).toLowerCase() === unit);
      if (hit) return hit;
    }
  }
  return variants[0];
}

function serverUnitPrice(product, item) {
  const variant = variantForItem(product, item);
  if (variant && variant.price !== undefined && variant.price !== null && variant.price !== "") {
    return toNumber(variant.price);
  }
  return toNumber(product.price !== undefined ? product.price : product.piecePrice);
}

// order + products ({ [productId]: data | null }) ->
//   { priceCheck, byVendor: { [vendorId]: { subtotal, itemCount, priceMismatch, mismatchedItems } } }
// House (super_admin) items are price-checked too but get no ledger.
function priceOrder(order, products) {
  const items = Array.isArray(order && order.items) ? order.items : [];
  let clientTotal = 0;
  let serverTotal = 0;
  const mismatchedItems = [];
  const byVendor = {};

  items.forEach((raw, index) => {
    const item = raw && typeof raw === "object" ? raw : {};
    const productId = text(item.productId);
    const clientQtyRaw = toNumber(item.qty, NaN);
    const clientPrice = toNumber(item.price);
    const clientVendor = text(item.vendorId) || HOUSE_VENDOR;
    const reasons = [];

    const qtyOk = Number.isInteger(clientQtyRaw) && clientQtyRaw >= 1;
    const qty = qtyOk ? clientQtyRaw : 0;
    if (!qtyOk) reasons.push("qty");
    clientTotal += clientPrice * (Number.isFinite(clientQtyRaw) ? clientQtyRaw : 0);

    const product = productId ? products[productId] : null;
    if (!product) {
      reasons.push("product_missing");
      mismatchedItems.push({ index, productId, reasons });
      return;
    }

    const unitPrice = serverUnitPrice(product, item);
    const vendorId = vendorOfProduct(product);
    if (Math.abs(unitPrice - clientPrice) > MONEY_EPSILON) reasons.push("price");
    if (vendorId !== clientVendor) reasons.push("vendor");

    const line = unitPrice * qty;
    serverTotal += line;
    if (reasons.length) mismatchedItems.push({ index, productId, reasons });

    if (vendorId === HOUSE_VENDOR) return;
    const v = byVendor[vendorId] || (byVendor[vendorId] = {
      subtotal: 0, itemCount: 0, priceMismatch: false, mismatchedItems: [],
    });
    v.subtotal += line;
    v.itemCount += qty;
    if (reasons.length) {
      v.priceMismatch = true;
      v.mismatchedItems.push({ index, productId, reasons });
    }
  });

  for (const v of Object.values(byVendor)) v.subtotal = round2(v.subtotal);
  clientTotal = round2(clientTotal);
  serverTotal = round2(serverTotal);

  return {
    priceCheck: {
      ok: mismatchedItems.length === 0 && Math.abs(clientTotal - serverTotal) <= MONEY_EPSILON,
      clientTotal,
      serverTotal,
      mismatchedItems,
    },
    byVendor,
  };
}

// The new pending ledger doc and the vendor_private increments for one vendor.
function newLedgerEntry({ orderId, vendorId, priced, vendorPrivate }) {
  const percent = commissionPercentOf(vendorPrivate);
  const adminCommission = round2(priced.subtotal * percent / 100);
  const vendorPayable = round2(priced.subtotal - adminCommission);
  return {
    ledger: {
      orderId,
      vendorId,
      subtotal: priced.subtotal,
      itemCount: priced.itemCount,
      commissionPercent: percent,
      adminCommission,
      vendorPayable,
      status: "pending",
      withdrawStatus: "not_requested",
      priceMismatch: priced.priceMismatch,
      needsReview: priced.priceMismatch,
      mismatchedItems: priced.mismatchedItems,
      debtCreated: false,
    },
    money: {
      totalSales: priced.subtotal,
      totalCommission: adminCommission,
      pendingBalance: vendorPayable,
    },
  };
}

// The ledger state an order status asks for, or null for "nothing to do".
//   delivered: status or deliveryStatus became "delivered" (admin or rider)
//   cancelled: status "cancelled"
//   returned:  status "returned" or "refunded"
function targetForOrder(before, after) {
  const b = before || {};
  const a = after || {};
  const statusChanged = text(b.status) !== text(a.status);
  const deliveryChanged = text(b.deliveryStatus) !== text(a.deliveryStatus);
  if (!statusChanged && !deliveryChanged) return null;
  const s = text(a.status).toLowerCase();
  if (s === "returned" || s === "refunded") return "returned";
  if (s === "cancelled") return "cancelled";
  if (s === "delivered" || text(a.deliveryStatus).toLowerCase() === "delivered") return "delivered";
  return null;
}

// One step forward only. Returns { status, money } or null (no-op).
//   pending   -> delivered | cancelled | returned
//   delivered -> cancelled | returned        (money already withdrawable)
//   cancelled, returned: final
function transition(ledger, target) {
  const from = text(ledger && ledger.status) || "pending";
  const subtotal = toNumber(ledger.subtotal);
  const commission = toNumber(ledger.adminCommission);
  const payable = toNumber(ledger.vendorPayable);
  if (from === target) return null;
  if (from === "cancelled" || from === "returned") return null;

  if (from === "pending" && target === "delivered") {
    return { status: "delivered", money: { pendingBalance: -payable, withdrawableBalance: payable, deliveredOrders: 1 } };
  }
  if (from === "pending" && (target === "cancelled" || target === "returned")) {
    return {
      status: target,
      money: { pendingBalance: -payable, totalSales: -subtotal, totalCommission: -commission, cancelledOrders: 1 },
    };
  }
  if (from === "delivered" && (target === "cancelled" || target === "returned")) {
    return {
      status: target,
      money: { withdrawableBalance: -payable, totalSales: -subtotal, totalCommission: -commission, cancelledOrders: 1 },
    };
  }
  return null;
}

function ledgerDocId(orderId, vendorId) {
  return `${orderId}_${vendorId}`;
}

module.exports = {
  DEFAULT_COMMISSION_PERCENT,
  HOUSE_VENDOR,
  commissionPercentOf,
  variantForItem,
  serverUnitPrice,
  priceOrder,
  newLedgerEntry,
  targetForOrder,
  transition,
  ledgerDocId,
};
