// The single channel-agnostic "brain" for the omnichannel messaging pipeline
// (spec §3). Every inbound channel (in-app AI chat, WhatsApp, Messenger,
// Instagram, TikTok) is meant to funnel through this one function — it never
// branches on `channel` to decide *how* to reply, only to build the
// conversation id and log entries; the caller (a channel-specific webhook or
// the app's own HTTPS endpoint) is responsible for actually sending the
// reply out over that channel.
//
// All Firestore/AI/notification access is injected via `deps` rather than
// imported directly, so this orchestrator is unit-testable with plain stubs
// instead of a Firestore fake (see functions/test/handleCustomerMessage.test.js) —
// the same "pure logic, thin Firestore-touching wrapper" split already used
// by aliexpress/searchImportRateLimit.js, just pushed one level further since
// this function's job *is* the Firestore/AI orchestration.

const { buildConversationId, truncatePreview } = require("./conversationId");
const { rankProducts } = require("./productMatch");
const { formatProductReply } = require("./replyFormatting");
const {
  containsHandoffKeyword,
  hasRepeatedUnresolvedQuestion,
  isLowConfidenceReply,
} = require("./handoffDetection");
const { shouldTriggerSearchImportFallback } = require("./searchImportGuard");

const HANDOFF_HOLDING_MESSAGE =
  "আপনার সাথে আমাদের টিমের একজন শীঘ্রই যোগাযোগ করবে। একটু অপেক্ষা করুন। 🙏";

const REPEAT_THRESHOLD = 3;

/**
 * @param {object} deps
 * @param {(conversationId: string, limit: number) => Promise<Array<{sender:string,text:string}>>} deps.getRecentMessages
 * @param {(conversationId: string, message: object) => Promise<void>} deps.writeMessage
 * @param {(conversationId: string, patch: object) => Promise<void>} deps.upsertConversation
 * @param {(query: string, limit: number) => Promise<Array<object>>} deps.searchProducts - candidate products (already scored/ranked, isActive only)
 * @param {(input: {systemPrompt: string, history: Array<{role:string,content:string}>, message: string}) => Promise<string>} deps.callAI
 * @param {string} deps.captionTemplate
 * @param {(title: string, body: string, data?: object) => Promise<void>} [deps.notifyAdmins]
 * @param {() => Date} [deps.now]
 * @param {(conversationId: string, providerMessageId: string) => Promise<boolean>} [deps.messageAlreadyProcessed]
 * @param {(query: string) => void} [deps.triggerSearchImportFallback] - fire-and-forget AliExpress
 *        search-miss import, same trigger SearchPage uses on a zero-result search box query
 *        (see aliexpressSearchImport). Called, never awaited, so a slow import never delays the reply.
 *
 * @param {{channel: string, externalUserId: string, customerName?: string|null, text: string, mediaUrl?: string|null, providerMessageId?: string|null}} input
 * @returns {Promise<{replyText: string, replyMediaUrl: string|null, productLinks: string[]|null, needsHuman: boolean, conversationId: string, duplicate?: true}>}
 */
async function handleCustomerMessage(deps, input) {
  const channel = String(input.channel || "").trim();
  const externalUserId = String(input.externalUserId || "").trim();
  const text = String(input.text || "").trim();
  const mediaUrl = input.mediaUrl || null;
  const customerName = input.customerName || null;
  const providerMessageId = input.providerMessageId || null;
  const now = deps.now || (() => new Date());

  const conversationId = buildConversationId(channel, externalUserId);

  if (!text && !mediaUrl) {
    return { replyText: "", replyMediaUrl: null, productLinks: null, needsHuman: false, conversationId };
  }

  if (providerMessageId && deps.messageAlreadyProcessed) {
    const alreadyProcessed = await deps.messageAlreadyProcessed(conversationId, providerMessageId);
    if (alreadyProcessed) {
      return { replyText: "", replyMediaUrl: null, productLinks: null, needsHuman: false, conversationId, duplicate: true };
    }
  }

  const recentMessages = await deps.getRecentMessages(conversationId, 20);

  await deps.writeMessage(conversationId, {
    sender: "customer",
    text,
    mediaUrl,
    productLinks: null,
    providerMessageId,
    timestamp: now(),
  });

  let replyText;
  let productLinks = null;
  let needsHuman = false;

  if (containsHandoffKeyword(text) || hasRepeatedUnresolvedQuestion(recentMessages, text, REPEAT_THRESHOLD)) {
    replyText = HANDOFF_HOLDING_MESSAGE;
    needsHuman = true;
  } else {
    const products = await deps.searchProducts(text, 5);
    const ranked = rankProducts(products, text, 5);

    if (ranked.length > 0) {
      const formatted = formatProductReply(ranked, deps.captionTemplate);
      replyText = formatted.replyText;
      productLinks = formatted.productLinks;
    } else {
      if (deps.triggerSearchImportFallback && shouldTriggerSearchImportFallback(text)) {
        deps.triggerSearchImportFallback(text);
      }

      const history = (recentMessages || [])
        .filter((m) => m && (m.sender === "customer" || m.sender === "bot") && String(m.text || "").trim())
        .slice(-10)
        .map((m) => ({ role: m.sender === "customer" ? "user" : "assistant", content: String(m.text).trim() }));

      const aiReply = await deps.callAI({ history, message: text });

      if (isLowConfidenceReply(aiReply)) {
        replyText = HANDOFF_HOLDING_MESSAGE;
        needsHuman = true;
      } else {
        replyText = aiReply.trim();
      }
    }
  }

  await deps.writeMessage(conversationId, {
    sender: "bot",
    text: replyText,
    mediaUrl: null,
    productLinks,
    providerMessageId: null,
    timestamp: now(),
  });

  await deps.upsertConversation(conversationId, {
    channel,
    externalUserId,
    customerName,
    needsHuman,
    lastMessageAt: now(),
    lastMessagePreview: truncatePreview(replyText, 120),
    unreadByAdmin: true,
  });

  if (needsHuman && deps.notifyAdmins) {
    await deps.notifyAdmins(
      "কাস্টমার সহায়তা প্রয়োজন 🆘",
      truncatePreview(text, 100),
      { type: "needs_human", conversationId, channel }
    );
  }

  return { replyText, replyMediaUrl: null, productLinks, needsHuman, conversationId };
}

module.exports = { handleCustomerMessage, HANDOFF_HOLDING_MESSAGE, REPEAT_THRESHOLD };
