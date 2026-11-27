// -----------------------------------------------------------------------------
// 14b step H: referrals. Only these functions write referrals/* (rules: no
// client create / update / delete).
//
// Settings: settings/app is the source (what the admin settings page saves);
// for a key missing there, the old settings/referral doc is used. The two
// docs name the keys differently:
//     settings/app             settings/referral (old)
//     enableReferral           referralEnabled
//     referralReward           referrerReward (or referralReward)
//     refereeReward            refereeReward
//     referralAutoApprove      autoApprove
// Auto-approve is ON only when the value is exactly true; missing = OFF.
//
// One credit for both paths (auto-approve in applyReferral, admin approval in
// approveReferral), so referrer and referee always get the same things:
//   referrer: points + reward, totalEarnings + reward, referralCount + 1
//   referee:  points + reward, totalEarnings + reward
//   wallet_logs/referral_referrer_{referrerId}_{refereeId}
//   wallet_logs/referral_referee_{refereeId}_{referrerId}
// A party whose wallet log already exists is not credited again (idempotent
// across both paths). referralCount moves only with the pending -> approved
// change of the referral itself, which happens once.
//
// deps: { db, FieldValue } (admin SDK in production, the emulator in tests).
// -----------------------------------------------------------------------------

const DEFAULT_REWARD = 25;
const ADMIN_ROLES = Object.freeze(["superAdmin", "super_admin"]);

class RequestError extends Error {
  constructor(code, message, reason) {
    super(message);
    this.code = code; // an HttpsError code
    this.reason = reason || code;
  }
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function has(obj, key) {
  return !!obj && Object.prototype.hasOwnProperty.call(obj, key) && obj[key] !== null && obj[key] !== undefined;
}

function nonNegative(value) {
  const n = typeof value === "number" ? value : (typeof value === "string" && value.trim() ? Number(value) : NaN);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function firstAmount(...values) {
  for (const v of values) {
    const n = nonNegative(v);
    if (n !== null) return n;
  }
  return DEFAULT_REWARD;
}

function readReferralSettings(appSettings, legacySettings) {
  const app = appSettings || {};
  const old = legacySettings || {};
  return {
    enabled: has(app, "enableReferral") ? app.enableReferral !== false : old.referralEnabled !== false,
    referrerReward: firstAmount(app.referralReward, old.referrerReward, old.referralReward),
    refereeReward: firstAmount(app.refereeReward, old.refereeReward),
    autoApprove: has(app, "referralAutoApprove") ? app.referralAutoApprove === true : old.autoApprove === true,
  };
}

function normalizeCode(value) {
  return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
}

function normalizeStatus(value) {
  return text(value).toLowerCase();
}

// referredUserId (written by the function); refereeId in older docs.
function refereeOf(referral) {
  return text(referral && referral.referredUserId) || text(referral && referral.refereeId);
}

function referrerLogId(referrerId, refereeId) {
  return `referral_referrer_${referrerId}_${refereeId}`;
}

function refereeLogId(refereeId, referrerId) {
  return `referral_referee_${refereeId}_${referrerId}`;
}

function logRefs(db, referrerId, refereeId) {
  return {
    referrerLog: db.collection("wallet_logs").doc(referrerLogId(referrerId, refereeId)),
    refereeLog: db.collection("wallet_logs").doc(refereeLogId(refereeId, referrerId)),
  };
}

// Writes the credit inside a transaction. All reads (the two log docs) must
// have been done by the caller already.
function writeCredit(tx, deps, c) {
  const { db, FieldValue } = deps;
  const now = FieldValue.serverTimestamp();
  const { referrerLog, refereeLog } = logRefs(db, c.referrerId, c.refereeId);

  const referrerUpdate = { referralCount: FieldValue.increment(1), updatedAt: now };
  let referrerCredited = 0;
  if (!c.referrerLogExists && c.referrerReward > 0) {
    referrerUpdate.points = FieldValue.increment(c.referrerReward);
    referrerUpdate.totalEarnings = FieldValue.increment(c.referrerReward);
    referrerCredited = c.referrerReward;
    tx.set(referrerLog, {
      userId: c.referrerId,
      type: "referral_reward",
      direction: "credit",
      amount: c.referrerReward,
      source: "referral",
      relatedUserId: c.refereeId,
      referralId: c.referralId,
      note: "Referral reward",
      createdAt: now,
    });
  }
  tx.set(db.collection("users").doc(c.referrerId), referrerUpdate, { merge: true });

  let refereeCredited = 0;
  if (!c.refereeLogExists && c.refereeReward > 0) {
    refereeCredited = c.refereeReward;
    tx.set(db.collection("users").doc(c.refereeId), {
      points: FieldValue.increment(c.refereeReward),
      totalEarnings: FieldValue.increment(c.refereeReward),
      updatedAt: now,
    }, { merge: true });
    tx.set(refereeLog, {
      userId: c.refereeId,
      type: "referee_reward",
      direction: "credit",
      amount: c.refereeReward,
      source: "referral",
      relatedUserId: c.referrerId,
      referralId: c.referralId,
      note: "Referral signup reward",
      createdAt: now,
    });
  }
  return { referrerCredited, refereeCredited };
}

// The body of the applyReferralReward HTTP function (code entered by the new
// user). Returns the response payload; throws Error("USER_PROFILE_NOT_FOUND").
async function applyReferral({ uid, code, deps }) {
  const { db, FieldValue } = deps;
  let payload = null;

  await db.runTransaction(async (tx) => {
    const userRef = db.collection("users").doc(uid);
    const appRef = db.collection("settings").doc("app");
    const legacyRef = db.collection("settings").doc("referral");
    const [userSnap, appSnap, legacySnap] = await Promise.all([tx.get(userRef), tx.get(appRef), tx.get(legacyRef)]);
    if (!userSnap.exists) throw new Error("USER_PROFILE_NOT_FOUND");
    const user = userSnap.data() || {};

    const settings = readReferralSettings(appSnap.exists ? appSnap.data() : {}, legacySnap.exists ? legacySnap.data() : {});
    // Referral switched off: nothing is read further, nothing is written.
    if (!settings.enabled) {
      payload = { ok: false, message: "Referral program is currently disabled." };
      return;
    }

    if (text(user.referredByUid) || text(user.referredByCode) || text(user.referredBy)) {
      payload = { ok: true, alreadyApplied: true, message: "You have already applied a referral code." };
      return;
    }
    if (normalizeCode(user.refCode) && normalizeCode(user.refCode) === code) {
      payload = { ok: false, message: "You cannot use your own referral code." };
      return;
    }

    const referrerSnap = await tx.get(db.collection("users").where("refCode", "==", code).limit(1));
    if (referrerSnap.empty) {
      payload = { ok: false, message: "Referral code not found." };
      return;
    }
    const referrerId = referrerSnap.docs[0].id;
    if (referrerId === uid) {
      payload = { ok: false, message: "You cannot use your own referral code." };
      return;
    }

    const referralRef = db.collection("referrals").doc(`${referrerId}_${uid}`);
    const { referrerLog, refereeLog } = logRefs(db, referrerId, uid);
    const [existing, referrerLogSnap, refereeLogSnap] = await Promise.all([
      tx.get(referralRef), tx.get(referrerLog), tx.get(refereeLog),
    ]);
    if (existing.exists) {
      payload = { ok: true, alreadyApplied: true, message: "You have already applied a referral code." };
      return;
    }

    const now = FieldValue.serverTimestamp();
    const status = settings.autoApprove ? "approved" : "pending";
    tx.set(userRef, {
      referredByUid: referrerId,
      referredByCode: code,
      referralAppliedAt: now,
      referralFirstOrderRewarded: settings.autoApprove,
      updatedAt: now,
    }, { merge: true });

    const referral = {
      referrerId,
      referredUserId: uid,
      referredByCode: code,
      referrerReward: settings.referrerReward,
      refereeReward: settings.refereeReward,
      status,
      autoApprove: settings.autoApprove,
      createdAt: now,
      updatedAt: now,
    };
    if (settings.autoApprove) {
      referral.approvedBy = "auto";
      referral.approvedAt = now;
    }
    tx.set(referralRef, referral);

    let credited = { referrerCredited: 0, refereeCredited: 0 };
    if (settings.autoApprove) {
      credited = writeCredit(tx, deps, {
        referralId: referralRef.id,
        referrerId,
        refereeId: uid,
        referrerReward: settings.referrerReward,
        refereeReward: settings.refereeReward,
        referrerLogExists: referrerLogSnap.exists,
        refereeLogExists: refereeLogSnap.exists,
      });
    }

    payload = {
      ok: true,
      alreadyApplied: false,
      status,
      referrerReward: credited.referrerCredited,
      refereeReward: credited.refereeCredited,
      message: settings.autoApprove
        ? "Referral applied successfully. Reward added to your balance."
        : "Referral code applied successfully. Reward is pending approval.",
    };
  });

  return payload;
}

// wallet.edit (list or map form) or super admin; never a blocked account.
function canDecideReferrals(user) {
  if (!user || typeof user !== "object") return false;
  if (user.isActive === false || user.isBanned === true) return false;
  const roles = Array.isArray(user.roles) ? user.roles : [];
  if (ADMIN_ROLES.includes(user.role) || roles.some((r) => ADMIN_ROLES.includes(r))) return true;
  const granted = user.permissions;
  if (Array.isArray(granted)) return granted.includes("wallet.edit");
  if (granted && typeof granted === "object") return granted["wallet.edit"] === true;
  return false;
}

function parseReferralId(data) {
  const id = text(data && typeof data === "object" ? data.referralId : "");
  if (!id || id.length > 300 || id.includes("/")) {
    throw new RequestError("invalid-argument", "referralId is not valid.", "bad_input");
  }
  return id;
}

async function checkDecider(db, uid) {
  if (!uid) throw new RequestError("unauthenticated", "Sign-in required.", "login");
  const me = await db.collection("users").doc(uid).get();
  if (!me.exists || !canDecideReferrals(me.data())) {
    throw new RequestError("permission-denied", "wallet.edit or super admin required.", "permission");
  }
}

function requirePending(snap) {
  if (!snap.exists) throw new RequestError("not-found", "Referral not found.", "not_found");
  const status = normalizeStatus(snap.get("status")) || "pending";
  if (status !== "pending") {
    throw new RequestError("failed-precondition", `Referral is already ${status}.`, `already_${status}`);
  }
}

async function approveReferral(auth, data, deps) {
  const { db, FieldValue } = deps;
  const uid = auth && auth.uid;
  await checkDecider(db, uid);
  const referralId = parseReferralId(data);
  const referralRef = db.collection("referrals").doc(referralId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    requirePending(snap);
    const referral = snap.data() || {};
    const referrerId = text(referral.referrerId);
    const refereeId = refereeOf(referral);
    if (!referrerId || !refereeId || referrerId === refereeId) {
      throw new RequestError("failed-precondition", "The referral has no valid user ids.", "bad_referral");
    }
    if (uid === referrerId || uid === refereeId) {
      throw new RequestError("permission-denied", "You cannot approve your own referral.", "self");
    }

    const { referrerLog, refereeLog } = logRefs(db, referrerId, refereeId);
    const [referrerSnap, refereeSnap, referrerLogSnap, refereeLogSnap] = await Promise.all([
      tx.get(db.collection("users").doc(referrerId)),
      tx.get(db.collection("users").doc(refereeId)),
      tx.get(referrerLog),
      tx.get(refereeLog),
    ]);
    if (!referrerSnap.exists || !refereeSnap.exists) {
      throw new RequestError("failed-precondition", "A user of this referral no longer exists.", "user_missing");
    }

    const credited = writeCredit(tx, deps, {
      referralId,
      referrerId,
      refereeId,
      referrerReward: nonNegative(referral.referrerReward) ?? 0,
      refereeReward: nonNegative(referral.refereeReward) ?? 0,
      referrerLogExists: referrerLogSnap.exists,
      refereeLogExists: refereeLogSnap.exists,
    });
    tx.update(referralRef, {
      status: "approved",
      approvedBy: uid,
      approvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status: "approved", ...credited };
  });
}

async function rejectReferral(auth, data, deps) {
  const { db, FieldValue } = deps;
  const uid = auth && auth.uid;
  await checkDecider(db, uid);
  const referralId = parseReferralId(data);
  const referralRef = db.collection("referrals").doc(referralId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(referralRef);
    requirePending(snap);
    tx.update(referralRef, {
      status: "rejected",
      rejectedBy: uid,
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status: "rejected" };
  });
}

module.exports = {
  DEFAULT_REWARD,
  RequestError,
  readReferralSettings,
  normalizeCode,
  normalizeStatus,
  refereeOf,
  referrerLogId,
  refereeLogId,
  canDecideReferrals,
  applyReferral,
  approveReferral,
  rejectReferral,
};
