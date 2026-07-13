const { setGlobalOptions } = require("firebase-functions/v2");
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const OpenAI = require("openai");
const { toFile } = require("openai");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });
const crypto = require("crypto");
const axios = require("axios");

admin.initializeApp();
const db = admin.firestore();

// ---- TikTok integration (isolated module — see functions/tiktok/) ----
// Required after admin.initializeApp() so the tiktok modules' own
// admin.firestore() calls never race the app's initialization.
const { tiktokOAuthStart, tiktokOAuthCallback, tiktokGetOAuthConfig } = require("./tiktok/oauth");
const { tiktokTokenRefreshSweep } = require("./tiktok/tokenRefresh");
const { tiktokConnectionStatusProjection } = require("./tiktok/connectionStatusProjection");
const { tiktokDisconnect } = require("./tiktok/disconnect");
const { postTikTokContent, tiktokForceRepublish } = require("./tiktok/dispatch");
const { tiktokGetCreatorInfo } = require("./tiktok/creatorInfo");
const { tiktokConfirmPublish } = require("./tiktok/publish");
const { tiktokWebhook } = require("./tiktok/resolve");
const { tiktokPublishJobsSweep } = require("./tiktok/jobsSweep");

let marketingSettingsCache = null;
let marketingSettingsCacheAt = 0;
const MARKETING_SETTINGS_CACHE_MS = 5 * 60 * 1000;

function textValue(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function boolValue(value, fallback = false) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === "boolean") return value;
  const text = String(value).trim().toLowerCase();
  if (["true", "1", "yes"].includes(text)) return true;
  if (["false", "0", "no"].includes(text)) return false;
  return fallback;
}

function mapValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

async function loadMarketingSettings(force = false) {
  const now = Date.now();

  if (!force && marketingSettingsCache && now - marketingSettingsCacheAt < MARKETING_SETTINGS_CACHE_MS) {
    return marketingSettingsCache;
  }

  const doc = await db.collection("settings").doc("app").get();
  const data = doc.data() || {};
  const marketingDefaults = mapValue(data.marketingDefaults);
  const socialApi = mapValue(data.socialApi);

  const settings = {
    enabled: boolValue(marketingDefaults.enabled ?? data.autoMarketingEnabled, true),
    channels: {
      fcm: boolValue(marketingDefaults.pushNotification ?? data.defaultPushMarketing, true),
      push: boolValue(marketingDefaults.pushNotification ?? data.defaultPushMarketing, true),
      inApp: boolValue(marketingDefaults.inAppNotification ?? data.defaultInAppMarketing, true),
      facebook: boolValue(marketingDefaults.facebook ?? data.defaultFacebookQueue, false),
      instagram: boolValue(marketingDefaults.instagram ?? data.defaultInstagramQueue, false),
      whatsapp: boolValue(marketingDefaults.whatsapp ?? data.defaultWhatsappQueue, false),
      messenger: boolValue(marketingDefaults.messenger ?? data.defaultMessengerQueue, false),
      tiktok: boolValue(marketingDefaults.tiktok ?? data.defaultTiktokQueue, false),
    },
    audience: textValue(marketingDefaults.audience ?? data.defaultMarketingAudience, "everyone"),
    publishTime: textValue(marketingDefaults.publishTime ?? data.defaultMarketingPublishTime, "immediately"),
    captionTemplate: textValue(
      marketingDefaults.captionTemplate ?? data.defaultMarketingCaption,
      "🛒 {productName}\nPrice: ৳{price}\nOrder now: {productUrl}"
    ),
    socialApi,
    apiReady: {
      facebook: textValue(socialApi.facebookPageId).length > 0 && textValue(socialApi.facebookPageAccessToken).length > 0,
      instagram: textValue(socialApi.instagramBusinessId).length > 0 && textValue(socialApi.instagramAccessToken).length > 0,
      whatsapp: textValue(socialApi.whatsappPhoneNumberId).length > 0 && textValue(socialApi.whatsappAccessToken).length > 0,
      messenger: textValue(socialApi.facebookPageAccessToken).length > 0,
      tiktok: textValue(socialApi.tiktokClientKey).length > 0 && textValue(socialApi.tiktokClientSecret).length > 0,
    },
  };

  marketingSettingsCache = settings;
  marketingSettingsCacheAt = now;
  return settings;
}

function hasRequestedSocialChannel(channels = {}) {
  return channels.facebook === true ||
    channels.instagram === true ||
    channels.whatsapp === true ||
    channels.messenger === true ||
    channels.tiktok === true;
}

function hasReadyRequestedSocialApi(channels = {}, apiReady = {}) {
  return (channels.facebook === true && apiReady.facebook === true) ||
    (channels.instagram === true && apiReady.instagram === true) ||
    (channels.whatsapp === true && apiReady.whatsapp === true) ||
    (channels.messenger === true && apiReady.messenger === true) ||
    (channels.tiktok === true && apiReady.tiktok === true);
}

async function writeCampaignAnalytics(queueId, outbox, patch = {}) {
  await db.collection("campaign_analytics").doc(queueId).set({
    queueId,
    productId: outbox.productId || queueId,
    productName: outbox.productName || "",
    channels: outbox.channels || {},
    status: outbox.status || "",
    socialStatus: outbox.socialStatus || "",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...patch,
  }, { merge: true });
}


function graphApiVersion(settings) {
  const raw = textValue(settings?.socialApi?.graphApiVersion, "v20.0");
  return raw.startsWith("v") ? raw : `v${raw}`;
}

function cleanUrl(value) {
  const url = textValue(value);
  return url.startsWith("http://") || url.startsWith("https://") ? url : "";
}

function captionForChannel(outbox, channel) {
  const captions = mapValue(outbox.captions);
  return textValue(
    captions[channel],
    textValue(
      captions.facebook || captions.whatsapp || outbox.marketingCaption,
      `${textValue(outbox.productName, "New Product")}\n${textValue(outbox.productUrl)}`
    )
  );
}

function normalizeRecipientList(value) {
  if (Array.isArray(value)) {
    return [...new Set(value.map((v) => textValue(v)).filter(Boolean))];
  }
  const text = textValue(value);
  if (!text) return [];
  return [...new Set(text.split(/[,,\n\s]+/).map((v) => v.trim()).filter(Boolean))];
}

async function metaGraphGet(settings, path, token, params = {}) {
  const version = graphApiVersion(settings);
  const cleanPath = String(path || "").replace(/^\/+/, "");
  const url = `https://graph.facebook.com/${version}/${cleanPath}`;

  const response = await axios.get(url, {
    params: { ...params, access_token: token },
    timeout: 30000,
    validateStatus: () => true,
  });

  if (response.status < 200 || response.status >= 300 || response.data?.error) {
    const apiError = response.data?.error || response.data || {};
    const message = apiError.message || `Meta API failed with status ${response.status}`;
    const error = new Error(message);
    error.status = response.status;
    error.api = apiError;
    throw error;
  }

  return response.data || {};
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForInstagramContainer(settings, creationId, token) {
  let lastStatus = {};

  for (let i = 0; i < 8; i++) {
    await sleep(i === 0 ? 3000 : 2000);

    lastStatus = await metaGraphGet(settings, creationId, token, {
      fields: "status_code,status",
    });

    const statusCode = textValue(lastStatus.status_code).toUpperCase();

    if (statusCode === "FINISHED") {
      return lastStatus;
    }

    if (["ERROR", "EXPIRED"].includes(statusCode)) {
      const error = new Error(`Instagram media container ${statusCode}`);
      error.api = lastStatus;
      throw error;
    }
  }

  const error = new Error("Instagram media container not ready");
  error.api = lastStatus;
  throw error;
}

async function metaGraphPost(settings, path, payload, token) {
  const version = graphApiVersion(settings);
  const cleanPath = String(path || "").replace(/^\/+/, "");
  const url = `https://graph.facebook.com/${version}/${cleanPath}`;

  const response = await axios.post(url, payload, {
    params: { access_token: token },
    timeout: 30000,
    validateStatus: () => true,
  });

  if (response.status < 200 || response.status >= 300 || response.data?.error) {
    const apiError = response.data?.error || response.data || {};
    const message = apiError.message || `Meta API failed with status ${response.status}`;
    const error = new Error(message);
    error.status = response.status;
    error.api = apiError;
    throw error;
  }

  return response.data || {};
}

function channelResult(status, extra = {}) {
  return {
    status,
    at: admin.firestore.FieldValue.serverTimestamp(),
    ...extra,
  };
}

async function postFacebookPage(settings, outbox) {
  const socialApi = mapValue(settings.socialApi);
  const pageId = textValue(socialApi.facebookPageId);
  const token = textValue(socialApi.facebookPageAccessToken);
  if (!pageId || !token) return channelResult("skipped_missing_credentials");

  const caption = captionForChannel(outbox, "facebook");
  const imageUrl = cleanUrl(outbox.imageUrl);
  const productUrl = cleanUrl(outbox.productUrl);

  if (imageUrl) {
    const data = await metaGraphPost(settings, `${pageId}/photos`, {
      url: imageUrl,
      caption: productUrl ? `${caption}\n\n${productUrl}` : caption,
      published: true,
    }, token);
    return channelResult("posted", { postId: textValue(data.post_id || data.id), response: data });
  }

  const data = await metaGraphPost(settings, `${pageId}/feed`, {
    message: caption,
    ...(productUrl ? { link: productUrl } : {}),
  }, token);
  return channelResult("posted", { postId: textValue(data.id), response: data });
}

async function postInstagramBusiness(settings, outbox) {
  const socialApi = mapValue(settings.socialApi);
  const instagramBusinessId = textValue(socialApi.instagramBusinessId);
  const token = textValue(socialApi.instagramAccessToken || socialApi.facebookPageAccessToken);
  const imageUrl = cleanUrl(outbox.imageUrl);

  if (!instagramBusinessId || !token) {
    return channelResult("skipped_missing_credentials");
  }

  if (!imageUrl) {
    return channelResult("skipped_missing_image_url");
  }

  const caption = captionForChannel(outbox, "instagram");

  const container = await metaGraphPost(settings, `${instagramBusinessId}/media`, {
    image_url: imageUrl,
    caption,
  }, token);

  const creationId = textValue(container.id);

  if (!creationId) {
    return channelResult("failed_missing_creation_id", { response: container });
  }

  const containerStatus = await waitForInstagramContainer(
    settings,
    creationId,
    token
  );

  const published = await metaGraphPost(settings, `${instagramBusinessId}/media_publish`, {
    creation_id: creationId,
  }, token);

  return channelResult("posted", {
    creationId,
    containerStatus,
    postId: textValue(published.id),
    response: published,
  });
}

function normalizeBangladeshWhatsAppNumber(value) {
  const digits = textValue(value).replace(/\D/g, "");
  if (/^8801\d{9}$/.test(digits)) return digits;
  if (/^01\d{9}$/.test(digits)) return `88${digits}`;
  return "";
}

function whatsappDeliveryId(queueId, userId) {
  return crypto.createHash("sha256").update(`${queueId}:${userId}`).digest("hex").slice(0, 40);
}

async function enqueueDynamicWhatsAppDeliveries(settings, queueId, outbox) {
  const socialApi = mapValue(settings.socialApi);
  const phoneNumberId = textValue(socialApi.whatsappPhoneNumberId);
  const tokenReady = textValue(socialApi.whatsappAccessToken).length > 0;
  if (!phoneNumberId || !tokenReady) return channelResult("skipped_missing_credentials");

  const caption = captionForChannel(outbox, "whatsapp");
  const productUrl = textValue(outbox.productUrl);
  const messageBody = `${caption}\n\nOrder now: ${productUrl}`.trim();
  const campaignId = textValue(queueId, textValue(outbox.productId));

  let lastDoc = null;
  let eligibleCount = 0;
  let queuedCount = 0;
  let skippedInvalidNumber = 0;
  const pageSize = 300;

  do {
    let query = db.collection("users")
      .where("whatsappOptIn", "==", true)
      .where("isActive", "==", true)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) break;
    eligibleCount += snap.size;

    let batch = db.batch();
    let writes = 0;
    for (const userDoc of snap.docs) {
      const user = userDoc.data() || {};
      if (user.isBanned === true || user.isDeleted === true) continue;
      const to = normalizeBangladeshWhatsAppNumber(user.whatsappNumber || user.phone);
      if (!to) { skippedInvalidNumber++; continue; }

      const deliveryId = whatsappDeliveryId(campaignId, userDoc.id);
      const ref = db.collection("whatsapp_deliveries").doc(deliveryId);
      batch.set(ref, {
        deliveryId,
        queueId: campaignId,
        productId: outbox.productId || campaignId,
        userId: userDoc.id,
        to,
        phoneNumberId,
        messageBody,
        status: "pending",
        attemptCount: 0,
        maxAttempts: 4,
        nextAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: false });
      writes++;
      queuedCount++;

      if (writes >= 400) {
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  } while (true);

  return channelResult("queued", {
    eligibleCount,
    queuedCount,
    skippedInvalidNumber,
    recipientSource: "users.whatsappOptIn",
  });
}

async function sendWhatsAppDelivery(deliveryRef, delivery) {
  const freshUser = await db.collection("users").doc(textValue(delivery.userId)).get();
  const user = freshUser.data() || {};
  if (!freshUser.exists || user.whatsappOptIn !== true || user.isActive === false || user.isBanned === true || user.isDeleted === true) {
    await deliveryRef.set({ status: "cancelled_opted_out", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  const settings = await loadMarketingSettings(true);
  const socialApi = mapValue(settings.socialApi);
  const token = textValue(socialApi.whatsappAccessToken);
  const phoneNumberId = textValue(socialApi.whatsappPhoneNumberId || delivery.phoneNumberId);
  if (!token || !phoneNumberId) throw new Error("WhatsApp credentials are not configured");

  const data = await metaGraphPost(settings, `${phoneNumberId}/messages`, {
    messaging_product: "whatsapp",
    to: textValue(delivery.to),
    type: "text",
    text: { preview_url: true, body: textValue(delivery.messageBody) },
  }, token);

  await deliveryRef.set({
    status: "sent",
    messageId: textValue(data.messages?.[0]?.id),
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastError: "",
  }, { merge: true });
}

async function processWhatsAppDeliveryRef(deliveryRef, delivery) {
  const attempts = toNumber(delivery.attemptCount || 0);
  try {
    await deliveryRef.set({
      status: "processing",
      attemptCount: admin.firestore.FieldValue.increment(1),
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await sendWhatsAppDelivery(deliveryRef, delivery);
  } catch (error) {
    const maxAttempts = toNumber(delivery.maxAttempts || 4) || 4;
    const finalFailure = attempts + 1 >= maxAttempts;
    await deliveryRef.set({
      status: finalFailure ? "failed_final" : "failed",
      lastError: error.message || String(error),
      nextAttemptAt: finalFailure ? null : admin.firestore.Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  }
}

async function postWhatsAppCloud(settings, outbox, queueId = "") {
  return enqueueDynamicWhatsAppDeliveries(settings, queueId || outbox.productId, outbox);
}

async function postMessengerPage(settings, outbox) {
  const socialApi = mapValue(settings.socialApi);
  const pageId = textValue(socialApi.facebookPageId || "me");
  const token = textValue(socialApi.messengerPageAccessToken || socialApi.facebookPageAccessToken);
  if (!token) return channelResult("skipped_missing_credentials");

  const recipients = normalizeRecipientList(
    socialApi.messengerRecipientPsids ||
    socialApi.messengerTestPsid ||
    socialApi.messengerRecipients
  );
  if (recipients.length === 0) return channelResult("skipped_missing_recipients");

  const messageText = `${captionForChannel(outbox, "messenger")}\n${textValue(outbox.productUrl)}`.trim();
  const results = [];

  for (const psid of recipients.slice(0, 50)) {
    const data = await metaGraphPost(settings, `${pageId}/messages`, {
      recipient: { id: psid },
      messaging_type: "UPDATE",
      message: { text: messageText },
    }, token);
    results.push({ psid, messageId: textValue(data.message_id), response: data });
  }

  return channelResult("posted", { sentCount: results.length, results });
}

async function dispatchMetaSocialChannels(settings, queueId, outbox) {
  const channels = mapValue(outbox.channels);
  const results = {};
  const errors = [];

  const run = async (channel, handler) => {
    if (channels[channel] !== true) return;
    try {
      results[channel] = await handler(settings, outbox);
    } catch (error) {
      results[channel] = channelResult("failed", {
        message: error.message || String(error),
        metaError: error.api || null,
      });
      errors.push(`${channel}: ${error.message || String(error)}`);
    }
  };

  await run("facebook", postFacebookPage);
  await run("instagram", postInstagramBusiness);
  await run("whatsapp", (currentSettings, currentOutbox) => postWhatsAppCloud(currentSettings, currentOutbox, queueId));
  await run("messenger", postMessengerPage);

  // postTikTokContent() only ever creates a tiktok_publish_jobs record with
  // status "pending_creator_review" (or "blocked_pending_audit") — it never
  // calls any TikTok publish endpoint. The actual publish call happens only
  // from tiktokConfirmPublish, gated behind an admin's manual tap on the
  // review screen (functions/tiktok/publish.js). Activating this hook is
  // therefore safe: it prepares work for a human, it does not publish.
  await run("tiktok", postTikTokContent);

  const resultValues = Object.values(results);
  const postedCount = resultValues.filter((r) => ["posted", "queued"].includes(r.status)).length;
  const failedCount = resultValues.filter((r) => r.status === "failed").length;
  const skippedCount = resultValues.filter((r) => String(r.status || "").startsWith("skipped")).length;

  return {
    results,
    postedCount,
    failedCount,
    skippedCount,
    errors,
    status: failedCount > 0 && postedCount === 0 ? "failed" : "completed",
    socialStatus: failedCount > 0 ? "partial_failed" : (postedCount > 0 ? "posted" : "skipped"),
  };
}

async function processMarketingQueueItem(queueId, outbox) {
  const settings = await loadMarketingSettings(true);
  const channels = mapValue(outbox.channels);
  const status = textValue(outbox.status);

  if (status === "scheduled") {
    const scheduledAt = outbox.scheduledAt;
    if (scheduledAt && typeof scheduledAt.toMillis === "function" && scheduledAt.toMillis() > Date.now()) {
      return;
    }
  }

  if (!settings.enabled) {
    await db.collection("marketing_outbox").doc(queueId).set({
      status: "skipped",
      socialStatus: "marketing_disabled",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return;
  }

  if (!hasRequestedSocialChannel(channels)) {
    await db.collection("marketing_outbox").doc(queueId).set({
      status: "completed",
      notificationStatus: channels.fcm === true || channels.inApp === true ? "sent_or_ready" : "not_requested",
      socialStatus: "not_requested",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await writeCampaignAnalytics(queueId, outbox, {
      socialStatus: "not_requested",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  if (!hasReadyRequestedSocialApi(channels, settings.apiReady)) {
    await db.collection("marketing_outbox").doc(queueId).set({
      status: "waiting_for_credentials",
      socialStatus: "waiting_for_credentials",
      apiReady: settings.apiReady,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await db.collection("marketing_logs").add({
      type: "social_dispatch_skipped",
      productId: outbox.productId || queueId,
      productName: outbox.productName || "",
      status: "waiting_for_credentials",
      apiReady: settings.apiReady,
      channels,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeCampaignAnalytics(queueId, outbox, {
      socialStatus: "waiting_for_credentials",
      apiReady: settings.apiReady,
    });
    return;
  }

  await db.collection("marketing_outbox").doc(queueId).set({
    status: "processing",
    socialStatus: "dispatching",
    apiReady: settings.apiReady,
    lastDispatchStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  const dispatch = await dispatchMetaSocialChannels(settings, queueId, outbox);

  const retryPatch = dispatch.failedCount > 0
    ? {
        retryCount: admin.firestore.FieldValue.increment(1),
        nextRetryAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
        lastError: dispatch.errors.join(" | "),
      }
    : {
        lastError: "",
        nextRetryAt: null,
      };

  await db.collection("marketing_outbox").doc(queueId).set({
    status: dispatch.status,
    socialStatus: dispatch.socialStatus,
    channelResults: dispatch.results,
    postedCount: dispatch.postedCount,
    failedCount: dispatch.failedCount,
    skippedCount: dispatch.skippedCount,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...retryPatch,
  }, { merge: true });

  await db.collection("marketing_logs").add({
    type: "social_dispatch_completed",
    queueId,
    productId: outbox.productId || queueId,
    productName: outbox.productName || "",
    status: dispatch.status,
    socialStatus: dispatch.socialStatus,
    postedCount: dispatch.postedCount,
    failedCount: dispatch.failedCount,
    skippedCount: dispatch.skippedCount,
    errors: dispatch.errors,
    channels,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await writeCampaignAnalytics(queueId, outbox, {
    status: dispatch.status,
    socialStatus: dispatch.socialStatus,
    channelResults: dispatch.results,
    postedCount: dispatch.postedCount,
    failedCount: dispatch.failedCount,
    skippedCount: dispatch.skippedCount,
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}



setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

function toNumber(value) {
  if (value === null || value === undefined) return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function getTokensFromUser(data) {
  const tokens = [];
  if (data?.fcmToken) tokens.push(data.fcmToken);
  if (Array.isArray(data?.fcmTokens)) tokens.push(...data.fcmTokens);
  return [...new Set(tokens.filter(Boolean))];
}

async function sendToTokens(tokens, title, body, data = {}) {
  const cleanTokens = [...new Set(tokens.filter(Boolean))];
  if (cleanTokens.length === 0) return;

  await admin.messaging().sendEachForMulticast({
    tokens: cleanTokens,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, String(v ?? "")])
    ),
  });
}

async function notifyAdmins(title, body, data = {}) {
  const snap = await db.collection("users")
    .where("role", "in", ["admin", "superAdmin"])
    .get();

  const tokens = [];
  snap.forEach((doc) => tokens.push(...getTokensFromUser(doc.data())));

  await sendToTokens(tokens, title, body, data);
}

async function notifyUser(userId, title, body, data = {}) {
  if (!userId) return;

  const doc = await db.collection("users").doc(userId).get();
  if (!doc.exists) return;

  await sendToTokens(
    getTokensFromUser(doc.data()),
    title,
    body,
    data
  );

  await db.collection("notifications").add({
    userId,
    role: "customer",
    title,
    body,
    data,
    isRead: false,
    pushSent: true,
    pushedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function notifyRider(riderId, title, body, data = {}) {
  if (!riderId) return;

  const doc = await db.collection("users").doc(riderId).get();
  if (!doc.exists) return;

  await sendToTokens(
    getTokensFromUser(doc.data()),
    title,
    body,
    data
  );

  await db.collection("notifications").add({
    userId: riderId,
    role: "delivery_partner",
    title,
    body,
    data,
    isRead: false,
    pushSent: true,
    pushedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function notifyVendors(vendorIds, title, body, data = {}) {
  if (!Array.isArray(vendorIds) || vendorIds.length === 0) return;

  const tokens = [];

  for (const vendorId of [...new Set(vendorIds.filter(Boolean))]) {
    const userDoc = await db.collection("users").doc(vendorId).get();
    if (userDoc.exists) tokens.push(...getTokensFromUser(userDoc.data()));

    const vendorDoc = await db.collection("vendors").doc(vendorId).get();
    if (vendorDoc.exists) tokens.push(...getTokensFromUser(vendorDoc.data()));
  }

  await sendToTokens(tokens, title, body, data);
}


function firstImageFromProduct(product) {
  if (Array.isArray(product?.images)) {
    for (const image of product.images) {
      const url = String(image || "").trim();
      if (url.startsWith("http")) return url;
    }
  }

  const image = String(product?.imageUrl || product?.image || "").trim();
  return image.startsWith("http") ? image : "";
}

function firstPriceFromProduct(product) {
  const direct = toNumber(product?.price || product?.piecePrice || 0);
  if (direct > 0) return direct;

  if (Array.isArray(product?.variants) && product.variants.length > 0) {
    return toNumber(product.variants[0]?.price || product.variants[0]?.piecePrice || 0);
  }

  return 0;
}

function cleanPushText(value, max = 130) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  if (text.length <= max) return text;
  return `${text.slice(0, Math.max(0, max - 3)).trim()}...`;
}

function shouldMarketProduct(product) {
  const approvalStatus = String(product?.approvalStatus || "approved").trim().toLowerCase();
  return product?.autoMarketingDisabled !== true
    && product?.isActive !== false
    && product?.isVisible !== false
    && product?.isPublished !== false
    && approvalStatus === "approved";
}

function productMarketingPayload(productId, product) {
  const name = cleanPushText(product?.name || product?.title || "New Product", 80);
  const price = firstPriceFromProduct(product);
  const category = cleanPushText(product?.category || "", 50);
  const imageUrl = firstImageFromProduct(product);
  const productUrl = `https://chalakcharmart.com/product/${encodeURIComponent(productId)}`;

  const title = cleanPushText(
    product?.banglaTitle || product?.metaTitle || name,
    70
  );

  const bodySource = product?.whatsappCaption
    || product?.facebookCaption
    || product?.banglaDescription
    || product?.metaDescription
    || product?.overview
    || product?.description
    || (price > 0 ? `New product added. Price: ৳${price.toFixed(0)}` : "New product added on ChalakChar Mart.");

  return {
    name,
    title: `নতুন পণ্য এসেছে 🛒`,
    body: cleanPushText(bodySource, 130),
    category,
    imageUrl,
    productUrl,
    price: price > 0 ? price.toFixed(0) : "",
    metaTitle: cleanPushText(product?.metaTitle || title, 70),
    metaDescription: cleanPushText(product?.metaDescription || bodySource, 155),
    facebookCaption: cleanPushText(product?.facebookCaption || bodySource, 500),
    whatsappCaption: cleanPushText(product?.whatsappCaption || bodySource, 500),
  };
}

function marketingQueueChannels(settings, existingChannels = {}) {
  const defaults = mapValue(settings?.channels);
  const existing = mapValue(existingChannels);

  const pick = (key, fallback) => {
    if (typeof existing[key] === "boolean") return existing[key];
    if (typeof defaults[key] === "boolean") return defaults[key];
    return fallback;
  };

  const fcm = pick("fcm", true);
  const push = pick("push", fcm);

  return {
    fcm,
    push,
    inApp: pick("inApp", true),
    facebook: pick("facebook", false),
    instagram: pick("instagram", false),
    whatsapp: pick("whatsapp", false),
    messenger: pick("messenger", false),
    tiktok: pick("tiktok", false),
  };
}

function initialMarketingQueueStatus(channels, settings) {
  if (!hasRequestedSocialChannel(channels)) return "fcm_inapp_ready";
  return hasReadyRequestedSocialApi(channels, settings.apiReady)
    ? "pending"
    : "pending_social_api_credentials";
}

function shouldPreserveMarketingStatus(status) {
  return [
    "processing",
    "completed",
    "failed_final",
    "cancelled",
  ].includes(textValue(status));
}

function marketingQueueNote(channels, settings) {
  if (!hasRequestedSocialChannel(channels)) {
    return "Push/In-App marketing queue created from Cloud Functions.";
  }

  if (hasReadyRequestedSocialApi(channels, settings.apiReady)) {
    return "Queued for Social Dispatcher from Cloud Functions.";
  }

  return "Social channel requested, but required API credentials are not ready yet.";
}

async function writeProductMarketingOutbox(queueId, productId, payload, options = {}) {
  const settings = await loadMarketingSettings(true);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const outboxRef = db.collection("marketing_outbox").doc(queueId);
  const existingSnap = await outboxRef.get();
  const existingData = existingSnap.exists ? (existingSnap.data() || {}) : {};
  const channels = marketingQueueChannels(settings, existingData.channels);
  const status = shouldPreserveMarketingStatus(existingData.status)
    ? textValue(existingData.status)
    : initialMarketingQueueStatus(channels, settings);

  await outboxRef.set({
    productId,
    productName: payload.name,
    category: payload.category,
    imageUrl: payload.imageUrl,
    productUrl: payload.productUrl,
    price: payload.price,
    reason: options.reason || existingData.reason || "new_product",
    audience: settings.audience,
    publishMode: settings.publishTime,
    channels,
    captions: {
      facebook: payload.facebookCaption,
      instagram: payload.facebookCaption,
      whatsapp: payload.whatsappCaption,
      messenger: payload.whatsappCaption || payload.facebookCaption,
      tiktok: payload.facebookCaption,
      metaTitle: payload.metaTitle,
      metaDescription: payload.metaDescription,
    },
    status,
    apiReady: settings.apiReady,
    apiStatus: settings.apiReady,
    source: options.source || "cloud_function",
    retryCount: toNumber(existingData.retryCount || 0),
    maxRetries: toNumber(existingData.maxRetries || 3) || 3,
    note: marketingQueueNote(channels, settings),
    ...(!existingSnap.exists ? { createdAt: now } : {}),
    updatedAt: now,
  }, { merge: true });

  return { queueId, existed: existingSnap.exists, channels, status, apiReady: settings.apiReady };
}

async function createProductMarketingOutbox(productId, product, payload) {
  return writeProductMarketingOutbox(productId, productId, payload, {
    reason: "new_product",
    source: "cloud_function_product_created",
  });
}

async function notifyCustomersAboutNewProduct(productId, product) {
  const payload = productMarketingPayload(productId, product);
  const data = {
    type: "new_product",
    productId,
    productName: payload.name,
    productUrl: payload.productUrl,
    imageUrl: payload.imageUrl,
    category: payload.category,
    price: payload.price,
  };

  const userSnap = await db.collection("users")
    .where("role", "in", ["user", "customer"])
    .limit(1000)
    .get();

  const tokens = [];
  const notificationBatches = [];
  let batch = db.batch();
  let writes = 0;
  let userCount = 0;

  userSnap.forEach((doc) => {
    const user = doc.data() || {};
    if (user.isActive === false || user.isBanned === true) return;

    userCount += 1;
    tokens.push(...getTokensFromUser(user));

    const notificationRef = db.collection("notifications").doc();
    batch.set(notificationRef, {
      userId: doc.id,
      role: "customer",
      title: payload.title,
      body: payload.body,
      type: "new_product",
      data,
      isRead: false,
      pushSent: true,
      pushedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    writes += 1;
    if (writes >= 450) {
      notificationBatches.push(batch);
      batch = db.batch();
      writes = 0;
    }
  });

  if (writes > 0) notificationBatches.push(batch);

  const cleanTokens = [...new Set(tokens.filter(Boolean))];

  for (let i = 0; i < cleanTokens.length; i += 500) {
    await sendToTokens(cleanTokens.slice(i, i + 500), payload.title, payload.body, data);
  }

  for (const b of notificationBatches) {
    await b.commit();
  }

  await createProductMarketingOutbox(productId, product, payload);

  await db.collection("marketing_logs").add({
    type: "new_product",
    productId,
    productName: payload.name,
    userCount,
    tokenCount: cleanTokens.length,
    notificationCount: userCount,
    status: "completed",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info("New product marketing automation completed", {
    productId,
    userCount,
    tokenCount: cleanTokens.length,
  });
}



function stockFromProduct(product) {
  const direct = toNumber(product?.stock || 0);
  if (direct > 0) return direct;

  if (Array.isArray(product?.variants)) {
    return product.variants.reduce((sum, variant) => {
      return sum + toNumber(variant?.stock || 0);
    }, 0);
  }

  return direct;
}

function mrpFromProduct(product) {
  const direct = toNumber(product?.oldPrice || product?.mrp || 0);
  if (direct > 0) return direct;

  if (Array.isArray(product?.variants) && product.variants.length > 0) {
    return toNumber(product.variants[0]?.mrp || product.variants[0]?.oldPrice || 0);
  }

  return 0;
}

function discountPercentFromProduct(product) {
  const price = firstPriceFromProduct(product);
  const mrp = mrpFromProduct(product);
  if (price <= 0 || mrp <= price) return 0;
  return Math.round(((mrp - price) / mrp) * 100);
}

async function bumpProductMarketingScore(productId, reason, points, extra = {}) {
  if (!productId || points === 0) return;

  const ref = db.collection("product_marketing_scores").doc(String(productId));
  await ref.set({
    productId: String(productId),
    score: admin.firestore.FieldValue.increment(points),
    [`signals.${reason}`]: admin.firestore.FieldValue.increment(points),
    lastReason: reason,
    lastExtra: extra,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function addProductMarketingLog(type, productId, payload = {}) {
  await db.collection("marketing_logs").add({
    type,
    productId: productId || "",
    ...payload,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendNotificationDocumentsToUsers(userIds, title, body, type, data = {}) {
  const cleanUserIds = [...new Set((userIds || []).filter(Boolean))];
  if (cleanUserIds.length === 0) return { userCount: 0, tokenCount: 0 };

  const tokens = [];
  const batches = [];
  let batch = db.batch();
  let writes = 0;

  for (const userId of cleanUserIds) {
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) continue;

    const user = userDoc.data() || {};
    if (user.isActive === false || user.isBanned === true) continue;

    tokens.push(...getTokensFromUser(user));

    batch.set(db.collection("notifications").doc(), {
      userId,
      role: "customer",
      title,
      body,
      type,
      data,
      isRead: false,
      pushSent: true,
      pushedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    writes += 1;
    if (writes >= 450) {
      batches.push(batch);
      batch = db.batch();
      writes = 0;
    }
  }

  if (writes > 0) batches.push(batch);

  const cleanTokens = [...new Set(tokens.filter(Boolean))];
  for (let i = 0; i < cleanTokens.length; i += 500) {
    await sendToTokens(cleanTokens.slice(i, i + 500), title, body, data);
  }

  for (const b of batches) await b.commit();

  return { userCount: cleanUserIds.length, tokenCount: cleanTokens.length };
}

async function notifyWishlistUsers(productId, product, reason, title, body, extraData = {}) {
  const wishlistSnap = await db.collectionGroup("wishlist")
    .where("productId", "==", productId)
    .limit(1000)
    .get();

  const userIds = [];
  wishlistSnap.forEach((doc) => {
    const parent = doc.ref.parent.parent;
    if (parent?.id) userIds.push(parent.id);
  });

  if (userIds.length === 0) {
    await addProductMarketingLog(reason, productId, {
      status: "skipped_no_wishlist_users",
    });
    return;
  }

  const payload = productMarketingPayload(productId, product);
  const data = {
    type: reason,
    productId,
    productName: payload.name,
    productUrl: payload.productUrl,
    imageUrl: payload.imageUrl,
    category: payload.category,
    price: payload.price,
    ...extraData,
  };

  const result = await sendNotificationDocumentsToUsers(
    userIds,
    title,
    cleanPushText(body, 130),
    reason,
    data
  );

  await writeProductMarketingOutbox(`${productId}_${reason}`, productId, payload, {
    reason,
    source: "cloud_function_product_update",
  });

  await addProductMarketingLog(reason, productId, {
    status: "completed",
    userCount: result.userCount,
    tokenCount: result.tokenCount,
  });
}

async function rebuildUserCategoryPreferenceFromOrder(orderData) {
  const userId = String(orderData?.userId || "").trim();
  const items = Array.isArray(orderData?.items) ? orderData.items : [];
  if (!userId || items.length === 0) return;

  const ref = db.collection("user_marketing_profiles").doc(userId);
  const updates = {
    userId,
    orderCount: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  for (const item of items) {
    const category = cleanPushText(item?.category || "Other", 50);
    if (!category) continue;
    updates[`categories.${category}`] = admin.firestore.FieldValue.increment(toNumber(item?.qty || 1));
  }

  await ref.set(updates, { merge: true });
}
async function reduceProductStockOnce(orderRef, orderData) {
  if (orderData.stockReduced === true) return;

  const items = Array.isArray(orderData.items) ? orderData.items : [];
  if (items.length === 0) return;

  const batch = db.batch();

  for (const item of items) {
    const productId = item.productId;
    const qty = Math.max(0, parseInt(item.qty ?? 0, 10));
    const selectedUnit = String(item.unit ?? "").toLowerCase();

    if (!productId || qty <= 0) continue;

    const productRef = db.collection("products").doc(String(productId));
    const productSnap = await productRef.get();
    if (!productSnap.exists) continue;

    const product = productSnap.data() || {};
    const variants = Array.isArray(product.variants) ? [...product.variants] : [];

    if (variants.length > 0) {
      let changed = false;

      for (let i = 0; i < variants.length; i++) {
        const v = { ...variants[i] };
        const variantName = String(v.name ?? "").toLowerCase();

        if (variantName === selectedUnit || !selectedUnit) {
          v.stock = Math.max(0, parseInt(v.stock ?? 0, 10) - qty);
          variants[i] = v;
          changed = true;
          break;
        }
      }

      if (changed) {
        const totalStock = variants.reduce((sum, v) => {
          return sum + Math.max(0, parseInt(v.stock ?? 0, 10));
        }, 0);

        batch.update(productRef, {
          variants,
          stock: totalStock,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } else {
      batch.update(productRef, {
        stock: admin.firestore.FieldValue.increment(-qty),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  batch.update(orderRef, {
    stockReduced: true,
    stockReducedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
}

async function createVendorCommissions(orderId, orderData) {
  const items = Array.isArray(orderData.items) ? orderData.items : [];
  if (items.length === 0) return;

  const commissionDefaultPercent = toNumber(orderData.commissionPercent || 10);
  const grouped = {};

  for (const item of items) {
    const vendorId = item.vendorId || orderData.vendorId;
    if (!vendorId) continue;

    const price = toNumber(item.price);
    const qty = toNumber(item.qty || 1);
    const lineTotal = price * qty;

    if (!grouped[vendorId]) grouped[vendorId] = 0;
    grouped[vendorId] += lineTotal;
  }

  const batch = db.batch();

  for (const [vendorId, grossAmount] of Object.entries(grouped)) {
    const commissionAmount = grossAmount * (commissionDefaultPercent / 100);
    const vendorNetAmount = grossAmount - commissionAmount;

    const ref = db.collection("vendor_earnings").doc(`${orderId}_${vendorId}`);

    batch.set(ref, {
      orderId,
      vendorId,
      grossAmount,
      commissionPercent: commissionDefaultPercent,
      commissionAmount,
      vendorNetAmount,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();
}

async function updateDailyAnalytics(orderData) {
  const now = new Date();
  const dayId = now.toISOString().slice(0, 10);
  const ref = db.collection("analytics_daily").doc(dayId);

  const total = toNumber(orderData.total || orderData.grandTotal || orderData.finalTotal);
  const items = Array.isArray(orderData.items) ? orderData.items : [];
  const itemCount = items.reduce((sum, item) => sum + toNumber(item.qty || 1), 0);

  await ref.set({
    date: dayId,
    orderCount: admin.firestore.FieldValue.increment(1),
    itemCount: admin.firestore.FieldValue.increment(itemCount),
    revenue: admin.firestore.FieldValue.increment(total),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.healthCheck = onRequest((req, res) => {
  cors(req, res, () => {
    res.status(200).json({
      ok: true,
      project: "chalakchar-mart",
      service: "cloud-functions",
      time: new Date().toISOString(),
    });
  });
});

exports.onNotificationCreated = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const notificationId = event.params.notificationId;
  const notification = event.data?.data() || {};

  if (notification.pushSent === true) {
    logger.info("Notification push skipped, already sent", { notificationId });
    return;
  }

  const userId = notification.userId;
  if (!userId) {
    logger.warn("Notification push skipped, missing userId", { notificationId });
    return;
  }

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    logger.warn("Notification push skipped, user not found", { notificationId, userId });
    return;
  }

  const tokens = getTokensFromUser(userDoc.data());

  await sendToTokens(
    tokens,
    notification.title || "ChalakChar Mart",
    notification.body || "You have a new notification",
    {
      type: notification.type || "notification",
      notificationId,
      userId,
    }
  );

  await event.data.ref.set({
    pushSent: true,
    pushedAt: admin.firestore.FieldValue.serverTimestamp(),
    pushTokenCount: tokens.length,
  }, { merge: true });

  logger.info("Notification push sent", {
    notificationId,
    userId,
    tokenCount: tokens.length,
  });
});

exports.onNewOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const orderId = event.params.orderId;
  const order = event.data?.data() || {};

  const userName = order.userName || "Customer";
  const total = toNumber(order.total || order.grandTotal || order.finalTotal);

  await notifyAdmins(
    "New Order Received 🛒",
    `${userName} placed an order. Total: ৳${total.toFixed(0)}`,
    { type: "admin_order", orderId }
  );

  const vendorIds = Array.isArray(order.vendorIds) ? order.vendorIds : [];

  await notifyVendors(
    vendorIds,
    "New Vendor Order 🏪",
    `You have a new order #${orderId.substring(0, 8)}`,
    { type: "vendor_order", orderId }
  );

  await updateDailyAnalytics(order);
  await rebuildUserCategoryPreferenceFromOrder(order);

  for (const item of (Array.isArray(order.items) ? order.items : [])) {
    if (item?.productId) {
      await bumpProductMarketingScore(String(item.productId), "order", 20, { orderId });
    }
  }

  logger.info("New order automation completed", { orderId });
});

exports.onOrderStatusUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const orderId = event.params.orderId;
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};

  const oldStatus = before.status;
  const newStatus = after.status;

  if (oldStatus === newStatus) return;

  const orderRef = db.collection("orders").doc(orderId);

  if (
    (newStatus === "confirmed" || newStatus === "delivered") &&
    after.stockReduced !== true
  ) {
    await reduceProductStockOnce(orderRef, after);
  }

  if (newStatus === "confirmed") {
    await createVendorCommissions(orderId, after);
  }

  await notifyUser(
    after.userId,
    "Order Update",
    `Your order #${orderId.substring(0, 8)} is now ${newStatus}`,
    {
      type: "order_status",
      orderId,
      status: newStatus,
    }
  );

  if (newStatus === "ready_for_pickup") {
    await notifyAdmins(
      "Rider Action Needed 🚚",
      `Order #${orderId.substring(0, 8)} is ready for delivery.`,
      {
        type: "rider_order",
        orderId,
      }
    );
  }

  if (newStatus === "assigned_to_rider" && after.deliveryPartnerId) {
    await notifyRider(
      after.deliveryPartnerId,
      "New Delivery Assigned 🚚",
      `Order #${orderId.substring(0, 8)} assigned to you.`,
      {
        type: "delivery_assigned",
        orderId,
      }
    );
  }

  if (newStatus === "picked_up") {
    await notifyUser(
      after.userId,
      "Order Picked Up 🚚",
      `Your order #${orderId.substring(0, 8)} is on the way.`,
      {
        type: "picked_up",
        orderId,
      }
    );
  }

  if (newStatus === "delivered") {
    await db.collection("delivery_logs").add({
      orderId,
      userId: after.userId || null,
      riderId: after.deliveryPartnerId || null,
      status: "delivered",
      paymentMethod: after.paymentMethod || "",
      total: toNumber(after.total || after.grandTotal || after.finalTotal),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await notifyUser(
      after.userId,
      "Order Delivered ✅",
      `Your order #${orderId.substring(0, 8)} has been delivered successfully.`,
      {
        type: "order_delivered",
        orderId,
      }
    );

    if (after.deliveryPartnerId) {
      await notifyRider(
        after.deliveryPartnerId,
        "Delivery Completed 💰",
        `Order #${orderId.substring(0, 8)} completed successfully.`,
        {
          type: "delivery_completed",
          orderId,
        }
      );
    }
  }

  logger.info("Order status automation completed", {
    orderId,
    oldStatus,
    newStatus,
  });
});


exports.onProductCreated = onDocumentCreated("products/{productId}", async (event) => {
  const productId = event.params.productId;
  const product = event.data?.data() || {};

  if (!shouldMarketProduct(product)) {
    logger.info("Product marketing skipped", {
      productId,
      isActive: product.isActive,
      isVisible: product.isVisible,
      isPublished: product.isPublished,
      approvalStatus: product.approvalStatus,
      autoMarketingDisabled: product.autoMarketingDisabled,
    });
    return;
  }

  try {
    await notifyCustomersAboutNewProduct(productId, product);
  } catch (error) {
    logger.error("New product marketing automation failed", {
      productId,
      message: error.message || String(error),
      error,
    });

    await db.collection("marketing_logs").add({
      type: "new_product",
      productId,
      status: "failed",
      message: error.message || String(error),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});



exports.onProductStockUpdated = onDocumentUpdated("products/{productId}", async (event) => {
  const productId = event.params.productId;
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};

  if (!shouldMarketProduct(after)) {
    logger.info("Product update marketing skipped", { productId });
    return;
  }

  const beforeStock = stockFromProduct(before);
  const afterStock = stockFromProduct(after);
  const alreadyAlerted = after.lowStockAlerted === true;

  if (afterStock > 0 && afterStock <= 5 && !alreadyAlerted) {
    await notifyAdmins(
      "Low Stock Alert ⚠️",
      `${after.name || "Product"} stock is low: ${afterStock}`,
      {
        type: "low_stock",
        productId,
      }
    );

    await db.collection("products").doc(productId).set({
      lowStockAlerted: true,
      lowStockAlertedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  if (afterStock > 5 && alreadyAlerted) {
    await db.collection("products").doc(productId).set({
      lowStockAlerted: false,
    }, { merge: true });
  }

  if (beforeStock <= 0 && afterStock > 0 && after.backInStockNotifiedAt == null) {
    await notifyWishlistUsers(
      productId,
      after,
      "back_in_stock",
      "Wishlist product back in stock 📦",
      `${after.name || "Your wishlist product"} is available again.`,
      { stock: afterStock }
    );

    await bumpProductMarketingScore(productId, "back_in_stock", 10, { stock: afterStock });

    await db.collection("products").doc(productId).set({
      backInStockNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  const beforeDiscount = discountPercentFromProduct(before);
  const afterDiscount = discountPercentFromProduct(after);

  if (afterDiscount >= 5 && afterDiscount > beforeDiscount) {
    const discountKey = `discount_${afterDiscount}`;

    if (after.lastDiscountMarketingKey !== discountKey) {
      await notifyWishlistUsers(
        productId,
        after,
        "wishlist_discount",
        "Wishlist product discount 🏷️",
        `${after.name || "Your wishlist product"} now has ${afterDiscount}% discount.`,
        { discountPercent: afterDiscount }
      );

      await bumpProductMarketingScore(productId, "discount", 15, { discountPercent: afterDiscount });

      await db.collection("products").doc(productId).set({
        lastDiscountMarketingKey: discountKey,
        lastDiscountMarketingAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }
});

exports.onWishlistItemCreated = onDocumentCreated("users/{userId}/wishlist/{productId}", async (event) => {
  const productId = String(event.params.productId || "").trim();
  const userId = String(event.params.userId || "").trim();
  const item = event.data?.data() || {};

  await bumpProductMarketingScore(productId, "wishlist", 5, { userId });

  const category = cleanPushText(item.category || "", 50);
  if (category) {
    await db.collection("user_marketing_profiles").doc(userId).set({
      userId,
      [`categories.${category}`]: admin.firestore.FieldValue.increment(2),
      lastWishlistProductId: productId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});

// Cart item trigger temporarily disabled because Eventarc trigger creation failed for
// cart/{userId}/items/{itemId} in this Firebase project during deployment.
// Phase-2 still works through wishlist, order, review, stock, and new-product triggers.
// Cart score can be re-enabled later after checking Firestore/Eventarc trigger support.

exports.onMarketingOutboxCreated = onDocumentCreated("marketing_outbox/{queueId}", async (event) => {
  const queueId = event.params.queueId;
  const data = event.data?.data() || {};
  const status = textValue(data.status);

  if (status === "scheduled") {
    logger.info("Marketing outbox scheduled; waiting for scheduler", { queueId });
    return;
  }

  try {
    await processMarketingQueueItem(queueId, data);
  } catch (error) {
    logger.error("Marketing outbox immediate dispatch failed", { queueId, error });
    await event.data.ref.set({
      status: "failed",
      socialStatus: "dispatch_error",
      lastError: error.message || String(error),
      retryCount: admin.firestore.FieldValue.increment(1),
      nextRetryAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});

exports.onWhatsAppDeliveryCreated = onDocumentCreated("whatsapp_deliveries/{deliveryId}", async (event) => {
  const delivery = event.data?.data() || {};
  try {
    await processWhatsAppDeliveryRef(event.data.ref, delivery);
  } catch (error) {
    logger.error("WhatsApp delivery failed", { deliveryId: event.params.deliveryId, message: error.message || String(error) });
  }
});

exports.processWhatsAppDeliveryRetries = onSchedule("every 15 minutes", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection("whatsapp_deliveries")
    .where("status", "in", ["pending", "failed"])
    .where("nextAttemptAt", "<=", now)
    .limit(100)
    .get();

  for (const doc of snap.docs) {
    try {
      await processWhatsAppDeliveryRef(doc.ref, doc.data() || {});
    } catch (error) {
      logger.error("Scheduled WhatsApp retry failed", { deliveryId: doc.id, message: error.message || String(error) });
    }
  }
});

exports.processMarketingQueueScheduled = onSchedule("every 15 minutes", async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db.collection("marketing_outbox")
    .where("status", "in", [
      "pending",
      "pending_social_api_credentials",
      "fcm_inapp_ready",
      "fcm_sent_social_api_not_connected",
      "failed",
      "retry_requested",
      "waiting_for_credentials",
      "scheduled"
    ])
    .limit(50)
    .get();

  if (snap.empty) {
    logger.info("No marketing queue retry items");
    return;
  }

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const retryCount = toNumber(data.retryCount || 0);

    if (retryCount >= 3) {
      await doc.ref.set({
        status: "failed_final",
        socialStatus: "max_retry_reached",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      continue;
    }

    if (data.nextRetryAt && data.nextRetryAt.toMillis && data.nextRetryAt.toMillis() > now.toMillis()) {
      continue;
    }

    try {
      await processMarketingQueueItem(doc.id, data);
    } catch (error) {
      await doc.ref.set({
        status: "failed",
        lastError: error.message || String(error),
        retryCount: admin.firestore.FieldValue.increment(1),
        nextRetryAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 15 * 60 * 1000)
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }
});


exports.expireCouponsDaily = onSchedule("every day 00:10", async () => {
  const now = admin.firestore.Timestamp.now();

  const snap = await db.collection("coupons")
    .where("isActive", "==", true)
    .where("expiry", "<=", now)
    .get();

  if (snap.empty) {
    logger.info("No expired coupons found");
    return;
  }

  const batch = db.batch();

  snap.forEach((doc) => {
    batch.update(doc.ref, {
      isActive: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();

  logger.info("Expired coupons disabled", {
    count: snap.size,
  });
});

exports.onProductReviewCreated = onDocumentCreated(
  "products/{productId}/reviews/{reviewId}",
  async (event) => {
    const productId = event.params.productId;
    if (!productId) return;

    const reviewsSnap = await db
      .collection("products")
      .doc(productId)
      .collection("reviews")
      .get();

    let totalRating = 0;
    let count = 0;

    reviewsSnap.forEach((doc) => {
      const rating = toNumber(doc.data().rating);
      if (rating > 0) {
        totalRating += rating;
        count++;
      }
    });

    const ratingAvg = count > 0 ? totalRating / count : 0;

    await db.collection("products").doc(productId).set({
      ratingAvg,
      ratingCount: count,
      reviewCount: count,
      ratingTotal: totalRating,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await bumpProductMarketingScore(productId, "review", 6, { ratingCount: count, ratingAvg });

    logger.info("Product rating updated", {
      productId,
      ratingAvg,
      ratingCount: count,
    });
  }
);

exports.onRiderLocationUpdated = onDocumentUpdated("rider_locations/{riderId}", async (event) => {
  const riderId = event.params.riderId;
  const after = event.data.after.data() || {};
  const orderId = after.activeOrderId;

  if (!orderId) return;

  await db.collection("orders").doc(orderId).set({
    riderId,
    riderLocation: {
      lat: after.lat || null,
      lng: after.lng || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
});

exports.rebuildProductRecommendationSignals = onSchedule("every 24 hours", async () => {
  const snap = await db.collection("orders")
    .where("status", "in", ["confirmed", "delivered"])
    .limit(500)
    .get();

  const productMap = {};

  snap.forEach((doc) => {
    const order = doc.data();
    const items = Array.isArray(order.items) ? order.items : [];

    for (const item of items) {
      const productId = item.productId;
      if (!productId) continue;

      if (!productMap[productId]) {
        productMap[productId] = {
          productId,
          orderCount: 0,
          qtySold: 0,
          score: 0,
        };
      }

      const qty = toNumber(item.qty || 1);

      productMap[productId].orderCount += 1;
      productMap[productId].qtySold += qty;
      productMap[productId].score += qty * 10;
    }
  });

  const batch = db.batch();

  for (const [productId, signal] of Object.entries(productMap)) {
    const ref = db.collection("recommendation_signals").doc(productId);

    batch.set(ref, {
      ...signal,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();

  logger.info("Recommendation signals rebuilt", {
    count: Object.keys(productMap).length,
  });
});

exports.aiOptimizeProduct = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 60,
    secrets: ["OPENAI_API_KEY"],
  },
  async (req, res) => {
    try {
      if (req.method === "OPTIONS") return res.status(204).send("");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const apiKey = (process.env.OPENAI_API_KEY || "").trim();
      if (!apiKey) {
        return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
      }

      const { title, description, category } = req.body || {};
      const cleanTitle = String(title || "").trim();
      const cleanDescription = String(description || "").trim();
      const cleanCategory = String(category || "").trim();
      const cat = cleanCategory.toLowerCase();

      if (!cleanTitle || cleanTitle.length < 2) {
        return res.status(400).json({ error: "Product title is required" });
      }

      let categoryPrompt = "";

      if (
        cat.includes("medicine") ||
        cat.includes("pharmacy") ||
        cat.includes("tablet") ||
        cat.includes("capsule") ||
        cat.includes("syrup")
      ) {
        categoryPrompt = `
Product type: Pharmacy / Medicine.
Write safe pharmacy ecommerce content.
Do not claim to cure disease.
Do not give dosage instructions.
Do not invent medical benefits.
Suggest a safe ecommerce category only.
`;
      } else if (
        cat.includes("grocery") ||
        cat.includes("vegetable") ||
        cat.includes("fruit") ||
        cat.includes("food") ||
        cat.includes("fish") ||
        cat.includes("meat") ||
        cat.includes("rice") ||
        cat.includes("oil")
      ) {
        categoryPrompt = `
Product type: Grocery / Food.
Focus on freshness, quality, cooking use, taste, and daily needs.
Avoid medical or exaggerated health claims.
Suggest category, subcategory, and product type from ecommerce grocery context.
`;
      } else if (
        cat.includes("electronics") ||
        cat.includes("mobile") ||
        cat.includes("computer") ||
        cat.includes("laptop") ||
        cat.includes("accessories")
      ) {
        categoryPrompt = `
Product type: Electronics.
Focus on features, usability, durability, and benefits.
Do not invent exact specs if not provided.
Suggest category, subcategory, and product type from ecommerce electronics context.
`;
      } else if (
        cat.includes("fashion") ||
        cat.includes("clothing") ||
        cat.includes("shirt") ||
        cat.includes("dress") ||
        cat.includes("shoe")
      ) {
        categoryPrompt = `
Product type: Fashion.
Focus on style, comfort, daily use, and appearance.
Do not invent fabric details if not provided.
Suggest category, subcategory, and product type from ecommerce fashion context.
`;
      } else {
        categoryPrompt = `
Product type: General ecommerce product.
Write clear, concise, SEO-friendly product content.
Avoid exaggerated claims.
Suggest the most likely ecommerce category, subcategory, and product type.
`;
      }

      const openai = new OpenAI({ apiKey });

      const prompt = `
Optimize this product for ChalakChar Mart.

${categoryPrompt}

Return ONLY valid JSON. No markdown. No extra text.

Required JSON format:
{
  "title": "SEO optimized English product title, maximum 70 characters",
  "banglaTitle": "Natural Bangla product title, maximum 70 characters",
  "description": "Short professional English description, 2 to 4 sentences",
  "banglaDescription": "Natural Bangla product description, 2 to 3 sentences",
  "seoTags": ["tag1", "tag2", "tag3"],
  "facebookCaption": "Short Facebook selling caption with emoji and CTA",
  "whatsappCaption": "Short WhatsApp selling message",
  "metaTitle": "SEO meta title, maximum 60 characters",
  "metaDescription": "SEO meta description, maximum 155 characters",
  "searchKeywords": ["keyword1", "keyword2", "keyword3"],
  "suggestedCategory": "Most likely main ecommerce category",
  "suggestedSubCategory": "Most likely ecommerce subcategory",
  "productType": "Specific product type"
}

Rules:
- Do not invent brand, weight, size, country, medical benefit, or technical specification.
- Keep title clean and marketplace-friendly.
- Bangla must be natural Bangla.
- SEO tags and search keywords must be lowercase English.
- Return 3 to 6 SEO tags.
- Return 5 to 10 search keywords.
- Facebook caption should be attractive but not fake.
- WhatsApp caption should be short and direct.
- suggestedCategory must be short, like Grocery, Vegetables, Fish, Meat, Electronics, Fashion, Pharmacy, Home, Beauty, or Other.
- suggestedSubCategory must be short and practical.
- productType must be specific but not invented beyond given product info.
- If the existing Category is provided, use it as a hint but still suggest the best category.

Product Title: ${cleanTitle}
Description: ${cleanDescription}
Current Category: ${cleanCategory}
`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.4,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content:
              "You are a careful ecommerce SEO product optimizer. Return only valid JSON. Do not invent unsupported product facts.",
          },
          { role: "user", content: prompt },
        ],
      });

      const text = completion.choices?.[0]?.message?.content || "{}";
      const parsed = JSON.parse(text);

      return res.status(200).json({
        title: String(parsed.title || cleanTitle).trim(),
        banglaTitle: String(parsed.banglaTitle || "").trim(),
        description: String(parsed.description || cleanDescription || "").trim(),
        banglaDescription: String(parsed.banglaDescription || "").trim(),

        seoTags: Array.isArray(parsed.seoTags)
          ? parsed.seoTags.map((t) => String(t).trim()).filter(Boolean).slice(0, 6)
          : [],

        facebookCaption: String(parsed.facebookCaption || "").trim(),
        whatsappCaption: String(parsed.whatsappCaption || "").trim(),
        metaTitle: String(parsed.metaTitle || "").trim(),
        metaDescription: String(parsed.metaDescription || "").trim(),

        searchKeywords: Array.isArray(parsed.searchKeywords)
          ? parsed.searchKeywords.map((t) => String(t).trim()).filter(Boolean).slice(0, 10)
          : [],

        suggestedCategory: String(parsed.suggestedCategory || "").trim(),
        suggestedSubCategory: String(parsed.suggestedSubCategory || "").trim(),
        productType: String(parsed.productType || "").trim(),
      });
    } catch (e) {
      console.error("AI OPTIMIZE ERROR:", e);

      let message = e.message || "AI optimization failed";

      if (e.status === 401 || e.code === "invalid_api_key") {
        message = "OpenAI API key is invalid. Please update OPENAI_API_KEY.";
      } else if (e.status === 429) {
        message = "OpenAI quota exceeded. Please check billing or usage limit.";
      }

      return res.status(e.status || 500).json({ error: message });
    }
  }
);


exports.aiGenerateProductImage = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: ["OPENAI_API_KEY"],
  },
  async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        return res.status(204).send("");
      }

      res.set("Access-Control-Allow-Origin", "*");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const apiKey = (process.env.OPENAI_API_KEY || "").trim();
      if (!apiKey) {
        return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
      }

      const { imageUrl, productName, style, customPrompt } = req.body || {};
      const cleanImageUrl = String(imageUrl || "").trim();
      const cleanProductName = String(productName || "").trim();
      const cleanStyle = String(style || "white_background").trim();
      const cleanCustomPrompt = String(customPrompt || "").trim();

      if (!cleanImageUrl || !cleanImageUrl.startsWith("http")) {
        return res.status(400).json({ error: "Valid imageUrl is required" });
      }

      const stylePrompts = {
        white_background:
          "Edit the reference product photo into a clean ecommerce product image on a pure white background. Preserve the exact product type, color, shape, design, and visible details from the reference image. Improve lighting, crop, and sharpness only. Do not change the product into another object.",
        studio:
          "Edit the reference product photo into a premium studio ecommerce image with soft lighting and clean shadow. Preserve the exact product type, color, shape, design, and visible details from the reference image. Do not change the product into another object.",
        lifestyle:
          "Edit the reference product photo into a realistic lifestyle ecommerce image. Keep the same product from the reference image as the hero product. Use a natural attractive setting, but do not change the product identity.",
        human_model:
          "Edit the reference product photo into a realistic ecommerce lifestyle image showing a generic AI-generated human model using or wearing the same product if appropriate. For shoes or sandals, show the same footwear on a person's feet. Avoid recognizable faces when not necessary. Do not recreate any real person. Do not change the product identity.",
        social_banner:
          "Edit the reference product photo into a clean social media promotional banner style image. Keep the same product as the hero product and leave clear empty space for text. Do not add fake offers, prices, or unsupported claims. Do not change the product identity.",
      };

      const selectedStylePrompt =
        stylePrompts[cleanStyle] || stylePrompts.white_background;

      const prompt = `
Use the uploaded image as the reference product image.

Product name hint: ${cleanProductName || "Unknown product"}

Task:
${cleanCustomPrompt || selectedStylePrompt}

Very important:
- The output must keep the same product shown in the reference image.
- Do not replace the product with a bottle, box, medicine, food, or any other unrelated object.
- Do not invent brand names, prices, weights, labels, or medical claims.
- Do not add text unless it is naturally visible on the original product packaging.
- Make the image suitable for an ecommerce admin product gallery.
- If the reference image shows shoes/sandals, the output must show the same shoes/sandals.
- If the reference image shows grocery/food/medicine/electronics/fashion, preserve that product category.
`;

      const imageResponse = await fetch(cleanImageUrl);
      if (!imageResponse.ok) {
        return res.status(400).json({
          error: `Could not download reference image: ${imageResponse.status}`,
        });
      }

      const imageArrayBuffer = await imageResponse.arrayBuffer();
      const imageBuffer = Buffer.from(imageArrayBuffer);

      if (!imageBuffer || imageBuffer.length === 0) {
        return res.status(400).json({
          error: "Reference image download returned empty data",
        });
      }

      const openai = new OpenAI({ apiKey });

      const result = await openai.images.edit({
        model: "gpt-image-1",
        image: await toFile(imageBuffer, "reference_product.png", {
          type: "image/png",
        }),
        prompt,
        size: "1024x1024",
        quality: "medium",
        n: 1,
      });

      const b64 = result.data?.[0]?.b64_json;
      if (!b64) {
        return res.status(500).json({
          error: "Image editing returned no image data",
        });
      }

      const buffer = Buffer.from(b64, "base64");
      const bucket = admin.storage().bucket();
      const token = crypto.randomUUID();
      const filePath = `products/ai_generated/${Date.now()}_${token}.png`;
      const file = bucket.file(filePath);

      await file.save(buffer, {
        metadata: {
          contentType: "image/png",
          metadata: {
            firebaseStorageDownloadTokens: token,
          },
        },
        resumable: false,
      });

      const imageUrlOut =
        `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(filePath)}?alt=media&token=${token}`;

      return res.status(200).json({
        imageUrl: imageUrlOut,
        style: cleanStyle,
        filePath,
      });
    } catch (e) {
      console.error("AI GENERATE PRODUCT IMAGE ERROR:", e);

      let message = e.message || "AI product image generation failed";

      if (e.status === 401 || e.code === "invalid_api_key") {
        message = "OpenAI API key is invalid. Please update OPENAI_API_KEY.";
      } else if (e.status === 429) {
        message = "OpenAI quota exceeded. Please check billing or usage limit.";
      }

      return res.status(e.status || 500).json({ error: message });
    }
  }
);

exports.aiProductFromImage = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 60,
    secrets: ["OPENAI_API_KEY"],
  },
  async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        return res.status(204).send("");
      }

      res.set("Access-Control-Allow-Origin", "*");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const apiKey = (process.env.OPENAI_API_KEY || "").trim();
      if (!apiKey) {
        return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
      }

      const { imageUrl, hintTitle, hintCategory } = req.body || {};
      const cleanImageUrl = String(imageUrl || "").trim();
      const cleanHintTitle = String(hintTitle || "").trim();
      const cleanHintCategory = String(hintCategory || "").trim();

      if (!cleanImageUrl || !cleanImageUrl.startsWith("http")) {
        return res.status(400).json({
          error: "Valid imageUrl is required",
        });
      }

      const openai = new OpenAI({ apiKey });

      const prompt = `
Analyze this product image for ChalakChar Mart and create an ecommerce product draft.

Return ONLY valid JSON. No markdown. No extra text.

Required JSON format:
{
  "title": "SEO optimized English product title, maximum 70 characters",
  "banglaTitle": "Natural Bangla product title, maximum 70 characters",
  "description": "Short professional English description, 2 to 4 sentences",
  "banglaDescription": "Natural Bangla product description, 2 to 3 sentences",
  "seoTags": ["tag1", "tag2", "tag3"],
  "facebookCaption": "Short Facebook selling caption with emoji and CTA",
  "whatsappCaption": "Short WhatsApp selling message",
  "metaTitle": "SEO meta title, maximum 60 characters",
  "metaDescription": "SEO meta description, maximum 155 characters",
  "searchKeywords": ["keyword1", "keyword2", "keyword3"],
  "suggestedCategory": "Most likely main ecommerce category",
  "suggestedSubCategory": "Most likely ecommerce subcategory",
  "productType": "Specific product type"
}

Rules:
- Identify only what is visible in the image.
- Do not invent brand, weight, size, country, medical benefit, price, or technical specification.
- If packaging label text is visible, you may use it.
- If product is uncertain, use a general safe name and category.
- Keep title clean and marketplace-friendly.
- Bangla must be natural Bangla.
- SEO tags and search keywords must be lowercase English.
- Return 3 to 6 SEO tags.
- Return 5 to 10 search keywords.
- suggestedCategory must be short, like Grocery, Vegetables, Fish, Meat, Electronics, Fashion, Pharmacy, Home, Beauty, or Other.
- suggestedSubCategory must be short and practical.
- productType must be specific but not invented beyond the visible image.
- Use hintTitle and hintCategory only as hints, not as guaranteed facts.

Hint Product Title: ${cleanHintTitle}
Hint Category: ${cleanHintCategory}
`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.3,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content:
              "You are a careful ecommerce product image analyzer. Return only valid JSON. Do not invent unsupported facts.",
          },
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              {
                type: "image_url",
                image_url: { url: cleanImageUrl },
              },
            ],
          },
        ],
      });

      const text = completion.choices?.[0]?.message?.content || "{}";
      const parsed = JSON.parse(text);

      return res.status(200).json({
        title: String(parsed.title || cleanHintTitle || "").trim(),
        banglaTitle: String(parsed.banglaTitle || "").trim(),
        description: String(parsed.description || "").trim(),
        banglaDescription: String(parsed.banglaDescription || "").trim(),

        seoTags: Array.isArray(parsed.seoTags)
          ? parsed.seoTags.map((t) => String(t).trim()).filter(Boolean).slice(0, 6)
          : [],

        facebookCaption: String(parsed.facebookCaption || "").trim(),
        whatsappCaption: String(parsed.whatsappCaption || "").trim(),
        metaTitle: String(parsed.metaTitle || "").trim(),
        metaDescription: String(parsed.metaDescription || "").trim(),

        searchKeywords: Array.isArray(parsed.searchKeywords)
          ? parsed.searchKeywords.map((t) => String(t).trim()).filter(Boolean).slice(0, 10)
          : [],

        suggestedCategory: String(parsed.suggestedCategory || "").trim(),
        suggestedSubCategory: String(parsed.suggestedSubCategory || "").trim(),
        productType: String(parsed.productType || "").trim(),
      });
    } catch (e) {
      console.error("AI IMAGE PRODUCT ERROR:", e);

      let message = e.message || "AI image product creation failed";

      if (e.status === 401 || e.code === "invalid_api_key") {
        message = "OpenAI API key is invalid. Please update OPENAI_API_KEY.";
      } else if (e.status === 429) {
        message = "OpenAI quota exceeded. Please check billing or usage limit.";
      }

      return res.status(e.status || 500).json({ error: message });
    }
  }
);


// -----------------------------------------------------------------------------
// Customer-facing AI: image product search + chat assistant
// -----------------------------------------------------------------------------

exports.imageProductSearch = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 60,
    secrets: ["OPENAI_API_KEY"],
  },
  async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        return res.status(204).send("");
      }

      res.set("Access-Control-Allow-Origin", "*");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const apiKey = (process.env.OPENAI_API_KEY || "").trim();
      if (!apiKey) {
        return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
      }

      const { imageBase64, mediaType } = req.body || {};
      const cleanBase64 = String(imageBase64 || "").trim();
      const cleanMediaType = String(mediaType || "image/jpeg").trim();

      if (!cleanBase64) {
        return res.status(400).json({ error: "imageBase64 is required" });
      }

      const openai = new OpenAI({ apiKey });

      const prompt = `
A customer uploaded this photo to search for a matching product on ChalakChar Mart, a Bangladeshi multi-vendor ecommerce store (pharmacy, grocery, beverages, cooking items, LPG cylinders, electronics, fashion, and more).

Identify the product shown in the photo for search matching purposes.

Return ONLY valid JSON. No markdown. No extra text.

Required JSON format:
{
  "productName": "Most likely product name",
  "brand": "Brand name if visible or known, otherwise empty string",
  "category": "Most likely ecommerce category, like Grocery, Vegetables, Fish, Meat, Electronics, Fashion, Pharmacy, Home, Beauty, Beverages, or Other",
  "keywords": ["keyword1", "keyword2", "keyword3"],
  "color": "Main color of the product",
  "description": "One line description of what is shown"
}

Rules:
- Identify only what is visible in the image, do not invent brand, price, or specifications.
- If packaging label text is visible, use it.
- If the product is uncertain, use a general safe name and category.
- keywords must be lowercase English, 3 to 8 items, useful for text search matching (name, brand, category, type).
`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content:
              "You are a careful ecommerce visual product search assistant. Return only valid JSON. Do not invent unsupported facts.",
          },
          {
            role: "user",
            content: [
              { type: "text", text: prompt },
              {
                type: "image_url",
                image_url: { url: `data:${cleanMediaType};base64,${cleanBase64}` },
              },
            ],
          },
        ],
      });

      const text = completion.choices?.[0]?.message?.content || "{}";
      const parsed = JSON.parse(text);

      return res.status(200).json({
        productName: String(parsed.productName || "").trim(),
        brand: String(parsed.brand || "").trim(),
        category: String(parsed.category || "").trim(),
        keywords: Array.isArray(parsed.keywords)
          ? parsed.keywords.map((k) => String(k).trim()).filter(Boolean).slice(0, 8)
          : [],
        color: String(parsed.color || "").trim(),
        description: String(parsed.description || "").trim(),
      });
    } catch (e) {
      console.error("IMAGE PRODUCT SEARCH ERROR:", e);

      let message = e.message || "Image product search failed";

      if (e.status === 401 || e.code === "invalid_api_key") {
        message = "OpenAI API key is invalid. Please update OPENAI_API_KEY.";
      } else if (e.status === 429) {
        message = "OpenAI quota exceeded. Please check billing or usage limit.";
      }

      return res.status(e.status || 500).json({ error: message });
    }
  }
);

exports.chatWithAssistant = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 60,
    secrets: ["OPENAI_API_KEY"],
  },
  async (req, res) => {
    try {
      if (req.method === "OPTIONS") {
        res.set("Access-Control-Allow-Origin", "*");
        res.set("Access-Control-Allow-Methods", "POST");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        return res.status(204).send("");
      }

      res.set("Access-Control-Allow-Origin", "*");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const apiKey = (process.env.OPENAI_API_KEY || "").trim();
      if (!apiKey) {
        return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
      }

      const { message, history } = req.body || {};
      const cleanMessage = String(message || "").trim();

      if (!cleanMessage) {
        return res.status(400).json({ error: "message is required" });
      }

      const cleanHistory = Array.isArray(history)
        ? history
          .filter((m) => m && (m.role === "user" || m.role === "assistant") && String(m.content || "").trim())
          .slice(-20)
          .map((m) => ({ role: m.role, content: String(m.content).trim().slice(0, 2000) }))
        : [];

      const systemPrompt = `You are the helpful customer support assistant for ChalakChar Mart, a Bangladeshi multi-vendor ecommerce platform focused on pharmacy and healthcare products, alongside grocery, beverages, cooking items, LPG cylinders, and more.
Answer customer questions briefly and in a friendly tone, in Bangla unless the customer writes in English.
You do not have live access to exact stock or prices, so for those questions tell the customer to check the product page or search results, and never invent a price, stock count, or delivery date.
Do not give medical dosage advice or diagnose medical conditions; for medicine questions, suggest they consult a pharmacist or doctor.`;

      const openai = new OpenAI({ apiKey });

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.5,
        max_tokens: 500,
        messages: [
          { role: "system", content: systemPrompt },
          ...cleanHistory,
          { role: "user", content: cleanMessage.slice(0, 2000) },
        ],
      });

      const reply = completion.choices?.[0]?.message?.content || "";

      return res.status(200).json({ reply: reply.trim() });
    } catch (e) {
      console.error("CHAT WITH ASSISTANT ERROR:", e);

      let message = e.message || "Chat assistant failed";

      if (e.status === 401 || e.code === "invalid_api_key") {
        message = "OpenAI API key is invalid. Please update OPENAI_API_KEY.";
      } else if (e.status === 429) {
        message = "OpenAI quota exceeded. Please check billing or usage limit.";
      }

      return res.status(e.status || 500).json({ error: message });
    }
  }
);


// -----------------------------------------------------------------------------
// Server-side Product SEO HTML for ChalakChar Mart
// -----------------------------------------------------------------------------
// Firebase Hosting rewrite:
//   /product/** -> productSeo
//
// This returns an HTML document with dynamic product meta tags before Flutter
// bootstraps. It is required for Google/Facebook/WhatsApp crawlers that read
// the initial HTML response.
// -----------------------------------------------------------------------------

function htmlEscape(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function jsonLdEscapeObject(obj) {
  return JSON.stringify(obj)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026");
}

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text.length ? text : fallback;
}

function compactWhitespace(value) {
  return cleanText(value).replace(/\s+/g, " ").trim();
}

function limitText(value, max) {
  const text = compactWhitespace(value);
  if (text.length <= max) return text;
  return `${text.slice(0, Math.max(0, max - 3)).trim()}...`;
}

function firstProductImage(product) {
  if (Array.isArray(product.images)) {
    for (const image of product.images) {
      const url = cleanText(image);
      if (url.startsWith("http")) return url;
    }
  }

  const imageUrl = cleanText(product.imageUrl || product.image);
  if (imageUrl.startsWith("http")) return imageUrl;

  return "https://chalakcharmart.com/icons/Icon-512.png";
}


function youtubeVideoIdFromProduct(product) {
  const raw = cleanText(
    product.videoUrl ||
    product.youtubeUrl ||
    product.youtubeLink ||
    product.videoLink ||
    product.youtubeVideoId ||
    ""
  );

  if (!raw) return "";
  if (/^[a-zA-Z0-9_-]{11}$/.test(raw)) return raw;

  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    const parts = url.pathname.split("/").filter(Boolean);

    if (host.includes("youtu.be")) {
      return parts[0] || "";
    }

    if (host.includes("youtube.com") || host.includes("youtube-nocookie.com")) {
      const v = url.searchParams.get("v");
      if (v) return v;

      for (const marker of ["embed", "shorts", "live"]) {
        const index = parts.indexOf(marker);
        if (index !== -1 && parts.length > index + 1) return parts[index + 1];
      }
    }
  } catch (error) {
    logger.warn("Invalid YouTube URL in product", { raw });
  }

  return "";
}

function youtubeThumbnail(videoId) {
  return videoId ? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg` : "";
}

function productKeywords(product) {
  const keywords = [];

  if (Array.isArray(product.searchKeywords)) {
    keywords.push(...product.searchKeywords);
  }

  if (Array.isArray(product.seoTags)) {
    keywords.push(...product.seoTags);
  }

  keywords.push(
    product.name,
    product.category,
    product.brand,
    product.manufacturer,
    "ChalakChar Mart",
    "online shopping Bangladesh"
  );

  return [...new Set(
    keywords
      .map((item) => cleanText(item).toLowerCase())
      .filter(Boolean)
  )].slice(0, 20).join(", ");
}

function productPrice(product) {
  const direct = toNumber(product.price || product.piecePrice || 0);
  if (direct > 0) return direct;

  if (Array.isArray(product.variants) && product.variants.length > 0) {
    return toNumber(product.variants[0]?.price || product.variants[0]?.piecePrice || 0);
  }

  return 0;
}

function productStock(product) {
  const direct = toNumber(product.stock || 0);
  if (direct > 0) return direct;

  if (Array.isArray(product.variants)) {
    return product.variants.reduce((sum, variant) => {
      return sum + toNumber(variant?.stock || 0);
    }, 0);
  }

  return 0;
}


async function productReviewSchemas(productId, productName) {
  try {
    const reviewsSnap = await db
      .collection("products")
      .doc(productId)
      .collection("reviews")
      .orderBy("createdAt", "desc")
      .limit(5)
      .get();

    if (reviewsSnap.empty) return [];

    const reviews = [];

    reviewsSnap.forEach((doc) => {
      const review = doc.data() || {};
      const rating = toNumber(review.rating || 0);
      const comment = limitText(review.comment || review.review || "", 300);
      const userName = cleanText(review.userName || review.name, "Customer");

      if (rating <= 0 || !comment) return;

      reviews.push({
        "@type": "Review",
        "itemReviewed": {
          "@type": "Product",
          "name": productName,
        },
        "author": {
          "@type": "Person",
          "name": userName,
        },
        "reviewRating": {
          "@type": "Rating",
          "ratingValue": rating.toFixed(1),
          "bestRating": "5",
          "worstRating": "1",
        },
        "reviewBody": comment,
      });
    });

    return reviews;
  } catch (error) {
    logger.warn("Product review schema skipped", {
      productId,
      message: error.message || String(error),
    });
    return [];
  }
}

exports.productSeo = onRequest(
  {
    region: "asia-south1",
    cors: false,
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    try {
      // Firebase Hosting rewrite and direct Cloud Function URL can expose
      // different path shapes. Examples:
      //   /product/PRODUCT_ID
      //   /PRODUCT_ID
      //   /productSeo/product/PRODUCT_ID
      // This parser always takes the last meaningful segment and removes query/hash.
      const rawPath = decodeURIComponent(
        String(req.path || req.url || req.originalUrl || "")
      ).split("?")[0].split("#")[0];

      const pathParts = rawPath
        .split("/")
        .map((part) => part.trim())
        .filter(Boolean)
        .filter((part) => part !== "product" && part !== "productSeo");

      let productId = cleanText(pathParts[pathParts.length - 1] || "");

      if (!productId) {
        res.set("Content-Type", "text/html; charset=utf-8");
        return res.status(404).send("<!DOCTYPE html><html><head><title>Product not found | ChalakChar Mart</title><meta name=\"robots\" content=\"noindex, follow\"></head><body>Product not found</body></html>");
      }

      // First try by Firestore document ID.
      let productDoc = await db.collection("products").doc(productId).get();

      logger.warn("SEO DEBUG", {
        productId,
        exists: productDoc.exists,
        projectId: admin.app().options.projectId,
      });

      const testDocs = await db.collection("products").limit(5).get();

      testDocs.forEach((d) => {
        logger.warn("PRODUCT_DOC", {
          id: d.id,
        });
      });

      // Fallbacks: some admin imports may save product id in a field instead of doc id.
      if (!productDoc.exists) {
        const fallbackFields = ["id", "productId", "sku"];

        for (const field of fallbackFields) {
          const querySnap = await db.collection("products")
            .where(field, "==", productId)
            .limit(1)
            .get();

          if (!querySnap.empty) {
            productDoc = querySnap.docs[0];
            productId = productDoc.id;
            break;
          }
        }
      }

      if (!productDoc.exists) {
        logger.warn("Product SEO not found", {
          rawPath,
          parsedProductId: productId,
          originalUrl: req.originalUrl || "",
          url: req.url || "",
          path: req.path || "",
        });

        res.set("Content-Type", "text/html; charset=utf-8");
        res.set("Cache-Control", "no-store, max-age=0");
        return res.status(404).send("<!DOCTYPE html><html><head><title>Product not found | ChalakChar Mart</title><meta name=\"robots\" content=\"noindex, follow\"></head><body>Product not found</body></html>");
      }

      const product = productDoc.data() || {};
      const baseUrl = "https://chalakcharmart.com";
      const productUrl = `${baseUrl}/product/${encodeURIComponent(productId)}`;

      const productName = cleanText(product.name, "Product");
      const title = limitText(
        product.metaTitle || `${productName} | Buy Online - ChalakChar Mart`,
        60
      );

      const description = limitText(
        product.metaDescription ||
          product.description ||
          product.overview ||
          `Buy ${productName} online from ChalakChar Mart.`,
        155
      );

      const image = firstProductImage(product);
      const videoId = youtubeVideoIdFromProduct(product);
      const videoThumbnail = youtubeThumbnail(videoId);
      const keywords = productKeywords(product);
      const category = cleanText(product.category, "Other");
      const brand = cleanText(product.brand || product.manufacturer, "ChalakChar Mart");
      const price = productPrice(product);
      const stock = productStock(product);

      const schema = {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": productName,
        "image": [image],
        "description": description,
        "sku": productId,
        "category": category,
        "brand": {
          "@type": "Brand",
          "name": brand,
        },
        "offers": {
          "@type": "Offer",
          "url": productUrl,
          "priceCurrency": "BDT",
          "price": price.toFixed(2),
          "availability": stock > 0
            ? "https://schema.org/InStock"
            : "https://schema.org/OutOfStock",
          "itemCondition": "https://schema.org/NewCondition",
          "shippingDetails": {
            "@type": "OfferShippingDetails",
            "shippingRate": {
              "@type": "MonetaryAmount",
              "value": "60",
              "currency": "BDT",
            },
            "shippingDestination": {
              "@type": "DefinedRegion",
              "addressCountry": "BD",
            },
            "deliveryTime": {
              "@type": "ShippingDeliveryTime",
              "handlingTime": {
                "@type": "QuantitativeValue",
                "minValue": 0,
                "maxValue": 1,
                "unitCode": "DAY",
              },
              "transitTime": {
                "@type": "QuantitativeValue",
                "minValue": 1,
                "maxValue": 5,
                "unitCode": "DAY",
              },
            },
          },
          "hasMerchantReturnPolicy": {
            "@type": "MerchantReturnPolicy",
            "applicableCountry": "BD",
            "returnPolicyCategory": "https://schema.org/MerchantReturnFiniteReturnWindow",
            "merchantReturnDays": 7,
            "returnMethod": "https://schema.org/ReturnByMail",
            "returnFees": "https://schema.org/FreeReturn",
          },
          "seller": {
            "@type": "Organization",
            "name": "ChalakChar Mart",
          },
        },
      };

      if (videoId) {
        schema.video = {
          "@type": "VideoObject",
          "name": productName,
          "description": description,
          "thumbnailUrl": videoThumbnail ? [videoThumbnail] : [image],
          "embedUrl": `https://www.youtube.com/embed/${videoId}`,
          "contentUrl": `https://www.youtube.com/watch?v=${videoId}`,
          "uploadDate": sitemapDate(product.updatedAt || product.createdAt),
        };
      }

      const ratingCount = parseInt(product.ratingCount || product.reviewCount || 0, 10);
      const ratingAvg = toNumber(product.ratingAvg || 0);

      if (ratingCount > 0 && ratingAvg > 0) {
        schema.aggregateRating = {
          "@type": "AggregateRating",
          "ratingValue": ratingAvg.toFixed(1),
          "reviewCount": ratingCount,
          "ratingCount": ratingCount,
          "bestRating": "5",
          "worstRating": "1",
        };
      }

      const reviewSchemas = await productReviewSchemas(productId, productName);
      if (reviewSchemas.length > 0) {
        schema.review = reviewSchemas;
      }

      const organizationSchema = {
        "@context": "https://schema.org",
        "@type": "Organization",
        "@id": `${baseUrl}/#organization`,
        "name": "ChalakChar Mart",
        "url": baseUrl,
        "logo": `${baseUrl}/icons/Icon-512.png`,
      };

      const websiteSchema = {
        "@context": "https://schema.org",
        "@type": "WebSite",
        "@id": `${baseUrl}/#website`,
        "url": baseUrl,
        "name": "ChalakChar Mart",
        "publisher": {
          "@id": `${baseUrl}/#organization`,
        },
        "potentialAction": {
          "@type": "SearchAction",
          "target": `${baseUrl}/search?q={search_term_string}`,
          "query-input": "required name=search_term_string",
        },
      };

      const breadcrumbSchema = {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "@id": `${productUrl}#breadcrumb`,
        "itemListElement": [
          {
            "@type": "ListItem",
            "position": 1,
            "name": "Home",
            "item": `${baseUrl}/`,
          },
          {
            "@type": "ListItem",
            "position": 2,
            "name": category || "Products",
            "item": `${baseUrl}/`,
          },
          {
            "@type": "ListItem",
            "position": 3,
            "name": productName,
            "item": productUrl,
          },
        ],
      };

      const jsonLdGraph = {
        "@context": "https://schema.org",
        "@graph": [
          organizationSchema,
          websiteSchema,
          breadcrumbSchema,
          schema,
        ],
      };

      const html = `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title>${htmlEscape(title)}</title>
  <meta name="title" content="${htmlEscape(title)}">
  <meta name="description" content="${htmlEscape(description)}">
  <meta name="keywords" content="${htmlEscape(keywords)}">
  <meta name="robots" content="index, follow">

  <meta property="og:site_name" content="ChalakChar Mart">
  <meta property="fb:app_id" content="996213106661804">
  <meta property="og:title" content="${htmlEscape(title)}">
  <meta property="og:description" content="${htmlEscape(description)}">
  <meta property="og:type" content="product">
  <meta property="og:url" content="${htmlEscape(productUrl)}">
  <meta property="og:image" content="${htmlEscape(videoThumbnail || image)}">
  ${videoId ? `<meta property="og:video" content="https://www.youtube.com/embed/${htmlEscape(videoId)}">
  <meta property="og:video:type" content="text/html">` : ""}
  <meta property="product:price:amount" content="${htmlEscape(price.toFixed(2))}">
  <meta property="product:price:currency" content="BDT">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${htmlEscape(title)}">
  <meta name="twitter:description" content="${htmlEscape(description)}">
  <meta name="twitter:image" content="${htmlEscape(image)}">

  <link rel="canonical" href="${htmlEscape(productUrl)}">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="manifest" href="manifest.json">

  <script type="application/ld+json">${jsonLdEscapeObject(jsonLdGraph)}</script>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;

      res.set("Content-Type", "text/html; charset=utf-8");
      res.set("Cache-Control", "public, max-age=300, s-maxage=600");
      return res.status(200).send(html);
    } catch (error) {
      logger.error("Product SEO render failed", error);
      res.set("Content-Type", "text/html; charset=utf-8");
      return res.status(500).send("<!DOCTYPE html><html><head><title>ChalakChar Mart</title></head><body>Something went wrong</body></html>");
    }
  }
);

// -----------------------------------------------------------------------------
// SEO Dynamic Sitemap for ChalakChar Mart
// -----------------------------------------------------------------------------
// URL:
//   https://chalakcharmart.com/sitemap.xml
//
// Includes:
//   - Homepage
//   - Active categories
//   - Active + approved products
// -----------------------------------------------------------------------------

function escapeXml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function seoSlug(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function sitemapDate(value) {
  try {
    if (value && typeof value.toDate === "function") {
      return value.toDate().toISOString().slice(0, 10);
    }
    if (value instanceof Date) {
      return value.toISOString().slice(0, 10);
    }
  } catch (e) {
    logger.warn("Invalid sitemap date", e);
  }

  return new Date().toISOString().slice(0, 10);
}

function sitemapUrl(loc, lastmod, changefreq = "weekly", priority = "0.8") {
  return `  <url>
    <loc>${escapeXml(loc)}</loc>
    <lastmod>${escapeXml(lastmod)}</lastmod>
    <changefreq>${escapeXml(changefreq)}</changefreq>
    <priority>${escapeXml(priority)}</priority>
  </url>`;
}

exports.sitemap = onRequest(
  {
    region: "asia-south1",
    cors: false,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (req, res) => {
    try {
      const baseUrl = "https://chalakcharmart.com";
      const today = new Date().toISOString().slice(0, 10);

      const urls = [
        sitemapUrl(`${baseUrl}/`, today, "daily", "1.0"),
        sitemapUrl(`${baseUrl}/about-us`, today, "monthly", "0.5"),
        sitemapUrl(`${baseUrl}/privacy-policy`, today, "monthly", "0.3"),
        sitemapUrl(`${baseUrl}/terms-conditions`, today, "monthly", "0.3"),
        sitemapUrl(`${baseUrl}/return-policy`, today, "monthly", "0.3"),
      ];

      const categoriesSnap = await db.collection("categories")
        .where("isActive", "==", true)
        .get();

      categoriesSnap.forEach((doc) => {
        const data = doc.data() || {};
        const name = data.name || "";
        const slug = seoSlug(name);

        if (!slug) return;

        urls.push(
          sitemapUrl(
            `${baseUrl}/category/${slug}`,
            sitemapDate(data.updatedAt || data.createdAt),
            "weekly",
            "0.8"
          )
        );
      });

      const productsSnap = await db.collection("products")
        .where("isActive", "==", true)
        .where("approvalStatus", "==", "approved")
        .get();

      productsSnap.forEach((doc) => {
        const data = doc.data() || {};

        urls.push(
          sitemapUrl(
            `${baseUrl}/product/${doc.id}`,
            sitemapDate(data.updatedAt || data.createdAt),
            "weekly",
            "0.7"
          )
        );
      });

      const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.join("\n")}
</urlset>
`;

      res.set("Content-Type", "application/xml; charset=utf-8");
      res.set("Cache-Control", "public, max-age=3600, s-maxage=3600");
      return res.status(200).send(xml);
    } catch (error) {
      logger.error("Dynamic sitemap generation failed", error);
      res.set("Content-Type", "text/plain; charset=utf-8");
      return res.status(500).send("Sitemap generation failed");
    }
  }
);

// -----------------------------------------------------------------------------
// Server-side Homepage SEO HTML for ChalakChar Mart
// -----------------------------------------------------------------------------
// Firebase Hosting rewrite:
//   / -> homeSeo
// -----------------------------------------------------------------------------
exports.homeSeo = onRequest(
  {
    region: "asia-south1",
    cors: false,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (req, res) => {
    try {
      const baseUrl = "https://chalakcharmart.com";

      const title = limitText(
        "ChalakChar Mart | Online Pharmacy, Grocery & Doctor Appointment in Bangladesh",
        60
      );

      const description = limitText(
        "ChalakChar Mart থেকে অনলাইনে কিনুন ওষুধ, মুদি, ফল-সবজি ও দৈনন্দিন পণ্য। " +
        "সহজে ডাক্তার অ্যাপয়েন্টমেন্ট বুক করুন এবং দ্রুত হোম ডেলিভারি পান বাংলাদেশ জুড়ে।",
        155
      );

      const image = `${baseUrl}/icons/Icon-512.png`;

      let categoryNames = [];
      let itemListElements = [];

      try {
        const categoriesSnap = await db.collection("categories")
          .where("isActive", "==", true)
          .get();

        let position = 1;
        categoriesSnap.forEach((doc) => {
          const data = doc.data() || {};
          const name = cleanText(data.name);
          const slug = seoSlug(name);
          if (!name || !slug) return;

          categoryNames.push(name);
          itemListElements.push({
            "@type": "ListItem",
            "position": position++,
            "name": name,
            "url": `${baseUrl}/category/${slug}`,
          });
        });
      } catch (e) {
        logger.warn("homeSeo: category fetch failed", e);
      }

      const keywords = [
        "online pharmacy bangladesh",
        "chalakchar mart",
        "grocery delivery bangladesh",
        "doctor appointment online",
        "medicine delivery dhaka",
        "online shopping bangladesh",
        ...categoryNames.map((c) => c.toLowerCase()),
      ].join(", ");

      const organizationSchema = {
        "@context": "https://schema.org",
        "@type": "Organization",
        "@id": `${baseUrl}/#organization`,
        "name": "ChalakChar Mart",
        "url": baseUrl,
        "logo": image,
      };

      const websiteSchema = {
        "@context": "https://schema.org",
        "@type": "WebSite",
        "@id": `${baseUrl}/#website`,
        "url": baseUrl,
        "name": "ChalakChar Mart",
        "publisher": { "@id": `${baseUrl}/#organization` },
        "potentialAction": {
          "@type": "SearchAction",
          "target": `${baseUrl}/search?q={search_term_string}`,
          "query-input": "required name=search_term_string",
        },
      };

      const graph = [organizationSchema, websiteSchema];

      if (itemListElements.length > 0) {
        graph.push({
          "@context": "https://schema.org",
          "@type": "ItemList",
          "@id": `${baseUrl}/#categories`,
          "itemListElement": itemListElements,
        });
      }

      const jsonLdGraph = { "@context": "https://schema.org", "@graph": graph };

      const html = `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title>${htmlEscape(title)}</title>
  <meta name="title" content="${htmlEscape(title)}">
  <meta name="description" content="${htmlEscape(description)}">
  <meta name="keywords" content="${htmlEscape(keywords)}">
  <meta name="robots" content="index, follow">

  <meta property="og:site_name" content="ChalakChar Mart">
  <meta property="fb:app_id" content="996213106661804">
  <meta property="og:title" content="${htmlEscape(title)}">
  <meta property="og:description" content="${htmlEscape(description)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${baseUrl}/">
  <meta property="og:image" content="${htmlEscape(image)}">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${htmlEscape(title)}">
  <meta name="twitter:description" content="${htmlEscape(description)}">
  <meta name="twitter:image" content="${htmlEscape(image)}">

  <link rel="canonical" href="${baseUrl}/">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="manifest" href="manifest.json">

  <script type="application/ld+json">${jsonLdEscapeObject(jsonLdGraph)}</script>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;

      res.set("Content-Type", "text/html; charset=utf-8");
      res.set("Cache-Control", "public, max-age=600, s-maxage=1800");
      return res.status(200).send(html);
    } catch (error) {
      logger.error("Home SEO render failed", error);
      res.set("Content-Type", "text/html; charset=utf-8");
      return res.status(500).send("<!DOCTYPE html><html><head><title>ChalakChar Mart</title></head><body>Something went wrong</body></html>");
    }
  }
);

// -----------------------------------------------------------------------------
// Secure Referral Reward Apply
// -----------------------------------------------------------------------------
// Client sends referral code + Firebase ID token.
// This function verifies auth, checks duplicate/self referral, reads settings/referral,
// then updates referrer/referee rewards using Admin SDK inside a Firestore transaction.
// -----------------------------------------------------------------------------
exports.applyReferralReward = onRequest(
  {
    region: "asia-south1",
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    cors(req, res, async () => {
      try {
        if (req.method === "OPTIONS") return res.status(204).send("");

        if (req.method !== "POST") {
          return res.status(405).json({
            ok: false,
            message: "Only POST request allowed",
          });
        }

        const authHeader = String(req.headers.authorization || "").trim();
        const idToken = authHeader.startsWith("Bearer ")
          ? authHeader.substring(7).trim()
          : "";

        if (!idToken) {
          return res.status(401).json({
            ok: false,
            message: "Login required",
          });
        }

        const decoded = await admin.auth().verifyIdToken(idToken);
        const uid = decoded.uid;

        const code = String(req.body?.code || "")
          .trim()
          .toUpperCase()
          .replace(/\s+/g, "");

        if (!code || code.length < 4 || code.length > 20) {
          return res.status(400).json({
            ok: false,
            message: "Invalid referral code",
          });
        }

        let responsePayload = null;

        await db.runTransaction(async (tx) => {
          const userRef = db.collection("users").doc(uid);
          const userSnap = await tx.get(userRef);

          if (!userSnap.exists) {
            throw new Error("USER_PROFILE_NOT_FOUND");
          }

          const user = userSnap.data() || {};

          const alreadyApplied =
            String(user.referredByUid || "").trim() ||
            String(user.referredByCode || "").trim() ||
            String(user.referredBy || "").trim();

          if (alreadyApplied) {
            responsePayload = {
              ok: true,
              alreadyApplied: true,
              message: "You have already applied a referral code.",
            };
            return;
          }

          const ownCode = String(user.refCode || "")
            .trim()
            .toUpperCase()
            .replace(/\s+/g, "");

          if (ownCode && ownCode === code) {
            responsePayload = {
              ok: false,
              message: "You cannot use your own referral code.",
            };
            return;
          }

          const settingsRef = db.collection("settings").doc("referral");
          const settingsSnap = await tx.get(settingsRef);
          const settings = settingsSnap.exists ? (settingsSnap.data() || {}) : {};

          if (settings.referralEnabled === false) {
            responsePayload = {
              ok: false,
              message: "Referral program is currently disabled.",
            };
            return;
          }

          const referrerQuery = db
            .collection("users")
            .where("refCode", "==", code)
            .limit(1);

          const referrerSnap = await tx.get(referrerQuery);

          if (referrerSnap.empty) {
            responsePayload = {
              ok: false,
              message: "Referral code not found.",
            };
            return;
          }

          const referrerDoc = referrerSnap.docs[0];
          const referrerId = referrerDoc.id;

          if (referrerId === uid) {
            responsePayload = {
              ok: false,
              message: "You cannot use your own referral code.",
            };
            return;
          }

          const autoApprove = settings.autoApprove !== false;
          const referrerReward = Math.max(
            0,
            toNumber(settings.referrerReward ?? settings.referralReward ?? 25)
          );
          const refereeReward = Math.max(
            0,
            toNumber(settings.refereeReward ?? 25)
          );

          const referralRef = db
            .collection("referrals")
            .doc(`${referrerId}_${uid}`);

          const existingReferral = await tx.get(referralRef);

          if (existingReferral.exists) {
            responsePayload = {
              ok: true,
              alreadyApplied: true,
              message: "You have already applied a referral code.",
            };
            return;
          }

          const now = admin.firestore.FieldValue.serverTimestamp();
          const status = autoApprove ? "approved" : "pending";

          const userUpdate = {
            referredByUid: referrerId,
            referredByCode: code,
            referralAppliedAt: now,
            referralFirstOrderRewarded: autoApprove,
            updatedAt: now,
          };

          const referrerUpdate = {
            updatedAt: now,
          };

          if (autoApprove) {
            userUpdate.points = admin.firestore.FieldValue.increment(refereeReward);
            userUpdate.totalEarnings = admin.firestore.FieldValue.increment(refereeReward);

            referrerUpdate.points = admin.firestore.FieldValue.increment(referrerReward);
            referrerUpdate.totalEarnings = admin.firestore.FieldValue.increment(referrerReward);
            referrerUpdate.referralCount = admin.firestore.FieldValue.increment(1);
          }

          tx.set(userRef, userUpdate, { merge: true });
          tx.set(db.collection("users").doc(referrerId), referrerUpdate, { merge: true });

          tx.set(referralRef, {
            referrerId,
            referredUserId: uid,
            referredByCode: code,
            referrerReward,
            refereeReward,
            status,
            autoApprove,
            createdAt: now,
            updatedAt: now,
          }, { merge: true });

          if (autoApprove) {
            const referrerWalletRef = db
              .collection("wallet_logs")
              .doc(`referral_referrer_${referrerId}_${uid}`);
            const refereeWalletRef = db
              .collection("wallet_logs")
              .doc(`referral_referee_${uid}_${referrerId}`);

            tx.set(referrerWalletRef, {
              userId: referrerId,
              type: "referral_reward",
              direction: "credit",
              amount: referrerReward,
              source: "referral",
              relatedUserId: uid,
              referralId: referralRef.id,
              note: "Referral reward",
              createdAt: now,
            }, { merge: true });

            tx.set(refereeWalletRef, {
              userId: uid,
              type: "referee_reward",
              direction: "credit",
              amount: refereeReward,
              source: "referral",
              relatedUserId: referrerId,
              referralId: referralRef.id,
              note: "Referral signup reward",
              createdAt: now,
            }, { merge: true });
          }

          responsePayload = {
            ok: true,
            alreadyApplied: false,
            status,
            referrerReward: autoApprove ? referrerReward : 0,
            refereeReward: autoApprove ? refereeReward : 0,
            message: autoApprove
              ? "Referral applied successfully. Reward added to your balance."
              : "Referral code applied successfully. Reward is pending approval.",
          };
        });

        return res.status(200).json(responsePayload || {
          ok: false,
          message: "Referral could not be applied.",
        });
      } catch (error) {
        logger.error("Apply referral reward failed", error);

        const rawMessage = String(error?.message || error || "");
        const message = rawMessage === "USER_PROFILE_NOT_FOUND"
          ? "User profile not found. Please login again."
          : "Referral could not be applied now.";

        return res.status(500).json({
          ok: false,
          message,
        });
      }
    });
  }
);

// ---- TikTok integration (isolated module, Phase A: OAuth + token lifecycle only) ----
// The existing dispatcher stub at dispatchMetaSocialChannels() (channels.tiktok
// branch) is intentionally left untouched until Phase C. Nothing below this
// point is called from anywhere else in this file yet.
exports.tiktokOAuthStart = tiktokOAuthStart;
exports.tiktokOAuthCallback = tiktokOAuthCallback;
exports.tiktokGetOAuthConfig = tiktokGetOAuthConfig;
exports.tiktokTokenRefreshSweep = tiktokTokenRefreshSweep;
exports.tiktokConnectionStatusProjection = tiktokConnectionStatusProjection;
exports.tiktokDisconnect = tiktokDisconnect;
exports.tiktokGetCreatorInfo = tiktokGetCreatorInfo;
exports.tiktokConfirmPublish = tiktokConfirmPublish;
exports.tiktokForceRepublish = tiktokForceRepublish;
exports.tiktokWebhook = tiktokWebhook;
exports.tiktokPublishJobsSweep = tiktokPublishJobsSweep;
