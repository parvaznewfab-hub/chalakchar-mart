// -----------------------------------------------------------------------------
// Step H2: who may cause automatic product marketing.
//
// Before step H2 any signed-in user could create a live, "approved" product,
// and onProductCreated then pushed it to up to 1000 customers and queued it
// for the shop's Facebook / Instagram / WhatsApp (live history: "posted"),
// with captions the creator wrote. The rules now stop that, and this is the
// second line: the new create trigger (onProductCreatedChecked) knows who
// wrote the document (onDocumentCreatedWithAuthContext) and markets only
//   - products written by the backend (service account: functions, imports,
//     scripts) or by staff in the app (admin / super admin / owner, or a
//     products.edit permission), not blocked; and
//   - never a vendor's product (owner's decision 2026-11-28: no automatic
//     marketing or push for vendor products, even after approval; an admin
//     can still queue one by hand).
// The product's own state (approved, live, not needsReview, not
// autoMarketingDisabled) is still checked by shouldMarketProduct.
// Pure helpers + one users/{uid} read (deps.db).
// -----------------------------------------------------------------------------

const SHOP_VENDOR_IDS = Object.freeze(["", "super_admin", "admin", "shop"]);
const STAFF_ROLES = Object.freeze(["admin", "superAdmin", "super_admin", "owner"]);
const BACKEND_AUTH_TYPES = Object.freeze(["service_account", "system"]);

function text(value) {
  return value === null || value === undefined ? "" : String(value).trim();
}

/** A vendor's product (marketplace listing), not one of the shop's own. */
function isVendorProduct(product) {
  if (!product || typeof product !== "object") return false;
  if (product.isMarketplace === true) return true;
  return !SHOP_VENDOR_IDS.includes(text(product.vendorId));
}

function hasPermission(user, permission) {
  const granted = user && user.permissions;
  if (Array.isArray(granted)) return granted.includes(permission);
  if (granted && typeof granted === "object") return granted[permission] === true;
  return false;
}

/** Staff who may publish shop products (same idea as can('products.edit')). */
function isProductStaff(user) {
  if (!user || typeof user !== "object") return false;
  if (user.isActive === false || user.isBanned === true) return false;
  const roles = Array.isArray(user.roles) ? user.roles : [];
  if (STAFF_ROLES.includes(user.role) || roles.some((r) => STAFF_ROLES.includes(r))) return true;
  return hasPermission(user, "products.edit");
}

/**
 * Why the writer of a new product may not trigger automatic marketing, or
 * null when they may. authType / authId come from the Firestore event
 * ("app_user" + uid, "service_account", "system", "api_key",
 * "unauthenticated", "unknown").
 */
async function writerBlockReason({ authType, authId, deps }) {
  const type = text(authType);
  if (BACKEND_AUTH_TYPES.includes(type)) return null;
  if (type !== "app_user") return `writer_${type || "unknown"}`;
  const uid = text(authId);
  if (!uid) return "writer_no_uid";
  const snap = await deps.db.collection("users").doc(uid).get();
  if (!snap.exists) return "writer_no_profile";
  return isProductStaff(snap.data()) ? null : "writer_not_staff";
}

/**
 * The decision for a newly created product: { market, reason }.
 * productBlockReason: the existing product-state check (shouldMarketProduct
 * as a reason function), passed in so the rule stays in one place.
 */
async function newProductMarketingDecision({ authType, authId, product, productBlockReason, deps }) {
  if (isVendorProduct(product)) return { market: false, reason: "vendor_product" };
  const productReason = productBlockReason(product);
  if (productReason) return { market: false, reason: productReason };
  const writerReason = await writerBlockReason({ authType, authId, deps });
  if (writerReason) return { market: false, reason: writerReason };
  return { market: true, reason: null };
}

module.exports = {
  SHOP_VENDOR_IDS,
  isVendorProduct,
  isProductStaff,
  writerBlockReason,
  newProductMarketingDecision,
};
