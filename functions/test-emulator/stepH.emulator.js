// 14b step H: functions/reviews and functions/referrals against the FIRESTORE
// EMULATOR (demo project, real transactions). Run: node tools/rules-test/run-steph.js

const test = require("node:test");
const assert = require("node:assert/strict");

const PROJECT = process.env.GCLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !PROJECT.startsWith("demo-")) {
  throw new Error("Refusing to run: needs FIRESTORE_EMULATOR_HOST and a demo-* project (emulator only).");
}

const admin = require("firebase-admin");
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const R = require("../reviews/productReviews");
const F = require("../referrals/referrals");

// 2026-11-27 12:00 Dhaka
let clock = Date.UTC(2026, 10, 27, 6, 0);
const deps = { db, FieldValue, now: () => clock };

async function clearAll() {
  const cols = await db.listCollections();
  for (const c of cols) await db.recursiveDelete(c);
}

const u = (role, extra = {}) => ({ role, roles: ["user", role], isActive: true, isBanned: false, vendorId: "", ...extra });

async function seed() {
  clock = Date.UTC(2026, 10, 27, 6, 0);
  const b = db.batch();
  b.set(db.doc("users/c1"), u("user", { name: "Karim Uddin", email: "karim@example.invalid", points: 0, totalEarnings: 0 }));
  b.set(db.doc("users/c2"), u("user", { name: "Rahima", points: 0, totalEarnings: 0, refCode: "C2CODE", referralCount: 0 }));
  b.set(db.doc("users/c3"), u("user", { name: "New", points: 0, totalEarnings: 0 }));
  b.set(db.doc("users/admin"), u("admin", { name: "Admin" }));
  b.set(db.doc("users/boss"), u("superAdmin", { name: "Boss" }));
  b.set(db.doc("users/walletStaff"), u("staff", { permissions: ["wallet.edit"] }));
  b.set(db.doc("users/usersStaff"), u("staff", { permissions: ["users.edit", "users.view"] }));
  for (let i = 1; i <= 7; i++) b.set(db.doc(`products/p${i}`), { name: `Product ${i}`, price: 100 });
  b.set(db.doc("products/pName"), { name: "Same name", price: 100 });
  // c1 received p1..p7 (one delivered order) and has a pending order for pPending.
  b.set(db.doc("products/pPending"), { name: "Pending item", price: 100 });
  b.set(db.doc("orders/o1"), {
    userId: "c1", status: "delivered",
    items: [1, 2, 3, 4, 5, 6, 7].map((i) => ({ productId: `p${i}`, name: `Product ${i}`, qty: 1, price: 100 })),
  });
  b.set(db.doc("orders/o2"), { userId: "c1", status: "pending", items: [{ productId: "pPending", qty: 1 }] });
  // name matches pName but the productId is a different one
  b.set(db.doc("orders/o3"), { userId: "c1", status: "delivered", items: [{ productId: "otherId", name: "Same name" }] });
  b.set(db.doc("settings/app"), { enableReferral: true, referralReward: 25, refereeReward: 25 });
  await b.commit();
}

const user = async (id) => (await db.doc(`users/${id}`).get()).data();
const exists = async (path) => (await db.doc(path).get()).exists;
const submit = (uid, data) => R.submitProductReview({ uid }, data, deps);

async function rejectsWith(promise, code, reason) {
  await assert.rejects(promise, (e) => {
    assert.equal(e.code, code);
    if (reason) assert.equal(e.reason, reason);
    return true;
  });
}

test.beforeEach(async () => { await clearAll(); await seed(); });

// ----------------------------------------------------------------- reviews
test("review: not a buyer -> refused", async () => {
  await rejectsWith(submit("c2", { productId: "p1", rating: 5, comment: "x" }), "permission-denied", "not_buyer");
  assert.equal(await exists("products/p1/reviews/c2"), false);
});

test("review: order still pending -> refused", async () => {
  await rejectsWith(submit("c1", { productId: "pPending", rating: 5 }), "permission-denied", "not_buyer");
});

test("review: delivered item with the same NAME but another productId -> refused", async () => {
  await rejectsWith(submit("c1", { productId: "pName", rating: 5 }), "permission-denied", "not_buyer");
});

test("review: not signed in / bad rating / 1001 characters -> refused", async () => {
  await rejectsWith(R.submitProductReview(null, { productId: "p1", rating: 5 }, deps), "unauthenticated");
  await rejectsWith(submit("c1", { productId: "p1", rating: 6 }), "invalid-argument", "bad_rating");
  await rejectsWith(submit("c1", { productId: "p1", rating: 5, comment: "ক".repeat(1001) }), "invalid-argument", "comment_too_long");
});

test("review: first review gives the points once; editing gives none", async () => {
  const r1 = await submit("c1", { productId: "p1", rating: 4, comment: "  ভালো product, but box ভাঙা  " });
  assert.deepEqual([r1.created, r1.rewarded, r1.reason], [true, 2, "rewarded"]);
  let c1 = await user("c1");
  assert.deepEqual([c1.points, c1.totalEarnings], [2, 2]);
  const review = (await db.doc("products/p1/reviews/c1").get()).data();
  assert.equal(review.userName, "Karim");
  assert.equal(review.comment, "ভালো product, but box ভাঙা");
  assert.equal(review.orderId, "o1");
  assert.equal(review.verifiedBuyer, true);
  assert.equal("userEmail" in review, false);
  assert.ok(!JSON.stringify(review).includes("@"));
  const log = (await db.doc("wallet_logs/review_p1_c1").get()).data();
  assert.deepEqual([log.userId, log.type, log.direction, log.amount, log.source, log.productId],
    ["c1", "review_reward", "credit", 2, "review", "p1"]);

  const r2 = await submit("c1", { productId: "p1", rating: 2, comment: "changed" });
  assert.deepEqual([r2.created, r2.rewarded], [false, 0]);
  c1 = await user("c1");
  assert.deepEqual([c1.points, c1.totalEarnings], [2, 2]);
  const edited = (await db.doc("products/p1/reviews/c1").get()).data();
  assert.deepEqual([edited.rating, edited.comment, edited.rewardGiven, edited.userName], [2, "changed", true, "Karim"]);
  assert.equal(edited.createdAt.toMillis(), review.createdAt.toMillis());
});

test("review: 6th review of the Dhaka day is saved without points; next day counts again", async () => {
  for (let i = 1; i <= 5; i++) {
    const r = await submit("c1", { productId: `p${i}`, rating: 5 });
    assert.equal(r.rewarded, 2, `review ${i}`);
  }
  const r6 = await submit("c1", { productId: "p6", rating: 5, comment: "sixth" });
  assert.deepEqual([r6.created, r6.rewarded, r6.reason], [true, 0, "daily_limit"]);
  assert.equal(await exists("products/p6/reviews/c1"), true);
  assert.equal(await exists("wallet_logs/review_p6_c1"), false);
  assert.equal((await user("c1")).points, 10);
  // 18:00 UTC = midnight in Dhaka
  clock = Date.UTC(2026, 10, 27, 18, 1);
  const r7 = await submit("c1", { productId: "p7", rating: 5 });
  assert.equal(r7.rewarded, 2);
  assert.equal((await user("c1")).points, 12);
});

test("review: two reviews at the same time around the limit -> exactly 5 rewarded", async () => {
  for (let i = 1; i <= 4; i++) await submit("c1", { productId: `p${i}`, rating: 5 });
  const both = await Promise.all([5, 6].map((i) => submit("c1", { productId: `p${i}`, rating: 5 })));
  assert.equal(both.filter((r) => r.rewarded > 0).length, 1);
  assert.equal((await user("c1")).points, 10);
  assert.equal((await db.doc("review_reward_days/c1_2026-11-27").get()).get("count"), 5);
});

test("review: amount from settings/app.reviewReward", async () => {
  await db.doc("settings/app").set({ reviewReward: 5 }, { merge: true });
  const r = await submit("c1", { productId: "p1", rating: 5 });
  assert.equal(r.rewarded, 5);
  assert.equal((await user("c1")).points, 5);
});

test("review delete: only admin; points stay; a new review of the same product gets no points", async () => {
  await submit("c1", { productId: "p1", rating: 5 });
  await rejectsWith(R.deleteProductReview({ uid: "c1" }, { productId: "p1", userId: "c1" }, deps), "permission-denied");
  await rejectsWith(R.deleteProductReview({ uid: "walletStaff" }, { productId: "p1", userId: "c1" }, deps), "permission-denied");
  assert.deepEqual(await R.deleteProductReview({ uid: "admin" }, { productId: "p1", userId: "c1" }, deps), { deleted: true });
  assert.equal(await exists("products/p1/reviews/c1"), false);
  assert.equal((await user("c1")).points, 2);
  const again = await submit("c1", { productId: "p1", rating: 3 });
  assert.deepEqual([again.created, again.rewarded, again.reason], [true, 0, "already_rewarded_for_product"]);
  assert.equal((await user("c1")).points, 2);
});

// ----------------------------------------------------------------- trigger
test("trigger: average right after create, edit and delete", async () => {
  const p = "products/p1";
  await db.doc(`${p}/reviews/a`).set({ rating: 5 });
  await db.doc(`${p}/reviews/b`).set({ rating: 4 });
  await db.doc(`${p}/reviews/c`).set({ rating: 4 });
  let r = await R.recomputeProductRating("p1", deps);
  assert.deepEqual([r.ratingAvg, r.ratingCount, r.ratingTotal], [4.33, 3, 13]);
  let prod = (await db.doc(p).get()).data();
  assert.deepEqual([prod.ratingAvg, prod.ratingCount, prod.reviewCount, prod.ratingTotal], [4.33, 3, 3, 13]);

  await db.doc(`${p}/reviews/b`).update({ rating: 1 });
  await R.recomputeProductRating("p1", deps);
  prod = (await db.doc(p).get()).data();
  assert.deepEqual([prod.ratingAvg, prod.ratingCount, prod.ratingTotal], [3.33, 3, 10]);

  await db.doc(`${p}/reviews/a`).delete();
  await R.recomputeProductRating("p1", deps);
  prod = (await db.doc(p).get()).data();
  assert.deepEqual([prod.ratingAvg, prod.ratingCount, prod.reviewCount, prod.ratingTotal], [2.5, 2, 2, 5]);

  await db.doc(`${p}/reviews/b`).delete();
  await db.doc(`${p}/reviews/c`).delete();
  await R.recomputeProductRating("p1", deps);
  prod = (await db.doc(p).get()).data();
  assert.deepEqual([prod.ratingAvg, prod.ratingCount, prod.reviewCount, prod.ratingTotal], [0, 0, 0, 0]);

  r = await R.recomputeProductRating("p1", deps);
  assert.equal(r.skipped, "unchanged");
});

test("trigger: a deleted product is not re-created", async () => {
  await db.doc("products/gone/reviews/a").set({ rating: 5 });
  const r = await R.recomputeProductRating("gone", deps);
  assert.equal(r.skipped, "product missing");
  assert.equal(await exists("products/gone"), false);
});

// --------------------------------------------------------------- referrals
const apply = (uid, code) => F.applyReferral({ uid, code, deps });

test("applyReferralReward: no auto-approve key -> pending, no points, no logs", async () => {
  const r = await apply("c3", "C2CODE");
  assert.deepEqual([r.ok, r.status, r.referrerReward, r.refereeReward], [true, "pending", 0, 0]);
  const ref = (await db.doc("referrals/c2_c3").get()).data();
  assert.deepEqual([ref.status, ref.autoApprove, ref.referredUserId, ref.referrerReward, ref.refereeReward],
    ["pending", false, "c3", 25, 25]);
  assert.deepEqual([(await user("c2")).points, (await user("c3")).points, (await user("c2")).referralCount], [0, 0, 0]);
  assert.equal(await exists("wallet_logs/referral_referrer_c2_c3"), false);
  assert.equal(await exists("wallet_logs/referral_referee_c3_c2"), false);
});

test("applyReferralReward: old settings/referral autoApprove only counts when settings/app has no key", async () => {
  await db.doc("settings/referral").set({ autoApprove: true });
  await db.doc("settings/app").set({ referralAutoApprove: false }, { merge: true });
  assert.equal((await apply("c3", "C2CODE")).status, "pending");
});

test("applyReferralReward: auto-approve on -> approved, same credit as admin approval", async () => {
  await db.doc("settings/app").set({ referralAutoApprove: true, referralReward: 30, refereeReward: 10 }, { merge: true });
  const r = await apply("c3", "C2CODE");
  assert.deepEqual([r.status, r.referrerReward, r.refereeReward], ["approved", 30, 10]);
  const c2 = await user("c2");
  const c3 = await user("c3");
  assert.deepEqual([c2.points, c2.totalEarnings, c2.referralCount], [30, 30, 1]);
  assert.deepEqual([c3.points, c3.totalEarnings], [10, 10]);
  assert.equal((await db.doc("referrals/c2_c3").get()).get("approvedBy"), "auto");
  assert.equal((await db.doc("wallet_logs/referral_referrer_c2_c3").get()).get("amount"), 30);
  assert.equal((await db.doc("wallet_logs/referral_referee_c3_c2").get()).get("amount"), 10);
});

test("applyReferralReward: referral switched off -> nothing written", async () => {
  await db.doc("settings/app").set({ enableReferral: false }, { merge: true });
  const r = await apply("c3", "C2CODE");
  assert.equal(r.ok, false);
  assert.equal(await exists("referrals/c2_c3"), false);
  assert.equal((await user("c3")).referredByUid, undefined);
});

async function pendingReferral(extra = {}) {
  await db.doc("referrals/ref1").set({
    referrerId: "c2", referredUserId: "c3", referrerReward: 25, refereeReward: 25,
    status: "pending", autoApprove: false, createdAt: FieldValue.serverTimestamp(), ...extra,
  });
}

test("approveReferral: needs wallet.edit or super admin", async () => {
  await pendingReferral();
  for (const who of ["c1", "admin", "usersStaff"]) {
    await rejectsWith(F.approveReferral({ uid: who }, { referralId: "ref1" }, deps), "permission-denied", "permission");
    await rejectsWith(F.rejectReferral({ uid: who }, { referralId: "ref1" }, deps), "permission-denied", "permission");
  }
  await rejectsWith(F.approveReferral(null, { referralId: "ref1" }, deps), "unauthenticated");
  assert.equal((await db.doc("referrals/ref1").get()).get("status"), "pending");
  assert.equal((await user("c2")).points, 0);
});

test("approveReferral: wallet.edit staff approves; credit as auto path; approvedBy; amounts from the referral doc", async () => {
  await pendingReferral({ referrerReward: 40, refereeReward: 15 });
  const r = await F.approveReferral({ uid: "walletStaff" }, { referralId: "ref1" }, deps);
  assert.deepEqual(r, { status: "approved", referrerCredited: 40, refereeCredited: 15 });
  const c2 = await user("c2");
  const c3 = await user("c3");
  assert.deepEqual([c2.points, c2.totalEarnings, c2.referralCount], [40, 40, 1]);
  assert.deepEqual([c3.points, c3.totalEarnings], [15, 15]);
  const ref = (await db.doc("referrals/ref1").get()).data();
  assert.equal(ref.status, "approved");
  assert.equal(ref.approvedBy, "walletStaff");
  assert.ok(ref.approvedAt);
  assert.equal((await db.doc("wallet_logs/referral_referrer_c2_c3").get()).get("referralId"), "ref1");
});

test("approveReferral: super admin approves an old-style doc (refereeId, 'Pending')", async () => {
  await db.doc("referrals/old1").set({ referrerId: "c2", refereeId: "c3", referrerReward: 5, refereeReward: 5, status: "Pending" });
  const r = await F.approveReferral({ uid: "boss" }, { referralId: "old1" }, deps);
  assert.equal(r.status, "approved");
  assert.equal((await user("c3")).points, 5);
});

test("approveReferral / rejectReferral: an approved or rejected referral cannot be decided again", async () => {
  await pendingReferral();
  await F.approveReferral({ uid: "walletStaff" }, { referralId: "ref1" }, deps);
  await rejectsWith(F.approveReferral({ uid: "walletStaff" }, { referralId: "ref1" }, deps), "failed-precondition", "already_approved");
  await rejectsWith(F.rejectReferral({ uid: "walletStaff" }, { referralId: "ref1" }, deps), "failed-precondition", "already_approved");
  assert.deepEqual([(await user("c2")).points, (await user("c2")).referralCount], [25, 1]);

  await db.doc("referrals/ref2").set({ referrerId: "c1", referredUserId: "c3", referrerReward: 25, refereeReward: 25, status: "pending" });
  assert.deepEqual(await F.rejectReferral({ uid: "boss" }, { referralId: "ref2" }, deps), { status: "rejected" });
  const ref2 = (await db.doc("referrals/ref2").get()).data();
  assert.deepEqual([ref2.status, ref2.rejectedBy], ["rejected", "boss"]);
  assert.ok(ref2.rejectedAt);
  await rejectsWith(F.approveReferral({ uid: "boss" }, { referralId: "ref2" }, deps), "failed-precondition", "already_rejected");
  assert.equal((await user("c1")).points, 0);
});

test("approveReferral: points already given on the auto path are not given again", async () => {
  await db.doc("settings/app").set({ referralAutoApprove: true }, { merge: true });
  await apply("c3", "C2CODE");
  // someone sets the referral back to pending by hand
  await db.doc("referrals/c2_c3").update({ status: "pending" });
  await F.approveReferral({ uid: "walletStaff" }, { referralId: "c2_c3" }, deps);
  const c2 = await user("c2");
  const c3 = await user("c3");
  assert.deepEqual([c2.points, c2.totalEarnings, c3.points, c3.totalEarnings], [25, 25, 25, 25]);
});

test("approveReferral: two approvals at the same time -> credited once", async () => {
  await pendingReferral();
  const results = await Promise.allSettled([
    F.approveReferral({ uid: "walletStaff" }, { referralId: "ref1" }, deps),
    F.approveReferral({ uid: "boss" }, { referralId: "ref1" }, deps),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const c2 = await user("c2");
  assert.deepEqual([c2.points, c2.referralCount, (await user("c3")).points], [25, 1, 25]);
});

test("approveReferral: a deleted user -> refused, nothing written; reject still works", async () => {
  await db.doc("referrals/orphan").set({ referrerId: "goneA", referredUserId: "goneB", referrerReward: 25, refereeReward: 25, status: "pending" });
  await rejectsWith(F.approveReferral({ uid: "boss" }, { referralId: "orphan" }, deps), "failed-precondition", "user_missing");
  assert.equal(await exists("users/goneA"), false);
  assert.equal(await exists("users/goneB"), false);
  assert.equal(await exists("wallet_logs/referral_referrer_goneA_goneB"), false);
  assert.equal((await F.rejectReferral({ uid: "boss" }, { referralId: "orphan" }, deps)).status, "rejected");
});

test("approveReferral: own referral -> refused", async () => {
  await db.doc("users/c2").set({ permissions: ["wallet.edit"] }, { merge: true });
  await pendingReferral();
  await rejectsWith(F.approveReferral({ uid: "c2" }, { referralId: "ref1" }, deps), "permission-denied", "self");
});
