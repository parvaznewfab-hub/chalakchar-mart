const { setGlobalOptions } = require("firebase-functions/v2");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
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

// ---- AliExpress delivery-estimate parsing (isolated, dependency-light module — see functions/aliexpress/) ----
const {
  parseAliExpressDeliveryEstimate,
  buildAliExpressDeliveryFirestoreFields,
  discoverAliExpressDeliveryCandidates,
} = require("./aliexpress/deliveryEstimate");
const {
  selectPreferredFreightOption,
  buildAliExpressFreightFirestoreFields,
} = require("./aliexpress/freightDeliveryEstimate");
const { resolveAliExpressVariantName } = require("./aliexpress/variantName");
const { resolveAliExpressVariantImage } = require("./aliexpress/variantImage");
const {
  computeVariantImagePatches,
  applyVariantImagePatchesToLatest,
} = require("./aliexpress/backfillVariantImages");
const {
  extractClientIp,
  parseRateLimitSettings,
  evaluateSearchImportRateLimit,
} = require("./aliexpress/searchImportRateLimit");
const { validateSearchImportQuery } = require("./aliexpress/searchImportQueryGuard");
const { resolveAliExpressShippingCostBDT } = require("./aliexpress/shippingCost");
const { resolveProductTaxonomy } = require("./category/resolveProductTaxonomy");
const { matchCategoryByKeyword } = require("./category/aliExpressCategoryKeywords");
const {
  buildCategorySuggestionPrompt,
  parseCategorySuggestionResponse,
} = require("./category/suggestAliExpressCategoryAi");

// ---- Unified omnichannel messaging pipeline (isolated module — see functions/messaging/) ----
const { handleCustomerMessage } = require("./messaging/handleCustomerMessage");

// ---- Meta webhook verification, shared by WhatsApp/Messenger/Instagram (see functions/meta/) ----
const { META_APP_SECRET, INSTAGRAM_APP_SECRET, META_WEBHOOK_VERIFY_TOKEN } = require("./meta/config");
const { verifyMetaSignature, WebhookVerificationError } = require("./meta/signatureVerify");
const { resolveVerificationChallenge } = require("./meta/webhookChallenge");

// ---- WhatsApp inbound webhook (isolated module — see functions/whatsapp/) ----
const { parseWhatsAppWebhookEvents } = require("./whatsapp/parseInboundMessage");
const { claimWhatsAppMessageId } = require("./whatsapp/dedupe");

// ---- Messenger/Instagram inbound webhooks (shared parser/dedupe — see functions/meta/) ----
const { parseMetaMessagingEvents } = require("./meta/parseMessagingEvents");
const { claimMetaMessageId } = require("./meta/dedupe");

let marketingSettingsCache = null;
let marketingSettingsCacheAt = 0;
const MARKETING_SETTINGS_CACHE_MS = 5 * 60 * 1000;
const PRODUCT_IMPORT_API_KEY = defineSecret("PRODUCT_IMPORT_API_KEY");
const ALIEXPRESS_APP_SECRET = defineSecret("ALIEXPRESS_APP_SECRET");
const ALIEXPRESS_APP_KEY = "540112";
// Separate Affiliate API app (aliexpress.affiliate.*.query) — a distinct
// AliExpress console app/approval from the Dropshipping AppKey/App Secret
// above, so it gets its own AppKey/App Secret pair rather than reusing
// ALIEXPRESS_APP_KEY/ALIEXPRESS_APP_SECRET. See aliExpressSignedApiRequest's
// options.appKey/appSecret override, used only by the two affiliate query
// call sites (aliexpressDiscoverProducts, aliexpressSearchImport).
const ALIEXPRESS_AFFILIATE_APP_KEY = defineSecret("ALIEXPRESS_AFFILIATE_APP_KEY");
const ALIEXPRESS_AFFILIATE_APP_SECRET = defineSecret("ALIEXPRESS_AFFILIATE_APP_SECRET");
const ALIEXPRESS_CALLBACK_URL = "https://chalakcharmart.com/api/aliexpress/callback";
const ALIEXPRESS_OAUTH_AUTHORIZE_URL = "https://api-sg.aliexpress.com/oauth/authorize";
const ALIEXPRESS_API_BASE_URL = "https://api-sg.aliexpress.com/rest";
// Same endpoint lib/pages/user/search_page.dart posts to on a zero-result
// search box query — see triggerAliExpressSearchImportFallback below, which
// is the chat-side equivalent trigger.
const ALIEXPRESS_SEARCH_IMPORT_URL = "https://asia-south1-chalakchar-mart.cloudfunctions.net/aliexpressSearchImport";

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

// Thin wrapper around the WhatsApp Cloud API send call — the one place that
// actually posts a WhatsApp message, reused by both the outbound marketing
// queue (sendWhatsAppDelivery below) and the whatsappWebhook reply path
// (spec §4), per the spec's "reuse those functions here instead of writing
// new ones" guidance. `phoneNumberId` is optional and only needed to
// preserve a historical delivery doc's own phoneNumberId as a fallback —
// new callers should rely on settings/app.socialApi.whatsappPhoneNumberId.
async function sendWhatsAppMessage(settings, { to, body, phoneNumberId } = {}) {
  const socialApi = mapValue(settings.socialApi);
  const token = textValue(socialApi.whatsappAccessToken);
  const resolvedPhoneNumberId = textValue(phoneNumberId || socialApi.whatsappPhoneNumberId);
  if (!token || !resolvedPhoneNumberId) throw new Error("WhatsApp credentials are not configured");

  const data = await metaGraphPost(settings, `${resolvedPhoneNumberId}/messages`, {
    messaging_product: "whatsapp",
    to: textValue(to),
    type: "text",
    text: { preview_url: true, body: textValue(body) },
  }, token);

  return { messageId: textValue(data.messages?.[0]?.id), response: data };
}

// Thin wrapper around the Messenger Send API — the one place that actually
// posts a Messenger reply, used by the messengerWebhook inbound-reply path.
// "RESPONSE" messaging_type is required for replying within the 24h
// standard messaging window (distinct from postMessengerPage's "UPDATE",
// which is a broadcast to an admin-configured recipient list, not a reply
// to an inbound message).
async function sendMessengerMessage(settings, { to, body } = {}) {
  const socialApi = mapValue(settings.socialApi);
  const pageId = textValue(socialApi.facebookPageId || "me");
  const token = textValue(socialApi.messengerPageAccessToken || socialApi.facebookPageAccessToken);
  if (!token) throw new Error("Messenger credentials are not configured");

  const data = await metaGraphPost(settings, `${pageId}/messages`, {
    recipient: { id: textValue(to) },
    messaging_type: "RESPONSE",
    message: { text: textValue(body) },
  }, token);

  return { messageId: textValue(data.message_id), response: data };
}

// Thin wrapper around the Instagram messaging Send API — the one place that
// actually posts an Instagram DM reply, used by the instagramWebhook
// inbound-reply path.
async function sendInstagramMessage(settings, { to, body } = {}) {
  const socialApi = mapValue(settings.socialApi);
  const instagramBusinessId = textValue(socialApi.instagramBusinessId);
  const token = textValue(socialApi.instagramAccessToken || socialApi.facebookPageAccessToken);
  if (!instagramBusinessId || !token) throw new Error("Instagram credentials are not configured");

  const data = await metaGraphPost(settings, `${instagramBusinessId}/messages`, {
    recipient: { id: textValue(to) },
    message: { text: textValue(body) },
  }, token);

  return { messageId: textValue(data.message_id), response: data };
}

async function sendWhatsAppDelivery(deliveryRef, delivery) {
  const freshUser = await db.collection("users").doc(textValue(delivery.userId)).get();
  const user = freshUser.data() || {};
  if (!freshUser.exists || user.whatsappOptIn !== true || user.isActive === false || user.isBanned === true || user.isDeleted === true) {
    await deliveryRef.set({ status: "cancelled_opted_out", updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  const settings = await loadMarketingSettings(true);
  const { messageId } = await sendWhatsAppMessage(settings, {
    to: textValue(delivery.to),
    body: textValue(delivery.messageBody),
    phoneNumberId: delivery.phoneNumberId,
  });

  await deliveryRef.set({
    status: "sent",
    messageId,
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



// -----------------------------------------------------------------------------
// AliExpress OAuth connection and token lifecycle
// -----------------------------------------------------------------------------

function aliExpressState(secret) {
  const issuedAt = Date.now();
  const nonce = crypto.randomBytes(18).toString("hex");
  const payload = `${issuedAt}.${nonce}`;
  const signature = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  return Buffer.from(`${payload}.${signature}`, "utf8").toString("base64url");
}

function verifyAliExpressState(state, secret) {
  try {
    const decoded = Buffer.from(textValue(state), "base64url").toString("utf8");
    const parts = decoded.split(".");
    if (parts.length !== 3) return false;
    const [issuedAtText, nonce, signature] = parts;
    const issuedAt = Number(issuedAtText);
    if (!Number.isFinite(issuedAt) || !nonce || Date.now() - issuedAt > 15 * 60 * 1000) return false;
    const expected = crypto.createHmac("sha256", secret)
      .update(`${issuedAtText}.${nonce}`)
      .digest("hex");
    return secureKeyEquals(signature, expected);
  } catch (_) {
    return false;
  }
}

function aliExpressTokenDate(value, fallbackSeconds = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return fallbackSeconds > 0
      ? admin.firestore.Timestamp.fromMillis(Date.now() + fallbackSeconds * 1000)
      : null;
  }
  // AliExpress responses may contain either a lifetime in seconds or an epoch value.
  if (numeric > 1000000000000) return admin.firestore.Timestamp.fromMillis(numeric);
  if (numeric > 1000000000) return admin.firestore.Timestamp.fromMillis(numeric * 1000);
  return admin.firestore.Timestamp.fromMillis(Date.now() + numeric * 1000);
}

function aliExpressTokenPayload(data, previous = {}) {
  const accessToken = textValue(data.access_token || data.accessToken);
  const refreshToken = textValue(data.refresh_token || data.refreshToken || previous.refreshToken);
  if (!accessToken) throw new Error("AliExpress did not return an access token");

  const accessExpiresAt = aliExpressTokenDate(
    data.expires_in || data.expire_time || data.expires_time,
    30 * 24 * 60 * 60
  );
  const refreshExpiresAt = aliExpressTokenDate(
    data.refresh_expires_in || data.refresh_token_valid_time || data.refresh_expires_time,
    60 * 24 * 60 * 60
  );

  return {
    provider: "aliexpress",
    appKey: ALIEXPRESS_APP_KEY,
    status: "connected",
    accessToken,
    refreshToken,
    accessExpiresAt,
    refreshExpiresAt,
    accountId: textValue(data.user_id || data.account_id || data.seller_id || previous.accountId),
    accountName: textValue(data.user_nick || data.account || previous.accountName),
    tokenType: textValue(data.token_type, "Bearer"),
    scope: textValue(data.scope),
    lastError: "",
    lastConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}


function aliExpressTopTimestamp(date = new Date()) {
  // AliExpress/TOP router expects GMT+8 in yyyy-MM-dd HH:mm:ss format.
  const gmt8 = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  const pad = (value) => String(value).padStart(2, "0");
  return `${gmt8.getUTCFullYear()}-${pad(gmt8.getUTCMonth() + 1)}-${pad(gmt8.getUTCDate())} ${pad(gmt8.getUTCHours())}:${pad(gmt8.getUTCMinutes())}:${pad(gmt8.getUTCSeconds())}`;
}

async function aliExpressTopApiRequest(method, sessionToken, businessParams = {}) {
  const appSecret = textValue(ALIEXPRESS_APP_SECRET.value());
  if (!appSecret) throw new Error("ALIEXPRESS_APP_SECRET is not configured");

  const params = {
    app_key: ALIEXPRESS_APP_KEY,
    format: "json",
    method,
    session: sessionToken,
    sign_method: "hmac",
    simplify: "true",
    timestamp: aliExpressTopTimestamp(),
    v: "2.0",
    ...Object.fromEntries(
      Object.entries(businessParams)
        .filter(([, value]) => value !== undefined && value !== null && textValue(value).length > 0)
        .map(([key, value]) => [key, String(value)])
    ),
  };

  const canonical = Object.keys(params)
    .sort()
    .map((key) => `${key}${params[key]}`)
    .join("");

  // TOP sign_method=hmac means HMAC-MD5, returned as uppercase hex.
  const sign = crypto
    .createHmac("md5", appSecret)
    .update(canonical, "utf8")
    .digest("hex")
    .toUpperCase();

  const response = await axios.post(
    "https://eco.taobao.com/router/rest",
    new URLSearchParams({ ...params, sign }).toString(),
    {
      headers: { "content-type": "application/x-www-form-urlencoded; charset=UTF-8" },
      timeout: 30000,
      validateStatus: () => true,
    }
  );

  const raw = response.data || {};
  const errorResponse = raw.error_response || raw.errorResponse;
  if (response.status < 200 || response.status >= 300 || errorResponse) {
    const apiError = errorResponse || raw;
    const message = textValue(
      apiError.sub_msg || apiError.msg || apiError.message,
      `AliExpress TOP API ${method} failed with status ${response.status}`
    );
    const error = new Error(message);
    error.status = response.status;
    error.code = textValue(apiError.sub_code || apiError.code, "ALIEXPRESS_TOP_API_FAILED");
    error.api = apiError;
    throw error;
  }

  const responseKey = `${method.replace(/\./g, "_")}_response`;
  return raw[responseKey] || raw;
}

async function aliExpressSignedApiRequest(apiName, businessParams = {}, options = {}) {
  // options.appKey/options.appSecret let affiliate-API call sites (see
  // ALIEXPRESS_AFFILIATE_APP_KEY/SECRET above) sign with the separate
  // Affiliate app credentials instead of the Dropshipping app's
  // ALIEXPRESS_APP_KEY/ALIEXPRESS_APP_SECRET used by every other caller.
  const usingAffiliateCreds = options.appKey !== undefined || options.appSecret !== undefined;
  const appKey = textValue(options.appKey, ALIEXPRESS_APP_KEY);
  const appSecret = usingAffiliateCreds
    ? textValue(options.appSecret)
    : textValue(ALIEXPRESS_APP_SECRET.value());
  if (!appSecret) {
    throw new Error(
      usingAffiliateCreds
        ? "ALIEXPRESS_AFFILIATE_APP_SECRET is not configured"
        : "ALIEXPRESS_APP_SECRET is not configured"
    );
  }

  // Two distinct IOP call styles share this helper:
  // - REST-style (options.sync falsy): apiName is a URL path like
  //   "/auth/token/create", posted to {API_BASE_URL}{apiName}. The path itself
  //   is prefixed into the signed string and is not sent as a body field.
  // - TOP-migrated / sync-style (options.sync === true): apiName is a dot
  //   method name like "aliexpress.ds.product.get". These always post to the
  //   constant /sync endpoint, the method name travels as a signed `method`
  //   body field (not a URL path), and the signature has no path prefix.
  const isSync = options.sync === true;

  const params = {
    app_key: appKey,
    timestamp: String(Date.now()),
    sign_method: "sha256",
    ...(isSync ? { method: apiName, simplify: "true" } : {}),
    ...Object.fromEntries(
      Object.entries(businessParams)
        .filter(([, value]) => value !== undefined && value !== null && textValue(value).length > 0)
        .map(([key, value]) => [key, String(value)])
    ),
  };

  const canonical = Object.keys(params)
    .sort()
    .map((key) => `${key}${params[key]}`)
    .join("");
  const sign = crypto
    .createHmac("sha256", appSecret)
    .update(isSync ? canonical : `${apiName}${canonical}`, "utf8")
    .digest("hex")
    .toUpperCase();

  const response = await axios.post(
    isSync ? "https://api-sg.aliexpress.com/sync" : `${ALIEXPRESS_API_BASE_URL}${apiName}`,
    new URLSearchParams({ ...params, sign }).toString(),
    {
      headers: { "content-type": "application/x-www-form-urlencoded; charset=UTF-8" },
      timeout: 30000,
      validateStatus: () => true,
    }
  );

  const raw = response.data || {};
  const errorResponse = raw.error_response;
  if (response.status < 200 || response.status >= 300 || errorResponse) {
    const apiError = errorResponse || raw;
    const message = textValue(
      apiError.sub_msg || apiError.error_message || apiError.message || apiError.msg,
      `AliExpress API ${apiName} failed with status ${response.status}`
    );
    const error = new Error(message);
    error.status = response.status;
    error.api = apiError;
    throw error;
  }

  if (isSync) {
    const responseKey = `${apiName.replace(/\./g, "_")}_response`;
    const container = mapValue(raw[responseKey] || raw);
    const rspCode = textValue(container.rsp_code || container.resp_code);
    if (rspCode && rspCode !== "200" && rspCode.toLowerCase() !== "success") {
      const error = new Error(textValue(container.rsp_msg || container.resp_msg, `AliExpress API ${apiName} failed with rsp_code ${rspCode}`));
      error.code = "ALIEXPRESS_SYNC_API_FAILED";
      error.api = container;
      throw error;
    }
    return mapValue(container.result || container.resp_result?.result || container);
  }

  const data = mapValue(raw.data || raw.result || raw);
  const errorCode = textValue(raw.code || raw.error_code || data.code || data.error_code);
  if (errorCode && errorCode !== "0" && errorCode.toLowerCase() !== "success") {
    const error = new Error(textValue(data.message, `AliExpress API ${apiName} failed with code ${errorCode}`));
    error.status = response.status;
    error.api = data;
    throw error;
  }
  return data;
}

async function aliExpressTokenRequest(params) {
  const isRefresh = textValue(params.grant_type) === "refresh_token";
  const apiCandidates = isRefresh
    ? ["/auth/token/security/refresh", "/auth/token/refresh"]
    : ["/auth/token/security/create", "/auth/token/create"];
  const businessParams = isRefresh
    ? { refresh_token: params.refresh_token }
    : { code: params.code, uuid: params.uuid };

  let lastError;
  for (const apiName of apiCandidates) {
    try {
      return await aliExpressSignedApiRequest(apiName, businessParams);
    } catch (error) {
      lastError = error;
      logger.warn("AliExpress token API attempt failed", {
        apiName,
        message: error.message,
        api: error.api || null,
      });
    }
  }
  throw lastError || new Error("AliExpress token request failed");
}

async function refreshAliExpressConnection(force = false) {
  const ref = db.collection("marketplace_connections").doc("aliexpress");
  const snap = await ref.get();
  if (!snap.exists) return { refreshed: false, reason: "not_connected" };

  const current = snap.data() || {};
  const refreshToken = textValue(current.refreshToken);
  if (!refreshToken) return { refreshed: false, reason: "missing_refresh_token" };

  const expiresAtMs = current.accessExpiresAt?.toMillis?.() || 0;
  const refreshWindowMs = 7 * 24 * 60 * 60 * 1000;
  if (!force && expiresAtMs > Date.now() + refreshWindowMs) {
    return { refreshed: false, reason: "token_still_valid", expiresAtMs };
  }

  try {
    const data = await aliExpressTokenRequest({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });
    await ref.set({
      ...aliExpressTokenPayload(data, current),
      lastRefreshedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { refreshed: true };
  } catch (error) {
    await ref.set({
      status: "refresh_failed",
      lastError: error.message || String(error),
      lastRefreshFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  }
}

exports.aliexpressOAuthStart = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_APP_SECRET], timeoutSeconds: 30 },
  async (req, res) => {
    cors(req, res, async () => {
      if (req.method === "OPTIONS") return res.status(204).send("");
      if (!["GET", "POST"].includes(req.method)) {
        return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
      }
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      const receivedKey = extractImportApiKey(req);
      if (!expectedKey || !secureKeyEquals(receivedKey, expectedKey)) {
        return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      }

      const secret = textValue(ALIEXPRESS_APP_SECRET.value());
      const state = aliExpressState(secret);
      const query = new URLSearchParams({
        response_type: "code",
        client_id: ALIEXPRESS_APP_KEY,
        redirect_uri: ALIEXPRESS_CALLBACK_URL,
        state,
        force_auth: "true",
      });
      return res.status(200).json({
        ok: true,
        authorizationUrl: `${ALIEXPRESS_OAUTH_AUTHORIZE_URL}?${query.toString()}`,
        expiresInSeconds: 900,
      });
    });
  }
);

exports.aliexpressOAuthCallback = onRequest(
  { secrets: [ALIEXPRESS_APP_SECRET], timeoutSeconds: 60, memory: "256MiB" },
  async (req, res) => {
    if (req.method !== "GET") return res.status(405).send("Method not allowed");
    const code = textValue(req.query.code);
    const state = textValue(req.query.state);
    const oauthError = textValue(req.query.error || req.query.error_description);
    if (oauthError) return res.status(400).send(`AliExpress authorization failed: ${oauthError}`);
    if (!code) return res.status(400).send("AliExpress authorization code is missing.");

    const secret = textValue(ALIEXPRESS_APP_SECRET.value());
    if (!verifyAliExpressState(state, secret)) {
      return res.status(400).send("Invalid or expired OAuth state. Start the connection again.");
    }

    try {
      const data = await aliExpressTokenRequest({
        code,
        grant_type: "authorization_code",
      });
      await db.collection("marketplace_connections").doc("aliexpress").set({
        ...aliExpressTokenPayload(data),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      return res.status(200).send(`<!doctype html><html><head><meta charset="utf-8"><title>AliExpress Connected</title></head><body style="font-family:Arial,sans-serif;padding:40px;max-width:720px;margin:auto"><h1>AliExpress connected successfully ✅</h1><p>The access and refresh tokens were saved securely on the Firebase server.</p><p>You may close this window.</p></body></html>`);
    } catch (error) {
      logger.error("AliExpress OAuth callback failed", { message: error.message, api: error.api || null });
      return res.status(500).send("AliExpress connection failed. Check Firebase Functions logs.");
    }
  }
);

exports.aliexpressConnectionStatus = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY], timeoutSeconds: 30 },
  async (req, res) => {
    cors(req, res, async () => {
      if (req.method === "OPTIONS") return res.status(204).send("");
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      const receivedKey = extractImportApiKey(req);
      if (!expectedKey || !secureKeyEquals(receivedKey, expectedKey)) {
        return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      }
      const snap = await db.collection("marketplace_connections").doc("aliexpress").get();
      const data = snap.data() || {};
      return res.status(200).json({
        ok: true,
        connected: snap.exists && data.status === "connected",
        status: textValue(data.status, "not_connected"),
        accountId: textValue(data.accountId),
        accountName: textValue(data.accountName),
        accessExpiresAt: data.accessExpiresAt?.toDate?.()?.toISOString?.() || null,
        refreshExpiresAt: data.refreshExpiresAt?.toDate?.()?.toISOString?.() || null,
        lastError: textValue(data.lastError),
      });
    });
  }
);

exports.aliexpressRefreshToken = onSchedule(
  { schedule: "every 12 hours", secrets: [ALIEXPRESS_APP_SECRET], timeoutSeconds: 120 },
  async () => {
    const result = await refreshAliExpressConnection(false);
    logger.info("AliExpress token refresh sweep completed", result);
  }
);

// -----------------------------------------------------------------------------
// External marketplace product import (AliExpress / n8n)
// -----------------------------------------------------------------------------

function importSafeId(value, fallback = "item") {
  const normalized = textValue(value, fallback)
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  return normalized || fallback;
}

function importNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function importInteger(value, fallback = 0) {
  return Math.max(0, Math.trunc(importNumber(value, fallback)));
}

function importStringList(value) {
  const raw = Array.isArray(value)
    ? value
    : textValue(value)
      ? String(value).split(/[\n,]+/)
      : [];

  return [...new Set(raw
    .map((item) => cleanUrl(item) || textValue(item))
    .filter(Boolean))];
}

function importKeywords(value, fallbackText = "") {
  const raw = Array.isArray(value)
    ? value
    : `${textValue(value)} ${textValue(fallbackText)}`.split(/[\s,;|]+/);

  return [...new Set(raw
    .map((item) => textValue(item).toLowerCase())
    .filter((item) => item.length >= 2))]
    .slice(0, 40);
}

function importVariants(rawVariants, fallback = {}) {
  const source = Array.isArray(rawVariants) && rawVariants.length
    ? rawVariants
    : [{
        id: "default",
        name: fallback.unit || "Default",
        price: fallback.price,
        mrp: fallback.mrp,
        stock: fallback.stock,
      }];

  const variants = [];
  const seen = new Set();

  for (let index = 0; index < source.length; index++) {
    const item = mapValue(source[index]);
    const name = textValue(
      item.name || item.unit || item.variantName || item.skuName,
      `Option ${index + 1}`
    );
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const price = importNumber(
      item.price ?? item.salePrice ?? item.piecePrice ?? fallback.price,
      0
    );
    if (price <= 0) continue;

    const mrpRaw = importNumber(
      item.mrp ?? item.oldPrice ?? item.originalPrice ?? fallback.mrp ?? price,
      price
    );
    const mrp = Math.max(price, mrpRaw);
    const stock = importInteger(
      item.stock ?? item.quantity ?? item.availableStock ?? fallback.stock,
      0
    );
    const variantId = importSafeId(
      item.id || item.variantId || item.skuId || `${name}_${index}`,
      `v_${index}`
    );

    variants.push({
      id: variantId,
      variantId,
      name,
      unit: name,
      variantName: name,
      price,
      piecePrice: price,
      mrp,
      oldPrice: mrp,
      stock,
      ...(textValue(item.skuId) ? { sourceSkuId: textValue(item.skuId) } : {}),
      ...(textValue(item.image) ? { image: textValue(item.image) } : {}),
      ...(textValue(item.imageUrl) ? { imageUrl: textValue(item.imageUrl) } : {}),
    });
  }

  if (!variants.length) {
    throw new Error("At least one valid variant with price greater than 0 is required");
  }

  return variants;
}

function marketplaceImportDocumentId(source, sourceProductId) {
  const digest = crypto
    .createHash("sha256")
    .update(`${source}:${sourceProductId}`)
    .digest("hex")
    .slice(0, 32);
  return `imp_${importSafeId(source, "marketplace").slice(0, 20)}_${digest}`;
}

function extractImportApiKey(req) {
  const authorization = textValue(req.get("authorization"));
  if (authorization.toLowerCase().startsWith("bearer ")) {
    return authorization.slice(7).trim();
  }
  return textValue(req.get("x-import-api-key") || req.query?.apiKey);
}

function secureKeyEquals(received, expected) {
  const left = Buffer.from(textValue(received));
  const right = Buffer.from(textValue(expected));
  return left.length > 0 && left.length === right.length && crypto.timingSafeEqual(left, right);
}

async function marketplaceImportSettings(source) {
  const snapshot = await db.collection("settings").doc("app").get();
  const root = snapshot.exists ? mapValue(snapshot.data()) : {};
  const settings = mapValue(root.importSettings);
  const sourceKey = importSafeId(source || "aliexpress", "aliexpress");
  const sourceMarkups = mapValue(settings.sourceMarkups);
  const fallbackMarkup = sourceKey === "aliexpress"
    ? importNumber(settings.aliExpressMarkupPercent, 10)
    : importNumber(settings.defaultMarkupPercent, 0);

  return {
    markupPercent: importNumber(sourceMarkups[sourceKey], fallbackMarkup),
    exchangeRate: Math.max(0, importNumber(settings.exchangeRate, 1)),
    minimumProfit: Math.max(0, importNumber(settings.minimumProfit, 0)),
    roundingMode: textValue(settings.roundingMode, "none").toLowerCase(),
    autoPublish: boolValue(settings.autoPublish, false),
    enableAi: boolValue(settings.enableAi, true),
    enableSeo: boolValue(settings.enableSeo, true),
    enableMarketing: boolValue(settings.enableMarketing, true),
    targetCurrency: textValue(settings.currency, "BDT").toUpperCase(),
  };
}

// additionalCostBDT: extra landed cost already in the target currency (BDT)
// — e.g. AliExpress freight/shipping — added AFTER exchange-rate conversion,
// BEFORE markup and the minimum-profit floor, so both actually apply to the
// full landed cost (product + shipping), not just the product price. Default
// 0 keeps every pre-existing caller (and the mrp/variant calls that don't
// pass it) byte-identical to before this param existed.
function applyImportPriceRule(rawValue, rawCost, settings, additionalCostBDT = 0) {
  const extra = Math.max(0, importNumber(additionalCostBDT, 0));
  const converted = Math.max(0, importNumber(rawValue, 0) * settings.exchangeRate) + extra;
  const cost = Math.max(0, importNumber(rawCost, rawValue) * settings.exchangeRate) + extra;
  let value = Math.max(converted * (1 + settings.markupPercent / 100), cost + settings.minimumProfit);

  if (settings.roundingMode === "99") {
    value = Math.max(0, Math.ceil(value) - 0.01);
  } else if (settings.roundingMode === "00" || settings.roundingMode === "integer") {
    value = Math.ceil(value);
  } else {
    value = Math.round(value * 100) / 100;
  }
  return value;
}

// -----------------------------------------------------------------------------
// AliExpress category resolution when the response has no usable
// category_name (see normalizeAliExpressProduct()'s comment on why that's
// left empty rather than guessed). Three-step fallback, cheapest first:
//   1. matchCategoryByKeyword() — free, instant, deterministic (see
//      functions/category/aliExpressCategoryKeywords.js).
//   2. AI suggestion via OpenAI — only tried on a keyword miss. Biased
//      toward reusing one of our real existing categories (active or not —
//      matches ensureCategoryExists()'s own "reuse an existing category
//      regardless of active state" policy); only proposes a brand new
//      category name when nothing genuinely fits.
//   3. ALIEXPRESS_CATEGORY_FALLBACK_NAME — a single fixed catch-all bucket,
//      used only if AI is unavailable/misconfigured/errors/times out, so a
//      transient OpenAI failure never blocks an import or produces a
//      one-off nonsense category name.
// Every non-empty candidate this produces still goes through
// resolveProductTaxonomy()/ensureCategoryExists() exactly like any other
// category name — this function only ever picks WHAT name to try, never
// creates or looks up a category doc itself.
// -----------------------------------------------------------------------------
const ALIEXPRESS_CATEGORY_FALLBACK_NAME = "Imported Products";
const ALIEXPRESS_CATEGORY_AI_TIMEOUT_MS = 15000;

async function fetchAllCategoryNames(db) {
  const snapshot = await db.collection("categories").select("name").get();
  return snapshot.docs.map((doc) => textValue(doc.data().name)).filter(Boolean);
}

async function suggestAliExpressCategoryWithAi({ title, candidateNames }) {
  const apiKey = textValue(process.env.OPENAI_API_KEY);
  if (!apiKey) return { matchedCategory: null, suggestedNewCategory: "" };

  try {
    const openai = new OpenAI({ apiKey, timeout: ALIEXPRESS_CATEGORY_AI_TIMEOUT_MS });
    const prompt = buildCategorySuggestionPrompt({ title, candidateNames });
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: "You are a careful ecommerce catalog categorizer. Return only valid JSON. Never invent a category name that wasn't given to you as a candidate.",
        },
        { role: "user", content: prompt },
      ],
    });
    const text = completion.choices?.[0]?.message?.content || "{}";
    return parseCategorySuggestionResponse(text, candidateNames);
  } catch (error) {
    logger.warn("AliExpress category AI suggestion failed, falling back", { message: error.message });
    return { matchedCategory: null, suggestedNewCategory: "" };
  }
}

async function resolveAliExpressCategoryName(db, { title, rawCategoryName }) {
  const raw = textValue(rawCategoryName);
  if (raw) return { categoryName: raw, method: "aliexpress" };

  const keywordMatch = matchCategoryByKeyword(title);
  if (keywordMatch) return { categoryName: keywordMatch, method: "keyword" };

  const candidateNames = await fetchAllCategoryNames(db);
  const { matchedCategory, suggestedNewCategory } = await suggestAliExpressCategoryWithAi({ title, candidateNames });
  if (matchedCategory) return { categoryName: matchedCategory, method: "ai_matched" };
  if (suggestedNewCategory) return { categoryName: suggestedNewCategory, method: "ai_new" };

  return { categoryName: ALIEXPRESS_CATEGORY_FALLBACK_NAME, method: "fallback" };
}

// options.forcePublish/options.forceUnpublish are code-level overrides —
// deliberately NOT read from `body`/req.body anywhere. They exist only so a
// trusted in-process caller can override the admin's global
// importSettings.autoPublish policy in a specific direction, without opening
// a way for external callers (n8n's webhook body, or any future one) to set
// the same field name in their JSON and bypass admin review:
//   - forcePublish: aliexpressSearchImport's search-miss trigger must publish
//     immediately — a real shopper is waiting on the exact product they just
//     searched for.
//   - forceUnpublish: the AliExpress discovery pipeline (aliexpressDiscoverProducts
//     / aliexpressScheduledDiscover) imports products nobody asked for, in
//     bulk, unattended — those must always land unpublished + needsReview
//     regardless of autoPublish, so nothing reaches shoppers before an admin
//     has looked at it. See options.needsReview below, set by the same callers.
// importAliExpressProduct (the n8n-facing webhook) is unattended/bulk just
// like Feature A — n8n pushes products nobody at ChalakChar Mart has looked
// at yet — so it passes the same { forceUnpublish: true, needsReview: true }
// as Feature A. n8n cannot override this via its request body; only this
// in-process options argument can.
async function buildMarketplaceProductPayload(body, options = {}) {
  const sourceData = mapValue(body.product || body.data || body);
  const source = importSafeId(body.source || sourceData.source || "aliexpress", "aliexpress");
  const sourceProductId = textValue(
    body.sourceProductId || sourceData.sourceProductId || sourceData.productId || sourceData.itemId
  );
  if (!sourceProductId) throw new Error("sourceProductId is required");

  const name = textValue(sourceData.name || sourceData.title);
  if (!name) throw new Error("Product name/title is required");

  const importSettings = await marketplaceImportSettings(source);
  // Imported products follow the Admin Panel review policy by default.
  // n8n cannot bypass it via the request body — only options.forcePublish /
  // options.forceUnpublish (never sourced from `body`) can override it. See
  // the comment above this function.
  const publish = options.forcePublish === true
    ? true
    : options.forceUnpublish === true
      ? false
      : importSettings.autoPublish;
  // No "Other" default here — an empty category must reach
  // resolveProductTaxonomy() as empty so it resolves to
  // Uncategorized/needsCategoryReview instead of silently becoming a real
  // "Other" category.
  const category = textValue(sourceData.category);
  const overview = textValue(sourceData.overview || sourceData.description);
  const overviewHtml = textValue(sourceData.overviewHtml);
  const specifications = (Array.isArray(sourceData.specifications) ? sourceData.specifications : [])
    .map((spec) => {
      const item = mapValue(spec);
      const name = textValue(item.name || item.label || item.key);
      const value = textValue(item.value);
      return name && value ? { name, value } : null;
    })
    .filter(Boolean);
  const deliveryDaysRaw = sourceData.deliveryDays;
  const deliveryDays = deliveryDaysRaw !== undefined && deliveryDaysRaw !== null && Number.isFinite(Number(deliveryDaysRaw))
    ? Math.max(0, Math.trunc(Number(deliveryDaysRaw)))
    : null;
  const manufacturer = textValue(sourceData.manufacturer || sourceData.brand);
  const images = importStringList(
    sourceData.images || sourceData.imageUrls || sourceData.productImages
  );
  const primaryImage = cleanUrl(
    sourceData.image || sourceData.imageUrl || sourceData.mainImage || images[0]
  );
  if (primaryImage && !images.includes(primaryImage)) images.unshift(primaryImage);

  // Resolved BEFORE price computation (unlike before) specifically so the
  // freight amount below can be folded into the sale price — see
  // shippingCostBDT. Still the sole delivery-estimate resolution, shared by
  // this import flow and syncAliExpressProduct.
  const aliExpressDeliveryFields = source === "aliexpress"
    ? await resolveAliExpressDeliveryFields(sourceProductId, sourceData)
    : {};

  // AliExpress shipping cost, folded into the sale price before markup —
  // see resolveAliExpressShippingCostBDT()'s own comment for why and how.
  const { shippingCostBDT, shippingCostOriginal, shippingCostCurrency } = resolveAliExpressShippingCostBDT(
    aliExpressDeliveryFields,
    importSettings,
    { sourceProductId }
  );

  const exchangeRate = importSettings.exchangeRate;
  const markupPercent = importSettings.markupPercent;
  const rawPrice = importNumber(
    sourceData.price ?? sourceData.salePrice ?? sourceData.piecePrice,
    0
  );
  const rawMrp = importNumber(
    sourceData.mrp ?? sourceData.oldPrice ?? sourceData.originalPrice ?? rawPrice,
    rawPrice
  );
  const finalPrice = applyImportPriceRule(rawPrice, rawPrice, importSettings, shippingCostBDT);
  const finalMrp = Math.max(finalPrice, applyImportPriceRule(rawMrp, rawPrice, importSettings, shippingCostBDT));

  const mappedVariants = (Array.isArray(sourceData.variants) ? sourceData.variants : [])
    .map((variant) => {
      const item = mapValue(variant);
      return {
        ...item,
        price: applyImportPriceRule(
          item.price ?? item.salePrice ?? rawPrice,
          item.price ?? item.salePrice ?? rawPrice,
          importSettings,
          shippingCostBDT
        ),
        mrp: Math.max(
          applyImportPriceRule(item.price ?? item.salePrice ?? rawPrice, item.price ?? item.salePrice ?? rawPrice, importSettings, shippingCostBDT),
          applyImportPriceRule(item.mrp ?? item.oldPrice ?? item.originalPrice ?? rawMrp, item.price ?? item.salePrice ?? rawPrice, importSettings, shippingCostBDT)
        ),
      };
    });

  const variants = importVariants(mappedVariants, {
    unit: sourceData.unit || "Default",
    price: finalPrice,
    mrp: finalMrp,
    stock: sourceData.stock ?? sourceData.quantity,
  });

  const first = variants[0];
  const stock = variants.reduce((total, variant) => total + importInteger(variant.stock), 0);
  const units = variants.map((variant) => variant.name);
  const slug = importSafeId(sourceData.slug || name, "product");
  const sourceUrl = cleanUrl(sourceData.sourceUrl || sourceData.productUrl || sourceData.url);
  const currency = importSettings.targetCurrency;
  const originalCurrency = textValue(sourceData.currency || body.sourceCurrency || "USD").toUpperCase();
  const searchKeywords = importKeywords(sourceData.searchKeywords, `${name} ${category} ${manufacturer}`);
  const seoTags = importKeywords(sourceData.seoTags, `${name} ${category}`);

  // For AliExpress imports specifically, never let an empty category_name
  // reach resolveProductTaxonomy() as empty anymore — resolveAliExpressCategoryName()
  // (keyword match -> AI suggestion -> fixed fallback bucket, see its own
  // comment above) always produces a real, non-empty candidate name, so the
  // product gets a genuine — and therefore visible — category instead of
  // landing in "Uncategorized" limbo (categoryId: null, no backing category
  // doc, invisible on every home/category section). Non-AliExpress sources
  // (n8n direct, etc.) are untouched: resolveAliExpressCategoryName() short-
  // circuits back to whatever was already provided when rawCategoryName is
  // non-empty, and this block is skipped entirely otherwise.
  let categoryInputForTaxonomy = textValue(sourceData.suggestedCategory || category);
  let categoryResolutionMethod = "provided";
  if (source === "aliexpress") {
    const resolvedCategory = await resolveAliExpressCategoryName(db, {
      title: name,
      rawCategoryName: categoryInputForTaxonomy,
    });
    categoryInputForTaxonomy = resolvedCategory.categoryName;
    categoryResolutionMethod = resolvedCategory.method;
  }

  // Backend imports (AliExpress, n8n, any future import source) always
  // resolve through the shared category/subcategory resolver and follow
  // the admin-tier defaults (visible immediately) — never the restricted
  // vendor-tier defaults, which only ever apply to vendor-initiated saves.
  const taxonomy = await resolveProductTaxonomy(
    db,
    categoryInputForTaxonomy,
    textValue(sourceData.suggestedSubCategory || sourceData.subCategory),
    { source }
  );

  // A keyword/AI/fallback-bucket resolution is still a best guess, not a
  // certainty — flagged for optional admin review via needsCategoryReview,
  // same as the old Uncategorized fallback, but WITHOUT ever leaving
  // categoryId null this time (the product is genuinely visible either way).
  const isLowConfidenceCategoryMatch = ["keyword", "ai_matched", "ai_new", "fallback"].includes(categoryResolutionMethod);
  const needsCategoryReview = isLowConfidenceCategoryMatch ? true : taxonomy.needsCategoryReview;

  const payload = {
    name,
    slug,
    generic: textValue(sourceData.generic),
    manufacturer,
    brand: manufacturer,
    type: textValue(sourceData.type || sourceData.productType),
    productType: textValue(sourceData.productType || sourceData.type),
    strength: textValue(sourceData.strength),
    overview,
    overviewHtml,
    specifications,
    deliveryDays,
    ...aliExpressDeliveryFields,
    // category stays the sole display-name field (backward compatible with
    // every existing category-based product query); when the resolver
    // matched/created a category, its canonical name wins so `category`
    // never drifts from `categoryId`. resolveProductTaxonomy() always
    // returns a non-empty categoryName ("Uncategorized" when nothing
    // resolved), so there's no further fallback needed here.
    category: taxonomy.categoryName,
    needsCategoryReview,
    // Distinct from needsCategoryReview (which flags a low-confidence
    // category guess): needsReview flags that the ENTIRE product was
    // auto-discovered and never chosen by a human — set only by
    // options.needsReview (aliexpressDiscoverProducts / aliexpressScheduledDiscover),
    // same trusted-in-process-caller pattern as forcePublish/forceUnpublish above.
    needsReview: options.needsReview === true,
    categoryResolutionMethod,
    ...(taxonomy.categoryId ? { categoryId: taxonomy.categoryId } : {}),
    ...(taxonomy.subcategoryId ? { subcategoryId: taxonomy.subcategoryId } : {}),
    suggestedCategory: textValue(sourceData.suggestedCategory || category),
    suggestedSubCategory: textValue(sourceData.suggestedSubCategory || sourceData.subCategory),
    image: primaryImage,
    imageUrl: primaryImage,
    images,
    videoUrl: cleanUrl(sourceData.videoUrl),
    youtubeUrl: cleanUrl(sourceData.youtubeUrl || sourceData.videoUrl),
    youtubeVideoId: textValue(sourceData.youtubeVideoId),
    videoThumbnailUrl: cleanUrl(sourceData.videoThumbnailUrl),
    videoDuration: textValue(sourceData.videoDuration),
    hasVideo: Boolean(cleanUrl(sourceData.videoUrl || sourceData.youtubeUrl) || textValue(sourceData.youtubeVideoId)),
    isActive: publish,
    isVisible: publish,
    isPublished: publish,
    showOnHome: boolValue(sourceData.showOnHome, publish),
    isMarketplace: false,
    vendorId: "super_admin",
    sellerId: "super_admin",
    vendorName: "ChalakChar Mart",
    shopName: "ChalakChar Mart",
    approvalStatus: publish ? "approved" : "draft",
    price: first.price,
    piecePrice: first.price,
    oldPrice: first.mrp,
    mrp: first.mrp,
    unit: first.name,
    units,
    stock,
    variants,
    metaTitle: textValue(sourceData.metaTitle, name).slice(0, 70),
    metaDescription: textValue(sourceData.metaDescription, overview || name).slice(0, 155),
    searchKeywords,
    seoTags,
    facebookCaption: textValue(sourceData.facebookCaption, `${name} এখন ChalakChar Mart-এ পাওয়া যাচ্ছে।`),
    whatsappCaption: textValue(sourceData.whatsappCaption, `${name} এখনই অর্ডার করুন।`),
    banglaTitle: textValue(sourceData.banglaTitle),
    banglaDescription: textValue(sourceData.banglaDescription),
    autoMarketingDisabled: !publish || !importSettings.enableMarketing || boolValue(sourceData.autoMarketingDisabled, false),
    aiOptimized: boolValue(sourceData.aiOptimized, false),
    importAiEnabled: importSettings.enableAi,
    importSeoEnabled: importSettings.enableSeo,
    importMarketingEnabled: importSettings.enableMarketing,

    source,
    sourceProductId,
    sourceUrl,
    sourceStoreId: textValue(sourceData.sourceStoreId || sourceData.storeId),
    sourceStoreName: textValue(sourceData.sourceStoreName || sourceData.storeName),
    sourceSkuCount: variants.length,
    syncEnabled: boolValue(body.syncEnabled ?? sourceData.syncEnabled, true),
    importType: textValue(body.importType || sourceData.importType, "automatic"),
    originalCurrency,
    currency,
    originalPrice: rawPrice,
    originalMrp: rawMrp,
    exchangeRate,
    markupPercent,
    shippingCostOriginal,
    shippingCostCurrency,
    shippingCostBDT,
    importedBy: textValue(body.importedBy, "n8n"),
    importedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastPriceSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    lastStockSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  return { source, sourceProductId, publish, payload };
}

// -----------------------------------------------------------------------------
// Category/subcategory resolution for Flutter callers (Admin manual create/
// edit, Admin CSV/JSON import, Vendor create/edit). Backend imports
// (AliExpress/n8n) call resolveProductTaxonomy() directly in-process —
// see buildMarketplaceProductPayload() above. Flutter never writes to the
// `categories`/`subcategories` collections itself; this callable is the
// only path, and it derives the source-based defaults (admin vs. vendor)
// from the AUTHENTICATED CALLER'S OWN ROLE, never from client-supplied
// input, so a vendor client cannot request admin-tier visibility.
// -----------------------------------------------------------------------------
async function requireProductCreatorAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? textValue((userDoc.data() || {}).role) : "";

  if (role === "admin" || role === "superAdmin") return { uid, source: "admin" };
  if (role === "vendor") return { uid, source: "vendor" };

  throw new HttpsError("permission-denied", "Product creation access required.");
}

exports.resolveProductCategory = onCall(async (request) => {
  const { source } = await requireProductCreatorAuth(request);
  const data = mapValue(request.data);
  const categoryName = textValue(data.categoryName || data.category);
  const subCategoryName = textValue(
    data.subCategoryName || data.subcategoryName || data.suggestedSubCategory
  );

  if (!categoryName) {
    throw new HttpsError("invalid-argument", "categoryName is required.");
  }

  const taxonomy = await resolveProductTaxonomy(db, categoryName, subCategoryName, { source });

  logger.info("Category resolved for product save", {
    source,
    categoryId: taxonomy.categoryId,
    subcategoryId: taxonomy.subcategoryId,
    createdCategory: taxonomy.createdCategory,
    createdSubcategory: taxonomy.createdSubcategory,
  });

  return taxonomy;
});

// -----------------------------------------------------------------------------
// AliExpress product details + one-click import engine
// -----------------------------------------------------------------------------

function aliExpressProductId(value) {
  const raw = textValue(value);
  const match = raw.match(/(?:item\/|productId=|product_id=)?(\d{8,})/i);
  return match ? match[1] : "";
}

async function activeAliExpressAccessToken() {
  const ref = db.collection("marketplace_connections").doc("aliexpress");
  let snap = await ref.get();
  if (!snap.exists || textValue(snap.data()?.status) !== "connected") {
    const error = new Error("AliExpress is not connected");
    error.code = "ALIEXPRESS_NOT_CONNECTED";
    throw error;
  }
  let data = snap.data() || {};
  const expiresAt = data.accessExpiresAt?.toMillis?.() || 0;
  if (expiresAt && expiresAt <= Date.now() + 5 * 60 * 1000) {
    await refreshAliExpressConnection(true);
    snap = await ref.get();
    data = snap.data() || {};
  }
  const token = textValue(data.accessToken);
  if (!token) {
    const error = new Error("AliExpress access token is missing");
    error.code = "ALIEXPRESS_TOKEN_MISSING";
    throw error;
  }
  return token;
}

function aliExpressFindObject(root, predicate) {
  const seen = new Set();
  const walk = (value) => {
    if (!value || typeof value !== "object" || seen.has(value)) return null;
    seen.add(value);
    if (predicate(value)) return value;
    for (const child of Object.values(value)) {
      if (Array.isArray(child)) {
        for (const item of child) {
          const found = walk(item);
          if (found) return found;
        }
      } else {
        const found = walk(child);
        if (found) return found;
      }
    }
    return null;
  };
  return walk(root);
}

function stripHtmlToText(html) {
  const raw = textValue(html);
  if (!raw) return "";

  let text = raw
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, "");

  text = text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'");

  return text
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function sanitizeAliExpressHtml(html) {
  const raw = textValue(html);
  if (!raw) return "";
  return raw
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/\son\w+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son\w+\s*=\s*'[^']*'/gi, "")
    .replace(/(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2/gi, '$1="#"')
    // AliExpress detail HTML frequently ships protocol-relative image URLs
    // (src="//ae01.alicdn.com/..."). flutter_html only recognizes an image
    // as loadable when its src has an explicit http/https scheme, so a
    // schemeless "//" URL never even attempts to load. Resolving it to
    // https keeps the exact same asset AliExpress serves.
    .replace(/(href|src)\s*=\s*(["'])\/\/([^"']+)\2/gi, '$1=$2https://$3$2')
    // When an <img> genuinely fails to load (expired/hotlink-protected CDN
    // asset, unsupported format, etc.), flutter_html's own fallback renders
    // the element's raw `alt` attribute as visible text in its place. That
    // is the source of the broken-icon-plus-stray-text seen at the end of
    // some imported descriptions — AliExpress-authored alt text was never
    // meant to be shown to a shopper on its own. Blanking alt keeps a failed
    // image a silent, empty gap instead of leaking that text.
    .replace(/\salt\s*=\s*"[^"]*"/gi, ' alt=""')
    .replace(/\salt\s*=\s*'[^']*'/gi, " alt=''")
    // AliExpress seller-authored text sometimes double-encodes entities
    // (e.g. "&amp;#x27;" instead of "&#x27;"). Collapse one extra layer so
    // the HTML renderer decodes to the actual character, not literal markup.
    .replace(/&amp;(#x?[0-9a-fA-F]+;|[a-zA-Z]+;)/g, "&$1")
    .trim();
}

function aliExpressSpecifications(rawProperties) {
  const list = aliExpressArray(rawProperties);
  const seen = new Set();
  const specs = [];
  for (const entry of list) {
    const item = mapValue(entry);
    const name = textValue(item.attr_name || item.attrName || item.name || item.property_name);
    const value = textValue(item.attr_value || item.attrValue || item.value || item.property_value);
    if (!name || !value || /^[[{]/.test(value)) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    specs.push({ name, value });
  }
  return specs;
}

function aliExpressArray(value) {
  if (Array.isArray(value)) return value;
  if (!value || typeof value !== "object") return [];
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) return child;
  }
  return [];
}

function aliExpressImageList(...values) {
  const output = [];
  const push = (value) => {
    if (Array.isArray(value)) return value.forEach(push);
    if (value && typeof value === "object") return Object.values(value).forEach(push);
    String(value || "").split(/[;,|]/).forEach((part) => {
      const url = cleanUrl(part.trim());
      if (url && !output.includes(url)) output.push(url);
    });
  };
  values.forEach(push);
  return output;
}

function normalizeAliExpressProduct(raw, requestedProductId) {
  const root = mapValue(raw);
  const result = mapValue(root.result || root.data || root);
  const base = aliExpressFindObject(result, (v) =>
    v.product_id !== undefined && (v.subject !== undefined || v.product_status_type !== undefined)
  ) || mapValue(result.ae_item_base_info_dto || result.base_info || result);
  const multimedia = aliExpressFindObject(result, (v) =>
    v.image_urls !== undefined || v.detail_image_urls !== undefined || v.video_url !== undefined
  ) || {};
  const skuContainer = aliExpressFindObject(result, (v) =>
    v.ae_item_sku_info_d_t_o !== undefined || v.skus !== undefined || v.sku_info_list !== undefined
  ) || {};
  const skuRaw = skuContainer.ae_item_sku_info_d_t_o || skuContainer.skus || skuContainer.sku_info_list || [];
  const skus = aliExpressArray(skuRaw).length ? aliExpressArray(skuRaw) : (Array.isArray(skuRaw) ? skuRaw : []);

  const images = aliExpressImageList(
    multimedia.image_urls, multimedia.detail_image_urls,
    base.image_urls, base.product_main_image_url, base.main_image_url
  );
  const variants = skus.map((sku, index) => {
    const item = mapValue(sku);
    const price = importNumber(
      item.offer_sale_price ?? item.sku_price ?? item.sale_price ?? item.price,
      0
    );
    const mrp = importNumber(
      item.sku_price ?? item.original_price ?? item.price ?? price,
      price
    );
    const stock = importInteger(
      item.sku_available_stock ?? item.ipm_sku_stock ?? item.inventory ?? item.stock,
      0
    );
    const variantName = resolveAliExpressVariantName(item);
    const variantImage = resolveAliExpressVariantImage(item, images[0]);
    return {
      id: textValue(item.sku_id || item.id, `sku_${index + 1}`),
      skuId: textValue(item.sku_id || item.id),
      name: variantName || `Option ${index + 1}`,
      price,
      mrp: Math.max(price, mrp),
      stock,
      image: variantImage.image,
      imageUrl: variantImage.imageUrl,
    };
  }).filter((v) => v.price > 0);

  const fallbackPrice = importNumber(
    base.offer_sale_price ?? base.sale_price ?? base.product_price ?? base.price,
    variants[0]?.price || 0
  );
  if (!variants.length && fallbackPrice > 0) {
    variants.push({ id: "default", name: "Default", price: fallbackPrice, mrp: fallbackPrice, stock: importInteger(base.quantity ?? base.stock, 0) });
  }

  const productId = textValue(base.product_id || requestedProductId);
  const detailHtmlRaw = base.detail || base.mobile_detail || base.description;
  const specifications = aliExpressSpecifications(result.ae_item_properties || base.ae_item_properties);
  const deliveryEstimate = parseAliExpressDeliveryEstimate(raw, { referenceDate: new Date() });
  const deliveryDays = deliveryEstimate.deliveryDays;
  return {
    source: "aliexpress",
    sourceProductId: productId,
    productId,
    name: textValue(base.subject || base.product_title || base.title, `AliExpress Product ${productId}`),
    title: textValue(base.subject || base.product_title || base.title, `AliExpress Product ${productId}`),
    description: stripHtmlToText(detailHtmlRaw),
    overview: stripHtmlToText(detailHtmlRaw),
    overviewHtml: sanitizeAliExpressHtml(detailHtmlRaw),
    specifications,
    // No literal-brand fallback here — an AliExpress response missing
    // category_name (mobile-parts/repair-accessory listings routinely omit
    // it) must fall through as empty so resolveProductTaxonomy() flags the
    // product "Uncategorized"/needsCategoryReview instead of it silently
    // landing in a fake "AliExpress" category.
    category: textValue(base.category_name),
    categoryId: textValue(base.category_id),
    currency: textValue(base.currency_code || base.currency, "USD").toUpperCase(),
    image: images[0] || "",
    imageUrl: images[0] || "",
    images,
    videoUrl: cleanUrl(multimedia.video_url || base.video_url),
    sourceUrl: `https://www.aliexpress.com/item/${productId}.html`,
    ratingAvg: importNumber(base.avg_evaluation_rating, 0),
    ratingCount: importInteger(base.evaluation_count, 0),
    deliveryDays,
    deliveryEstimate,
    stock: variants.reduce((sum, v) => sum + importInteger(v.stock, 0), 0),
    price: variants[0]?.price || fallbackPrice,
    mrp: variants[0]?.mrp || fallbackPrice,
    variants,
    rawAliExpress: raw,
  };
}

async function fetchAliExpressProduct(productId, options = {}) {
  const accessToken = await activeAliExpressAccessToken();

  // This app was created in the AliExpress overseas/IOP console.
  // IOP apps use the API-SG gateway. Legacy TOP/Taobao router rejects
  // this six-digit AppKey with isv.appkey-not-exists.
  //
  // aliexpress.ds.product.get is a TOP-migrated (dot-name) API, so it must be
  // called as a `method` body field through the constant /sync endpoint, not
  // as a REST path segment.
  const data = await aliExpressSignedApiRequest(
    "aliexpress.ds.product.get",
    {
      access_token: accessToken,
      product_id: productId,
      ship_to_country: textValue(options.shipToCountry, "BD"),
      target_currency: textValue(options.targetCurrency, "USD"),
      target_language: textValue(options.targetLanguage, "EN"),
    },
    { sync: true }
  );

  // --- DEBUG LOGGING: delivery/logistics fields (discovery only) ---
  // No secrets, API keys, access tokens, or authorization headers are logged
  // here — only product logistics data from the response body. This is a
  // human-readable dump for confirming the real field name; it is NEVER
  // used to select what gets saved (see aliexpress/deliveryEstimate.js).
  try {
    const root = mapValue(data);
    const result = mapValue(root.result || root.data || root);
    logger.info("ALIEXPRESS_DEBUG raw logistics-like fields (discovery only, not used for parsing)", {
      productId,
      knownLogisticsContainer: mapValue(result.logistics_info_dto || result.logistics_info),
      discoveredCandidates: discoverAliExpressDeliveryCandidates(result),
      topLevelResultKeys: Object.keys(result),
    });
  } catch (debugError) {
    logger.warn("ALIEXPRESS_DEBUG logging failed", { productId, message: debugError.message });
  }
  // --- END DEBUG LOGGING ---

  const product = normalizeAliExpressProduct(data, productId);

  logger.info("AliExpress delivery estimate resolved", {
    productId,
    deliverySourceField: product.deliveryEstimate?.deliverySourceField || null,
    deliverySyncStatus: product.deliveryEstimate?.deliverySyncStatus || null,
    estimatedDeliveryDate: product.deliveryEstimate?.estimatedDeliveryDate || null,
    estimatedDeliveryMinDate: product.deliveryEstimate?.estimatedDeliveryMinDate || null,
    estimatedDeliveryMaxDate: product.deliveryEstimate?.estimatedDeliveryMaxDate || null,
    estimatedDeliveryText: product.deliveryEstimate?.estimatedDeliveryText || null,
    deliveryDays: product.deliveryEstimate?.deliveryDays ?? null,
    shippingMethod: product.deliveryEstimate?.shippingMethod || null,
  });

  return product;
}

// -----------------------------------------------------------------------------
// AliExpress delivery-estimate resolution: freight.calculate (primary,
// confirmed working — returns a real day-range like "10-20day") falling
// back to the product.get-based delivery_time day-count if the freight call
// fails or returns no usable option. Shared by both the import flow
// (buildMarketplaceProductPayload) and the sync flow (syncAliExpressProduct)
// — there is only one implementation of this resolution logic.
// -----------------------------------------------------------------------------
async function resolveAliExpressDeliveryFields(productId, product, options = {}) {
  try {
    const accessToken = await activeAliExpressAccessToken();
    const skuId = textValue(options.skuId) || textValue(product?.variants?.[0]?.skuId);

    // No ship-from/origin-country field exists anywhere in the
    // aliexpress.ds.product.get response this project already parses, so
    // "CN" is used as an explicit fallback — the overwhelmingly common
    // AliExpress dropshipping warehouse origin — never silent (logged below).
    const sendGoodsCountryCode = textValue(options.sendGoodsCountryCode, "CN");

    const dto = {
      product_id: Number(productId),
      product_num: 1,
      country_code: textValue(options.countryCode, "BD"),
      send_goods_country_code: sendGoodsCountryCode,
      ...(skuId ? { sku_id: skuId } : {}),
    };

    const data = await aliExpressSignedApiRequest(
      "aliexpress.logistics.buyer.freight.calculate",
      {
        access_token: accessToken,
        param_aeop_freight_calculate_for_buyer_d_t_o: JSON.stringify(dto),
      },
      { sync: true }
    );

    const result = mapValue(data.result || data);
    const selected = selectPreferredFreightOption(result);

    if (selected) {
      logger.info("AliExpress freight delivery estimate resolved", {
        productId,
        serviceName: selected.service_name || null,
        estimatedDeliveryTime: selected.estimated_delivery_time || null,
        freightAmount: mapValue(selected.freight).amount ?? null,
      });
      return buildAliExpressFreightFirestoreFields(selected);
    }

    logger.warn("AliExpress freight.calculate returned no valid shipping option, falling back to product.get delivery_time", { productId });
  } catch (error) {
    logger.warn("AliExpress freight.calculate failed, falling back to product.get delivery_time", {
      productId,
      message: error.message,
      code: error.code || "",
    });
  }

  return buildAliExpressDeliveryFirestoreFields(product?.deliveryEstimate);
}

async function saveImportedMarketplaceProduct(body, options = {}) {
  const { source, sourceProductId, publish, payload } = await buildMarketplaceProductPayload(body, options);
  const productId = marketplaceImportDocumentId(source, sourceProductId);
  const productRef = db.collection("products").doc(productId);
  const mode = textValue(body?.mode, "upsert").toLowerCase();
  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(productRef);
    const exists = snapshot.exists;
    if (exists && mode === "create") { const e = new Error("Product already imported"); e.code = "ALREADY_EXISTS"; throw e; }
    if (!exists && mode === "update") { const e = new Error("Imported product not found"); e.code = "NOT_FOUND"; throw e; }
    const previous = exists ? (snapshot.data() || {}) : {};
    transaction.set(productRef, {
      ...payload,
      importRevision: importInteger(previous.importRevision, 0) + 1,
      ...(exists ? { createdAt: previous.createdAt || admin.firestore.FieldValue.serverTimestamp() } : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
    }, { merge: true });
    return { created: !exists, updated: exists };
  });
  return { productId, source, sourceProductId, publish, ...result, productUrl: `https://chalakcharmart.com/product/${encodeURIComponent(productId)}` };
}

exports.aliexpressProductDetails = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_APP_SECRET], timeoutSeconds: 60, memory: "512MiB" },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (!["GET", "POST"].includes(req.method)) return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    try {
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      if (!expectedKey || !secureKeyEquals(extractImportApiKey(req), expectedKey)) return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      const input = req.method === "GET" ? req.query : mapValue(req.body);
      const productId = aliExpressProductId(input.productId || input.productUrl || input.url);
      if (!productId) return res.status(400).json({ ok: false, error: "PRODUCT_ID_REQUIRED" });
      const product = await fetchAliExpressProduct(productId, input);
      return res.status(200).json({ ok: true, product });
    } catch (error) {
      logger.error("AliExpress product details failed", { message: error.message, code: error.code || "", api: error.api || null });
      return res.status(500).json({ ok: false, error: error.code || "ALIEXPRESS_PRODUCT_FAILED", message: error.message });
    }
  })
);

exports.aliexpressImportByUrl = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_APP_SECRET, "OPENAI_API_KEY"], timeoutSeconds: 120, memory: "512MiB" },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "POST") return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    try {
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      if (!expectedKey || !secureKeyEquals(extractImportApiKey(req), expectedKey)) return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      const body = mapValue(req.body);
      const productId = aliExpressProductId(body.productId || body.productUrl || body.url);
      if (!productId) return res.status(400).json({ ok: false, error: "PRODUCT_ID_REQUIRED" });
      const product = await fetchAliExpressProduct(productId, body);
      const result = await saveImportedMarketplaceProduct({ ...body, source: "aliexpress", sourceProductId: productId, product, importedBy: "aliexpress_api" });
      logger.info("AliExpress one-click import completed", { productId, targetProductId: result.productId, created: result.created, updated: result.updated });
      return res.status(result.created ? 201 : 200).json({ ok: true, ...result });
    } catch (error) {
      const code = textValue(error.code);
      const status = code === "ALREADY_EXISTS" ? 409 : code === "NOT_FOUND" ? 404 : /required|valid variant|price greater/i.test(textValue(error.message)) ? 400 : 500;
      logger.error("AliExpress one-click import failed", { message: error.message, code, api: error.api || null });
      return res.status(status).json({ ok: false, error: code || "ALIEXPRESS_IMPORT_FAILED", message: error.message });
    }
  })
);

const ALIEXPRESS_SYNC_BATCH_SIZE = 8;
const ALIEXPRESS_SYNC_BATCH_DELAY_MS = 1500;

// Bookkeeping/meta keys written by every sync — never part of the
// changed-vs-unchanged comparison (a serverTimestamp always "changes").
const ALIEXPRESS_SYNC_BOOKKEEPING_FIELDS = new Set([
  "lastSyncedAt", "lastPriceSyncAt", "lastStockSyncAt", "updatedAt",
  "deliveryLastSyncedAt", "deliverySource", "deliverySourceField", "deliverySyncStatus",
]);

// Compares proposed field updates against the product's existing data to
// decide whether this sync actually changed anything worth counting.
// Firestore Timestamps are normalized to milliseconds before comparing —
// never compared by object identity/reference.
function aliExpressSyncHasRealChange(existing, updates) {
  for (const [key, value] of Object.entries(updates)) {
    if (ALIEXPRESS_SYNC_BOOKKEEPING_FIELDS.has(key)) continue;
    const prev = existing[key];
    if (value instanceof admin.firestore.Timestamp) {
      const prevMs = prev instanceof admin.firestore.Timestamp ? prev.toMillis() : null;
      if (prevMs !== value.toMillis()) return true;
    } else if (prev !== value) {
      return true;
    }
  }
  return false;
}

// Refreshes price/oldPrice/stock/inStock and delivery fields from AliExpress
// for one already-imported product. Deliberately leaves everything else
// (variants, description, images, category...) untouched — those may be
// hand-edited in the admin panel and this sync must not clobber them.
//
// Delivery fields specifically: buildAliExpressDeliveryFirestoreFields()
// only ever includes a key when this fetch actually produced a value for it,
// so a previously-saved exact date is never overwritten by a synthetic
// deliveryDays-derived date, and is never erased just because AliExpress
// temporarily returned no delivery data this run.
async function syncAliExpressProduct(productSnap, importSettings) {
  const productData = productSnap.data() || {};
  const sourceProductId = textValue(productData.sourceProductId);
  if (!sourceProductId) {
    const error = new Error("Product is missing sourceProductId");
    error.code = "MISSING_SOURCE_PRODUCT_ID";
    error.skip = true;
    throw error;
  }

  logger.info("AliExpress sync: fetching product", { productId: productSnap.id, sourceProductId });
  const fresh = await fetchAliExpressProduct(sourceProductId, { targetCurrency: "USD" });

  // Resolved before price so the freight amount can be folded into it — see
  // resolveAliExpressShippingCostBDT()'s own comment.
  const deliveryFields = await resolveAliExpressDeliveryFields(sourceProductId, fresh);
  const { shippingCostBDT, shippingCostOriginal, shippingCostCurrency } = resolveAliExpressShippingCostBDT(
    deliveryFields,
    importSettings,
    { sourceProductId }
  );

  const finalPrice = applyImportPriceRule(fresh.price, fresh.price, importSettings, shippingCostBDT);
  const finalMrp = Math.max(finalPrice, applyImportPriceRule(fresh.mrp, fresh.price, importSettings, shippingCostBDT));
  const stock = importInteger(fresh.stock, 0);

  // originalPrice/originalMrp/exchangeRate/markupPercent/shippingCost* are
  // the inputs applyImportPriceRule() just used to compute finalPrice above —
  // previously only set at initial import and never refreshed here, so they
  // silently went stale (e.g. still showing the exchangeRate from months ago)
  // even though price/oldPrice were correctly recomputed every sync. Written
  // every sync now so they always describe how the CURRENT price/oldPrice
  // were actually derived.
  const updates = {
    price: finalPrice,
    oldPrice: finalMrp,
    stock,
    inStock: stock > 0,
    originalPrice: fresh.price,
    originalMrp: fresh.mrp,
    exchangeRate: importSettings.exchangeRate,
    markupPercent: importSettings.markupPercent,
    shippingCostBDT,
    shippingCostOriginal,
    shippingCostCurrency,
    ...deliveryFields,
  };

  // Self-heal: a product that has never gotten a real category (categoryId
  // still null — true "Uncategorized" limbo from before this resolver
  // existed/improved) gets one more resolution attempt here, each sync
  // cycle, until it succeeds. Gated on categoryId being falsy specifically
  // (not just needsCategoryReview) so a product an admin already manually
  // re-filed is never touched — a manual category edit always sets a real
  // categoryId, even though nothing currently clears the stale
  // needsCategoryReview flag itself. This is the ONLY category-related
  // write this function makes; every other product's category/categoryId/
  // subcategoryId stays untouched exactly as before.
  if (!productData.categoryId && productData.needsCategoryReview === true) {
    try {
      const resolvedCategory = await resolveAliExpressCategoryName(db, {
        title: textValue(fresh.name || productData.name),
        rawCategoryName: textValue(fresh.category),
      });
      const taxonomy = await resolveProductTaxonomy(db, resolvedCategory.categoryName, "", { source: "aliexpress" });

      if (taxonomy.categoryId) {
        const isLowConfidenceCategoryMatch = ["keyword", "ai_matched", "ai_new", "fallback"].includes(resolvedCategory.method);
        updates.category = taxonomy.categoryName;
        updates.categoryId = taxonomy.categoryId;
        updates.categoryResolutionMethod = resolvedCategory.method;
        updates.needsCategoryReview = isLowConfidenceCategoryMatch;
        logger.info("AliExpress sync: self-healed Uncategorized product", {
          productId: productSnap.id,
          sourceProductId,
          category: taxonomy.categoryName,
          method: resolvedCategory.method,
        });
      }
    } catch (error) {
      logger.warn("AliExpress sync: category self-heal failed, left untouched", {
        productId: productSnap.id,
        sourceProductId,
        message: error.message,
      });
    }
  }

  const changed = aliExpressSyncHasRealChange(productData, updates);

  updates.lastSyncedAt = admin.firestore.FieldValue.serverTimestamp();
  updates.lastPriceSyncAt = admin.firestore.FieldValue.serverTimestamp();
  updates.lastStockSyncAt = admin.firestore.FieldValue.serverTimestamp();
  updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

  await productSnap.ref.update(updates);
  logger.info(`AliExpress sync: product ${changed ? "updated" : "unchanged"}`, {
    productId: productSnap.id,
    sourceProductId,
    price: finalPrice,
    oldPrice: finalMrp,
    stock,
    deliverySyncStatus: updates.deliverySyncStatus,
    deliverySourceField: updates.deliverySourceField,
    changed,
  });
  return { changed };
}

// Single shared sync core used by BOTH the manual HTTP endpoint and the
// scheduled job below — there is intentionally only one implementation of
// the query+batch+log loop.
async function runAliExpressSync({ requireSyncEnabled }) {
  let query = db.collection("products").where("source", "==", "aliexpress");
  if (requireSyncEnabled) query = query.where("syncEnabled", "==", true);
  const snapshot = await query.get();
  const docs = snapshot.docs;
  const totalChecked = docs.length;
  let updated = 0;
  let unchanged = 0;
  let skipped = 0;
  let failed = 0;
  const errors = [];

  logger.info("AliExpress sync: starting", { totalChecked, requireSyncEnabled });
  const importSettings = await marketplaceImportSettings("aliexpress");

  for (let i = 0; i < docs.length; i += ALIEXPRESS_SYNC_BATCH_SIZE) {
    const batch = docs.slice(i, i + ALIEXPRESS_SYNC_BATCH_SIZE);
    logger.info("AliExpress sync: processing batch", {
      batchStart: i,
      batchSize: batch.length,
      totalChecked,
    });

    await Promise.all(batch.map(async (docSnap) => {
      try {
        const result = await syncAliExpressProduct(docSnap, importSettings);
        if (result.changed) updated++; else unchanged++;
      } catch (error) {
        const entry = {
          productId: docSnap.id,
          sourceProductId: textValue(docSnap.data()?.sourceProductId),
          error: error.code || "SYNC_FAILED",
          message: error.message || String(error),
        };
        errors.push(entry);
        if (error.skip) {
          skipped++;
          logger.warn("AliExpress sync: product skipped", entry);
        } else {
          failed++;
          logger.error("AliExpress sync: product failed", entry);
        }
      }
    }));

    const isLastBatch = i + ALIEXPRESS_SYNC_BATCH_SIZE >= docs.length;
    if (!isLastBatch) await sleep(ALIEXPRESS_SYNC_BATCH_DELAY_MS);
  }

  const summary = { totalChecked, updated, unchanged, skipped, failed };
  logger.info("AliExpress sync: completed", summary);
  return { ...summary, errors };
}

exports.aliexpressSyncAllProducts = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_APP_SECRET, "OPENAI_API_KEY"], timeoutSeconds: 540, memory: "512MiB" },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (!["GET", "POST"].includes(req.method)) return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    try {
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      if (!expectedKey || !secureKeyEquals(extractImportApiKey(req), expectedKey)) return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      // Manual/admin-triggered: syncs every AliExpress product regardless of
      // syncEnabled, since an explicit admin action overrides that flag.
      const result = await runAliExpressSync({ requireSyncEnabled: false });
      return res.status(200).json({ ok: true, ...result });
    } catch (error) {
      logger.error("AliExpress sync all failed", { message: error.message, code: error.code || "" });
      return res.status(500).json({ ok: false, error: error.code || "ALIEXPRESS_SYNC_FAILED", message: error.message });
    }
  })
);

// -----------------------------------------------------------------------------
// Scheduled AliExpress job overlap lock — shared by aliexpressScheduledSync
// (every 6 hours) and aliexpressScheduledDiscover (daily) below, one
// system_locks/{jobName} doc per job so the two never contend on the same lock.
//
// Lock is transaction-acquired and owner-token based: each invocation mints
// a random lockOwner, only takes the lock if it's free or the previous
// holder's expiresAt has passed (stale-lock recovery), and on release only
// clears the lock if lockOwner still matches its own token — so a
// slow-finishing run whose lock already expired and was reacquired by a
// newer run can never delete that newer run's lock out from under it.
// -----------------------------------------------------------------------------
const ALIEXPRESS_SYNC_LOCK_TTL_MS = 15 * 60 * 1000; // well beyond the 540s function timeout

function aliExpressJobLockRef(jobName) {
  return db.collection("system_locks").doc(jobName);
}

async function acquireAliExpressJobLock(jobName, ttlMs = ALIEXPRESS_SYNC_LOCK_TTL_MS) {
  const lockOwner = `${Date.now()}_${crypto.randomBytes(6).toString("hex")}`;
  const lockRef = aliExpressJobLockRef(jobName);
  const acquired = await db.runTransaction(async (tx) => {
    const snap = await tx.get(lockRef);
    const data = snap.exists ? (snap.data() || {}) : {};
    const expiresAtMs = data.expiresAt?.toMillis?.() || 0;
    const isHeld = data.locked === true && expiresAtMs > Date.now();
    if (isHeld) return false;
    tx.set(lockRef, {
      locked: true,
      lockOwner,
      lockedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + ttlMs),
    });
    return true;
  });
  return acquired ? lockOwner : null;
}

async function releaseAliExpressJobLock(jobName, lockOwner) {
  const lockRef = aliExpressJobLockRef(jobName);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(lockRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (data.lockOwner !== lockOwner) return; // lock now belongs to a newer run — leave it alone
    tx.set(lockRef, { locked: false, releasedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  });
}

async function acquireAliExpressSyncLock() {
  return acquireAliExpressJobLock("aliexpressScheduledSync");
}

async function releaseAliExpressSyncLock(lockOwner) {
  return releaseAliExpressJobLock("aliexpressScheduledSync", lockOwner);
}

exports.aliexpressScheduledSync = onSchedule(
  { schedule: "every 6 hours", secrets: [ALIEXPRESS_APP_SECRET, "OPENAI_API_KEY"], timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const lockOwner = await acquireAliExpressSyncLock();
    if (!lockOwner) {
      logger.warn("AliExpress scheduled sync: previous run still in progress (lock held), skipping this tick");
      return;
    }
    try {
      logger.info("AliExpress scheduled sync: starting");
      const result = await runAliExpressSync({ requireSyncEnabled: true });
      logger.info("AliExpress scheduled sync: finished", result);
    } catch (error) {
      logger.error("AliExpress scheduled sync: fatal error", { message: error.message || String(error) });
    } finally {
      await releaseAliExpressSyncLock(lockOwner);
    }
  }
);

// -----------------------------------------------------------------------------
// One-time AliExpress variant-image backfill.
//
// Updates ONLY variants[].image / variants[].imageUrl on already-imported
// AliExpress products — never price, stock, name, variant order, or any
// other product field. Matching is confident-only (see
// aliexpress/variantMatch.js): sourceSkuId -> skuId -> variantId -> id ->
// exact cleaned name, never fuzzy/substring/index matching. Concurrency
// safety: patches are computed against the variants read at the start of
// the run, then re-applied against a FRESH re-read of each product
// immediately before writing (see applyVariantImagePatchesToLatest), so a
// concurrent admin edit is never overwritten.
// -----------------------------------------------------------------------------
const ALIEXPRESS_BACKFILL_DEFAULT_LIMIT = 50;
const ALIEXPRESS_BACKFILL_MAX_LIMIT = 200;
const ALIEXPRESS_BACKFILL_WRITE_BATCH_LIMIT = 400; // stays under Firestore's 500-op cap

async function aliexpressBackfillVariantImagesHandler(options = {}) {
  const dryRun = options.dryRun !== false; // default true
  const limit = Math.min(
    Math.max(importInteger(options.limit, ALIEXPRESS_BACKFILL_DEFAULT_LIMIT), 1),
    ALIEXPRESS_BACKFILL_MAX_LIMIT
  );

  let productDocs = [];
  if (textValue(options.productId)) {
    const snap = await db.collection("products").doc(textValue(options.productId)).get();
    if (snap.exists) productDocs = [snap];
  } else {
    let query = db.collection("products").where("source", "==", "aliexpress");
    if (textValue(options.sourceProductId)) {
      query = query.where("sourceProductId", "==", textValue(options.sourceProductId));
    }
    const snapshot = await query.limit(limit).get();
    productDocs = snapshot.docs;
  }

  const scannedProducts = productDocs.length;
  let updatedProducts = 0;
  let updatedVariants = 0;
  let skippedVariants = 0;
  let failedProducts = 0;
  const results = [];

  let batch = db.batch();
  let batchOps = 0;

  // Only ever called sequentially, between chunks (never from within the
  // concurrent Promise.all below) — no risk of a double-commit/reset race.
  async function commitBatchIfNeeded(force = false) {
    if (batchOps === 0) return;
    if (force || batchOps >= ALIEXPRESS_BACKFILL_WRITE_BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }

  logger.info("AliExpress variant image backfill: starting", { scannedProducts, dryRun, limit });

  for (let i = 0; i < productDocs.length; i += ALIEXPRESS_SYNC_BATCH_SIZE) {
    const chunk = productDocs.slice(i, i + ALIEXPRESS_SYNC_BATCH_SIZE);

    await Promise.all(chunk.map(async (snap) => {
      const productData = snap.data() || {};
      const sourceProductId = textValue(productData.sourceProductId);
      const productResult = {
        productId: snap.id,
        sourceProductId,
        status: "skipped",
        updatedVariants: 0,
        skippedVariants: [],
      };

      try {
        if (!sourceProductId) {
          productResult.reason = "MISSING_SOURCE_PRODUCT_ID";
          return;
        }

        const fresh = await fetchAliExpressProduct(sourceProductId, { targetCurrency: "USD" });
        const existingVariants = Array.isArray(productData.variants) ? productData.variants : [];
        const { patches, skipped } = computeVariantImagePatches(existingVariants, fresh.variants || []);
        productResult.skippedVariants = skipped;

        if (!patches.length) {
          productResult.status = "unchanged";
          return;
        }

        if (dryRun) {
          productResult.status = "would_update";
          productResult.updatedVariants = patches.length;
          return;
        }

        // Re-read the latest doc right before writing — see module doc.
        const latestSnap = await snap.ref.get();
        const latestData = latestSnap.data() || {};
        const latestVariants = Array.isArray(latestData.variants) ? latestData.variants : [];
        const { updatedVariants: patchedVariants, appliedCount, reappliedSkipped } =
          applyVariantImagePatchesToLatest(latestVariants, patches);

        productResult.skippedVariants = [...productResult.skippedVariants, ...reappliedSkipped];

        if (appliedCount === 0) {
          productResult.status = "skipped_stale";
          return;
        }

        batch.update(snap.ref, { variants: patchedVariants });
        batchOps += 1;

        productResult.status = "updated";
        productResult.updatedVariants = appliedCount;
      } catch (error) {
        productResult.status = "failed";
        productResult.error = error.message || String(error);
        logger.error("AliExpress variant image backfill: product failed", {
          productId: snap.id,
          sourceProductId,
          message: productResult.error,
        });
      } finally {
        if (productResult.status === "updated" || productResult.status === "would_update") updatedProducts += 1;
        if (productResult.status === "failed") failedProducts += 1;
        skippedVariants += productResult.skippedVariants.length;
        updatedVariants += productResult.updatedVariants;
        results.push(productResult);
      }
    }));

    // Sequential — safe to commit here even though the map() above ran concurrently.
    if (!dryRun) await commitBatchIfNeeded();

    const isLastChunk = i + ALIEXPRESS_SYNC_BATCH_SIZE >= productDocs.length;
    if (!isLastChunk) await sleep(ALIEXPRESS_SYNC_BATCH_DELAY_MS);
  }

  if (!dryRun) await commitBatchIfNeeded(true);

  const summary = { scannedProducts, updatedProducts, updatedVariants, skippedVariants, failedProducts, dryRun };
  logger.info("AliExpress variant image backfill: completed", summary);
  return { ...summary, results };
}

exports.aliexpressBackfillVariantImages = onRequest(
  { secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_APP_SECRET], timeoutSeconds: 540, memory: "512MiB" },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (!["GET", "POST"].includes(req.method)) return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    try {
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      if (!expectedKey || !secureKeyEquals(extractImportApiKey(req), expectedKey)) return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
      const input = req.method === "GET" ? req.query : mapValue(req.body);
      const result = await aliexpressBackfillVariantImagesHandler({
        productId: input.productId,
        sourceProductId: input.sourceProductId,
        dryRun: input.dryRun !== undefined ? boolValue(input.dryRun, true) : true,
        limit: input.limit,
      });
      return res.status(200).json({ ok: true, ...result });
    } catch (error) {
      logger.error("AliExpress variant image backfill failed", { message: error.message, code: error.code || "" });
      return res.status(500).json({ ok: false, error: error.code || "ALIEXPRESS_BACKFILL_FAILED", message: error.message });
    }
  })
);

// -----------------------------------------------------------------------------
// AliExpress affiliate discovery (Feature A: aliexpressDiscoverProducts,
// on-demand, and aliexpressScheduledDiscover, daily/unattended) + search-miss
// on-demand import (Feature B: aliexpressSearchImport).
//
// All three call AliExpress's *affiliate* product-search APIs
// (aliexpress.affiliate.hotproduct.query / aliexpress.affiliate.product.query),
// which require a tracking_id issued by AliExpress's affiliate program — a
// separate approval from the Dropshipping API AppKey/App Secret already
// configured for the rest of this file. Until that approval exists,
// activeAliExpressTrackingId() resolves to an empty string,
// aliExpressSignedApiRequest's own param filter silently drops the empty
// tracking_id, and AliExpress's API rejects the call with a normal error —
// surfaced as an ok:false JSON response like any other AliExpress API
// failure, not a crash or a deploy blocker. Set
// settings/app.importSettings.aliexpressTrackingId once the real value is
// available; no code changes needed after that.
//
// Feature A is unattended and unsupervised (nobody asked for these specific
// products, unlike Feature B which reacts to an actual shopper's search), so
// everything it saves goes in via saveImportedMarketplaceProduct with
// { forceUnpublish: true, needsReview: true } — see buildMarketplaceProductPayload
// — regardless of the admin's global importSettings.autoPublish policy. An
// admin must review and manually publish each one from the Admin Panel.
// -----------------------------------------------------------------------------
async function activeAliExpressTrackingId() {
  const snapshot = await db.collection("settings").doc("app").get();
  const root = snapshot.exists ? mapValue(snapshot.data()) : {};
  return textValue(mapValue(root.importSettings).aliexpressTrackingId);
}

// -----------------------------------------------------------------------------
// aliexpressSearchImport rate limiting — reads from the same settings/app
// doc/importSettings nesting every other import knob already lives under
// (see activeAliExpressTrackingId above, marketplaceImportSettings below),
// so limits can be tuned from the admin panel without a redeploy.
// searchImportRateLimitEnabled is an emergency off-switch: if the limits
// ever produce false positives against real shoppers, it can be disabled
// the same way, no redeploy required.
// -----------------------------------------------------------------------------
// Delegates to parseRateLimitSettings() in aliexpress/searchImportRateLimit.js
// for the actual defaulting logic — this stays a thin fetch so the defaults
// live in one testable, dependency-free place.
async function searchImportRateLimitSettings() {
  const snapshot = await db.collection("settings").doc("app").get();
  const root = snapshot.exists ? mapValue(snapshot.data()) : {};
  return parseRateLimitSettings(mapValue(root.importSettings));
}

// Thin wrapper: fetches current settings/IP, then delegates the actual
// two-layer (IP + uid) decision to evaluateSearchImportRateLimit() in
// aliexpress/searchImportRateLimit.js, which is the tested, dependency-free
// copy of this logic.
async function enforceSearchImportRateLimit(req, uid) {
  const settings = await searchImportRateLimitSettings();
  if (!settings.enabled) return null;

  return evaluateSearchImportRateLimit(db, {
    ip: extractClientIp(req),
    uid,
    ipLimitPerHour: settings.ipLimitPerHour,
    uidLimitPerHour: settings.uidLimitPerHour,
    burstLimit: settings.burstLimit,
    burstWindowMs: settings.burstWindowMs,
  });
}

// Extracts the flat list of affiliate product entries from an
// aliexpress.affiliate.*.query response. AliExpress's published affiliate
// API docs describe the result as `{ products: { product: [...] } }`, but
// this hasn't been confirmed against a real response yet (blocked on
// tracking_id — see above), so this defensively tries every plausible
// container shape via the existing aliExpressArray() helper (already used
// the same way for aliexpress.ds.product.get's SKU list) instead of
// assuming one exact path. Once a real tracking_id is set and this has run
// against live data, check the "AliExpress affiliate query result shape"
// log line below against what actually came back.
function extractAliExpressAffiliateProducts(result) {
  const root = mapValue(result);
  const candidate = root.products ?? root.product ?? root.result ?? root;
  return aliExpressArray(candidate).map(mapValue).filter((item) => Object.keys(item).length > 0);
}

function aliExpressAffiliateProductId(item) {
  return textValue(
    item.product_id || item.productId || aliExpressProductId(item.product_detail_url || item.promotion_link)
  );
}

function aliExpressAffiliateProductUrl(item) {
  const directUrl = cleanUrl(item.product_detail_url || item.promotion_link);
  if (directUrl) return directUrl;
  const productId = aliExpressAffiliateProductId(item);
  return productId ? `https://www.aliexpress.com/item/${productId}.html` : "";
}

// Comma/newline-separated string OR array of search keywords — same shape
// convention as importStringList(), but without its cleanUrl() step (these
// are search terms, not URLs).
function discoverKeywordList(value) {
  const raw = Array.isArray(value) ? value : textValue(value) ? String(value).split(/[\n,]+/) : [];
  return [...new Set(raw.map((item) => textValue(item)).filter(Boolean))];
}

const ALIEXPRESS_DISCOVER_DEFAULT_LIMIT = 15;
// Hard ceiling regardless of what settings/body ask for — an unattended
// daily job must never dump more than a handful of unreviewed products into
// the catalog in one run, even if someone fat-fingers the Firestore setting.
const ALIEXPRESS_DISCOVER_MAX_LIMIT = 20;
// Spacing between per-item AliExpress detail-fetch+save calls, same spirit
// as ALIEXPRESS_SYNC_BATCH_DELAY_MS above.
const ALIEXPRESS_DISCOVER_ITEM_DELAY_MS = 500;

// Feature A only ever sources mobile and laptop spare parts — never a
// general/broad "hot products" sweep across all of AliExpress. This is the
// code-level default (used whenever settings/app.importSettings.
// aliexpressDiscoverKeywords is empty/unset) so the unattended daily job
// stays scoped to this niche even on a fresh project or a cleared Firestore
// setting; an admin can still narrow/reorder the list from the Admin Panel
// (stored at the same path, no redeploy needed) but can't widen discovery
// into unrelated categories by clearing it.
const ALIEXPRESS_DISCOVER_DEFAULT_KEYWORDS = [
  "charger",
  "phone cable",
  "mobile motherboard",
  "mobile display digitizer",
  "phone back cover",
  "mobile battery",
  "camera module",
  "charging port flex",
  "speaker mic flex",
  "laptop ssd",
  "laptop ram",
  "laptop keyboard",
  "laptop battery",
  "laptop charger adapter",
  "laptop cooling fan",
  "laptop screen display",
  "laptop hinge",
];

// settings/app.importSettings.aliexpress* knobs specific to the discovery
// pipeline — same importSettings nesting as every other import knob (see
// activeAliExpressTrackingId, marketplaceImportSettings), tunable from
// Firestore without a redeploy. No categoryId knob — Feature A is keyword-only
// (see ALIEXPRESS_DISCOVER_DEFAULT_KEYWORDS above); AliExpress category-id
// based browsing would reintroduce exactly the general/broad sweep this
// pipeline must never do.
async function aliexpressDiscoverSettings() {
  const snapshot = await db.collection("settings").doc("app").get();
  const root = snapshot.exists ? mapValue(snapshot.data()) : {};
  const settings = mapValue(root.importSettings);
  const configuredKeywords = discoverKeywordList(settings.aliexpressDiscoverKeywords);
  return {
    keywords: configuredKeywords.length ? configuredKeywords : ALIEXPRESS_DISCOVER_DEFAULT_KEYWORDS,
    limit: Math.min(
      Math.max(importInteger(settings.aliexpressDiscoverDailyLimit, ALIEXPRESS_DISCOVER_DEFAULT_LIMIT), 1),
      ALIEXPRESS_DISCOVER_MAX_LIMIT
    ),
    // Off by default. This project has no separate staging Firebase project,
    // so this flag is the staging gate for aliexpressScheduledDiscover: the
    // scheduled job deploys and fires daily, but no-ops until an admin flips
    // this on in Firestore after a manual dry-run (and optionally a small
    // live test) via aliexpressDiscoverProducts looks right.
    scheduleEnabled: boolValue(settings.aliexpressDiscoverScheduleEnabled, false),
  };
}

// Shared core for both the manual/on-demand HTTP endpoint
// (aliexpressDiscoverProducts) and the daily scheduled job
// (aliexpressScheduledDiscover) — there is intentionally only one
// implementation of the discover -> dedupe -> fetch -> import loop.
//
// dryRun (default true) skips fetchAliExpressProduct and
// saveImportedMarketplaceProduct entirely — the only Firestore access in
// dry-run mode is the read-only products/{id} existence check, so a preview
// run is always side-effect-free.
async function runAliExpressDiscover(options = {}) {
  const settings = await aliexpressDiscoverSettings();
  const keywords = Array.isArray(options.keywords) && options.keywords.length ? options.keywords : settings.keywords;
  const limit = Math.min(
    Math.max(importInteger(options.limit, settings.limit), 1),
    ALIEXPRESS_DISCOVER_MAX_LIMIT
  );
  const dryRun = options.dryRun !== false; // default true — same safety-first default as aliexpressBackfillVariantImagesHandler

  if (!keywords.length) {
    logger.warn("AliExpress discover: no keywords configured, skipping", { dryRun });
    return { keywordsChecked: 0, discovered: 0, imported: 0, skippedExisting: 0, failed: 0, limit, dryRun, results: [] };
  }

  const trackingId = await activeAliExpressTrackingId();
  const appKey = textValue(ALIEXPRESS_AFFILIATE_APP_KEY.value());
  const appSecret = textValue(ALIEXPRESS_AFFILIATE_APP_SECRET.value());

  let discovered = 0;
  let imported = 0;
  let skippedExisting = 0;
  let failed = 0;
  const results = [];

  for (const keyword of keywords) {
    if (imported >= limit) break;

    let items = [];
    try {
      const apiResult = await aliExpressSignedApiRequest(
        "aliexpress.affiliate.hotproduct.query",
        {
          keywords: keyword,
          page_size: 20,
          tracking_id: trackingId,
          target_currency: "USD",
          target_language: "EN",
          ship_to_country: "BD",
        },
        { sync: true, appKey, appSecret }
      );
      items = extractAliExpressAffiliateProducts(apiResult);
      discovered += items.length;
    } catch (error) {
      failed += 1;
      results.push({ keyword, status: "keyword_query_failed", message: error.message });
      logger.warn("AliExpress discover: keyword query failed, continuing", { keyword, message: error.message });
      continue;
    }

    for (const item of items) {
      if (imported >= limit) break;

      const sourceProductId = aliExpressAffiliateProductId(item);
      if (!sourceProductId) continue;

      const productId = marketplaceImportDocumentId("aliexpress", sourceProductId);
      const existingSnap = await db.collection("products").doc(productId).get();
      if (existingSnap.exists) {
        skippedExisting += 1;
        continue;
      }

      if (dryRun) {
        imported += 1;
        results.push({ keyword, sourceProductId, productId, productUrl: aliExpressAffiliateProductUrl(item), status: "would_import" });
        continue;
      }

      try {
        const product = await fetchAliExpressProduct(sourceProductId);
        const saved = await saveImportedMarketplaceProduct(
          { source: "aliexpress", sourceProductId, product, importedBy: "aliexpress_discover", mode: "create" },
          { forceUnpublish: true, needsReview: true }
        );
        imported += 1;
        results.push({ keyword, sourceProductId, productId: saved.productId, status: "imported" });
      } catch (error) {
        if (error.code === "ALREADY_EXISTS") {
          skippedExisting += 1;
        } else {
          failed += 1;
          results.push({ keyword, sourceProductId, status: "failed", message: error.message });
          logger.warn("AliExpress discover: one product failed, continuing", { keyword, sourceProductId, message: error.message });
        }
      } finally {
        // Paces real AliExpress API calls only — the dry-run/skip/already-
        // exists paths above never reach fetchAliExpressProduct, so there's
        // nothing to space out there.
        await sleep(ALIEXPRESS_DISCOVER_ITEM_DELAY_MS);
      }
    }
  }

  const summary = {
    keywordsChecked: keywords.length,
    discovered,
    imported,
    skippedExisting,
    failed,
    limit,
    dryRun,
    trackingIdConfigured: Boolean(trackingId),
  };
  logger.info("AliExpress discover: completed", summary);
  return { ...summary, results };
}

exports.aliexpressDiscoverProducts = onRequest(
  {
    secrets: [PRODUCT_IMPORT_API_KEY, ALIEXPRESS_AFFILIATE_APP_KEY, ALIEXPRESS_AFFILIATE_APP_SECRET, ALIEXPRESS_APP_SECRET, "OPENAI_API_KEY"],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "POST") return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
    try {
      const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
      if (!expectedKey || !secureKeyEquals(extractImportApiKey(req), expectedKey)) return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });

      const body = mapValue(req.body);
      // Manual/on-demand trigger for the same discover+import pipeline the
      // daily aliexpressScheduledDiscover job runs — lets an admin (or a
      // test call) preview or force a run without waiting for the schedule.
      // dryRun defaults to true: hitting this endpoint must never write a
      // product by accident.
      const result = await runAliExpressDiscover({
        dryRun: body.dryRun !== undefined ? boolValue(body.dryRun, true) : true,
        keywords: body.keywords !== undefined ? discoverKeywordList(body.keywords) : undefined,
        limit: body.limit ?? body.page_size,
      });

      return res.status(200).json({ ok: true, ...result });
    } catch (error) {
      logger.error("AliExpress discover products failed", { message: error.message, code: error.code || "", api: error.api || null });
      return res.status(500).json({ ok: false, error: error.code || "ALIEXPRESS_DISCOVER_FAILED", message: error.message });
    }
  })
);

// -----------------------------------------------------------------------------
// Scheduled AliExpress discovery (once daily) — Cloud Scheduler-driven, no
// n8n involved. Reuses the aliexpressScheduledSync overlap-lock machinery
// (see acquireAliExpressJobLock above) under its own job name so the two
// scheduled jobs never contend on the same lock doc, and stays inert
// (scheduleEnabled defaults to false — see aliexpressDiscoverSettings) until
// an admin has confirmed a dry-run via aliexpressDiscoverProducts looks right.
// -----------------------------------------------------------------------------
exports.aliexpressScheduledDiscover = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "Asia/Dhaka",
    secrets: [ALIEXPRESS_AFFILIATE_APP_KEY, ALIEXPRESS_AFFILIATE_APP_SECRET, ALIEXPRESS_APP_SECRET, "OPENAI_API_KEY"],
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const settings = await aliexpressDiscoverSettings();
    if (!settings.scheduleEnabled) {
      logger.info("AliExpress scheduled discover: disabled via importSettings.aliexpressDiscoverScheduleEnabled, skipping");
      return;
    }

    const lockOwner = await acquireAliExpressJobLock("aliexpressScheduledDiscover");
    if (!lockOwner) {
      logger.warn("AliExpress scheduled discover: previous run still in progress (lock held), skipping this tick");
      return;
    }
    try {
      logger.info("AliExpress scheduled discover: starting");
      const result = await runAliExpressDiscover({ dryRun: false });
      logger.info("AliExpress scheduled discover: finished", result);
    } catch (error) {
      logger.error("AliExpress scheduled discover: fatal error", { message: error.message || String(error) });
    } finally {
      await releaseAliExpressJobLock("aliexpressScheduledDiscover", lockOwner);
    }
  }
);

// -----------------------------------------------------------------------------
// searchImportLog/{docId} — one doc per normalized search query, used to
// dedupe concurrent search-miss import requests and cache the outcome for
// 24h so the same miss doesn't re-trigger an AliExpress call on every
// shopper who searches it. docId is the same normalization used for the
// dedupe key everywhere else the query text itself would be unsafe as a
// Firestore doc ID (matches importSafeId's existing lowercase/collapse-to-_
// convention used throughout this file).
// -----------------------------------------------------------------------------
const SEARCH_IMPORT_STALE_MS = 24 * 60 * 60 * 1000;

function searchImportLogDocId(query) {
  return importSafeId(query, "query");
}

// Firestore-only (no external network calls) so this is safe to run inside
// a transaction — Firestore may retry a transaction on contention, and an
// AliExpress API call must never be retried implicitly like that. Returns
// which caller "won" the right to actually call AliExpress for this query;
// losers get the cached/in-flight outcome without ever touching the network.
async function claimSearchImportSlot(query, uid) {
  const docId = searchImportLogDocId(query);
  const ref = db.collection("searchImportLog").doc(docId);

  const outcome = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const data = snap.exists ? (snap.data() || {}) : null;

    if (data) {
      const requestedAtMs = data.requestedAt?.toMillis?.() || 0;
      const isFresh = Date.now() - requestedAtMs < SEARCH_IMPORT_STALE_MS;

      if (data.status === "pending" && isFresh) {
        if (uid) transaction.update(ref, { waitingUserIds: admin.firestore.FieldValue.arrayUnion(uid) });
        return { docId, won: false, status: "already_pending", productIds: [] };
      }

      if (data.status === "done" && isFresh) {
        return { docId, won: false, status: "already_done", productIds: Array.isArray(data.productIds) ? data.productIds : [] };
      }

      // Falls through to re-claim below for: stale "done" (past the 24h
      // refresh window), stale "pending" (a previous run crashed before
      // ever reaching "done"/"failed" — never leave a query stuck forever),
      // and any "failed" record regardless of age (a transient AliExpress
      // error shouldn't force a 24h wait before the next shopper can retry).
    }

    transaction.set(ref, {
      query,
      status: "pending",
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      waitingUserIds: uid ? [uid] : [],
      productIds: [],
    });
    return { docId, won: true };
  });

  return outcome;
}

// Verifies the Firebase Auth ID token from `Authorization: Bearer <token>`
// if one was sent, returning the verified uid — never the client-supplied
// body.userId, which can't be trusted on its own (same principle as
// requireProductCreatorAuth deriving role server-side rather than trusting
// client input). A missing or invalid token resolves to `null` (anonymous)
// rather than rejecting the request — search-miss import is meant to work
// for guest/anonymous search too, per the spec; it just can't push a
// "product found" notification to nobody.
async function verifyOptionalFirebaseIdToken(req) {
  const authHeader = textValue(req.get("authorization"));
  if (!authHeader.toLowerCase().startsWith("bearer ")) return null;
  const idToken = authHeader.slice(7).trim();
  if (!idToken) return null;

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded.uid;
  } catch (error) {
    logger.warn("AliExpress search-import: ID token verification failed, treating as anonymous", { message: error.message });
    return null;
  }
}

exports.aliexpressSearchImport = onRequest(
  {
    secrets: [ALIEXPRESS_APP_SECRET, ALIEXPRESS_AFFILIATE_APP_KEY, ALIEXPRESS_AFFILIATE_APP_SECRET, "OPENAI_API_KEY"],
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (req, res) => cors(req, res, async () => {
    if (req.method === "OPTIONS") return res.status(204).send("");
    if (req.method !== "POST") return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });

    const body = mapValue(req.body);
    if (!textValue(body.query)) return res.status(400).json({ ok: false, error: "QUERY_REQUIRED" });

    // Rejects junk (partial keystrokes, item IDs, URLs, HTML/code) before
    // anything else, so it costs no rate-limit quota, no Firestore write and
    // no AliExpress call. See aliexpress/searchImportQueryGuard.js.
    const validation = validateSearchImportQuery(body.query);
    if (!validation.ok) {
      logger.info("AliExpress search-import: query rejected", { query: validation.query.slice(0, 100), reason: validation.reason });
      return res.status(400).json({ ok: false, error: "QUERY_REJECTED", reason: validation.reason });
    }
    const query = validation.query;

    const uid = await verifyOptionalFirebaseIdToken(req);

    // Rate limiting must never take the endpoint down on its own failure —
    // fail open on an unexpected error here, same resilience posture as
    // verifyOptionalFirebaseIdToken above (a broken safety check degrades
    // to "allow", never to an outage for real shoppers).
    let rateLimitDenial = null;
    try {
      rateLimitDenial = await enforceSearchImportRateLimit(req, uid);
    } catch (error) {
      logger.warn("AliExpress search-import: rate limit check failed, allowing request", { message: error.message });
    }

    if (rateLimitDenial) {
      logger.warn("AliExpress search-import: rate limited", {
        query,
        uid: uid || null,
        scope: rateLimitDenial.scope,
        limit: rateLimitDenial.limit,
        retryAfterSeconds: rateLimitDenial.retryAfterSeconds,
      });
      return res.status(429)
        .set("Retry-After", String(rateLimitDenial.retryAfterSeconds))
        .json({
          ok: false,
          error: "RATE_LIMITED",
          message: `Too many search-import requests. Try again in ${rateLimitDenial.retryAfterSeconds}s.`,
          retryAfterSeconds: rateLimitDenial.retryAfterSeconds,
        });
    }

    let claim;
    try {
      claim = await claimSearchImportSlot(query, uid);
    } catch (error) {
      logger.error("AliExpress search-import: claim transaction failed", { query, message: error.message });
      return res.status(500).json({ ok: false, error: "ALIEXPRESS_SEARCH_IMPORT_FAILED", message: error.message });
    }

    if (!claim.won) {
      return res.status(200).json({ ok: true, status: claim.status, productIds: claim.productIds });
    }

    const logRef = db.collection("searchImportLog").doc(claim.docId);

    try {
      const trackingId = await activeAliExpressTrackingId();
      const result = await aliExpressSignedApiRequest(
        "aliexpress.affiliate.product.query",
        {
          keywords: query,
          page_size: 5,
          tracking_id: trackingId,
          target_currency: "USD",
          target_language: "EN",
          ship_to_country: "BD",
        },
        {
          sync: true,
          appKey: textValue(ALIEXPRESS_AFFILIATE_APP_KEY.value()),
          appSecret: textValue(ALIEXPRESS_AFFILIATE_APP_SECRET.value()),
        }
      );

      const items = extractAliExpressAffiliateProducts(result).slice(0, 5);
      const productIds = [];

      for (const item of items) {
        const sourceProductId = aliExpressAffiliateProductId(item);
        if (!sourceProductId) continue;

        try {
          const product = await fetchAliExpressProduct(sourceProductId);
          // forcePublish: true — search-miss imports must be live immediately;
          // a real shopper is waiting on the exact product they just searched
          // for. Passed as the second (options) argument, never as a `body`
          // field, so it can't be confused with (or spoofed via) any
          // request-body-driven publish flag — see buildMarketplaceProductPayload.
          // needsReview: true — still flagged for admin follow-up even though
          // it's live immediately, since nobody at ChalakChar Mart vetted this
          // specific listing before it went live; only the shopper's search
          // query picked it.
          const saved = await saveImportedMarketplaceProduct(
            {
              source: "aliexpress",
              sourceProductId,
              product,
              importedBy: "search_trigger",
            },
            { forcePublish: true, needsReview: true }
          );
          productIds.push(saved.productId);
        } catch (itemError) {
          logger.warn("AliExpress search-import: one product failed, continuing", {
            query,
            sourceProductId,
            message: itemError.message,
          });
        }
      }

      await logRef.update({
        status: "done",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        productIds,
      });

      logger.info("AliExpress search-import completed", {
        query,
        trackingIdConfigured: Boolean(trackingId),
        resultCount: items.length,
        importedCount: productIds.length,
      });

      const finalSnap = await logRef.get();
      const waitingUserIds = Array.isArray(finalSnap.data()?.waitingUserIds) ? finalSnap.data().waitingUserIds : [];

      await Promise.all(waitingUserIds.map((waitingUid) =>
        notifyUser(waitingUid, "Product found! 🎉", "The product you searched for is now available.", {
          type: "search_import_done",
          query,
          productIds,
        }).catch((notifyError) => {
          logger.warn("AliExpress search-import: notifyUser failed", { query, uid: waitingUid, message: notifyError.message });
        })
      ));

      return res.status(200).json({ ok: true, status: "done", productIds });
    } catch (error) {
      logger.error("AliExpress search-import failed", { query, message: error.message, code: error.code || "", api: error.api || null });

      try {
        await logRef.update({ status: "failed", completedAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (updateError) {
        logger.error("AliExpress search-import: failed to write failed status", { query, message: updateError.message });
      }

      return res.status(500).json({ ok: false, error: error.code || "ALIEXPRESS_SEARCH_IMPORT_FAILED", message: error.message });
    }
  })
);

exports.importAliExpressProduct = onRequest(
  {
    secrets: [PRODUCT_IMPORT_API_KEY, "OPENAI_API_KEY"],
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (req, res) => {
    cors(req, res, async () => {
      if (req.method === "OPTIONS") return res.status(204).send("");
      if (req.method !== "POST") {
        return res.status(405).json({ ok: false, error: "METHOD_NOT_ALLOWED" });
      }

      try {
        const expectedKey = textValue(PRODUCT_IMPORT_API_KEY.value());
        const receivedKey = extractImportApiKey(req);
        if (!expectedKey || !secureKeyEquals(receivedKey, expectedKey)) {
          return res.status(401).json({ ok: false, error: "UNAUTHORIZED" });
        }

        const { source, sourceProductId, publish, payload } = await buildMarketplaceProductPayload(
          mapValue(req.body),
          { forceUnpublish: true, needsReview: true }
        );
        const productId = marketplaceImportDocumentId(source, sourceProductId);
        const productRef = db.collection("products").doc(productId);
        const mode = textValue(req.body?.mode, "upsert").toLowerCase();

        const result = await db.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(productRef);
          const exists = snapshot.exists;

          if (exists && mode === "create") {
            const error = new Error("Product already imported");
            error.code = "ALREADY_EXISTS";
            throw error;
          }
          if (!exists && mode === "update") {
            const error = new Error("Imported product not found");
            error.code = "NOT_FOUND";
            throw error;
          }

          const previous = exists ? (snapshot.data() || {}) : {};
          transaction.set(productRef, {
            ...payload,
            importRevision: importInteger(previous.importRevision, 0) + 1,
            ...(exists
              ? { createdAt: previous.createdAt || admin.firestore.FieldValue.serverTimestamp() }
              : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
          }, { merge: true });

          return { created: !exists, updated: exists };
        });

        logger.info("Marketplace product import completed", {
          productId,
          source,
          sourceProductId,
          publish,
          ...result,
        });

        return res.status(result.created ? 201 : 200).json({
          ok: true,
          productId,
          source,
          sourceProductId,
          publish,
          ...result,
          productUrl: `https://chalakcharmart.com/product/${encodeURIComponent(productId)}`,
        });
      } catch (error) {
        const code = textValue(error?.code);
        const status = code === "ALREADY_EXISTS" ? 409
          : code === "NOT_FOUND" ? 404
          : /required|valid variant|price greater/i.test(textValue(error?.message)) ? 400
          : 500;

        logger.error("Marketplace product import failed", {
          message: error?.message || String(error),
          code,
        });

        return res.status(status).json({
          ok: false,
          error: code || "IMPORT_FAILED",
          message: error?.message || String(error),
        });
      }
    });
  }
);

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

// System prompt for the in-app AI chat, scoped to ChalakChar Mart per the
// omnichannel messaging spec §3 — shared by every channel that falls through
// to the general-question AI branch of handleCustomerMessage.
const CUSTOMER_ASSISTANT_SYSTEM_PROMPT = `You are the helpful customer support assistant for ChalakChar Mart, a Bangladeshi multi-vendor ecommerce platform focused on pharmacy and healthcare products, alongside grocery, beverages, cooking items, LPG cylinders, and more.
Answer customer questions briefly and in a friendly tone, in Bangla unless the customer writes in English.
You do not have live access to exact stock or prices, so for those questions tell the customer to check the product page or search results, and never invent a price, stock count, or delivery date.
Do not give medical dosage advice or diagnose medical conditions; for medicine questions, suggest they consult a pharmacist or doctor.
If you are not confident you can answer correctly, say so plainly (e.g. "I'm not sure about that") rather than guessing — an uncertain answer is routed to a human teammate instead of being shown to the customer.`;

// Recent conversation history read for both AI context and the "same
// question asked 3+ times" handoff check (spec §6) — capped well above the
// 10 messages handleCustomerMessage actually forwards to the AI call.
const CHAT_HISTORY_LOOKBACK = 20;

async function getRecentConversationMessages(conversationId, limit = CHAT_HISTORY_LOOKBACK) {
  const snapshot = await db
    .collection("conversations")
    .doc(conversationId)
    .collection("messages")
    .orderBy("timestamp", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => doc.data()).reverse();
}

async function writeConversationMessage(conversationId, message) {
  await db
    .collection("conversations")
    .doc(conversationId)
    .collection("messages")
    .add({
      sender: message.sender,
      text: String(message.text || ""),
      productLinks: message.productLinks || null,
      mediaUrl: message.mediaUrl || null,
      providerMessageId: message.providerMessageId || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function upsertConversation(conversationId, patch) {
  const ref = db.collection("conversations").doc(conversationId);
  const snap = await ref.get();

  const payload = {
    channel: patch.channel,
    externalUserId: patch.externalUserId,
    customerName: patch.customerName || null,
    needsHuman: Boolean(patch.needsHuman),
    lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMessagePreview: patch.lastMessagePreview || "",
    unreadByAdmin: Boolean(patch.unreadByAdmin),
  };

  if (!snap.exists) {
    payload.status = "open";
    payload.assignedTo = null;
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await ref.set(payload, { merge: true });
}

// Candidate pool for product-search intent — mirrors SearchPage's own
// approach of scoring/filtering a fetched batch in memory (see
// messaging/productMatch.js), since there is no dedicated search index to
// query against instead. Ordered by createdAt so newer catalog additions are
// represented in the pool rather than only ever seeing the oldest 300 docs.
async function fetchCandidateProductsForChat() {
  const snapshot = await db.collection("products").orderBy("createdAt", "desc").limit(300).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

async function callCustomerAssistantAI({ history, message }) {
  const apiKey = (process.env.OPENAI_API_KEY || "").trim();
  if (!apiKey) throw new Error("Missing OPENAI_API_KEY");

  const openai = new OpenAI({ apiKey });
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    temperature: 0.5,
    max_tokens: 500,
    messages: [
      { role: "system", content: CUSTOMER_ASSISTANT_SYSTEM_PROMPT },
      ...history,
      { role: "user", content: message.slice(0, 2000) },
    ],
  });

  return completion.choices?.[0]?.message?.content || "";
}

// Fire-and-forget trigger for the AliExpress search-miss fallback from chat
// (mirrors search_page.dart's _triggerSearchImport) — dispatches a POST to
// the already-deployed aliexpressSearchImport endpoint and does not await
// its response. aliexpressSearchImport awaits the full AliExpress
// fetch/import synchronously before responding (up to timeoutSeconds: 120),
// so awaiting it here would stall the chat reply by the same amount; posting
// to it as its own independent Cloud Run invocation — the same way the
// client's un-awaited http.post already does — means that work continues
// regardless of what happens to this function's own response cycle.
function triggerAliExpressSearchImportFallback(query) {
  axios.post(ALIEXPRESS_SEARCH_IMPORT_URL, { query }, { timeout: 120000 }).catch((error) => {
    logger.warn("Chat search-import fallback: dispatch failed", { query, message: error.message });
  });
}

async function customerMessageDeps(overrides = {}) {
  const settings = await loadMarketingSettings();
  return {
    getRecentMessages: getRecentConversationMessages,
    writeMessage: writeConversationMessage,
    upsertConversation,
    searchProducts: fetchCandidateProductsForChat,
    callAI: callCustomerAssistantAI,
    captionTemplate: settings.captionTemplate,
    notifyAdmins,
    triggerSearchImportFallback: triggerAliExpressSearchImportFallback,
    ...overrides,
  };
}

// Resolves the "app" channel's externalUserId (see conversation-id
// convention in the omnichannel messaging spec §2): a verified Firebase uid
// when the shopper is signed in, otherwise the client-persisted anonymous
// guestId (see ChatService in chat_service.dart). A request with neither
// still gets an answer — it just starts a fresh, non-continuing
// conversation thread rather than being rejected outright.
async function resolveAppChannelIdentity(req) {
  const authHeader = String(req.get("authorization") || "");
  if (authHeader.toLowerCase().startsWith("bearer ")) {
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.slice(7).trim());
      return { externalUserId: decoded.uid, customerName: decoded.name || null };
    } catch (error) {
      logger.warn("chatWithAssistant: ID token verification failed, falling back to guestId", { message: error.message });
    }
  }

  const guestId = textValue(req.body?.guestId);
  if (guestId) return { externalUserId: `guest_${guestId}`, customerName: null };

  return { externalUserId: `anon_${crypto.randomUUID()}`, customerName: null };
}

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
        res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
        return res.status(204).send("");
      }

      res.set("Access-Control-Allow-Origin", "*");

      if (req.method !== "POST") {
        return res.status(405).json({ error: "Only POST request allowed" });
      }

      const cleanMessage = String(req.body?.message || "").trim();
      if (!cleanMessage) {
        return res.status(400).json({ error: "message is required" });
      }

      const { externalUserId, customerName } = await resolveAppChannelIdentity(req);
      const deps = await customerMessageDeps();

      const result = await handleCustomerMessage(deps, {
        channel: "app",
        externalUserId,
        customerName,
        text: cleanMessage,
      });

      return res.status(200).json({ reply: result.replyText.trim(), needsHuman: result.needsHuman });
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
// WhatsApp inbound webhook (omnichannel messaging pipeline spec, phase 2).
//
// GET requests are Meta's one-time subscription handshake (hub.mode=subscribe
// &hub.verify_token=...&hub.challenge=...) — answered from
// meta/webhookChallenge.js, never touching Firestore.
//
// POST requests are inbound message events. Every POST is rejected outright
// (401, before any Firestore read/write) unless its X-Hub-Signature-256
// header verifies against META_APP_SECRET — see meta/signatureVerify.js.
// Once verified, this always acks 200 regardless of what happens during
// processing (spec §5/design principle 4: never let a processing error turn
// into a Meta retry-storm or a disabled subscription), mirroring
// tiktok/resolve.js's tiktokWebhook handler.
// -----------------------------------------------------------------------------
exports.whatsappWebhook = onRequest(
  { region: "asia-south1", timeoutSeconds: 60, secrets: [META_APP_SECRET, "OPENAI_API_KEY"] },
  async (req, res) => {
    if (req.method === "GET") {
      const challenge = resolveVerificationChallenge({
        mode: textValue(req.query?.["hub.mode"]),
        verifyToken: textValue(req.query?.["hub.verify_token"]),
        challenge: req.query?.["hub.challenge"],
        expectedVerifyToken: textValue(META_WEBHOOK_VERIFY_TOKEN.value()),
      });

      if (challenge === null) {
        logger.warn("WhatsApp webhook: verification handshake rejected");
        return res.status(403).send("Forbidden");
      }

      return res.status(200).send(challenge);
    }

    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    try {
      verifyMetaSignature({
        rawBody: req.rawBody,
        signatureHeader: req.get("x-hub-signature-256"),
        appSecret: textValue(META_APP_SECRET.value()),
      });
    } catch (error) {
      logger.warn("WhatsApp webhook: signature rejected", {
        code: error instanceof WebhookVerificationError ? error.code : "UNKNOWN",
      });
      return res.status(401).send("invalid signature");
    }

    try {
      const events = parseWhatsAppWebhookEvents(mapValue(req.body));

      for (const event of events) {
        if (!event.from || event.type !== "text" || !event.text) {
          logger.info("WhatsApp webhook: skipping non-text or empty message", {
            type: event.type,
            messageId: event.messageId,
          });
          continue;
        }

        const deps = await customerMessageDeps({
          messageAlreadyProcessed: async (_conversationId, providerMessageId) =>
            !(await claimWhatsAppMessageId(db, providerMessageId)),
        });

        const result = await handleCustomerMessage(deps, {
          channel: "whatsapp",
          externalUserId: event.from,
          customerName: event.customerName,
          text: event.text,
          providerMessageId: event.messageId,
        });

        if (result.duplicate || !result.replyText) continue;

        try {
          const settings = await loadMarketingSettings();
          await sendWhatsAppMessage(settings, { to: event.from, body: result.replyText });
        } catch (sendError) {
          logger.error("WhatsApp webhook: failed to send reply", { message: sendError.message, to: event.from });
        }
      }
    } catch (error) {
      logger.error("WhatsApp webhook: processing failed", { message: error.message });
      // Fall through to the 200 ack below regardless — an unexpected
      // processing error must never cause Meta to retry-storm this event.
    }

    return res.status(200).send("EVENT_RECEIVED");
  }
);

// -----------------------------------------------------------------------------
// Messenger inbound webhook (omnichannel messaging pipeline, phase 3).
//
// Same structure as whatsappWebhook above — GET is Meta's verification
// handshake (meta/webhookChallenge.js), POST is rejected before any
// Firestore access unless its X-Hub-Signature-256 header verifies against
// the same META_APP_SECRET (Messenger shares the one main Meta App with
// WhatsApp — see meta/config.js. Instagram does NOT: it's configured under
// a separate companion app with its own secret, see instagramWebhook
// below). Always acks 200 once verified, regardless of processing outcome,
// for the same retry-storm reason.
// -----------------------------------------------------------------------------
exports.messengerWebhook = onRequest(
  { region: "asia-south1", timeoutSeconds: 60, secrets: [META_APP_SECRET, "OPENAI_API_KEY"] },
  async (req, res) => {
    if (req.method === "GET") {
      const challenge = resolveVerificationChallenge({
        mode: textValue(req.query?.["hub.mode"]),
        verifyToken: textValue(req.query?.["hub.verify_token"]),
        challenge: req.query?.["hub.challenge"],
        expectedVerifyToken: textValue(META_WEBHOOK_VERIFY_TOKEN.value()),
      });

      if (challenge === null) {
        logger.warn("Messenger webhook: verification handshake rejected");
        return res.status(403).send("Forbidden");
      }

      return res.status(200).send(challenge);
    }

    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    try {
      verifyMetaSignature({
        rawBody: req.rawBody,
        signatureHeader: req.get("x-hub-signature-256"),
        appSecret: textValue(META_APP_SECRET.value()),
      });
    } catch (error) {
      logger.warn("Messenger webhook: signature rejected", {
        code: error instanceof WebhookVerificationError ? error.code : "UNKNOWN",
      });
      return res.status(401).send("invalid signature");
    }

    try {
      const events = parseMetaMessagingEvents(mapValue(req.body));

      for (const event of events) {
        if (!event.from || event.type !== "text" || !event.text) {
          logger.info("Messenger webhook: skipping non-text or empty message", {
            type: event.type,
            messageId: event.messageId,
          });
          continue;
        }

        const deps = await customerMessageDeps({
          messageAlreadyProcessed: async (_conversationId, providerMessageId) =>
            !(await claimMetaMessageId(db, "messengerProcessedMessages", providerMessageId)),
        });

        const result = await handleCustomerMessage(deps, {
          channel: "messenger",
          externalUserId: event.from,
          customerName: event.customerName,
          text: event.text,
          providerMessageId: event.messageId,
        });

        if (result.duplicate || !result.replyText) continue;

        try {
          const settings = await loadMarketingSettings();
          await sendMessengerMessage(settings, { to: event.from, body: result.replyText });
        } catch (sendError) {
          logger.error("Messenger webhook: failed to send reply", { message: sendError.message, to: event.from });
        }
      }
    } catch (error) {
      logger.error("Messenger webhook: processing failed", { message: error.message });
      // Fall through to the 200 ack below regardless — same retry-storm
      // avoidance as whatsappWebhook.
    }

    return res.status(200).send("EVENT_RECEIVED");
  }
);

// -----------------------------------------------------------------------------
// Instagram inbound webhook (omnichannel messaging pipeline, phase 3).
//
// Same structure as messengerWebhook above — Instagram DMs webhook through
// the identical entry[].messaging[] shape (meta/parseMessagingEvents.js),
// just under object: "instagram" instead of "page". Signature verification
// is the one thing that does NOT match whatsappWebhook/messengerWebhook:
// Meta's dashboard put Instagram's webhook subscription under a separate
// companion app ("ChalakChar Mart Social Automat-IG", App ID
// 2423413004818243) rather than the main app WhatsApp/Messenger share, so
// Instagram signs its webhook POSTs with its own INSTAGRAM_APP_SECRET —
// verifying against META_APP_SECRET would reject every real delivery here.
// The GET verify-token handshake is unaffected (META_WEBHOOK_VERIFY_TOKEN
// is a value we chose ourselves, reused across every app's dashboard, not
// something Meta signs per-app).
// -----------------------------------------------------------------------------
exports.instagramWebhook = onRequest(
  { region: "asia-south1", timeoutSeconds: 60, secrets: [INSTAGRAM_APP_SECRET, "OPENAI_API_KEY"] },
  async (req, res) => {
    if (req.method === "GET") {
      const challenge = resolveVerificationChallenge({
        mode: textValue(req.query?.["hub.mode"]),
        verifyToken: textValue(req.query?.["hub.verify_token"]),
        challenge: req.query?.["hub.challenge"],
        expectedVerifyToken: textValue(META_WEBHOOK_VERIFY_TOKEN.value()),
      });

      if (challenge === null) {
        logger.warn("Instagram webhook: verification handshake rejected");
        return res.status(403).send("Forbidden");
      }

      return res.status(200).send(challenge);
    }

    if (req.method !== "POST") {
      return res.status(405).send("Method Not Allowed");
    }

    try {
      verifyMetaSignature({
        rawBody: req.rawBody,
        signatureHeader: req.get("x-hub-signature-256"),
        appSecret: textValue(INSTAGRAM_APP_SECRET.value()),
      });
    } catch (error) {
      logger.warn("Instagram webhook: signature rejected", {
        code: error instanceof WebhookVerificationError ? error.code : "UNKNOWN",
      });
      return res.status(401).send("invalid signature");
    }

    try {
      const events = parseMetaMessagingEvents(mapValue(req.body));

      for (const event of events) {
        if (!event.from || event.type !== "text" || !event.text) {
          logger.info("Instagram webhook: skipping non-text or empty message", {
            type: event.type,
            messageId: event.messageId,
          });
          continue;
        }

        const deps = await customerMessageDeps({
          messageAlreadyProcessed: async (_conversationId, providerMessageId) =>
            !(await claimMetaMessageId(db, "instagramProcessedMessages", providerMessageId)),
        });

        const result = await handleCustomerMessage(deps, {
          channel: "instagram",
          externalUserId: event.from,
          customerName: event.customerName,
          text: event.text,
          providerMessageId: event.messageId,
        });

        if (result.duplicate || !result.replyText) continue;

        try {
          const settings = await loadMarketingSettings();
          await sendInstagramMessage(settings, { to: event.from, body: result.replyText });
        } catch (sendError) {
          logger.error("Instagram webhook: failed to send reply", { message: sendError.message, to: event.from });
        }
      }
    } catch (error) {
      logger.error("Instagram webhook: processing failed", { message: error.message });
      // Fall through to the 200 ack below regardless — same retry-storm
      // avoidance as whatsappWebhook.
    }

    return res.status(200).send("EVENT_RECEIVED");
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
