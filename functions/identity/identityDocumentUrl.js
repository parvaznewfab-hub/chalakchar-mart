// -----------------------------------------------------------------------------
// 14b step C: admin-only viewing of vendor / rider identity documents.
//
// getIdentityDocumentUrl({ kind, ownerId, which }) returns a V4 signed URL
// that works for 5 minutes. It never trusts a path from the client:
//   - kind:  "vendor" | "rider"
//   - ownerId: the vendor doc id / rider uid
//   - which: vendor "nidFront" | "nidBack" | "tradeLicense"; rider "nidFront" | "nidBack"
// The Storage path is read from vendor_private/{ownerId} or
// delivery_partner_private/{ownerId} and must sit inside that owner's own
// document folder. The URL is returned only; it is never stored or logged.
// The log line holds who, when, whose (ownerId) and which kind of document (no path, no URL,
// no personal value).
//
// Permissions (same lists as storage.rules canSeeVendorDocuments /
// canSeeRiderDocuments): vendor documents need vendors.view / vendors.edit /
// vendors.approve / vendors.payouts; rider documents need delivery.view /
// delivery.approve / delivery.block; role admin or superAdmin always.
// A banned or inactive staff account gets nothing.
// -----------------------------------------------------------------------------

const SIGNED_URL_MINUTES = 5;

const KINDS = Object.freeze({
  vendor: {
    privateCollection: "vendor_private",
    folder: (ownerId) => `vendors/${ownerId}/documents/`,
    files: { nidFront: "nidFrontPath", nidBack: "nidBackPath", tradeLicense: "tradeLicensePath" },
    permissions: ["vendors.view", "vendors.edit", "vendors.approve", "vendors.payouts"],
  },
  rider: {
    privateCollection: "delivery_partner_private",
    folder: (ownerId) => `delivery_partner_documents/${ownerId}/`,
    files: { nidFront: "nidFrontPath", nidBack: "nidBackPath" },
    permissions: ["delivery.view", "delivery.approve", "delivery.block"],
  },
});

const ADMIN_ROLES = ["superAdmin", "super_admin", "admin"];
const OWNER_ID = /^[A-Za-z0-9_-]{1,128}$/;

class RequestError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // an HttpsError code
  }
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

// Same meaning as userHasAnyPermission() in storage.rules.
function userCanSeeDocuments(user, permissions) {
  if (!user || typeof user !== "object") return false;
  if (user.isActive === false || user.isBanned === true) return false;
  const roles = Array.isArray(user.roles) ? user.roles : [];
  if (ADMIN_ROLES.includes(user.role) || roles.some((r) => ADMIN_ROLES.includes(r))) return true;
  const granted = user.permissions;
  if (Array.isArray(granted)) return permissions.some((p) => granted.includes(p));
  if (granted && typeof granted === "object") return permissions.some((p) => granted[p] === true);
  return false;
}

function parseRequest(data) {
  const d = data && typeof data === "object" ? data : {};
  const kind = text(d.kind);
  const ownerId = text(d.ownerId);
  const which = text(d.which);
  const spec = Object.prototype.hasOwnProperty.call(KINDS, kind) ? KINDS[kind] : null;
  if (!spec) throw new RequestError("invalid-argument", "kind must be vendor or rider.");
  if (!OWNER_ID.test(ownerId)) throw new RequestError("invalid-argument", "ownerId is not valid.");
  if (!Object.prototype.hasOwnProperty.call(spec.files, which)) {
    throw new RequestError("invalid-argument", `which must be one of ${Object.keys(spec.files).join(", ")}.`);
  }
  return { kind, ownerId, which, spec };
}

// The stored path must be a plain object path inside the owner's folder.
function pathInsideOwnerFolder(spec, ownerId, path) {
  const p = text(path);
  if (!p || p.includes("..") || p.includes("//") || p.includes("\\")) return false;
  const folder = spec.folder(ownerId);
  return p.startsWith(folder) && p.length > folder.length;
}

// deps: { db, bucket, logger, now } (injected for tests).
async function getIdentityDocumentUrl(auth, data, deps) {
  const uid = auth && auth.uid;
  if (!uid) throw new RequestError("unauthenticated", "Sign-in required.");

  const { kind, ownerId, which, spec } = parseRequest(data);

  const userSnap = await deps.db.collection("users").doc(uid).get();
  if (!userSnap.exists || !userCanSeeDocuments(userSnap.data(), spec.permissions)) {
    throw new RequestError("permission-denied", "Not allowed to view these documents.");
  }

  const privateSnap = await deps.db.collection(spec.privateCollection).doc(ownerId).get();
  const path = privateSnap.exists ? text(privateSnap.get(spec.files[which])) : "";
  if (!path) throw new RequestError("not-found", "No document on file.");
  if (!pathInsideOwnerFolder(spec, ownerId, path)) {
    throw new RequestError("failed-precondition", "The stored document path is not valid.");
  }

  const file = deps.bucket.file(path);
  const [exists] = await file.exists();
  if (!exists) throw new RequestError("not-found", "The document file is missing.");

  const now = deps.now();
  const expiresAt = now + SIGNED_URL_MINUTES * 60 * 1000;
  const [url] = await file.getSignedUrl({ version: "v4", action: "read", expires: expiresAt });

  deps.logger.info("identity document viewed", {
    viewerUid: uid,
    ownerId,
    kind,
    which,
    at: new Date(now).toISOString(),
  });

  return { url, expiresAt: new Date(expiresAt).toISOString() };
}

module.exports = {
  KINDS,
  SIGNED_URL_MINUTES,
  RequestError,
  userCanSeeDocuments,
  parseRequest,
  pathInsideOwnerFolder,
  getIdentityDocumentUrl,
};
