/**
 * One-time cleanup script — NOT a deployed Cloud Function.
 *
 * Deletes settings/app.socialApi.tiktokClientSecret, the legacy field the
 * Flutter admin form used to write into before the client-secret input was
 * removed. The real secret now lives only in Secret Manager.
 *
 * Never prints the field's value — only a categorical status.
 *
 * Run once, locally, with a service account that has Firestore access:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node functions/tiktok/scripts/removeLegacyTikTokClientSecret.js
 *
 * Delete the downloaded service-account key file afterward.
 */
const admin = require("firebase-admin");

admin.initializeApp();

async function run() {
  const ref = admin.firestore().collection("settings").doc("app");
  const doc = await ref.get();

  if (!doc.exists) {
    console.log("settings/app does not exist. Nothing to do.");
    return;
  }

  const socialApi = (doc.data() || {}).socialApi || {};
  const hasField = Object.prototype.hasOwnProperty.call(socialApi, "tiktokClientSecret");

  if (!hasField) {
    console.log("Status: field absent. No action needed.");
    return;
  }

  const isEmpty = String(socialApi.tiktokClientSecret || "").trim().length === 0;
  console.log(
    isEmpty
      ? "Status: field empty. Removing key anyway for cleanliness."
      : "Status: field contains data and requires deletion. Deleting now (value not logged)."
  );

  await ref.set({
    socialApi: { tiktokClientSecret: admin.firestore.FieldValue.delete() },
  }, { merge: true });

  console.log("Done: settings/app.socialApi.tiktokClientSecret has been deleted.");
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Migration failed:", error.message || String(error));
    process.exit(1);
  });
