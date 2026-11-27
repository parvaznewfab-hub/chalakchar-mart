// -----------------------------------------------------------------------------
// 14b step H: product reviews (products/{productId}/reviews/{uid}).
//
// Only these functions write reviews; the client never does (firestore.rules:
// read for everyone, no client write).
//
//   submitProductReview({ productId, rating, comment })
//     - signed in; rating a whole number 1..5; comment trimmed, at most 1000
//       characters (Unicode code points, so Bengali counts per letter);
//     - verified buyer: one of the caller's own orders has status delivered /
//       received / completed AND an item whose productId is this product
//       (no name matching);
//     - first review: written with the caller's FIRST name (from users/{uid},
//       never the email) and, in the same transaction, the reward:
//         points + totalEarnings on users/{uid},
//         wallet_logs/review_{productId}_{uid} (once per product, ever),
//         review_reward_days/{uid}_{YYYY-MM-DD} (Asia/Dhaka day counter).
//       At most 5 rewarded reviews per Dhaka day; after that the review is
//       still saved, without points. Amount: settings/app.reviewReward, else 2.
//     - existing review: only rating, comment and updatedAt change; no reward.
//   deleteProductReview({ productId, userId })  admin / super admin only.
//     Points already given stay (owner's decision).
//   recomputeProductRating(productId)  the onProductReviewWritten trigger:
//     ratingAvg / ratingCount / reviewCount / ratingTotal from all reviews.
//
// deps: { db, FieldValue, now } (admin SDK in production, the emulator in
// tests).
// -----------------------------------------------------------------------------

const REVIEW_ORDER_STATUSES = Object.freeze(["delivered", "received", "completed"]);
const MAX_COMMENT_CHARS = 1000;
const MAX_NAME_CHARS = 40;
const DAILY_REWARD_LIMIT = 5;
const DEFAULT_REVIEW_REWARD = 2;
const DHAKA_OFFSET_MS = 6 * 60 * 60 * 1000; // UTC+6, no daylight saving
const ADMIN_ROLES = Object.freeze(["superAdmin", "super_admin", "admin", "owner"]);
const RATING_FIELDS = Object.freeze(["ratingAvg", "ratingCount", "reviewCount", "ratingTotal"]);

class RequestError extends Error {
  constructor(code, message, reason) {
    super(message);
    this.code = code; // an HttpsError code
    this.reason = reason || code; // short machine-readable reason for the app
  }
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function charCount(value) {
  return [...String(value)].length;
}

function dhakaDay(ms) {
  return new Date(ms + DHAKA_OFFSET_MS).toISOString().slice(0, 10);
}

// First word of the profile name, clipped; "Customer" when there is none.
// Never the email.
function firstName(name) {
  const first = text(name).split(/\s+/)[0] || "";
  if (!first || first.includes("@")) return "Customer";
  const chars = [...first];
  return chars.length > MAX_NAME_CHARS ? chars.slice(0, MAX_NAME_CHARS).join("") : first;
}

function reviewRewardAmount(appSettings) {
  const raw = appSettings ? appSettings.reviewReward : undefined;
  const n = typeof raw === "number" ? raw : (typeof raw === "string" && raw.trim() ? Number(raw) : NaN);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_REVIEW_REWARD;
}

function validProductId(id) {
  return id.length > 0 && id.length <= 200 && !id.includes("/") && id !== "." && id !== "..";
}

function parseReviewInput(data) {
  const d = data && typeof data === "object" ? data : {};
  const productId = text(d.productId);
  if (!validProductId(productId)) throw new RequestError("invalid-argument", "productId is not valid.", "bad_product");
  const rating = d.rating;
  if (typeof rating !== "number" || !Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new RequestError("invalid-argument", "rating must be a whole number from 1 to 5.", "bad_rating");
  }
  if (d.comment !== undefined && d.comment !== null && typeof d.comment !== "string") {
    throw new RequestError("invalid-argument", "comment must be text.", "bad_comment");
  }
  const comment = text(d.comment);
  if (charCount(comment) > MAX_COMMENT_CHARS) {
    throw new RequestError("invalid-argument", `comment is longer than ${MAX_COMMENT_CHARS} characters.`, "comment_too_long");
  }
  return { productId, rating, comment };
}

// True when this order makes its owner a verified buyer of productId.
function orderMakesVerifiedBuyer(order, productId) {
  if (!order || typeof order !== "object") return false;
  const status = text(order.status).toLowerCase();
  if (!REVIEW_ORDER_STATUSES.includes(status)) return false;
  const items = Array.isArray(order.items) ? order.items : [];
  return items.some((item) => item && typeof item === "object" && text(item.productId) === productId);
}

async function findVerifiedOrderId(db, uid, productId) {
  const snap = await db.collection("orders").where("userId", "==", uid).get();
  const hit = snap.docs.find((doc) => orderMakesVerifiedBuyer(doc.data(), productId));
  return hit ? hit.id : null;
}

function rewardLogId(productId, uid) {
  return `review_${productId}_${uid}`;
}

function rewardDayId(uid, day) {
  return `${uid}_${day}`;
}

async function submitProductReview(auth, data, deps) {
  const uid = auth && auth.uid;
  if (!uid) throw new RequestError("unauthenticated", "Sign-in required.", "login");
  const { productId, rating, comment } = parseReviewInput(data);
  const { db, FieldValue } = deps;

  const productSnap = await db.collection("products").doc(productId).get();
  if (!productSnap.exists) throw new RequestError("not-found", "Product not found.", "no_product");

  const orderId = await findVerifiedOrderId(db, uid, productId);
  if (!orderId) {
    throw new RequestError("permission-denied", "Only a buyer who received this product can review it.", "not_buyer");
  }

  const day = dhakaDay(deps.now());
  const reviewRef = db.collection("products").doc(productId).collection("reviews").doc(uid);
  const userRef = db.collection("users").doc(uid);
  const settingsRef = db.collection("settings").doc("app");
  const logRef = db.collection("wallet_logs").doc(rewardLogId(productId, uid));
  const dayRef = db.collection("review_reward_days").doc(rewardDayId(uid, day));

  return db.runTransaction(async (tx) => {
    const [reviewSnap, userSnap, settingsSnap, logSnap, daySnap] = await Promise.all([
      tx.get(reviewRef), tx.get(userRef), tx.get(settingsRef), tx.get(logRef), tx.get(dayRef),
    ]);
    const user = userSnap.exists ? userSnap.data() : null;
    if (user && (user.isBanned === true || user.isActive === false)) {
      throw new RequestError("permission-denied", "This account is blocked.", "blocked");
    }

    if (reviewSnap.exists) {
      tx.update(reviewRef, { rating, comment, updatedAt: FieldValue.serverTimestamp() });
      return { created: false, rewarded: 0, reason: "edited" };
    }

    const amount = reviewRewardAmount(settingsSnap.exists ? settingsSnap.data() : {});
    const usedToday = daySnap.exists ? Number(daySnap.get("count")) || 0 : 0;
    let reason = "rewarded";
    if (!user) reason = "no_profile";
    else if (logSnap.exists) reason = "already_rewarded_for_product";
    else if (amount <= 0) reason = "reward_off";
    else if (usedToday >= DAILY_REWARD_LIMIT) reason = "daily_limit";
    const reward = reason === "rewarded";

    tx.create(reviewRef, {
      productId,
      userId: uid,
      userName: firstName(user && user.name),
      rating,
      comment,
      verifiedBuyer: true,
      orderId,
      rewardAmount: reward ? amount : 0,
      rewardGiven: reward,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (reward) {
      tx.update(userRef, {
        points: FieldValue.increment(amount),
        totalEarnings: FieldValue.increment(amount),
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.create(logRef, {
        userId: uid,
        type: "review_reward",
        direction: "credit",
        amount,
        source: "review",
        productId,
        note: "Product review reward",
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.set(dayRef, {
        userId: uid,
        day,
        count: usedToday + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { created: true, rewarded: reward ? amount : 0, reason };
  });
}

function isAdminUser(user) {
  if (!user || typeof user !== "object") return false;
  if (user.isActive === false || user.isBanned === true) return false;
  const roles = Array.isArray(user.roles) ? user.roles : [];
  return ADMIN_ROLES.includes(user.role) || roles.some((r) => ADMIN_ROLES.includes(r));
}

async function deleteProductReview(auth, data, deps) {
  const uid = auth && auth.uid;
  if (!uid) throw new RequestError("unauthenticated", "Sign-in required.", "login");
  const d = data && typeof data === "object" ? data : {};
  const productId = text(d.productId);
  const reviewerId = text(d.userId);
  if (!validProductId(productId) || !validProductId(reviewerId)) {
    throw new RequestError("invalid-argument", "productId and userId are required.", "bad_input");
  }
  const { db } = deps;
  const me = await db.collection("users").doc(uid).get();
  if (!me.exists || !isAdminUser(me.data())) {
    throw new RequestError("permission-denied", "Only an admin can delete reviews.", "permission");
  }
  const ref = db.collection("products").doc(productId).collection("reviews").doc(reviewerId);
  const snap = await ref.get();
  if (!snap.exists) throw new RequestError("not-found", "Review not found.", "no_review");
  await ref.delete();
  return { deleted: true };
}

function ratingStats(ratings) {
  let total = 0;
  let count = 0;
  for (const r of ratings) {
    const n = Number(r);
    if (Number.isInteger(n) && n >= 1 && n <= 5) {
      total += n;
      count += 1;
    }
  }
  const avg = count > 0 ? Math.round((total / count) * 100) / 100 : 0;
  return { ratingAvg: avg, ratingCount: count, reviewCount: count, ratingTotal: total };
}

async function recomputeProductRating(productId, deps) {
  const { db, FieldValue } = deps;
  const productRef = db.collection("products").doc(productId);
  return db.runTransaction(async (tx) => {
    const productSnap = await tx.get(productRef);
    // Never re-create a deleted product just to store a rating.
    if (!productSnap.exists) return { skipped: "product missing" };
    const reviews = await tx.get(productRef.collection("reviews"));
    const stats = ratingStats(reviews.docs.map((d) => d.get("rating")));
    const current = productSnap.data() || {};
    if (RATING_FIELDS.every((f) => current[f] === stats[f])) return { skipped: "unchanged", ...stats };
    tx.update(productRef, { ...stats, updatedAt: FieldValue.serverTimestamp() });
    return { updated: true, ...stats };
  });
}

module.exports = {
  REVIEW_ORDER_STATUSES,
  MAX_COMMENT_CHARS,
  DAILY_REWARD_LIMIT,
  DEFAULT_REVIEW_REWARD,
  RequestError,
  dhakaDay,
  firstName,
  reviewRewardAmount,
  parseReviewInput,
  orderMakesVerifiedBuyer,
  rewardLogId,
  rewardDayId,
  isAdminUser,
  ratingStats,
  submitProductReview,
  deleteProductReview,
  recomputeProductRating,
};
