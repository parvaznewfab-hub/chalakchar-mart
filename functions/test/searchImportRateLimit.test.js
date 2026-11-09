const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { FakeFirestore } = require("./helpers/fakeFirestore");
const {
  WINDOW_MS,
  BURST_WINDOW_MS,
  extractClientIp,
  sanitizeRateLimitIdentity,
  checkRateLimit,
  parseRateLimitSettings,
  evaluateSearchImportRateLimit,
} = require("../aliexpress/searchImportRateLimit");

describe("extractClientIp", () => {
  test("takes the first entry of X-Forwarded-For (the real client, per Google's Cloud Functions 2nd gen docs)", () => {
    const req = { get: (name) => (name === "x-forwarded-for" ? "1.2.3.4, 169.254.1.1" : undefined) };
    assert.equal(extractClientIp(req), "1.2.3.4");
  });

  test("trims whitespace around the first entry", () => {
    const req = { get: () => "  5.6.7.8  , 10.0.0.1" };
    assert.equal(extractClientIp(req), "5.6.7.8");
  });

  test("falls back to \"unknown\" when the header is missing (e.g. local emulator)", () => {
    const req = { get: () => undefined };
    assert.equal(extractClientIp(req), "unknown");
  });

  test("works against a plain headers object, not just req.get()", () => {
    const req = { headers: { "x-forwarded-for": "9.9.9.9" } };
    assert.equal(extractClientIp(req), "9.9.9.9");
  });
});

describe("sanitizeRateLimitIdentity", () => {
  test("lowercases and keeps IPv4 dots", () => {
    assert.equal(sanitizeRateLimitIdentity("1.2.3.4"), "1.2.3.4");
  });

  test("collapses IPv6 colons to underscores (Firestore doc IDs can't hold arbitrary chars safely)", () => {
    assert.equal(sanitizeRateLimitIdentity("2001:db8::1"), "2001_db8_1");
  });

  test("blank/undefined input falls back", () => {
    assert.equal(sanitizeRateLimitIdentity(""), "unknown");
    assert.equal(sanitizeRateLimitIdentity(undefined), "unknown");
  });
});

describe("checkRateLimit", () => {
  test("first request in a fresh window is allowed and starts count at 1", async () => {
    const db = new FakeFirestore();
    const result = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 3, now: 1_000_000 });
    assert.equal(result.allowed, true);
    assert.equal(result.remaining, 2);
    assert.equal(db._collections.rateLimits["ip_1.2.3.4"].count, 1);
  });

  test("requests under the limit are allowed and increment the counter", async () => {
    const db = new FakeFirestore();
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 3, now: 1_000_000 });
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 3, now: 1_000_100 });
    const third = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 3, now: 1_000_200 });
    assert.equal(third.allowed, true);
    assert.equal(third.remaining, 0);
    assert.equal(db._collections.rateLimits["ip_1.2.3.4"].count, 3);
  });

  test("the request that would exceed the limit is denied with a positive retryAfterSeconds", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 2, now });
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 2, now: now + 100 });
    const denied = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 2, now: now + 200 });

    assert.equal(denied.allowed, false);
    assert.equal(denied.remaining, 0);
    assert.ok(denied.retryAfterSeconds > 0);
    // Denial must not mutate stored state — count stays at the limit, not limit+1.
    assert.equal(db._collections.rateLimits["ip_1.2.3.4"].count, 2);
  });

  test("a new window (after WINDOW_MS) resets the counter instead of staying denied", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 1, now });
    const stillDenied = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 1, now: now + 1000 });
    assert.equal(stillDenied.allowed, false);

    const nextWindow = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 1, now: now + WINDOW_MS + 1 });
    assert.equal(nextWindow.allowed, true);
    assert.equal(nextWindow.remaining, 0);
  });

  test("different keys (different IPs/uids) never share a bucket", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await checkRateLimit(db, { key: "ip_1.1.1.1", limitPerHour: 1, now });
    const otherIp = await checkRateLimit(db, { key: "ip_2.2.2.2", limitPerHour: 1, now });
    assert.equal(otherIp.allowed, true);
  });

  test("retryAfterSeconds counts down to the window's actual reset time, not a fixed value", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 1, now });
    const denied = await checkRateLimit(db, {
      key: "ip_1.2.3.4",
      limitPerHour: 1,
      now: now + WINDOW_MS - 5000,
    });
    assert.equal(denied.retryAfterSeconds, 5);
  });

  test("limitPerHour is floored at 1 even if misconfigured to 0 or negative", async () => {
    const db = new FakeFirestore();
    const result = await checkRateLimit(db, { key: "ip_1.2.3.4", limitPerHour: 0, now: 1_000_000 });
    assert.equal(result.limit, 1);
    assert.equal(result.allowed, true);
  });
});

describe("parseRateLimitSettings", () => {
  test("defaults to enabled with 12/hour IP and 25/hour uid when settings/app has nothing configured", () => {
    const parsed = parseRateLimitSettings({});
    assert.equal(parsed.enabled, true);
    assert.equal(parsed.ipLimitPerHour, 12);
    assert.equal(parsed.uidLimitPerHour, 25);
    assert.equal(parsed.burstLimit, 5);
    assert.equal(parsed.burstWindowMs, 10 * 60 * 1000);
  });

  test("burst limit and window are configurable from settings/app", () => {
    const parsed = parseRateLimitSettings({ searchImportBurstLimit: 3, searchImportBurstWindowMinutes: 15 });
    assert.equal(parsed.burstLimit, 3);
    assert.equal(parsed.burstWindowMs, 15 * 60 * 1000);
  });

  test("null/undefined importSettings falls back to the same defaults", () => {
    assert.deepEqual(parseRateLimitSettings(null), parseRateLimitSettings({}));
    assert.deepEqual(parseRateLimitSettings(undefined), parseRateLimitSettings({}));
  });

  test("admin-configured values override the defaults", () => {
    const parsed = parseRateLimitSettings({
      searchImportRateLimitEnabled: false,
      searchImportIpLimitPerHour: 15,
      searchImportUidLimitPerHour: 30,
    });
    assert.equal(parsed.enabled, false);
    assert.equal(parsed.ipLimitPerHour, 15);
    assert.equal(parsed.uidLimitPerHour, 30);
  });

  test("non-numeric or non-positive configured limits fall back to the default rather than breaking", () => {
    const parsed = parseRateLimitSettings({
      searchImportIpLimitPerHour: "not a number",
      searchImportUidLimitPerHour: -5,
    });
    assert.equal(parsed.ipLimitPerHour, 12);
    assert.equal(parsed.uidLimitPerHour, 25);
  });

  test("enabled only accepts real booleans — a stray string doesn't accidentally disable protection", () => {
    const parsed = parseRateLimitSettings({ searchImportRateLimitEnabled: "false" });
    assert.equal(parsed.enabled, true);
  });
});

describe("evaluateSearchImportRateLimit", () => {
  test("allows a fresh IP and uid under both limits", async () => {
    const db = new FakeFirestore();
    const result = await evaluateSearchImportRateLimit(db, {
      ip: "1.2.3.4",
      uid: "user_1",
      ipLimitPerHour: 12,
      uidLimitPerHour: 25,
      now: 1_000_000,
    });
    assert.equal(result, null);
  });

  test("denies on the IP layer once the IP limit is exhausted, before ever checking uid", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    // Seed the IP bucket already at its limit, so this uid has never been
    // checked yet — isolates "IP denial skips the uid check" from "the uid
    // bucket was already touched by an earlier allowed request".
    db._seed("rateLimits", "ip_1.2.3.4", { count: 1, windowStart: now });

    const result = await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: "user_1", ipLimitPerHour: 1, uidLimitPerHour: 25, now: now + 10 });
    assert.equal(result.scope, "ip");
    assert.ok(result.retryAfterSeconds > 0);
    // uid bucket must be untouched — the IP denial short-circuited before it was checked.
    assert.equal(db._collections.rateLimits["uid_user_1"], undefined);
  });

  test("denies on the uid layer when IP still has room but this uid is exhausted", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: "user_1", ipLimitPerHour: 100, uidLimitPerHour: 1, now });

    const result = await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: "user_1", ipLimitPerHour: 100, uidLimitPerHour: 1, now: now + 10 });
    assert.equal(result.scope, "uid");
  });

  test("an anonymous caller (no uid) is only ever checked against the IP layer", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: null, ipLimitPerHour: 5, uidLimitPerHour: 1, now });
    const result = await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: null, ipLimitPerHour: 5, uidLimitPerHour: 1, now: now + 10 });
    assert.equal(result, null);
    assert.equal(Object.keys(db._collections.rateLimits).some((k) => k.startsWith("uid_")), false);
  });

  test("burst layer: 5 per 10 minutes per IP, then denied with scope ip_burst", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    const params = { ip: "1.2.3.4", uid: null, ipLimitPerHour: 12, uidLimitPerHour: 25, burstLimit: 5, burstWindowMs: BURST_WINDOW_MS };
    for (let i = 0; i < 5; i++) {
      assert.equal(await evaluateSearchImportRateLimit(db, { ...params, now: now + i }), null);
    }
    const sixth = await evaluateSearchImportRateLimit(db, { ...params, now: now + 10 });
    assert.equal(sixth.scope, "ip_burst");
    assert.equal(sixth.limit, 5);
    // The denied 6th request must not consume hourly quota.
    assert.equal(db._collections.rateLimits["ip_1.2.3.4"].count, 5);
  });

  test("burst layer resets after its window while the hourly count keeps accumulating", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    const params = { ip: "1.2.3.4", uid: null, ipLimitPerHour: 12, uidLimitPerHour: 25, burstLimit: 5, burstWindowMs: BURST_WINDOW_MS };
    for (let i = 0; i < 5; i++) await evaluateSearchImportRateLimit(db, { ...params, now: now + i });

    const afterBurstWindow = await evaluateSearchImportRateLimit(db, { ...params, now: now + BURST_WINDOW_MS + 1 });
    assert.equal(afterBurstWindow, null);
    assert.equal(db._collections.rateLimits["ip_1.2.3.4"].count, 6);
  });

  test("burst layer applies per uid too, independent of other users on the same IP", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    const base = { ip: "9.9.9.9", ipLimitPerHour: 100, uidLimitPerHour: 100, burstLimit: 2, burstWindowMs: BURST_WINDOW_MS };
    // IP burst is also 2, so give user_b a different IP to isolate the uid layer.
    await evaluateSearchImportRateLimit(db, { ...base, uid: "user_a", now });
    await evaluateSearchImportRateLimit(db, { ...base, uid: "user_a", now: now + 1 });
    const userA = await evaluateSearchImportRateLimit(db, { ...base, ip: "8.8.8.8", uid: "user_a", now: now + 2 });
    const userB = await evaluateSearchImportRateLimit(db, { ...base, ip: "7.7.7.7", uid: "user_b", now: now + 2 });
    assert.equal(userA.scope, "uid_burst");
    assert.equal(userB, null);
  });

  test("no burstLimit means no burst layer (backward compatible)", async () => {
    const db = new FakeFirestore();
    await evaluateSearchImportRateLimit(db, { ip: "1.2.3.4", uid: "u", ipLimitPerHour: 12, uidLimitPerHour: 25, now: 1_000_000 });
    assert.equal(Object.keys(db._collections.rateLimits).some((k) => k.includes("burst")), false);
  });

  test("two different signed-in users behind the same IP each get their own uid budget", async () => {
    const db = new FakeFirestore();
    const now = 1_000_000;
    // Exhaust the shared IP's generous limit is avoided here — IP limit high, uid limit tight,
    // confirming uid_A being exhausted doesn't block uid_B on the same IP.
    await evaluateSearchImportRateLimit(db, { ip: "9.9.9.9", uid: "user_a", ipLimitPerHour: 100, uidLimitPerHour: 1, now });
    const userA = await evaluateSearchImportRateLimit(db, { ip: "9.9.9.9", uid: "user_a", ipLimitPerHour: 100, uidLimitPerHour: 1, now: now + 10 });
    const userB = await evaluateSearchImportRateLimit(db, { ip: "9.9.9.9", uid: "user_b", ipLimitPerHour: 100, uidLimitPerHour: 1, now: now + 10 });

    assert.equal(userA.scope, "uid");
    assert.equal(userB, null);
  });
});
