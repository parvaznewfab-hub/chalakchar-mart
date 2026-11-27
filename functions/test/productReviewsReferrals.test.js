// 14b step H: pure helpers of functions/reviews and functions/referrals.
const test = require("node:test");
const assert = require("node:assert/strict");
const R = require("../reviews/productReviews");
const F = require("../referrals/referrals");

test("dhakaDay: Asia/Dhaka is UTC+6, the day turns at 18:00 UTC", () => {
  assert.equal(R.dhakaDay(Date.UTC(2026, 10, 27, 17, 59)), "2026-11-27");
  assert.equal(R.dhakaDay(Date.UTC(2026, 10, 27, 18, 0)), "2026-11-28");
});

test("firstName: first word only, clipped to 40, never an email", () => {
  assert.equal(R.firstName("Karim Uddin Ahmed"), "Karim");
  assert.equal(R.firstName("  মোহাম্মদ   করিম "), "মোহাম্মদ");
  assert.equal(R.firstName(""), "Customer");
  assert.equal(R.firstName(undefined), "Customer");
  assert.equal(R.firstName("someone@example.com"), "Customer");
  assert.equal([...R.firstName("ক".repeat(80))].length, 40);
});

test("reviewRewardAmount: settings/app.reviewReward, else 2", () => {
  assert.equal(R.reviewRewardAmount({}), 2);
  assert.equal(R.reviewRewardAmount({ reviewReward: 5 }), 5);
  assert.equal(R.reviewRewardAmount({ reviewReward: "3" }), 3);
  assert.equal(R.reviewRewardAmount({ reviewReward: 0 }), 0);
  assert.equal(R.reviewRewardAmount({ reviewReward: -1 }), 2);
  assert.equal(R.reviewRewardAmount({ reviewReward: "abc" }), 2);
});

test("parseReviewInput: rating whole 1..5, comment trimmed and at most 1000 code points", () => {
  assert.deepEqual(R.parseReviewInput({ productId: "p1", rating: 4, comment: "  ভালো  " }),
    { productId: "p1", rating: 4, comment: "ভালো" });
  for (const rating of [0, 6, 4.5, "5", null]) {
    assert.throws(() => R.parseReviewInput({ productId: "p1", rating }), /rating/);
  }
  assert.throws(() => R.parseReviewInput({ productId: "a/b", rating: 5 }), /productId/);
  assert.doesNotThrow(() => R.parseReviewInput({ productId: "p1", rating: 5, comment: "ক".repeat(1000) }));
  assert.throws(() => R.parseReviewInput({ productId: "p1", rating: 5, comment: "ক".repeat(1001) }), /1000/);
  // Spaces around do not count.
  assert.doesNotThrow(() => R.parseReviewInput({ productId: "p1", rating: 5, comment: ` ${"a".repeat(1000)} ` }));
});

test("orderMakesVerifiedBuyer: status delivered/received/completed and productId in items; no name match", () => {
  const item = { productId: "p1", name: "Case" };
  assert.equal(R.orderMakesVerifiedBuyer({ status: "Delivered", items: [item] }, "p1"), true);
  assert.equal(R.orderMakesVerifiedBuyer({ status: "completed", items: [item] }, "p1"), true);
  assert.equal(R.orderMakesVerifiedBuyer({ status: "pending", items: [item] }, "p1"), false);
  assert.equal(R.orderMakesVerifiedBuyer({ status: "delivered", items: [{ name: "Case" }] }, "p1"), false);
  assert.equal(R.orderMakesVerifiedBuyer({ status: "delivered", items: [{ id: "p1" }] }, "p1"), false);
});

test("ratingStats: only whole ratings 1..5 count, average to 2 decimals", () => {
  assert.deepEqual(R.ratingStats([5, 4, 4]), { ratingAvg: 4.33, ratingCount: 3, reviewCount: 3, ratingTotal: 13 });
  assert.deepEqual(R.ratingStats([]), { ratingAvg: 0, ratingCount: 0, reviewCount: 0, ratingTotal: 0 });
  assert.deepEqual(R.ratingStats([7, "x", 3]), { ratingAvg: 3, ratingCount: 1, reviewCount: 1, ratingTotal: 3 });
});

test("isAdminUser: admin / super admin / owner, not blocked", () => {
  assert.equal(R.isAdminUser({ role: "admin" }), true);
  assert.equal(R.isAdminUser({ role: "user", roles: ["superAdmin"] }), true);
  assert.equal(R.isAdminUser({ role: "admin", isBanned: true }), false);
  assert.equal(R.isAdminUser({ role: "staff", permissions: ["products.edit"] }), false);
});

test("readReferralSettings: settings/app first, old settings/referral for missing keys", () => {
  assert.deepEqual(F.readReferralSettings({}, {}),
    { enabled: true, referrerReward: 25, refereeReward: 25, autoApprove: false });
  // live today: both docs 25/25, no auto-approve key -> OFF
  assert.deepEqual(F.readReferralSettings(
    { enableReferral: true, referralReward: 25, refereeReward: 25 },
    { referralEnabled: true, referrerReward: 25, refereeReward: 25, maxRewardPerUser: 0 }),
  { enabled: true, referrerReward: 25, refereeReward: 25, autoApprove: false });
  // different key names in the two docs
  assert.deepEqual(F.readReferralSettings({}, { referrerReward: 30, refereeReward: 10, autoApprove: true, referralEnabled: false }),
    { enabled: false, referrerReward: 30, refereeReward: 10, autoApprove: true });
  assert.equal(F.readReferralSettings({}, { referralReward: 40 }).referrerReward, 40);
  // app wins
  assert.deepEqual(F.readReferralSettings(
    { enableReferral: false, referralReward: 50, refereeReward: 20, referralAutoApprove: false },
    { referralEnabled: true, referrerReward: 30, refereeReward: 10, autoApprove: true }),
  { enabled: false, referrerReward: 50, refereeReward: 20, autoApprove: false });
  assert.equal(F.readReferralSettings({ referralAutoApprove: "true" }, {}).autoApprove, false);
  assert.equal(F.readReferralSettings({ referralAutoApprove: true }, {}).autoApprove, true);
});

test("canDecideReferrals: wallet.edit (list or map) or super admin; plain admin is not enough", () => {
  assert.equal(F.canDecideReferrals({ role: "superAdmin" }), true);
  assert.equal(F.canDecideReferrals({ role: "staff", permissions: ["wallet.edit"] }), true);
  assert.equal(F.canDecideReferrals({ role: "staff", permissions: { "wallet.edit": true } }), true);
  assert.equal(F.canDecideReferrals({ role: "admin" }), false);
  assert.equal(F.canDecideReferrals({ role: "staff", permissions: ["users.edit"] }), false);
  assert.equal(F.canDecideReferrals({ role: "superAdmin", isActive: false }), false);
});

test("refereeOf / normalizeStatus: old field names and any letter case", () => {
  assert.equal(F.refereeOf({ referredUserId: "u2" }), "u2");
  assert.equal(F.refereeOf({ refereeId: "u3" }), "u3");
  assert.equal(F.normalizeStatus("Pending"), "pending");
});
