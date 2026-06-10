const { setGlobalOptions } = require("firebase-functions/v2");
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const OpenAI = require("openai");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

admin.initializeApp();
const db = admin.firestore();


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

exports.onProductStockUpdated = onDocumentUpdated("products/{productId}", async (event) => {
  const productId = event.params.productId;
  const after = event.data.after.data() || {};

  const stock = toNumber(after.stock);
  const alreadyAlerted = after.lowStockAlerted === true;

  if (stock > 0 && stock <= 5 && !alreadyAlerted) {
    await notifyAdmins(
      "Low Stock Alert ⚠️",
      `${after.name || "Product"} stock is low: ${stock}`,
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

  if (stock > 5 && alreadyAlerted) {
    await db.collection("products").doc(productId).set({
      lowStockAlerted: false,
    }, { merge: true });
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

exports.onReviewCreated = onDocumentCreated("reviews/{reviewId}", async (event) => {
  const review = event.data?.data() || {};
  const productId = review.productId;

  if (!productId) return;

  const reviewsSnap = await db.collection("reviews")
    .where("productId", "==", productId)
    .get();

  let totalRating = 0;
  let count = 0;

  reviewsSnap.forEach((doc) => {
    totalRating += toNumber(doc.data().rating);
    count++;
  });

  const avgRating = count > 0 ? totalRating / count : 0;

  await db.collection("products").doc(productId).set({
    ratingAvg: avgRating,
    ratingCount: count,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
});

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
      if (req.method === "OPTIONS") {
        return res.status(204).send("");
      }

      if (req.method !== "POST") {
        return res.status(405).json({
          error: "Only POST request allowed",
        });
      }

      const apiKey = process.env.OPENAI_API_KEY;

      if (!apiKey) {
        console.error("Missing OPENAI_API_KEY");
        return res.status(500).json({
          error: "Missing OPENAI_API_KEY",
        });
      }

      const { title, description, category } = req.body || {};

      if (!title || String(title).trim().length < 2) {
        return res.status(400).json({
          error: "Product title is required",
        });
      }

      const openai = new OpenAI({
        apiKey,
      });

      const prompt = `
Optimize this ecommerce product for ChalakChar Mart.

Return ONLY valid JSON.

Required JSON fields:
{
  "title": "SEO optimized English product title",
  "banglaTitle": "Natural Bangla product title",
  "description": "Professional product description",
  "seoTags": ["tag1", "tag2", "tag3"]
}

Product Title: ${String(title || "").trim()}
Description: ${String(description || "").trim()}
Category: ${String(category || "").trim()}
`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.7,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content:
              "You are an ecommerce SEO product optimizer. Return only valid JSON. No markdown.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
      });

      const text = completion.choices?.[0]?.message?.content || "{}";

      console.log("AI OPTIMIZE RESPONSE:", text);

      const parsed = JSON.parse(text);

      return res.status(200).json({
        title: parsed.title || title,
        banglaTitle: parsed.banglaTitle || "",
        description: parsed.description || description || "",
        seoTags: Array.isArray(parsed.seoTags) ? parsed.seoTags : [],
      });
    } catch (e) {
      console.error("AI OPTIMIZE ERROR:", e);

      return res.status(500).json({
        error: e.message || "AI optimization failed",
      });
    }
  }
);