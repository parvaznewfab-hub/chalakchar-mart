const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");

function textValue(value, fallback = "") {
  if (value === null || value === undefined) return fallback;
  const str = String(value).trim();
  return str.length > 0 ? str : fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

async function loadAppSettings() {
  const doc = await admin.firestore().collection("settings").doc("app").get();
  return doc.exists ? doc.data() || {} : {};
}

async function requireAdminAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userDoc = await admin.firestore().collection("users").doc(uid).get();
  const role = userDoc.exists ? String((userDoc.data() || {}).role || "") : "";

  if (role !== "admin" && role !== "superAdmin") {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  return uid;
}

module.exports = { textValue, mapValue, loadAppSettings, requireAdminAuth };
