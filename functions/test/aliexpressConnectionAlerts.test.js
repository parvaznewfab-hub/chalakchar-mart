const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
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
} = require("../aliexpress/connectionAlerts");

const NOW = Date.parse("2026-11-14T03:35:00Z");
const DAY = 24 * 60 * 60 * 1000;

// In-memory stand-in for system_alerts/aliexpress + the alert sink.
function fakeDeps(initialState = {}, overrides = {}) {
  const deps = {
    state: { ...initialState },
    sent: [],
    nowMs: NOW,
    readState: async () => ({ ...deps.state }),
    writeState: async (patch) => { Object.assign(deps.state, patch); },
    sendAlert: async (alert) => { deps.sent.push(alert); },
    logger: { error() {}, warn() {}, info() {} },
    ...overrides,
  };
  return deps;
}

const notConnectedErrors = (n) => Array.from({ length: n }, (_, i) => ({ productId: `p${i}`, error: "ALIEXPRESS_NOT_CONNECTED" }));

describe("decideConnectionFailedAlert", () => {
  test("alerts on first sight of refresh_failed", () => {
    assert.equal(decideConnectionFailedAlert({ status: "refresh_failed", lastAlertAtMs: 0, nowMs: NOW }), "alert");
  });

  test("no repeat inside the reminder window, reminder once it has passed", () => {
    assert.equal(decideConnectionFailedAlert({ status: "refresh_failed", lastAlertAtMs: NOW - 12 * 60 * 60 * 1000, nowMs: NOW }), null);
    assert.equal(decideConnectionFailedAlert({ status: "refresh_failed", lastAlertAtMs: NOW - REMINDER_INTERVAL_MS, nowMs: NOW }), "alert");
  });

  test("clears once connected again, so the next failure alerts immediately", () => {
    assert.equal(decideConnectionFailedAlert({ status: "connected", lastAlertAtMs: NOW - 1000, nowMs: NOW }), "clear");
    assert.equal(decideConnectionFailedAlert({ status: "connected", lastAlertAtMs: 0, nowMs: NOW }), null);
  });
});

describe("decideRefreshExpiryAlert", () => {
  const base = { status: "connected", warnedForMs: 0, expiredAlertedForMs: 0, nowMs: NOW };

  test("nothing when expiry is far away or unknown", () => {
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: NOW + 30 * DAY }), null);
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: 0 }), null);
  });

  test("warns once within the warning window", () => {
    const exp = NOW + EXPIRY_WARNING_MS;
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: exp }), "expiring");
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: exp, warnedForMs: exp }), null);
  });

  test("a reconnect (new expiry date) re-arms the warning", () => {
    const oldExp = NOW + 2 * DAY;
    const newExp = NOW + 3 * DAY;
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: newExp, warnedForMs: oldExp }), "expiring");
  });

  test("expired alerts once while status still says connected", () => {
    const exp = NOW - DAY;
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: exp }), "expired");
    assert.equal(decideRefreshExpiryAlert({ ...base, refreshExpiresAtMs: exp, expiredAlertedForMs: exp }), null);
  });

  test("expired is suppressed when connection_failed already covers it", () => {
    assert.equal(decideRefreshExpiryAlert({ ...base, status: "refresh_failed", refreshExpiresAtMs: NOW - DAY }), null);
  });
});

describe("isTotalSyncFailure / topSyncErrorCode", () => {
  test("all failed is a total failure; any success is not; empty run is not", () => {
    assert.equal(isTotalSyncFailure({ totalChecked: 117, updated: 0, unchanged: 0, skipped: 0, failed: 117 }), true);
    assert.equal(isTotalSyncFailure({ totalChecked: 117, updated: 0, unchanged: 1, skipped: 0, failed: 116 }), false);
    assert.equal(isTotalSyncFailure({ totalChecked: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0 }), false);
  });

  test("skips alone are not failures; failures plus skips with no success are", () => {
    assert.equal(isTotalSyncFailure({ totalChecked: 3, updated: 0, unchanged: 0, skipped: 3, failed: 0 }), false);
    assert.equal(isTotalSyncFailure({ totalChecked: 3, updated: 0, unchanged: 0, skipped: 1, failed: 2 }), true);
  });

  test("unsaleable products count as answered, not failed", () => {
    assert.equal(isTotalSyncFailure({ totalChecked: 3, updated: 0, unchanged: 0, unsaleable: 3, skipped: 0, failed: 0 }), false);
    assert.equal(isTotalSyncFailure({ totalChecked: 3, updated: 0, unchanged: 0, unsaleable: 1, skipped: 0, failed: 2 }), false);
  });

  test("a crashed run is a total failure", () => {
    assert.equal(isTotalSyncFailure({ fatal: true, message: "boom" }), true);
    assert.equal(topSyncErrorCode({ fatal: true }), "SYNC_FATAL");
  });

  test("picks the most common failure code and ignores skip entries", () => {
    const errors = [
      ...notConnectedErrors(3),
      { error: "SYNC_FAILED" },
      { error: "MISSING_SOURCE_PRODUCT_ID" },
      { error: "MISSING_SOURCE_PRODUCT_ID" },
      { error: "MISSING_SOURCE_PRODUCT_ID" },
      { error: "MISSING_SOURCE_PRODUCT_ID" },
    ];
    assert.equal(topSyncErrorCode({ errors }), "ALIEXPRESS_NOT_CONNECTED");
    assert.equal(topSyncErrorCode({ errors: [] }), "SYNC_FAILED");
  });
});

describe("decideSyncFailureAlert", () => {
  const allFailed = { totalChecked: 2, updated: 0, unchanged: 0, skipped: 0, failed: 2 };
  const healthy = { totalChecked: 2, updated: 1, unchanged: 1, skipped: 0, failed: 0 };

  test("alerts, then reminds only after the reminder window", () => {
    assert.equal(decideSyncFailureAlert({ summary: allFailed, inFailure: false, lastAlertAtMs: 0, nowMs: NOW }), "alert");
    assert.equal(decideSyncFailureAlert({ summary: allFailed, inFailure: true, lastAlertAtMs: NOW - 6 * 60 * 60 * 1000, nowMs: NOW }), null);
    assert.equal(decideSyncFailureAlert({ summary: allFailed, inFailure: true, lastAlertAtMs: NOW - REMINDER_INTERVAL_MS, nowMs: NOW }), "alert");
  });

  test("recovered only after a failure state, never on a normal healthy run", () => {
    assert.equal(decideSyncFailureAlert({ summary: healthy, inFailure: true, lastAlertAtMs: NOW - 1000, nowMs: NOW }), "recovered");
    assert.equal(decideSyncFailureAlert({ summary: healthy, inFailure: false, lastAlertAtMs: 0, nowMs: NOW }), null);
  });
});

describe("runConnectionAlerts", () => {
  test("today's real state (refresh_failed, refresh expired 2026-09-18) sends exactly one connection_failed alert", async () => {
    const deps = fakeDeps();
    const sent = await runConnectionAlerts(
      { status: "refresh_failed", refreshExpiresAtMs: Date.parse("2026-09-18T16:06:32Z"), lastError: "The specified refresh token is invalid or expired" },
      deps
    );
    assert.deepEqual(sent, ["connection_failed"]);
    assert.equal(deps.sent.length, 1);
    assert.match(deps.sent[0].body, /refresh token is invalid or expired/);
    assert.match(deps.sent[0].body, /api\/aliexpress\/start/);
    assert.equal(deps.state.connectionFailedAlertAtMs, NOW);

    // 12h later (next job tick): no repeat.
    deps.nowMs = NOW + 12 * 60 * 60 * 1000;
    assert.deepEqual(await runConnectionAlerts({ status: "refresh_failed", refreshExpiresAtMs: Date.parse("2026-09-18T16:06:32Z") }, deps), []);
    // 24h later: daily reminder.
    deps.nowMs = NOW + DAY;
    assert.deepEqual(await runConnectionAlerts({ status: "refresh_failed", refreshExpiresAtMs: Date.parse("2026-09-18T16:06:32Z") }, deps), ["connection_failed"]);
  });

  test("after reconnect: clears failure state; later warns once before the new expiry", async () => {
    const deps = fakeDeps({ connectionFailedAlertAtMs: NOW - DAY });
    const newExpiry = NOW + 60 * DAY;
    assert.deepEqual(await runConnectionAlerts({ status: "connected", refreshExpiresAtMs: newExpiry }, deps), []);
    assert.equal(deps.state.connectionFailedAlertAtMs, 0);

    deps.nowMs = newExpiry - 4 * DAY;
    assert.deepEqual(await runConnectionAlerts({ status: "connected", refreshExpiresAtMs: newExpiry }, deps), ["refresh_expiring"]);
    assert.match(deps.sent[0].body, /4 days/);
    deps.nowMs += 12 * 60 * 60 * 1000;
    assert.deepEqual(await runConnectionAlerts({ status: "connected", refreshExpiresAtMs: newExpiry }, deps), []);

    deps.nowMs = newExpiry + 1000;
    assert.deepEqual(await runConnectionAlerts({ status: "connected", refreshExpiresAtMs: newExpiry }, deps), ["refresh_expired"]);
    deps.nowMs += 12 * 60 * 60 * 1000;
    assert.deepEqual(await runConnectionAlerts({ status: "connected", refreshExpiresAtMs: newExpiry }, deps), []);
  });

  test("an alert failure never throws and leaves state unchanged so it retries next tick", async () => {
    const deps = fakeDeps({}, { sendAlert: async () => { throw new Error("FCM down"); } });
    const sent = await runConnectionAlerts({ status: "refresh_failed", refreshExpiresAtMs: 0 }, deps);
    assert.deepEqual(sent, []);
    assert.equal(deps.state.connectionFailedAlertAtMs, undefined);
  });
});

describe("runSyncAlerts", () => {
  const allFailed = { totalChecked: 117, updated: 0, unchanged: 0, skipped: 0, failed: 117, errors: notConnectedErrors(117) };

  test("6-hourly all-failed runs alert once per day, then recover once", async () => {
    const deps = fakeDeps();
    assert.deepEqual(await runSyncAlerts(allFailed, deps), ["sync_failed"]);
    assert.match(deps.sent[0].body, /all 117 of 117 products \(ALIEXPRESS_NOT_CONNECTED\)/);
    assert.equal(deps.sent[0].data.errorCode, "ALIEXPRESS_NOT_CONNECTED");

    for (const hours of [6, 12, 18]) {
      deps.nowMs = NOW + hours * 60 * 60 * 1000;
      assert.deepEqual(await runSyncAlerts(allFailed, deps), []);
    }
    deps.nowMs = NOW + DAY;
    assert.deepEqual(await runSyncAlerts(allFailed, deps), ["sync_failed"]);

    deps.nowMs = NOW + DAY + 6 * 60 * 60 * 1000;
    const healthy = { totalChecked: 117, updated: 90, unchanged: 25, skipped: 0, failed: 2, errors: [] };
    assert.deepEqual(await runSyncAlerts(healthy, deps), ["sync_recovered"]);
    assert.equal(deps.state.syncInFailure, false);
    assert.deepEqual(await runSyncAlerts(healthy, deps), []);
  });

  test("a crashed run alerts with the crash message", async () => {
    const deps = fakeDeps();
    assert.deepEqual(await runSyncAlerts({ fatal: true, message: "DEADLINE_EXCEEDED" }, deps), ["sync_failed"]);
    assert.match(deps.sent[0].body, /crashed: DEADLINE_EXCEEDED/);
  });

  test("partial failures and empty runs never alert", async () => {
    const deps = fakeDeps();
    assert.deepEqual(await runSyncAlerts({ totalChecked: 5, updated: 0, unchanged: 1, skipped: 0, failed: 4, errors: notConnectedErrors(4) }, deps), []);
    assert.deepEqual(await runSyncAlerts({ totalChecked: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0, errors: [] }, deps), []);
    assert.equal(deps.sent.length, 0);
  });
});

describe("createAliExpressAlertDeps", () => {
  function fakeFirestoreForAlerts() {
    const store = { added: [], stateWrites: [], state: null };
    const db = {
      collection(name) {
        return {
          doc: () => ({
            get: async () => ({ exists: Boolean(store.state), data: () => store.state }),
            set: async (data, opts) => { store.stateWrites.push({ name, data, opts }); },
          }),
          add: async (data) => { store.added.push({ name, data }); return { id: "n1" }; },
        };
      },
    };
    const admin = { firestore: { FieldValue: { serverTimestamp: () => "SERVER_TS" } } };
    return { db, admin, store };
  }

  test("sendAlert records a staff-only, already-pushed notification and pushes to admins", async () => {
    const { db, admin, store } = fakeFirestoreForAlerts();
    const pushes = [];
    const deps = createAliExpressAlertDeps({ db, admin, notifyAdmins: async (...args) => { pushes.push(args); }, logger: null });

    await deps.sendAlert({ kind: "sync_failed", title: "T", body: "B", data: { errorCode: "X" } });

    assert.equal(store.added.length, 1);
    const record = store.added[0];
    assert.equal(record.name, "notifications");
    assert.equal(record.data.type, ALERT_NOTIFICATION_TYPE);
    assert.equal(record.data.pushSent, true, "must be pre-marked so onNotificationCreated does not push again");
    assert.equal("userId" in record.data, false, "no userId: invisible to customers");
    assert.equal(record.data.isRead, false);
    assert.deepEqual(record.data.data, { source: "aliexpress", alertKind: "sync_failed", errorCode: "X" });

    assert.equal(pushes.length, 1);
    assert.equal(pushes[0][0], "T");
    assert.equal(pushes[0][2].alertKind, "sync_failed");
  });

  test("a push failure still keeps the notification record and does not throw", async () => {
    const { db, admin, store } = fakeFirestoreForAlerts();
    const deps = createAliExpressAlertDeps({ db, admin, notifyAdmins: async () => { throw new Error("FCM down"); }, logger: null });
    await deps.sendAlert({ kind: "connection_failed", title: "T", body: "B" });
    assert.equal(store.added.length, 1);
  });

  test("writeState merges into system_alerts/aliexpress", async () => {
    const { db, admin, store } = fakeFirestoreForAlerts();
    const deps = createAliExpressAlertDeps({ db, admin, notifyAdmins: async () => {}, logger: null });
    await deps.writeState({ syncInFailure: true });
    assert.equal(store.stateWrites[0].name, "system_alerts");
    assert.deepEqual(store.stateWrites[0].opts, { merge: true });
    assert.equal(store.stateWrites[0].data.syncInFailure, true);
  });
});
