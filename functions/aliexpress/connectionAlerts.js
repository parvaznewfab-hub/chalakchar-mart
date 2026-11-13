// -----------------------------------------------------------------------------
// Admin alerts for the AliExpress connection and the scheduled price/stock
// sync, added after the 2026-09/11 incident. The OAuth refresh token
// (marketplace_connections/aliexpress) hit its hard expiry, the connection
// went to status "refresh_failed", and every aliexpressScheduledSync run
// failed 100% with ALIEXPRESS_NOT_CONNECTED for ~6 weeks. Nobody was told.
//
// Three alerts:
//   1. connection_failed — status is "refresh_failed". Sent on first sight,
//      then re-sent at most once per REMINDER_INTERVAL_MS until the status
//      changes. Cleared once the connection is no longer refresh_failed, so
//      the next failure alerts immediately.
//   2. refresh_expiring / refresh_expired — AliExpress does NOT extend the
//      refresh token when the access token is refreshed, so it has a hard
//      expiry and needs a manual reconnect. Warns once when refreshExpiresAt
//      is within EXPIRY_WARNING_MS, and once when it has passed. Both are
//      keyed by the refreshExpiresAt value they were sent for, so a reconnect
//      (new refreshExpiresAt) re-arms them with no explicit reset.
//      "expired" is suppressed while status is refresh_failed, because
//      connection_failed already covers that state. "expired" exists for the
//      gap where the refresh token is dead but status still says "connected"
//      (refresh is only attempted near access-token expiry).
//   3. sync_failed / sync_recovered — a scheduled sync run where nothing
//      synced (updated + unchanged == 0) and at least one product failed, or
//      the whole run threw. Reminded at most once per
//      REMINDER_INTERVAL_MS while it persists. One "recovered" alert on the
//      first run that syncs something again.
//
// Alert bookkeeping lives in system_alerts/aliexpress, never on the
// connection doc itself, so the OAuth callback / refresh writes never have
// to know about it.
//
// The decide* functions are pure (plain values in, decision out). The run*
// functions take their I/O as injected deps ({ readState, writeState,
// sendAlert, nowMs }) so they're unit-testable without Firestore or FCM.
// -----------------------------------------------------------------------------

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

// 23h, not 24h: the jobs driving these checks fire every 12h / 6h at
// near-fixed times, so a strict 24h threshold could miss a daily reminder by
// a few seconds of scheduling jitter and slip it a whole extra cycle.
const REMINDER_INTERVAL_MS = 23 * HOUR_MS;
const EXPIRY_WARNING_MS = 5 * DAY_MS;

const ALERT_STATE_COLLECTION = "system_alerts";
const ALERT_STATE_DOC_ID = "aliexpress";
const ALERT_NOTIFICATION_TYPE = "admin_system_alert";
const RECONNECT_HINT = "Reconnect: open https://chalakcharmart.com/api/aliexpress/start (x-import-api-key header) and follow the authorizationUrl.";

function isReminderDue(lastAlertAtMs, nowMs) {
  return !lastAlertAtMs || nowMs - lastAlertAtMs >= REMINDER_INTERVAL_MS;
}

function formatDate(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

// ---- 1. connection_failed ---------------------------------------------------

/**
 * @param {{ status: string, lastAlertAtMs: number, nowMs: number }} input
 * @returns {"alert" | "clear" | null}
 */
function decideConnectionFailedAlert({ status, lastAlertAtMs, nowMs }) {
  if (status === "refresh_failed") return isReminderDue(lastAlertAtMs, nowMs) ? "alert" : null;
  return lastAlertAtMs ? "clear" : null;
}

// ---- 2. refresh token expiry ------------------------------------------------

/**
 * @param {{ status: string, refreshExpiresAtMs: number, warnedForMs: number,
 *           expiredAlertedForMs: number, nowMs: number }} input
 * @returns {"expiring" | "expired" | null}
 */
function decideRefreshExpiryAlert({ status, refreshExpiresAtMs, warnedForMs, expiredAlertedForMs, nowMs }) {
  if (!refreshExpiresAtMs) return null;

  if (refreshExpiresAtMs <= nowMs) {
    if (status === "refresh_failed") return null; // connection_failed already covers it
    return expiredAlertedForMs === refreshExpiresAtMs ? null : "expired";
  }

  if (refreshExpiresAtMs - nowMs <= EXPIRY_WARNING_MS) {
    return warnedForMs === refreshExpiresAtMs ? null : "expiring";
  }

  return null;
}

// ---- 3. sync failure ----------------------------------------------------------

// Products AliExpress answered for. "unsaleable" counts: AliExpress did
// respond (with "All SKU Unsaleable"), so the connection and sync work.
function syncSucceededCount(summary) {
  return (Number(summary?.updated) || 0) + (Number(summary?.unchanged) || 0) + (Number(summary?.unsaleable) || 0);
}

function isTotalSyncFailure(summary) {
  if (!summary) return false;
  if (summary.fatal) return true;
  return syncSucceededCount(summary) === 0 && (Number(summary.failed) || 0) > 0;
}

/**
 * The most common error code across a sync run's per-product errors, e.g.
 * "ALIEXPRESS_NOT_CONNECTED". Skips (missing sourceProductId) are included
 * in `errors` by runAliExpressSync but aren't failures, so they're ignored.
 */
function topSyncErrorCode(summary) {
  if (summary?.fatal) return "SYNC_FATAL";
  const counts = new Map();
  for (const entry of Array.isArray(summary?.errors) ? summary.errors : []) {
    if (!entry || entry.error === "MISSING_SOURCE_PRODUCT_ID") continue;
    const code = String(entry.error || "SYNC_FAILED");
    counts.set(code, (counts.get(code) || 0) + 1);
  }
  let top = "";
  let topCount = 0;
  for (const [code, count] of counts) {
    if (count > topCount) {
      top = code;
      topCount = count;
    }
  }
  return top || "SYNC_FAILED";
}

/**
 * @param {{ summary: object, inFailure: boolean, lastAlertAtMs: number, nowMs: number }} input
 * @returns {"alert" | "recovered" | null}
 */
function decideSyncFailureAlert({ summary, inFailure, lastAlertAtMs, nowMs }) {
  if (isTotalSyncFailure(summary)) return isReminderDue(lastAlertAtMs, nowMs) ? "alert" : null;
  if (inFailure && syncSucceededCount(summary) > 0) return "recovered";
  return null;
}

// ---- runners (I/O injected) -------------------------------------------------

// Never lets an alerting problem break the job that called it: the refresh
// and sync jobs must behave exactly as before even if FCM or the
// notifications write fails.
async function safely(deps, label, fn) {
  try {
    return await fn();
  } catch (error) {
    deps.logger?.error?.(`AliExpress alert: ${label} failed`, { message: error?.message || String(error) });
    return null;
  }
}

/**
 * Runs alerts 1 and 2 against the current connection doc. Called from the
 * 12-hourly aliexpressRefreshToken job, after its refresh attempt.
 *
 * @param {{ status?: string, refreshExpiresAtMs?: number }} connection
 * @param {{ readState: () => Promise<object>, writeState: (patch: object) => Promise<void>,
 *           sendAlert: (alert: object) => Promise<void>, nowMs?: number, logger?: object }} deps
 * @returns {Promise<string[]>} the alert kinds sent this call
 */
async function runConnectionAlerts(connection, deps) {
  return (await safely(deps, "connection check", async () => {
    const nowMs = deps.nowMs ?? Date.now();
    const status = String(connection?.status || "not_connected");
    const refreshExpiresAtMs = Number(connection?.refreshExpiresAtMs) || 0;
    const state = (await deps.readState()) || {};
    const sent = [];
    const patch = {};

    const failedDecision = decideConnectionFailedAlert({
      status,
      lastAlertAtMs: Number(state.connectionFailedAlertAtMs) || 0,
      nowMs,
    });
    if (failedDecision === "alert") {
      await deps.sendAlert({
        kind: "connection_failed",
        title: "AliExpress connection failed ⚠️",
        body: `AliExpress login could not be refreshed${connection?.lastError ? ` (${connection.lastError})` : ""}. Price/stock sync and imports are stopped. ${RECONNECT_HINT}`,
        data: { status },
      });
      patch.connectionFailedAlertAtMs = nowMs;
      sent.push("connection_failed");
    } else if (failedDecision === "clear") {
      patch.connectionFailedAlertAtMs = 0;
    }

    const expiryDecision = decideRefreshExpiryAlert({
      status,
      refreshExpiresAtMs,
      warnedForMs: Number(state.refreshExpiryWarnedForMs) || 0,
      expiredAlertedForMs: Number(state.refreshExpiredAlertedForMs) || 0,
      nowMs,
    });
    if (expiryDecision === "expiring") {
      const daysLeft = Math.max(1, Math.ceil((refreshExpiresAtMs - nowMs) / DAY_MS));
      await deps.sendAlert({
        kind: "refresh_expiring",
        title: "AliExpress login expires soon ⏳",
        body: `AliExpress login expires on ${formatDate(refreshExpiresAtMs)} (${daysLeft} day${daysLeft === 1 ? "" : "s"}). It cannot renew itself. Reconnect before then or price/stock sync stops. ${RECONNECT_HINT}`,
        data: { refreshExpiresAt: new Date(refreshExpiresAtMs).toISOString() },
      });
      patch.refreshExpiryWarnedForMs = refreshExpiresAtMs;
      sent.push("refresh_expiring");
    } else if (expiryDecision === "expired") {
      await deps.sendAlert({
        kind: "refresh_expired",
        title: "AliExpress login expired ⚠️",
        body: `AliExpress login expired on ${formatDate(refreshExpiresAtMs)}. Price/stock sync will fail once the current access token runs out. ${RECONNECT_HINT}`,
        data: { refreshExpiresAt: new Date(refreshExpiresAtMs).toISOString() },
      });
      patch.refreshExpiredAlertedForMs = refreshExpiresAtMs;
      sent.push("refresh_expired");
    }

    if (Object.keys(patch).length) await deps.writeState(patch);
    return sent;
  })) || [];
}

/**
 * Runs alert 3 for one finished (or crashed) scheduled sync run. Pass
 * { fatal: true, message } when runAliExpressSync itself threw.
 *
 * @returns {Promise<string[]>} the alert kinds sent this call
 */
async function runSyncAlerts(summary, deps) {
  return (await safely(deps, "sync check", async () => {
    const nowMs = deps.nowMs ?? Date.now();
    const state = (await deps.readState()) || {};
    const decision = decideSyncFailureAlert({
      summary,
      inFailure: state.syncInFailure === true,
      lastAlertAtMs: Number(state.syncFailureAlertAtMs) || 0,
      nowMs,
    });

    if (decision === "alert") {
      const code = topSyncErrorCode(summary);
      const body = summary?.fatal
        ? `AliExpress price/stock sync crashed: ${summary.message || "unknown error"}. No products were synced.`
        : `AliExpress price/stock sync failed for all ${Number(summary.failed) || 0} of ${Number(summary.totalChecked) || 0} products (${code}). Prices and stock are not being updated.${code === "ALIEXPRESS_NOT_CONNECTED" ? ` ${RECONNECT_HINT}` : ""}`;
      await deps.sendAlert({
        kind: "sync_failed",
        title: "AliExpress sync failing ⚠️",
        body,
        data: { errorCode: code, totalChecked: Number(summary?.totalChecked) || 0, failed: Number(summary?.failed) || 0 },
      });
      await deps.writeState({ syncInFailure: true, syncFailureAlertAtMs: nowMs });
      return ["sync_failed"];
    }

    if (decision === "recovered") {
      await deps.sendAlert({
        kind: "sync_recovered",
        title: "AliExpress sync recovered ✅",
        body: `AliExpress price/stock sync is working again: ${Number(summary.updated) || 0} updated, ${Number(summary.unchanged) || 0} unchanged, ${Number(summary.failed) || 0} failed.`,
        data: { updated: Number(summary.updated) || 0, unchanged: Number(summary.unchanged) || 0, failed: Number(summary.failed) || 0 },
      });
      await deps.writeState({ syncInFailure: false, syncFailureAlertAtMs: 0 });
      return ["sync_recovered"];
    }

    // A total failure inside the reminder window still marks the state, so a
    // run that starts failing right after a recovery is tracked correctly.
    if (isTotalSyncFailure(summary) && state.syncInFailure !== true) {
      await deps.writeState({ syncInFailure: true });
    }
    return [];
  })) || [];
}

/**
 * Builds the system_alerts/aliexpress read/write and the send function from
 * real Firestore + notifyAdmins. Each alert goes to admin push (notifyAdmins)
 * AND to a notifications/{id} doc so the Admin Panel's Notifications page
 * keeps a lasting record:
 *   - no userId     -> invisible to customers (rules: only userId == uid or
 *                      notifications.view/manage staff can read)
 *   - pushSent:true -> onNotificationCreated skips it (no double push; the
 *                      push already went out via notifyAdmins)
 */
function createAliExpressAlertDeps({ db, admin, notifyAdmins, logger }) {
  const stateRef = db.collection(ALERT_STATE_COLLECTION).doc(ALERT_STATE_DOC_ID);
  return {
    logger,
    readState: async () => {
      const snap = await stateRef.get();
      return snap.exists ? (snap.data() || {}) : {};
    },
    writeState: async (patch) => {
      await stateRef.set({ ...patch, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    },
    sendAlert: async ({ kind, title, body, data = {} }) => {
      const payload = { source: "aliexpress", alertKind: kind, ...data };
      // Record first: if FCM fails, the admin page still has the alert.
      await db.collection("notifications").add({
        title,
        body,
        type: ALERT_NOTIFICATION_TYPE,
        audience: "admins",
        isRead: false,
        pushSent: true,
        data: payload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      try {
        await notifyAdmins(title, body, { type: ALERT_NOTIFICATION_TYPE, ...payload });
      } catch (error) {
        logger?.warn?.("AliExpress alert: admin push failed (notification record was saved)", { kind, message: error?.message || String(error) });
      }
      logger?.info?.("AliExpress alert sent", { kind });
    },
  };
}

module.exports = {
  REMINDER_INTERVAL_MS,
  EXPIRY_WARNING_MS,
  ALERT_NOTIFICATION_TYPE,
  decideConnectionFailedAlert,
  decideRefreshExpiryAlert,
  decideSyncFailureAlert,
  isTotalSyncFailure,
  topSyncErrorCode,
  runConnectionAlerts,
  runSyncAlerts,
  createAliExpressAlertDeps,
};
