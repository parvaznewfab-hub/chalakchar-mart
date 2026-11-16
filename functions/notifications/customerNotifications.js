// Customer notification text (Bangla) and the link fields a notification doc
// carries so the app can open what it is about. Pure: no Firestore here.
//
// Doc fields added for customers (besides title/body/data):
//   type      data.type, also at top level (the app shows a label from it)
//   category  "order" | "new_product" | "offer" (label + preference filter)
//   productId product the notification is about -> product page
//   orderId   order the notification is about -> order tracking page
//   route     web path for productId ("/product/<id>")

const ORDER_STATUS_BN = {
  pending: "অপেক্ষমাণ",
  confirmed: "নিশ্চিত করা হয়েছে",
  processing: "প্রস্তুত হচ্ছে",
  ready_for_pickup: "পাঠানোর জন্য প্রস্তুত",
  assigned_to_rider: "ডেলিভারি কর্মীকে দেওয়া হয়েছে",
  assigned: "ডেলিভারি কর্মীকে দেওয়া হয়েছে",
  picked_up: "পথে আছে",
  on_the_way: "পথে আছে",
  out_for_delivery: "পথে আছে",
  delivered: "ডেলিভারি হয়েছে",
  cancelled: "বাতিল করা হয়েছে",
  returned: "ফেরত এসেছে",
};

const ORDER_TYPES = new Set(["order", "order_status", "picked_up", "order_delivered", "order_placed"]);
const OFFER_TYPES = new Set(["wishlist_discount", "offer", "broadcast", "promo", "price_drop"]);
const PRODUCT_TYPES = new Set(["new_product", "search_import_done", "back_in_stock"]);

/** Marketing (new products and offers) is what the user can switch off. */
const MARKETING_TYPES = new Set(["new_product", "back_in_stock", "wishlist_discount", "offer", "broadcast", "promo", "price_drop"]);

function shortOrderId(orderId) {
  return String(orderId || "").substring(0, 8);
}

function orderStatusBn(status) {
  const key = String(status || "").trim();
  return ORDER_STATUS_BN[key] || key;
}

function categoryForType(type) {
  const t = String(type || "").trim();
  if (ORDER_TYPES.has(t) || t.startsWith("order")) return "order";
  if (OFFER_TYPES.has(t)) return "offer";
  if (PRODUCT_TYPES.has(t)) return "new_product";
  return "general";
}

function isMarketingType(type) {
  return MARKETING_TYPES.has(String(type || "").trim());
}

/**
 * false only when the user switched off "নতুন পণ্য ও অফার" in Settings
 * (users/{uid}.notificationPrefs.marketing === false). Order updates ignore it.
 */
function allowsMarketing(user) {
  const prefs = user && typeof user.notificationPrefs === "object" ? user.notificationPrefs : null;
  return !(prefs && prefs.marketing === false);
}

/** Top-level fields for a customer notification doc, from its data map. */
function linkFields(data = {}) {
  const type = String(data.type || "").trim();
  const fields = { category: categoryForType(type) };
  if (type) fields.type = type;

  let productId = String(data.productId || "").trim();
  if (!productId && Array.isArray(data.productIds) && data.productIds.length > 0) {
    productId = String(data.productIds[0] || "").trim();
  }
  if (productId) {
    fields.productId = productId;
    fields.route = `/product/${encodeURIComponent(productId)}`;
  }

  const orderId = String(data.orderId || "").trim();
  if (orderId) fields.orderId = orderId;

  return fields;
}

const templates = {
  orderStatus(orderId, status) {
    return {
      title: "অর্ডার আপডেট",
      body: `আপনার অর্ডার #${shortOrderId(orderId)} এখন: ${orderStatusBn(status)}।`,
    };
  },
  orderPickedUp(orderId) {
    return {
      title: "অর্ডার পথে আছে 🚚",
      body: `আপনার অর্ডার #${shortOrderId(orderId)} রওনা হয়েছে।`,
    };
  },
  orderDelivered(orderId) {
    return {
      title: "অর্ডার ডেলিভারি হয়েছে ✅",
      body: `আপনার অর্ডার #${shortOrderId(orderId)} সফলভাবে ডেলিভারি হয়েছে।`,
    };
  },
  /** names: names of the imported products, first one is linked. */
  searchImportFound(names, query) {
    const clean = (names || []).map((n) => String(n || "").trim()).filter(Boolean);
    const first = clean[0];
    if (!first) {
      const q = String(query || "").trim();
      return {
        title: "আপনার খোঁজা পণ্য পাওয়া গেছে! 🎉",
        body: q ? `"${q}" এখন পাওয়া যাচ্ছে। দেখতে চাপুন।` : "আপনি যে পণ্যটি খুঁজছিলেন সেটি এখন পাওয়া যাচ্ছে।",
      };
    }
    const more = clean.length > 1 ? ` (আরও ${clean.length - 1}টি পণ্য)` : "";
    return {
      title: "আপনার খোঁজা পণ্য পাওয়া গেছে! 🎉",
      body: `${first}${more} এখন পাওয়া যাচ্ছে। দেখতে চাপুন।`,
    };
  },
  backInStock(name) {
    return {
      title: "পছন্দের পণ্য আবার স্টকে 📦",
      body: `${String(name || "").trim() || "আপনার পছন্দের পণ্য"} আবার পাওয়া যাচ্ছে।`,
    };
  },
  wishlistDiscount(name, percent) {
    return {
      title: "পছন্দের পণ্যে ছাড় 🏷️",
      body: `${String(name || "").trim() || "আপনার পছন্দের পণ্য"}-এ এখন ${percent}% ছাড়।`,
    };
  },
};

module.exports = {
  ORDER_STATUS_BN,
  orderStatusBn,
  categoryForType,
  isMarketingType,
  allowsMarketing,
  linkFields,
  templates,
};
