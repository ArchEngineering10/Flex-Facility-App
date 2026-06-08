/* =========================
 * functions/index.js
 * =======================*/

/* ----- imports ----- */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { Resend } = require("resend");
const express = require("express");
const cors = require("cors");
const rateLimit = require("express-rate-limit");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const axios = require("axios");

/* ----- init ----- */
admin.initializeApp();

/* =========================
   Resend (lazy init)
========================= */
let _resend = null;
function getResend() {
  if (!_resend) {
    const key = functions.config()?.resend?.key;
    if (!key || typeof key !== "string" || !key.startsWith("re_")) {
      throw new Error(
        'Resend API key missing/invalid. Set:\n' +
          '  firebase functions:config:set resend.key="re_xxxxxx"'
      );
    }
    _resend = new Resend(key);
  }
  return _resend;
}

const MAIL_FROM = { email: "no-reply@archengineeringservices.com", name: "Flex Facility" };
const REPLY_TO = { email: "admin@archengineeringservices.com", name: "Flex Facility Support" };
const COMMON_HEADERS = {
  "List-Unsubscribe":
    "<mailto:admin@archengineeringservices.com>, <https://archengineeringservices.com/unsubscribe>",
  "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
};

const LOGO_URL = "https://firebasestorage.googleapis.com/v0/b/flex-facility-app-b55aa.firebasestorage.app/o/logo.png?alt=media&token=e0a6f925-77c0-4d85-88f4-f89b640e913c";


function getLogoImgSrc() {
  return LOGO_URL;
}


const BRAND_COLORS = {
  primary: "#1C2D5E",
  blue: "#2563eb",
  green: "#16a34a",
  red: "#dc2626",
  lightBg: "#f5f7fb",
  cardBg: "#ffffff",
};

function sendTransactionalEmail({ to, subject, text, html, fromName }) {
  const resend = getResend();
  const fromStr = `${fromName || MAIL_FROM.name} <${MAIL_FROM.email}>`;

  return resend.emails.send({
    from: fromStr,
    to: Array.isArray(to) ? to : [to],
    reply_to: REPLY_TO.email,
    subject,
    ...(text ? { text } : {}),
    ...(html ? { html } : {}),
    headers: COMMON_HEADERS,
  });
}

/* =========================
   Helpers
========================= */
/* =============================================================================
   CHAT HELPER — writes a system message into the client's conversation.
   All automated messages (booking, payment, reminder, etc.) use this.
============================================================================= */
async function sendSystemChatMessage(clientUid, text, messageType) {
  if (!clientUid) return;
  try {
    const db = admin.firestore();
    const userSnap = await db.collection("users").doc(clientUid).get();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const clientName = userData.name ||
      [userData.firstName, userData.lastName].filter(Boolean).join(" ") ||
      userData.email ||
      "Client";

    await db
      .collection("conversations")
      .doc(clientUid)
      .collection("messages")
      .add({
        senderRole: "system",
        type: messageType || "system",
        text,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });

    // Update conversation meta so admin inbox shows latest activity
    await db.collection("conversations").doc(clientUid).set(
      {
        clientId: clientUid,
        clientName,
        clientEmail: userData.email || "",
        clientPhoto: userData.photoUrl || userData.photoURL || "",
        lastMessage: text,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSenderRole: "system",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } catch (e) {
    console.error(`sendSystemChatMessage error for ${clientUid}:`, e.message);
  }
}

function dateFromSlotDocId(slotId) {
  const dateKey = String(slotId || "").split("|")[0];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return null;
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function dateFromFirestoreValue(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function getSlotDate(slotId, slotData = {}) {
  return dateFromSlotDocId(slotId) || dateFromFirestoreValue(slotData.date);
}

function formatSlotDateForDisplay(slotId, slotData = {}, options) {
  const slotDate = getSlotDate(slotId, slotData);
  if (!slotDate) return "";
  return slotDate.toLocaleDateString("en-US", options);
}

function safeRefId(ref) {
  if (!ref) return undefined;
  const s = String(ref).trim();
  return s.length <= 40 ? s : s.slice(0, 40);
}
function buildSquareAddress(addr = {}) {
  const out = {};
  if (addr.line1) out.address_line_1 = String(addr.line1);
  if (addr.line2) out.address_line_2 = String(addr.line2);
  if (addr.locality) out.locality = String(addr.locality);
  if (addr.adminArea) out.administrative_district_level_1 = String(addr.adminArea);
  if (addr.postalCode) out.postal_code = String(addr.postalCode);
  if (addr.country) out.country = String(addr.country);
  return Object.keys(out).length ? out : undefined;
}

/* ========= Email HTML builders ========= */

/** Booking / reschedule / cancel HTML */
function buildBookingEmailHtml({
  heading,
  statusColor,
  slotDate,
  slotTime,
  trainer,
  introText,
  extraNote,
}) {
  const dateLine = slotDate || "";
  const timeLine = slotTime || "";
  const trainerName = trainer || "your trainer";
  const logoImgSrc = getLogoImgSrc();

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />
                <div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  ${heading}
                </div>
                <p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">
                  ${introText}
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 8px 24px;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Session details
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Date</td>
                    <td style="padding:4px 0;">${dateLine}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Time</td>
                    <td style="padding:4px 0;">${timeLine}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Trainer</td>
                    <td style="padding:4px 0;">${trainerName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Location</td>
                    <td style="padding:4px 0;">Flex Facility</td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:8px 24px 16px 24px;">
                <p style="margin:8px 0 0 0;font-size:13px;color:#4b5563;line-height:1.6;">
                  ${extraNote ||
                    "Need to make a change? You can manage your session directly from the Flex Facility app."}
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 20px 24px;border-top:1px solid #e5e7eb;">
                <p style="margin:0;font-size:12px;color:#9ca3af;">
                  Thank you for training with Flex Facility.
                </p>
              </td>
            </tr>
          </table>

          <p style="margin-top:16px;font-size:11px;color:#9ca3af;text-align:center;">
            (c) ${new Date().getFullYear()} Flex Facility  All rights reserved
          </p>
        </td>
      </tr>
    </table>
  </div>
  `;
}

/** Payment success HTML */
function buildPaymentSuccessHtml({ firstName, lastName, planName, amount, referenceId }) {
  const name = `${firstName || ""} ${lastName || ""}`.trim() || "";
  const greeting = name ? `Hi ${name},` : "Hi,";
  const logoImgSrc = getLogoImgSrc();

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />
                <div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  Your payment was successful
                </div>
                <p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">
                  ${greeting}<br/>
                  Thank you for your payment. Your plan is now active.
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 8px 24px;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Order summary
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Plan</td>
                    <td style="padding:4px 0;">${planName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Total charged</td>
                    <td style="padding:4px 0;font-weight:600;">$${amount}</td>
                  </tr>
                  ${
                    referenceId
                      ? `<tr>
                          <td style="padding:4px 0;width:120px;color:#6b7280;">Reference</td>
                          <td style="padding:4px 0;">${referenceId}</td>
                        </tr>`
                      : ""
                  }
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:8px 24px 16px 24px;">
                <p style="margin:8px 0 0 0;font-size:13px;color:#4b5563;line-height:1.6;">
                  You can view and manage your sessions any time from the Flex Facility app.
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 20px 24px;border-top:1px solid #e5e7eb;">
                <p style="margin:0;font-size:12px;color:#9ca3af;">
                  Need help? Reply to this email or contact <a href="mailto:${REPLY_TO.email}" style="color:${BRAND_COLORS.primary};text-decoration:none;">${REPLY_TO.email}</a>.
                </p>
              </td>
            </tr>
          </table>

          <p style="margin-top:16px;font-size:11px;color:#9ca3af;text-align:center;">
            (c) ${new Date().getFullYear()} Flex Facility  All rights reserved
          </p>
        </td>
      </tr>
    </table>
  </div>
  `;
}

/* =========================
   Square REST client (ENV-AWARE)
========================= */
function resolveSquareEnv(req) {
  const hdr = (req?.headers?.["x-square-env"] || "").toString().toLowerCase();
  if (hdr === "sandbox" || hdr === "production") return hdr;
  const cfgEnv = (functions.config()?.square?.env || "sandbox").toLowerCase();
  return cfgEnv === "production" ? "production" : "sandbox";
}

function getSquareConfig(req) {
  const env = resolveSquareEnv(req);
  const cfg = functions.config()?.square || {};

  const sandboxToken = (cfg.sandbox_token || "").trim();
  const prodToken = (cfg.prod_token || "").trim();

  const sandboxLocationId = (cfg.sandbox_location_id || cfg.location_id || "").trim();
  const prodLocationId = (cfg.prod_location_id || cfg.location_id || "").trim();

  const isProd = env === "production";
  const token = isProd ? prodToken : sandboxToken;
  const locationId = isProd ? prodLocationId : sandboxLocationId;
  const baseURL = isProd ? "https://connect.squareup.com" : "https://connect.squareupsandbox.com";

  if (!token) {
    const hint = isProd ? "prod_token" : "sandbox_token";
    throw new Error(`Square ${env} token not set. Run:\n  firebase functions:config:set square.${hint}="EAAA-..."`);
  }
  if (!locationId) {
    const hint = isProd ? "prod_location_id" : "sandbox_location_id";
    throw new Error(`Square ${env} location_id not set. Run:\n  firebase functions:config:set square.${hint}="LXXXX..."`);
  }

  return { env, isProd, baseURL, token, locationId };
}

function squareHttp(req) {
  const cfg = getSquareConfig(req);
  return axios.create({
    baseURL: cfg.baseURL,
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      "Square-Version": "2024-08-21",
    },
    timeout: 20000,
  });
}

function getBearerToken(req) {
  const header = req.headers.authorization || req.headers.Authorization || "";
  const match = String(header).match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

async function requireFirebaseUser(req) {
  const token = getBearerToken(req);
  if (!token) {
    const err = new Error("Authentication required.");
    err.statusCode = 401;
    throw err;
  }
  try {
    return await admin.auth().verifyIdToken(token);
  } catch (e) {
    const err = new Error("Invalid authentication token.");
    err.statusCode = 401;
    throw err;
  }
}

async function getUserProfile(uid, authUser) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  const data = snap.exists ? snap.data() || {} : {};
  const displayName = (data.name || authUser.name || "").toString().trim();
  const parts = displayName ? displayName.split(/\s+/) : [];
  return {
    email: (data.email || authUser.email || "").toString().trim(),
    firstName: (data.firstName || parts[0] || "").toString().trim(),
    lastName: (data.lastName || parts.slice(1).join(" ") || "").toString().trim(),
    displayName,
  };
}

async function resolvePaymentPlan(planId) {
  const id = (planId || "").toString().trim();
  if (!id) {
    const err = new Error("Missing plan id.");
    err.statusCode = 400;
    throw err;
  }

  // Built-in subscriptions that are not stored in the normal plans collection.
  const builtInPlans = {
    pdf_subscription_monthly: {
      planId: "pdf_subscription_monthly",
      planName: "PDF Workouts Monthly Subscription",
      planCategory: "PDF Access",
      description: "Unlimited access to all PDF workouts for 30 days",
      price: 9.99,
      sessions: 1,
      type: "pdf",
      isPdf: true,
    },
    video_subscription_monthly: {
      planId: "video_subscription_monthly",
      planName: "Video Workouts Monthly Subscription",
      planCategory: "Video Access",
      description: "Unlimited access to all video workouts for 30 days",
      price: 1.00,
      sessions: 1,
      type: "video",
    },
  };
  if (builtInPlans[id]) return builtInPlans[id];

  const snap = await admin.firestore().collection("plans").doc(id).get();
  if (!snap.exists) {
    const err = new Error("Plan not found.");
    err.statusCode = 404;
    throw err;
  }
  const data = snap.data() || {};
  const price = Number(data.price || 0);
  const sessions = Number(data.sessions || 0);
  if (!Number.isFinite(price) || price <= 0) {
    const err = new Error("Plan price is invalid.");
    err.statusCode = 400;
    throw err;
  }
  return {
    planId: id,
    planName: data.name || "Training Plan",
    planCategory: data.category || "",
    description: data.description || "",
    price,
    sessions: Number.isFinite(sessions) ? sessions : 0,
  };
}

/* =========================
   Square API wrappers
========================= */
async function ensureSquareCustomer({ req, email, given_name, family_name, referenceId }) {
  const http = squareHttp(req);
  try {
    if (email) {
      const { data } = await http.post("/v2/customers/search", {
        query: { filter: { email_address: { exact: email } } },
        limit: 1,
      });
      const c = (data.customers || [])[0];
      if (c) return c;
    }
  } catch (_) {}

  const payload = {
    email_address: email,
    given_name,
    family_name,
    ...(referenceId ? { reference_id: referenceId } : {}),
  };
  const { data } = await http.post("/v2/customers", payload);
  return data.customer;
}

async function squareCreateOrder({
  req,
  locationId,
  name,
  amountCents,
  currency = "USD",
  customerId,
  referenceId,
}) {
  const http = squareHttp(req);
  const { data } = await http.post("/v2/orders", {
    order: {
      location_id: locationId,
      ...(customerId ? { customer_id: customerId } : {}),
      ...(referenceId ? { reference_id: referenceId } : {}),
      line_items: [
        {
          name,
          quantity: "1",
          base_price_money: { amount: Number(amountCents), currency },
        },
      ],
    },
  });
  return data.order;
}

async function squareCreatePayment({
  req,
  sourceId,
  amountCents,
  currency = "USD",
  idempotencyKey,
  locationId,
  verificationToken,
  orderId,
  customerId,
  note,
  referenceId,
  buyerEmail,
  billingAddress,
}) {
  const cfg = getSquareConfig(req);
  const http = squareHttp(req);
  const body = {
    source_id: sourceId,
    idempotency_key: idempotencyKey,
    amount_money: { amount: Number(amountCents), currency },
    location_id: locationId || cfg.locationId,
    ...(verificationToken ? { verification_token: verificationToken } : {}),
    ...(orderId ? { order_id: orderId } : {}),
    ...(customerId ? { customer_id: customerId } : {}),
    ...(note ? { note } : {}),
    ...(referenceId ? { reference_id: referenceId } : {}),
    ...(buyerEmail ? { buyer_email_address: buyerEmail } : {}),
    ...(billingAddress ? { billing_address: billingAddress } : {}),
  };
  const { data } = await http.post("/v2/payments", body);
  return data;
}

/* ---------- create link/invoice helpers ---------- */
async function squareCreateInvoice({ req, locationId, orderId, customerId, title, description }) {
  const http = squareHttp(req);
  const { data } = await http.post("/v2/invoices", {
    invoice: {
      location_id: locationId,
      order_id: orderId,
      title,
      description,
      primary_recipient: { customer_id: customerId },
      payment_requests: [{ request_type: "BALANCE" }],
    },
    idempotency_key:
      typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex"),
  });
  return data.invoice;
}
async function squarePublishInvoice({ req, invoiceId, version }) {
  const http = squareHttp(req);
  const idempotency_key =
    typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");
  const { data } = await http.post(`/v2/invoices/${invoiceId}/publish`, { idempotency_key, version });
  return data.invoice;
}
async function squareCreateQuickPayLink({ req, name, amountCents, currency = "USD", locationId }) {
  const http = squareHttp(req);
  const idempotency_key =
    typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");

  const { data } = await http.post("/v2/online-checkout/payment-links", {
    idempotency_key,
    quick_pay: {
      name,
      price_money: { amount: Number(amountCents), currency },
      location_id: locationId,
      payment_note: name,
    },
  });
  return data.payment_link;
}

/* ---------- write client_purchases on success ---------- */
async function createClientPurchaseFromPayment({ buyer, planName, amountCents, refId, payment }) {
  const db = admin.firestore();

  // Prefer explicit userId from buyer; fallback by email lookup
  let userId = buyer.userId || null;
  if (!userId && buyer.email) {
    const snap = await db
      .collection("users")
      .where("email", "==", buyer.email)
      .limit(1)
      .get();
    if (!snap.empty) userId = snap.docs[0].id;
  }
  if (!userId) {
    console.warn("  No userId found for purchase, skipping client_purchases / subscription write");
    return;
  }

  const planId = buyer.planId || null;
  const totalSessions = Number(buyer.sessions || 0);
  const priceDollars =
    buyer.price != null ? Number(buyer.price) : Number(amountCents || 0) / 100;

  const clientName = ((buyer.firstName || "") + " " + (buyer.lastName || "")).trim();

  //   Decide if this is the PDF workouts subscription plan
  const isPdfSubscription =
    buyer.planId === "pdf_subscription_monthly" ||
    buyer.planName === "PDF Workouts Monthly Subscription" ||
    planName === "PDF Workouts Monthly Subscription" ||
    buyer.isPdf === true ||
    buyer.type === "pdf";
  const isVideoSubscription =
    buyer.planId === "video_subscription_monthly" ||
    buyer.planName === "Video Workouts Monthly Subscription" ||
    planName === "Video Workouts Monthly Subscription" ||
    buyer.type === "video";

  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const paymentDocId = payment?.id && !String(payment.id).includes("/")
    ? String(payment.id)
    : null;

  //  1) Normal plans   write to client_purchases (for Active Plans dashboard)
  if (!isPdfSubscription && !isVideoSubscription) {
    const purchaseRef = paymentDocId
      ? db.collection("client_purchases").doc(paymentDocId)
      : db.collection("client_purchases").doc();
    const existingPurchase = await purchaseRef.get();
    if (existingPurchase.exists) {
      console.log("client_purchases already exists for payment:", purchaseRef.id);
      return;
    }

    const purchaseData = {
      purchaseId: purchaseRef.id,
      docId: purchaseRef.id,
      userId,
      clientName,
      planId,
      planName: buyer.planName || planName || "Training Plan",
      planCategory: buyer.planCategory || "",
      price: priceDollars,
      sessions: totalSessions,
      totalSessions: totalSessions,
      remainingSessions: totalSessions,
      bookedSessions: 0,
      usedSessions: 0,
      availableSessions: totalSessions,
      description: buyer.description || "",
      isActive: true,
      status: "active",
      purchaseDate: nowTs,
      createdAt: nowTs,
      updatedAt: nowTs,
      paymentMethod: "square",
      paymentStatus: (payment && payment.status) || "COMPLETED",
      isRepurchase: false,
      referenceId: refId || null,
      paymentId: payment?.id || null,
      email: buyer.email || "",
    };

    await purchaseRef.set(purchaseData);
    console.log(" client_purchases created:", purchaseRef.id);
  } else {
    console.log("Subscription purchase detected - skipping client_purchases for user:", userId);
  }

  //  2) Content subscriptions create entries used by workout tabs
  if (isPdfSubscription || isVideoSubscription) {
    try {
      console.log("Creating/Updating content subscription for user:", userId);

      // 30 days from now
      const nowDate = new Date();
      const endDate = new Date(nowDate.getTime() + 30 * 24 * 60 * 60 * 1000);

      const nowTsServer = admin.firestore.FieldValue.serverTimestamp();
      const startTs = admin.firestore.Timestamp.fromDate(nowDate);
      const endTs = admin.firestore.Timestamp.fromDate(endDate);

      const userName = clientName;
      const userEmail = buyer.email || "";

      const subscriptionType = isPdfSubscription ? "pdf" : "video";
      const subscriptionPlanName = buyer.planName || planName ||
        (isPdfSubscription
          ? "PDF Workouts Monthly Subscription"
          : "Video Workouts Monthly Subscription");

      // client_subscriptions (read by PDFWorkoutsTab / VideoWorkoutsTab)
      const subRef = paymentDocId
        ? db.collection("client_subscriptions").doc(paymentDocId)
        : db.collection("client_subscriptions").doc();
      const existingSub = await subRef.get();
      if (existingSub.exists) {
        console.log("client_subscriptions already exists for payment:", subRef.id);
        return;
      }
      await subRef.set({
        userId,
        userName,
        userEmail,
        planName: subscriptionPlanName,
        price: priceDollars,
        purchaseDate: startTs,
        startDate: startTs,
        endDate: endTs,
        isActive: true,
        status: "active",
        paymentMethod: "square",
        paymentStatus: (payment && payment.status) || "COMPLETED",
        timezone: "server",
        createdAt: nowTsServer,
        type: subscriptionType,
        isPdf: isPdfSubscription,
        paymentId: payment?.id || null,
        referenceId: refId || null,
      });

      if (isPdfSubscription) {
        // mirror to pdf_subscribers (for admin listing)
        await db.collection("pdf_subscribers").doc(subRef.id).set({
          userId,
          userName,
          userEmail,
          startDate: startTs,
          endDate: endTs,
          isActive: true,
          status: "active",
          createdAt: nowTsServer,
        });
      }

      console.log(" Content subscription created for user:", userId);
    } catch (err) {
      console.error("  Error creating content subscription:", err.message || err);
      throw err;
    }
  }
}


/* =========================
   EMAIL TRIGGERS
========================= */

/**
 * Booking created (new session)
 */
exports.notifyBookingOnCreate = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const bookedEmails = data.booked_emails || [];
    const bookedBy = data.booked_by || [];

    // Send chat messages first — runs even if no emails are configured
    const slotTime = data.time;
    const slotDate = formatSlotDateForDisplay(snap.id, data);
    const trainer = data.trainer_name || "your trainer";
    const isReschedule = data.is_reschedule === true;
    const formattedDate = formatSlotDateForDisplay(snap.id, data, {
      weekday: "long", month: "long", day: "numeric",
    });
    for (const uid of bookedBy) {
      if (!uid) continue;
      const msg = isReschedule
        ? `🔄 Session rescheduled\n📅 ${formattedDate}\n⏰ ${slotTime}\n👤 Trainer: ${trainer}`
        : `✅ Session booked!\n📅 ${formattedDate}\n⏰ ${slotTime}\n👤 Trainer: ${trainer}\n\nPlease arrive 5 minutes early.`;
      await sendSystemChatMessage(uid, msg, isReschedule ? "session_rescheduled" : "session_booked");
    }

    // Emails — only if emails are available
    if (isReschedule) {
      await snap.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
    }
    if (bookedEmails.length === 0) return;

    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
    const bookedNames = data.booked_names || [];

    // Build "Name (email)" pairs for trainer-facing emails
    const clientList = bookedEmails.map((email, i) => {
      const name = bookedNames[i] || email;
      return `${name} (${email})`;
    });

    // Send to clients  personalized per client
    await Promise.all(
      bookedEmails.map((email, i) => {
        const clientName = bookedNames[i] || "there";
        const subject = isReschedule
          ? `[RESCHEDULED] ${slotDate} ${slotTime}`
          : `[BOOKING CONFIRMED] ${slotDate} ${slotTime}`;
        const heading = isReschedule ? "Your session has been rescheduled" : "Your session has been scheduled";
        const introText = isReschedule
          ? `Hi ${clientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`
          : `Hi ${clientName},<br/>Your training session has been scheduled. Below are the details so you can add it to your calendar.`;
        const extraNote = isReschedule
          ? "If this time no longer works, you can reschedule again from the Flex Facility app."
          : "Please arrive 5 minutes early and bring a water bottle and towel.";
        const plainText = isReschedule
          ? `Hi ${clientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`
          : `Hi ${clientName},\n\nYour session is confirmed.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;
        const html = buildBookingEmailHtml({
          heading,
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText,
          extraNote,
        });
        return sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject,
          text: plainText,
          html,
        }).catch((err) => console.error(`Error sending booking (onCreate) to ${email}:`, err));
      })
    );



    // Trainer notification - always send to Kenny
    const trainerSubject = isReschedule
      ? `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`
      : `[TRAINER BOOKING] ${slotDate} ${slotTime}`;
    const trainerHeading = isReschedule ? "Session rescheduled" : "New session booked";
    const trainerIntro = isReschedule
      ? "One of your sessions has been rescheduled."
      : "A new client session has been booked in your schedule.";
    const trainerText = `Hi ${trainer},\n\n${isReschedule ? "A client session has been rescheduled." : "A new session has been booked."}\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient(s):\n${clientList.map((c) => `   ${c}`).join("\n")}\n\n Flex Facility`;
    const trainerHtml = buildBookingEmailHtml({
      heading: trainerHeading,
      statusColor: BRAND_COLORS.blue,
      slotDate,
      slotTime,
      trainer,
      introText: trainerIntro,
      extraNote: `Client(s): ${clientList.join(", ")}`,
    });

    await sendTransactionalEmail({
      to: trainerEmail,
      fromName: "Flex Facility Bookings",
      subject: trainerSubject,
      text: trainerText,
      html: trainerHtml,
    }).catch((err) => console.error(`Error sending trainer booking email to ${trainerEmail}:`, err));

  });

/**
 * Booking updated (newly booked, cancelled, or rescheduled)
 */
exports.handleBookingAndCancellation = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeEmails = before.booked_emails || [];
    const afterEmails = after.booked_emails || [];
    const beforeNames = before.booked_names || [];
    const afterNames = after.booked_names || [];
    const newlyBooked = afterEmails.filter((e) => !beforeEmails.includes(e));
    const cancelled = beforeEmails.filter((e) => !afterEmails.includes(e));
    const beforeBy = before.booked_by || [];
    const afterBy  = after.booked_by  || [];
    const newlyBookedUids = afterBy.filter((uid) => !beforeBy.includes(uid));
    const slotId = change.after.id || change.after.ref.id;

    // Helper to build "Name (email)" string
    const clientLabel = (email, emailArr, nameArr) => {
      const idx = emailArr.indexOf(email);
      const name = idx >= 0 && nameArr[idx] ? nameArr[idx] : email;
      return `${name} (${email})`;
    };

    const slotTime = after.time || before.time;
    const slotDate = formatSlotDateForDisplay(slotId, after.date ? after : before);
    const trainer = after.trainer_name || before.trainer_name || "your trainer";
    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();

    // ── Chat messages — runs FIRST before any early returns ──────────────────
    const chatDate = formatSlotDateForDisplay(slotId, after.date ? after : before, {
      weekday: "long", month: "long", day: "numeric",
    });
    const cancelledUids = beforeBy.filter((uid) => !afterBy.includes(uid));
    const isRescheduleCancelFlag = after.is_reschedule_cancel === true;
    const isRescheduleFlag = after.is_reschedule === true || before.is_reschedule === true;

    // Regular cancellation — skip if this is part of a reschedule flow
    if (!isRescheduleCancelFlag && cancelledUids.length > 0) {
      for (const uid of cancelledUids) {
        if (!uid) continue;
        await sendSystemChatMessage(
          uid,
          `❌ Session cancelled\n📅 ${chatDate}\n⏰ ${slotTime}\n\nYou can rebook anytime from Book Session.`,
          "session_cancelled"
        );
      }
    }

    // Reschedule — new slot booked as part of a reschedule
    if (isRescheduleFlag && newlyBookedUids.length > 0) {
      for (const uid of newlyBookedUids) {
        if (!uid) continue;
        await sendSystemChatMessage(
          uid,
          `🔄 Session rescheduled\n📅 ${chatDate}\n⏰ ${slotTime}\n👤 Trainer: ${trainer}`,
          "session_rescheduled"
        );
      }
    } else if (!isRescheduleFlag && newlyBookedUids.length > 0) {
      // Regular new booking (onUpdate path — slot already existed)
      for (const uid of newlyBookedUids) {
        if (!uid) continue;
        await sendSystemChatMessage(
          uid,
          `✅ Session booked!\n📅 ${chatDate}\n⏰ ${slotTime}\n👤 Trainer: ${trainer}\n\nPlease arrive 5 minutes early.`,
          "session_booked"
        );
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    const tasks = [];

    // If the old slot was flagged as a reschedule cancel, skip all email sending for it
    if (after.is_reschedule_cancel === true) {
      await change.after.ref.update({ is_reschedule_cancel: admin.firestore.FieldValue.delete() });
      return;
    }

    const isReschedule = before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      // Both added and removed on same doc (old path  keep existing logic)

      const email = newlyBooked[0];
      const rescheduleClientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();

      const text = `Hi ${rescheduleClientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been rescheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${rescheduleClientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`,
        extraNote: "If this time no longer works, you can reschedule again from the Flex Facility app.",
      });

      await sendTransactionalEmail({
        to: email,
        fromName: "Flex Facility Bookings",
        subject: `[RESCHEDULED] ${slotDate} ${slotTime}`,
        text,
        html,
      });

      if (trainerEmail) {
        const clientInfo = clientLabel(email, afterEmails, afterNames);
        const trainerText = `Hi ${trainer},

A client session has been rescheduled.

New Date: ${slotDate}
New Time: ${slotTime}
Client: ${clientInfo}

 Flex Facility`;
        const trainerHtml = buildBookingEmailHtml({
          heading: "Session rescheduled",
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText: "One of your sessions has been rescheduled.",
          extraNote: `Client: ${clientInfo}`,
        });

        await sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`,
          text: trainerText,
          html: trainerHtml,
        }).catch((err) =>
          console.error(`Error sending trainer reschedule email to ${trainerEmail}:`, err)
        );
      }

      if (after.is_reschedule) {
        await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
      }
      return;
    }

    // New path: is_reschedule flag on new slot (email only added here, cancel handled separately)
    if (after.is_reschedule === true && newlyBooked.length >= 1) {
      await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });

      for (const email of newlyBooked) {
        const clientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();
        const text = `Hi ${clientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;
        const html = buildBookingEmailHtml({
          heading: "Your session has been rescheduled",
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText: `Hi ${clientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`,
          extraNote: "If this time no longer works, you can reschedule again from the Flex Facility app.",
        });
        await sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[RESCHEDULED] ${slotDate} ${slotTime}`,
          text,
          html,
        }).catch((err) => console.error(`Error sending rescheduled email to ${email}:`, err));
      }

      // Trainer notification
      const reschedLabels = newlyBooked.map((e) => clientLabel(e, afterEmails, afterNames));
      const trainerText = `Hi ${trainer},\n\nA client session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nClient: ${reschedLabels.join(", ")}\n\n Flex Facility`;
      const trainerHtml = buildBookingEmailHtml({
        heading: "Session rescheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: "One of your sessions has been rescheduled.",
        extraNote: `Client: ${reschedLabels.join(", ")}`,
      });
      await sendTransactionalEmail({
        to: trainerEmail,
        fromName: "Flex Facility Bookings",
        subject: `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`,
        text: trainerText,
        html: trainerHtml,
      }).catch((err) => console.error(`Error sending trainer reschedule email:`, err));

      return;
    }

    // Newly booked
    const slotTimestamp = (after.date || before.date).toDate();
    const minsUntilSession = Math.round((slotTimestamp.getTime() - Date.now()) / 60000);
    const isLastMinuteBooking = minsUntilSession >= 0 && minsUntilSession <= 90;

    for (const email of newlyBooked) {
      const bookedClientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();
      const text = `Hi ${bookedClientName},\n\nYour session is confirmed.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n- Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been scheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${bookedClientName},<br/>Your training session has been scheduled. Below are the details so you can add it to your calendar.`,
        extraNote: "Please arrive 5 minutes early and bring a water bottle and towel.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[BOOKING CONFIRMED] ${slotDate} ${slotTime}`,
          text,
          html,
        })
      );


    }

    // Trainer notification for newly booked clients (non-reschedule)
    if (newlyBooked.length > 0) {
      const newLabels = newlyBooked.map((e) => clientLabel(e, afterEmails, afterNames));
      tasks.push(
        sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER BOOKING] ${slotDate} ${slotTime}`,
          text: `Hi ${trainer},\n\nA new session has been booked.\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient(s): ${newLabels.join(", ")}\n\n- Flex Facility`,
          html: buildBookingEmailHtml({
            heading: "New session booked",
            statusColor: BRAND_COLORS.blue,
            slotDate,
            slotTime,
            trainer,
            introText: "A client has just booked a session.",
            extraNote: `Client(s): ${newLabels.join(", ")}`,
          }),
        }).catch((err) => console.error(`Error sending trainer new booking email:`, err))
      );
    }

    // Cancelled
    for (const email of cancelled) {
      const cancelledClientName = (() => { const idx = beforeEmails.indexOf(email); return idx >= 0 && beforeNames[idx] ? beforeNames[idx] : "there"; })();
      const text = `Hi ${cancelledClientName},\n\nYour session has been cancelled.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nIf this was a mistake, you can rebook in the app.\n\n Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been cancelled",
        statusColor: BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${cancelledClientName},<br/>Your upcoming session has been cancelled. If this was a mistake, you can rebook a new time from the Flex Facility app.`,
        extraNote: "You will not be charged for this cancelled session.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[CANCELLED] ${cancelledClientName} - ${slotDate} ${slotTime}`,
          text,
          html,
        })
      );

      // Notify Kenny about the cancellation
      const clientInfo = clientLabel(email, beforeEmails, beforeNames);
      const trainerCancelText = `Hi ${trainer},\n\nA client has cancelled their session.\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient: ${clientInfo}\n\n Flex Facility`;
      const trainerCancelHtml = buildBookingEmailHtml({
        heading: "Session cancelled by client",
        statusColor: BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText: "A client has cancelled their upcoming session.",
        extraNote: `Client: ${clientInfo}`,
      });
      tasks.push(
        sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER CANCELLED] ${slotDate} ${slotTime}`,
          text: trainerCancelText,
          html: trainerCancelHtml,
        }).catch((err) => console.error(`Error sending trainer cancel email:`, err))
      );
    }



    if (tasks.length) await Promise.all(tasks);
  });

/* =========================
   EXPRESS APP
========================= */
const ALLOWED_ORIGINS = [
  "https://flex-facility-app-b55aa.web.app",
  "https://flex-facility-app-b55aa.firebaseapp.com",
];

const app = express();
app.use(cors({
  origin: (origin, callback) => {
    // Allow non-browser clients (Flutter mobile app) and whitelisted web origins
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return callback(null, true);
    callback(new Error("Not allowed by CORS"));
  },
  credentials: true,
}));
app.use(express.json());

const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests. Please wait a minute and try again." },
});

const paymentLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests. Please wait a minute and try again." },
});

/* =========================
   AUTH EMAILS: verify + reset
========================= */

const AUTH_CONTINUE_URL = "https://flex-facility-app-b55aa.web.app/email-verified.html";
const AUTH_RESET_CONTINUE_URL = "https://flex-facility-app-b55aa.web.app/password-reset-complete.html";

// Send email verification link
/* =========================
   AUTH EMAILS: verify + reset
========================= */

// Send email verification link
app.post("/auth/send-verification-email", authLimiter, async (req, res) => {
    try {
        const { email, displayName } = req.body || {};
        if (!email) {
            return res.status(400).json({ ok: false, error: "Missing email" });
        }

        const actionCodeSettings = {
      url: AUTH_CONTINUE_URL,
      handleCodeInApp: false,
        };

    // Generate Firebase action link and convert it to our hosted verification page URL.
        const link = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);
    let verifyUrl = link;
    try {
      const parsed = new URL(link);
      const mode = parsed.searchParams.get("mode") || "verifyEmail";
      const oobCode = parsed.searchParams.get("oobCode") || "";
      const apiKey = parsed.searchParams.get("apiKey") || "";

      if (oobCode && apiKey) {
      verifyUrl = `${AUTH_CONTINUE_URL}?mode=${encodeURIComponent(mode)}&oobCode=${encodeURIComponent(oobCode)}&apiKey=${encodeURIComponent(apiKey)}`;
      }
    } catch (parseErr) {
      console.warn("Unable to map Firebase verify link to custom page:", parseErr.message || parseErr);
    }
       
        const safeName = displayName ? ` ${displayName}` : "";
    const logoImgSrc = getLogoImgSrc();
       
        const emailHtml = `
            <div style="font-family:Arial,Helvetica,sans-serif;background:#f5f7fb;padding:20px;">
                <div style="max-width:600px;margin:auto;background:#ffffff;padding:20px;border-radius:10px;">
          <div style="text-align:center;margin-bottom:12px;">
            <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:inline-block;border-radius:50%;object-fit:cover;" />
          </div>
                    <h2 style="color:#1C2D5E;">Welcome to Flex Facility</h2>
                    <p>Hi${safeName},</p>
                    <p>Please verify your email address by clicking the button below:</p>
                    <div style="text-align:center;margin:25px 0;">
            <a href="${verifyUrl}"
                           style="background:#2563eb;color:#ffffff;padding:12px 20px;
                           text-decoration:none;border-radius:6px;font-weight:bold;">
                           Verify Email Address
                        </a>
                    </div>
                </div>
            </div>
        `;

    await sendTransactionalEmail({
            to: email,
            fromName: "Flex Facility",
            subject: "Verify your Flex Facility email address",
      text: `Hi${safeName},\n\nPlease tap the Verify Email Address button in this email to verify your account.\n\n`,
            html: emailHtml,
    });

        return res.json({ ok: true });
    } catch (e) {
        console.error("send-verification-email error:", e.message || e);
        return res.status(500).json({ ok: false, error: e.message });
    }
});

app.post("/auth/send-password-reset-email", authLimiter, async (req, res) => {
  try {
    const { email, displayName } = req.body || {};
    if (!email) {
      return res.status(400).json({ ok: false, error: "Missing email" });
    }

    const actionCodeSettings = {
      url: AUTH_RESET_CONTINUE_URL,
      handleCodeInApp: false,
    };

    const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
    const safeName = displayName ? ` ${displayName}` : "";
    const logoImgSrc = getLogoImgSrc();

    const emailHtml = `
      <div style="font-family:Arial,Helvetica,sans-serif;background:#f5f7fb;padding:20px;">
        <div style="max-width:600px;margin:auto;background:#ffffff;padding:20px;border-radius:10px;">
          <div style="text-align:center;margin-bottom:12px;">
            <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:inline-block;border-radius:50%;object-fit:cover;" />
          </div>
          <h2 style="color:#1C2D5E;">Reset your password</h2>
          <p>Hi${safeName},</p>
          <p>Please reset your password by clicking the button below:</p>
          <div style="text-align:center;margin:25px 0;">
            <a href="${resetLink}"
               style="background:#2563eb;color:#ffffff;padding:12px 20px;
               text-decoration:none;border-radius:6px;font-weight:bold;">
               Reset Password
            </a>
          </div>
        </div>
      </div>
    `;

    await sendTransactionalEmail({
      to: email,
      fromName: "Flex Facility",
      subject: "Reset your Flex Facility password",
      text: `Hi${safeName},\n\nPlease tap the Reset Password button in this email to reset your password.\n\n`,
      html: emailHtml,
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error("send-password-reset-email error:", e.message || e);
    return res.status(500).json({ ok: false, error: e.message });
  }
});
/* =========================
   Existing API routes
========================= */

app.get("/health", (req, res) => {
  let squareConfigured = false;
  let env = "sandbox";
  try {
    const cfg = getSquareConfig(req);
    squareConfigured = !!cfg.token;
    env = cfg.env;
  } catch (_) {
    squareConfigured = false;
  }
  res.json({ ok: true, function: "api", squareConfigured, env });
});

app.get("/checkout", (_req, res) => {
  const filePath = path.join(__dirname, "templates", "checkout.html");
  if (fs.existsSync(filePath)) {
    res.set("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(fs.readFileSync(filePath, "utf8"));
  } else {
    res
      .status(200)
      .send("<html><body><h3>Square Checkout</h3><p>templates/checkout.html not found.</p></body></html>");
  }
});

app.post("/checkout-session", paymentLimiter, async (req, res) => {
  try {
    const authUser = await requireFirebaseUser(req);
    const { planId, referenceId } = req.body || {};
    const plan = await resolvePaymentPlan(planId);
    const checkoutRef = admin.firestore().collection("checkout_sessions").doc();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1000);

    await checkoutRef.set({
      uid: authUser.uid,
      planId: plan.planId,
      planName: plan.planName,
      planCategory: plan.planCategory || "",
      planDescription: plan.description || "",
      sessions: plan.sessions || 0,
      amountCents: Math.round(Number(plan.price) * 100),
      priceDollars: Number(plan.price),
      type: plan.type || null,
      isPdf: plan.isPdf === true,
      referenceId: safeRefId(referenceId) || null,
      authToken: getBearerToken(req),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    });

    return res.json({ ok: true, checkoutId: checkoutRef.id });
  } catch (e) {
    const statusCode = e.statusCode || 400;
    return res.status(statusCode).json({
      ok: false,
      error: e.message || "Could not create checkout session.",
    });
  }
});

app.get("/checkout-session/:id", async (req, res) => {
  try {
    const id = (req.params.id || "").toString();
    const snap = await admin.firestore().collection("checkout_sessions").doc(id).get();
    if (!snap.exists) {
      return res.status(404).json({ ok: false, error: "Checkout session not found." });
    }
    const data = snap.data() || {};
    if (data.expiresAt?.toDate && data.expiresAt.toDate().getTime() < Date.now()) {
      return res.status(410).json({ ok: false, error: "Checkout session expired." });
    }
    return res.json({ ok: true, checkout: data });
  } catch (e) {
    return res.status(500).json({ ok: false, error: "Could not load checkout session." });
  }
});

/* =========================
   Card /process-payment (plan active immediately)
========================= */
app.post("/process-payment", paymentLimiter, async (req, res) => {
  try {
    const {
      token,
      amountCents: requestAmountCents,
      planName = "Fitness Plan",
      currency = "USD",
      locationId,
      verificationToken,
      buyer = {},
      billingDetails = {}, // line1, line2, locality, adminArea, postalCode, country
      referenceId,
    } = req.body || {};

    const bearerToken = getBearerToken(req);
    let authUser = null;
    let userProfile = null;
    if (bearerToken) {
      authUser = await admin.auth().verifyIdToken(bearerToken);
      userProfile = await getUserProfile(authUser.uid, authUser);
    }

    const planId = (req.body?.planId || buyer.planId || "").toString().trim();
    let plan;
    let amountCents;
    try {
      plan = await resolvePaymentPlan(planId);
      amountCents = Math.round(Number(plan.price) * 100);
    } catch (planErr) {
      if (authUser) throw planErr;
      amountCents = Math.round(Number(requestAmountCents || 0));
      plan = {
        planId: planId || buyer.planId || null,
        planName: buyer.planName || planName || "Training Plan",
        planCategory: buyer.planCategory || "",
        description: buyer.description || "",
        price: buyer.price != null ? Number(buyer.price) : amountCents / 100,
        sessions: Number(buyer.sessions || 0),
        type: buyer.type,
        isPdf: buyer.isPdf === true,
      };
      console.warn("process-payment: using legacy client-supplied plan data");
    }

    if (!token) {
      return res.status(400).json({ ok: false, error: "Missing card token." });
    }

    if (!Number.isFinite(amountCents) || amountCents <= 0 || amountCents > 1000000) {
      return res.status(400).json({ ok: false, error: "Invalid payment amount." });
    }

    const cfg = getSquareConfig(req);
    const env = cfg.env || "sandbox";

    const sandboxToken = (functions.config()?.square?.sandbox_token || "").trim();
    const prodToken = (functions.config()?.square?.prod_token || "").trim();

    const sandboxLocationId =
      (functions.config()?.square?.sandbox_location_id || functions.config()?.square?.location_id || "").trim();
    const prodLocationId =
      (functions.config()?.square?.prod_location_id || functions.config()?.square?.location_id || "").trim();

    const isProd = env === "production";
    const tokenToUse = isProd ? prodToken : sandboxToken;
    const locId = locationId || (isProd ? prodLocationId : sandboxLocationId);

    if (!tokenToUse) throw new Error(`Square ${env} token missing in functions config`);
    if (!locId) throw new Error(`Square ${env} locationId missing in functions config`);

    const trustedBuyer = {
      userId: authUser?.uid || buyer.userId || null,
      planId: plan.planId,
      planName: plan.planName,
      planCategory: plan.planCategory,
      sessions: plan.sessions,
      price: plan.price,
      description: plan.description,
      email: userProfile?.email || buyer.email || "",
      firstName: userProfile?.firstName || buyer.firstName || "",
      lastName: userProfile?.lastName || buyer.lastName || "",
      type: plan.type,
      isPdf: plan.isPdf === true,
    };

    // Create/find customer
    let customerId;
    try {
      const customer = await ensureSquareCustomer({
        req,
        email: trustedBuyer.email,
        given_name: trustedBuyer.firstName,
        family_name: trustedBuyer.lastName,
        referenceId: safeRefId(referenceId),
      });
      customerId = customer.id;
    } catch (e) {
      console.warn("ensureSquareCustomer warning:", e?.response?.data || e.message);
    }

    const refId = safeRefId(referenceId);
    const idempotencyKey =
      refId ||
      (typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex"));

    // Create order
    let orderId;
    try {
      const order = await squareCreateOrder({
        req,
        locationId: locId,
        name: plan.planName || "Training Plan",
        amountCents,
        currency,
        customerId,
        referenceId: refId,
      });
      orderId = order.id;
    } catch (e) {
      console.warn("squareCreateOrder warning:", e?.response?.data || e.message);
    }

    // Charge
    const result = await squareCreatePayment({
      req,
      sourceId: token.id || token,
      amountCents,
      currency,
      idempotencyKey,
      locationId: locId,
      verificationToken,
      orderId,
      customerId,
      referenceId: refId,
      note: `${trustedBuyer.firstName || ""} ${trustedBuyer.lastName || ""} - ${plan.planName}`,
      buyerEmail: trustedBuyer.email,
      billingAddress: buildSquareAddress(billingDetails),
    });

    const paymentStatus = (result.payment?.status || "").toString().toUpperCase();
    if (paymentStatus !== "COMPLETED") {
      return res.status(402).json({
        ok: false,
        error: "Payment was not completed.",
        paymentStatus,
      });
    }

    // Email receipt (best effort)
    if (trustedBuyer.email) {
      try {
        const dollars = (amountCents / 100).toFixed(2);

        const plainText = `Hi ${trustedBuyer.firstName || ""} ${trustedBuyer.lastName || ""},

      Your payment for "${plan.planName}" was successful.
      Amount: $${dollars}
      ${refId ? `Reference: ${refId}\n` : ""}
      Thank you,
      Flex Facility`;

        const html = buildPaymentSuccessHtml({
          firstName: trustedBuyer.firstName,
          lastName: trustedBuyer.lastName,
          planName: plan.planName,
          amount: dollars,
          referenceId: refId,
        });

        await sendTransactionalEmail({
          to: trustedBuyer.email,
          fromName: "Flex Facility Billing",
          subject: `Payment Successful - ${plan.planName}`,
          text: plainText,
          html,
        });
      } catch (e) {
        console.error("SendGrid error:", e?.response?.data || e.message);
      }
    }

    // Write access after Square confirms payment.
    await createClientPurchaseFromPayment({
      buyer: trustedBuyer,
      planName: plan.planName,
      amountCents,
      refId,
      payment: result.payment,
    });

    if (authUser?.uid) {
      const dollars = (amountCents / 100).toFixed(2);

      // ── Chat message to client ────────────────────────────────────────
      await sendSystemChatMessage(
        authUser.uid,
        `💳 Payment received!\n📋 Plan: ${plan.planName}\n💵 Amount: $${dollars}\n✅ ${plan.sessions > 0 ? plan.sessions + " sessions are now active" : "Access is now active"}.`,
        "payment_confirmed"
      );

      // ── FCM push to Kenny ─────────────────────────────────────────────
      try {
        const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
        const trainerSnap = await admin.firestore()
          .collection("users").where("email", "==", trainerEmail).limit(1).get();
        if (!trainerSnap.empty) {
          const fcmToken = trainerSnap.docs[0].data().fcm_token;
          const clientName = `${userProfile.firstName} ${userProfile.lastName}`.trim() || userProfile.email;
          if (fcmToken) {
            await admin.messaging().send({
              token: fcmToken,
              notification: {
                title: "💳 New Payment Received!",
                body: `${clientName} paid $${dollars} for ${plan.planName}`,
              },
              data: { type: "payment_received", clientId: authUser.uid },
              android: {
                priority: "high",
                notification: { channelId: "flex_high_importance", priority: "high", sound: "default" },
              },
              apns: { payload: { aps: { sound: "default", badge: 1 } }, headers: { "apns-priority": "10" } },
            });
            console.log(`Payment FCM sent to trainer for ${authUser.uid}`);
          }
        }
      } catch (e) {
        console.error("Payment FCM to trainer error:", e.message);
      }
    }

    return res.json({ ok: true, paymentId: result.payment?.id });
  } catch (e) {
    // Log only the message - never the full object which may contain tokens
    console.error("process-payment error:", e?.response?.data?.errors?.[0]?.code || e.message || "unknown");
    let clientMessage = "Payment failed. Please check your card details or try another card.";
    const statusCode = e.statusCode || 400;
    if (e.response?.data?.errors?.length) {
      const sqErr = e.response.data.errors[0];
      clientMessage = sqErr.detail || sqErr.message || clientMessage;
    } else if (e.statusCode) {
      clientMessage = e.message || clientMessage;
    }
    return res.status(statusCode).json({ ok: false, error: clientMessage });
  }
});

/* =========================
   Invoices (plan active on webhook)
========================= */

// Create & publish invoice, save metadata; DO NOT activate plan yet
app.post("/create-invoice", paymentLimiter, async (req, res) => {
  try {
    const cfg = getSquareConfig(req);
    const db = admin.firestore();

    const { plan = {}, customer = {}, userId } = req.body || {};

    const name = plan.name || "Fitness Plan";
    const price = Number(plan.price || 0);
    const amountCents = Math.round(price * 100);
    const description = plan.description || "";

    const email = customer.email || "customer@example.com";
    const given_name = customer.given_name || "";
    const family_name = customer.family_name || "";

    // 1) Create / find Square customer
    const cust = await ensureSquareCustomer({
      req,
      email,
      given_name,
      family_name,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId),
    });

    // 2) Create Square order for the invoice
    const order = await squareCreateOrder({
      req,
      locationId: cfg.locationId,
      name,
      amountCents,
      currency: "USD",
      customerId: cust.id,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId),
    });

    // 3) Create & publish invoice
    const draft = await squareCreateInvoice({
      req,
      locationId: cfg.locationId,
      orderId: order.id,
      customerId: cust.id,
      title: name,
      description,
    });

    const published = await squarePublishInvoice({
      req,
      invoiceId: draft.id,
      version: draft.version,
    });

    // 4) Save metadata for webhook
    const metaRef = db.collection("invoice_metadata").doc(published.id);
    const metaData = {
      invoiceId: published.id,
      userId: userId || plan.userId || null,
      planId: plan.docId || plan.id || null,
      planName: plan.name || name,
      planCategory: plan.category || "",
      sessions: plan.sessions || 0,
      price: price, // dollars
      description,
      email,
      firstName: given_name,
      lastName: family_name,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId) || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      processed: false,
    };

    await metaRef.set(metaData);

    // Return invoice to client (includes public_url)
    return res.json({ ok: true, invoice: published });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("create-invoice error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

// Webhook: called by Square when invoice is paid -> activate plan
// Webhook: called by Square when invoice is paid -> activate plan
app.post("/square-webhook", async (req, res) => {
  try {
    // Verify Square HMAC-SHA256 signature to reject forged webhook calls
    const sigKey = (functions.config()?.square?.webhook_signature_key || "").trim();
    if (sigKey) {
      const squareSig = req.headers["x-square-signature"] || "";
      const webhookUrl = `https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api/square-webhook`;
      const payload = JSON.stringify(req.body);
      const expected = crypto
        .createHmac("sha256", sigKey)
        .update(webhookUrl + payload)
        .digest("base64");
      if (squareSig !== expected) {
        console.warn("square-webhook: invalid signature - request rejected");
        return res.status(403).json({ ok: false, error: "Invalid webhook signature" });
      }
    }

    const eventType = req.body.type || req.body.event_type;
    const dataObject = req.body.data && req.body.data.object;
    const invoice = dataObject && dataObject.invoice;

    if (!eventType || !invoice) {
      console.warn("square-webhook: missing eventType or invoice in payload");
      return res.status(200).send("ignored");
    }

    console.log("square-webhook event:", eventType, "invoiceId:", invoice.id);

    if (eventType !== "invoice.payment_made" && eventType !== "invoice.paid") {
      return res.status(200).send("ignored event type");
    }

    const invoiceId = invoice.id;
    const db = admin.firestore();
    const metaRef = db.collection("invoice_metadata").doc(invoiceId);
    const metaSnap = await metaRef.get();  //  fixed line

    if (!metaSnap.exists) {
      console.warn("square-webhook: no invoice_metadata for", invoiceId);
      return res.status(200).send("no metadata");
    }

    const meta = metaSnap.data() || {};

    if (meta.processed) {
      console.log("square-webhook: invoice already processed", invoiceId);
      return res.status(200).send("already processed");
    }

    // Build buyer object
    const buyer = {
      userId: meta.userId || null,
      planId: meta.planId || null,
      planName: meta.planName || "Training Plan",
      planCategory: meta.planCategory || "",
      sessions: meta.sessions || 0,
      price: meta.price || 0,
      description: meta.description || "",
      firstName: meta.firstName || "",
      lastName: meta.lastName || "",
      email: meta.email || "",
    };

    const amountCents = Math.round(Number(meta.price || 0) * 100);

    // Create client_purchases entry so plan is ACTIVE in app
    await createClientPurchaseFromPayment({
      buyer,
      planName: meta.planName,
      amountCents,
      refId: meta.referenceId || invoiceId,
      payment: null,
    });

    await metaRef.update({
      processed: true,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("square-webhook: plan activated for invoice", invoiceId);
    return res.status(200).send("ok");
  } catch (e) {
    console.error("square-webhook error:", e.response?.data || e);
    return res.status(500).send("error");
  }
});


/* =========================
   Create/Send Pay Link
========================= */

app.post("/payment-link/email", paymentLimiter, async (req, res) => {
  try {
    const cfg = getSquareConfig(req);

    const {
      planName,
      amountCents,            // required if publicUrl not provided
      recipientEmail,
      recipientName = "",
      publicUrl,              // optional: if provided, we email this directly
    } = req.body || {};

    if (!planName || !recipientEmail) {
      return res.status(400).json({ ok: false, error: "Missing planName or recipientEmail" });
    }

    // Determine which URL to send
    let url = (publicUrl || "").trim();
    if (!url) {
      if (!amountCents) {
        return res.status(400).json({
          ok: false,
          error: "amountCents required when publicUrl is not provided",
        });
      }
      const link = await squareCreateQuickPayLink({
        req,
        name: planName,
        amountCents: Number(amountCents),
        currency: "USD",
        locationId: cfg.locationId,
      });
      url = link.url;
    }

    const safeName = recipientName ? ` ${recipientName}` : "";

    const html = `
      <div style="font-family:Arial,Helvetica,sans-serif;color:#222;line-height:1.6">
        <h2 style="color:#1C2D5E;">Complete your payment  ${planName}</h2>
        <p>Hi${safeName},</p>
        <p>Your secure payment link for <b>${planName}</b> is ready.</p>
        <p>
          <a href="${url}"
             style="display:inline-block;padding:10px 16px;background:#2563eb;color:#fff;text-decoration:none;border-radius:6px;">
            Pay Now
          </a>
        </p>
        ${
          amountCents
            ? `<p>Amount: <b>$${(Number(amountCents) / 100).toFixed(2)}</b></p>`
            : ""
        }
        <p>If the button doesnt work, copy and paste this URL:</p>
        <p style="word-break:break-all"><a href="${url}">${url}</a></p>
        <p style="margin-top:20px;color:#555;font-size:14px;">
          Need help? Email <a href="mailto:${REPLY_TO.email}">${REPLY_TO.email}</a>.
        </p>
      </div>
    `;

    await sendTransactionalEmail({
      to: recipientEmail,
      fromName: "Flex Facility Billing",
      subject: `Payment link " ${planName}`,
      text: `Hi${safeName},\n\nPlease complete your payment for "${planName}" using this secure link:\n${url}\n\nThank you,\nFlex Facility`,
      html,
    });

    return res.json({ ok: true, url });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("payment-link/email error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});
// Add this endpoint BEFORE the existing routes
// Serve verification page from templates
app.get("/verify-email", (req, res) => {
    const templatePath = path.join(__dirname, "templates", "verify-email.html");
   
    if (fs.existsSync(templatePath)) {
        res.set("Content-Type", "text/html; charset=utf-8");
        res.status(200).send(fs.readFileSync(templatePath, "utf8"));
    } else {
        // Fallback if template doesn't exist
        res.set("Content-Type", "text/html; charset=utf-8");
        res.status(200).send(`
            <!DOCTYPE html>
            <html>
            <head>
                <title>Email Verification - Flex Facility</title>
                <meta charset="UTF-8">
            </head>
            <body>
                <div style="text-align: center; padding: 50px;">
                    <h2>Email Verification</h2>
                    <p>Processing your verification...</p>
                    <script>
                        const urlParams = new URLSearchParams(window.location.search);
                        const mode = urlParams.get('mode');
                        const oobCode = urlParams.get('oobCode');
                        const apiKey = urlParams.get('apiKey');
                       
                        if (mode === 'verifyEmail' && oobCode) {
                            fetch('/api/verify-email-handler', {
                                method: 'POST',
                                headers: {'Content-Type': 'application/json'},
                                body: JSON.stringify({mode, oobCode, apiKey})
                            })
                            .then(res => res.json())
                            .then(data => {
                                if (data.success) {
                                    window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?verified=true';
                                } else {
                                    window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?error=verification_failed';
                                }
                            })
                            .catch(() => {
                                window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?error=network_error';
                            });
                        }
                    </script>
                </div>
            </body>
            </html>
        `);
    }
});

// POST handler for actual verification
app.post("/verify-email-handler", async (req, res) => {
    try {
        const { mode, oobCode, apiKey } = req.body;
       
        if (mode !== 'verifyEmail' || !oobCode) {
            return res.status(400).json({
                success: false,
                error: "Invalid verification request"
            });
        }
       
        // Get Web API Key from config or use the one from request
        let webApiKey = apiKey;
        if (!webApiKey) {
            try {
                webApiKey = functions.config()?.firebase?.web_api_key;
            } catch(e) {
                // If not set in config, you need to add it
                console.error("Web API Key not configured. Run: firebase functions:config:set firebase.web_api_key=\"YOUR_KEY\"");
            }
        }
       
        if (!webApiKey) {
            return res.status(400).json({
                success: false,
                error: "Service configuration error"
            });
        }
       
        // Call Firebase Auth REST API to verify the email
        const response = await axios.post(
          `https://identitytoolkit.googleapis.com/v1/accounts:update?key=${webApiKey}`,
            {
                oobCode: oobCode
            }
        );
       
        console.log("Email verified successfully:", response.data);
       
        return res.json({
            success: true,
            message: "Email verified successfully"
        });
       
    } catch (error) {
        console.error("Email verification error:", error.response?.data || error.message);
       
        let errorMessage = "Verification failed";
        if (error.response?.data?.error?.message) {
            const fbError = error.response.data.error.message;
            if (fbError === "INVALID_OOB_CODE") {
                errorMessage = "The verification link has expired or is invalid";
            } else if (fbError === "OPERATION_NOT_ALLOWED") {
                errorMessage = "Email verification is not enabled";
            } else {
                errorMessage = fbError;
            }
        }
       
        return res.status(400).json({
            success: false,
            error: errorMessage
        });
    }
});
// Mount Express
exports.api = functions.https.onRequest(app);

/**
 * Chat: sends an FCM push to the recipient whenever a new message is written.
 * Conversation document ID = clientUid (one doc per client).
 */
exports.onNewChatMessage = functions
  .runWith({ memory: '128MB', timeoutSeconds: 30 })
  .firestore.document('conversations/{clientId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { clientId } = context.params;
    const senderRole = data.senderRole; // 'client' | 'admin' | 'system'
    const text = (data.text || '').toString();
    const preview = text.length > 120 ? text.substring(0, 120) + '…' : text;
    const db = admin.firestore();

    // System messages (automated: booking, payment, reminder) — no push needed.
    // The client can see these in their chat history; a push would be noisy/confusing.
    if (senderRole === 'system') return null;

    try {
      if (senderRole === 'client') {
        // Client sent a message → notify trainer
        const convSnap = await db.collection('conversations').doc(clientId).get();
        const clientName = convSnap.exists
          ? (convSnap.data().clientName || 'Client')
          : 'Client';

        const trainerEmail = (functions.config()?.trainer?.email || 'Kenny@flextraining.co').trim();
        const trainerSnap = await db.collection('users')
          .where('email', '==', trainerEmail)
          .limit(1)
          .get();

        if (trainerSnap.empty) return null;
        const fcmToken = trainerSnap.docs[0].data().fcm_token;
        if (!fcmToken) return null;

        await admin.messaging().send({
          token: fcmToken,
          notification: { title: clientName, body: preview },
          data: { type: 'chat_message', clientId, senderRole: 'client' },
          android: {
            priority: 'high',
            notification: { channelId: 'flex_high_importance', priority: 'high', sound: 'default' },
          },
          apns: {
            payload: { aps: { sound: 'default', badge: 1 } },
            headers: { 'apns-priority': '10' },
          },
        });

        console.log(`Chat FCM sent to trainer for message from client ${clientId}`);

      } else {
        // Admin sent a message → notify the specific client
        const clientDoc = await db.collection('users').doc(clientId).get();
        if (!clientDoc.exists) return null;
        const fcmToken = clientDoc.data().fcm_token;
        if (!fcmToken) return null;

        await admin.messaging().send({
          token: fcmToken,
          notification: { title: 'Kenny Sims', body: preview },
          data: { type: 'chat_message', clientId, senderRole: 'admin' },
          android: {
            priority: 'high',
            notification: { channelId: 'flex_high_importance', priority: 'high', sound: 'default' },
          },
          apns: {
            payload: { aps: { sound: 'default', badge: 1 } },
            headers: { 'apns-priority': '10' },
          },
        });

        console.log(`Chat FCM sent to client ${clientId}`);
      }
    } catch (e) {
      console.error('onNewChatMessage error:', e.message || e);
    }

    return null;
  });

// Notify trainer when a new client signs up
exports.onNewUserSignup = functions.auth.user().onCreate(async (user) => {
  try {
    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
    const clientEmail = user.email || "Unknown";
    const clientName = user.displayName || clientEmail.split("@")[0];
    const signupTime = new Date().toLocaleString("en-US", { timeZone: "America/Chicago" });
    const logoImgSrc = getLogoImgSrc();

    await sendTransactionalEmail({
      to: trainerEmail,
      fromName: "Flex Facility",
      subject: `New Client Signed Up - ${clientName}`,
      text:
        `Hi,\n\nA new client has signed up for Flex Facility.\n\n` +
        `Name: ${clientName}\nEmail: ${clientEmail}\nSigned up: ${signupTime}\n\n- Flex Facility`,
      html:
        `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
        `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
        `<tr><td style="padding:24px;">` +
        `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
        `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
        `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
        `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">New Client Signed Up</div>` +
        `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">A new client has joined Flex Facility.</p>` +
        `</td></tr>` +
        `<tr><td style="padding:16px 24px 8px 24px;">` +
        `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Client details</p>` +
        `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Name</td><td style="padding:4px 0;"><strong>${clientName}</strong></td></tr>` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Email</td><td style="padding:4px 0;"><strong>${clientEmail}</strong></td></tr>` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Signed up</td><td style="padding:4px 0;"><strong>${signupTime}</strong></td></tr>` +
        `</table>` +
        `</td></tr>` +
        `<tr><td style="padding:16px 24px 24px 24px;">` +
        `<p style="margin:0;font-size:14px;color:#4b5563;">You can view their profile in the Flex Facility admin dashboard.</p>` +
        `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Facility</p>` +
        `</td></tr></table></td></tr></table></div>`,
    });
    console.log(`New signup notification sent to trainer for user: ${clientEmail}`);

    // Chat message: welcome message to new client
    await sendSystemChatMessage(
      user.uid,
      `👋 Welcome to Flex Facility, ${clientName}!\n\nYou can book sessions, view your workouts, and message Kenny right here.\n\nLet's get started! 💪`,
      "welcome"
    );
  } catch (e) {
    console.error("Failed to send new signup notification:", e.message);
  }
});

/**
 * Scheduled session reminder  runs every hour.
 * Finds slots starting in about 30 minutes and sends email + push notification
 * to every booked client who has an FCM token saved.
 */
exports.sendSessionReminders = functions
  .runWith({ memory: "256MB", timeoutSeconds: 120 })
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();

    // Window: 25-40 min from now. Non-overlapping with consecutive 15-min runs so each
    // slot gets exactly one reminder at ~30 min before session time.
    const windowStart = new Date(now.getTime() + 25 * 60 * 1000);
    const windowEnd   = new Date(now.getTime() + 40 * 60 * 1000);

    const slotsSnap = await db.collection("trainer_slots")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    if (slotsSnap.empty) {
      console.log("No upcoming slots in reminder window.");
      return null;
    }

    for (const slotDoc of slotsSnap.docs) {
      const slot = slotDoc.data();

      // Skip cancelled slots entirely
      if (slot.status === "cancelled" || slot.cancelled === true) continue;

      const bookedEmails = slot.booked_emails || [];
      const bookedBy = slot.booked_by || [];
      const statusByUser = slot.status_by_user || {};
      const slotTime     = slot.time || "";
      const slotDate     = formatSlotDateForDisplay(slotDoc.id, slot, {
        weekday: "long", month: "long", day: "numeric"
      });
      const trainer      = slot.trainer_name || "your trainer";
      const reminderTimeLabel = "30 minutes";
      // Use booked_by as primary loop — always populated even if emails missing
      for (let i = 0; i < bookedBy.length; i++) {
        const uid   = bookedBy[i];
        const email = bookedEmails[i] || null;
        if (!uid) continue;

        // Skip individually cancelled clients
        if (statusByUser[uid] === "Cancelled") continue;
        try {
          // Send email and push only if email address is available
          if (email) {
            const logoImgSrc = getLogoImgSrc();
            await sendTransactionalEmail({
              to: email,
              fromName: "Flex Facility",
              subject: `[REMINDER] Upcoming Session - ${slotTime} on ${slotDate}`,
              text:
                `Hi,\n\nThis is a reminder that your training session with ${trainer} is coming up ${reminderTimeLabel}.\n\n` +
                `Date: ${slotDate}\nTime: ${slotTime}\n\n` +
                `Please make sure to arrive on time.\n\n- Flex Training`,
              html:
                `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
                `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
                `<tr><td style="padding:24px;">` +
                `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
                `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
                `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
                `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">Session Reminder</div>` +
                `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">This is a reminder that your training session with <strong>${trainer}</strong> is coming up <strong>${reminderTimeLabel}</strong>.</p>` +
                `</td></tr>` +
                `<tr><td style="padding:16px 24px 8px 24px;">` +
                `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Session details</p>` +
                `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
                `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Date</td><td style="padding:4px 0;"><strong>${slotDate}</strong></td></tr>` +
                `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Time</td><td style="padding:4px 0;"><strong>${slotTime}</strong></td></tr>` +
                `</table>` +
                `</td></tr>` +
                `<tr><td style="padding:16px 24px 24px 24px;">` +
                `<p style="margin:0;font-size:14px;color:#4b5563;">Please make sure to arrive on time.</p>` +
                `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Training</p>` +
                `</td></tr></table></td></tr></table></div>`,
            });
            console.log(`Reminder email sent to ${email} for slot ${slotDoc.id}`);

            // Push notification
            const userDoc = await db.collection("users").doc(uid).get();
            const fcmToken = userDoc.exists ? userDoc.data().fcm_token : null;
            if (fcmToken) {
              await admin.messaging().send({
                token: fcmToken,
                notification: {
                  title: "Session Reminder",
                  body: `Your session with ${trainer} is in 30 minutes.`,
                },
                android: {
                  priority: "high",
                  notification: { channelId: "session_reminders", priority: "high", sound: "default" },
                },
                apns: {
                  payload: { aps: { sound: "default", badge: 1, contentAvailable: true } },
                  headers: { "apns-priority": "10" },
                },
                data: { slotId: slotDoc.id, type: "reminder" },
              });
              console.log(`Reminder push sent to ${email} (${uid}) for slot ${slotDoc.id}`);
            }
          }

          // Chat message: always runs regardless of email availability
          await sendSystemChatMessage(
            uid,
            `🔔 Session reminder!\n📅 ${slotDate}\n⏰ ${slotTime}\n👤 Trainer: ${trainer}\n\nSee you soon — don't forget to bring water!`,
            "session_reminder"
          );
        } catch (e) {
          console.error(`Failed to send reminder to ${uid}:`, e);
        }
      }

      // Send reminder to trainer if there are booked clients
      if (bookedBy.length > 0) {
        try {
          const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
          const clientNames = (slot.booked_names || []).join(", ") || "clients";
          const logoImgSrc = getLogoImgSrc();
          await sendTransactionalEmail({
            to: trainerEmail,
            fromName: "Flex Facility",
            subject: `[REMINDER] Upcoming Session - ${slotTime} on ${slotDate}`,
            text:
              `Hi ${trainer},\n\nThis is a reminder that you have a session coming up in 30 minutes.\n\n` +
              `Date: ${slotDate}\nTime: ${slotTime}\nClients: ${clientNames}\n\n- Flex Facility`,
            html:
              `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
              `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
              `<tr><td style="padding:24px;">` +
              `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
              `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
              `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
              `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">Session Reminder</div>` +
              `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">Hi <strong>${trainer}</strong>, you have a session coming up in <strong>30 minutes</strong>.</p>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 8px 24px;">` +
              `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Session details</p>` +
              `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Date</td><td style="padding:4px 0;"><strong>${slotDate}</strong></td></tr>` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Time</td><td style="padding:4px 0;"><strong>${slotTime}</strong></td></tr>` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Clients</td><td style="padding:4px 0;"><strong>${clientNames}</strong></td></tr>` +
              `</table>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 24px 24px;">` +
              `<p style="margin:0;font-size:14px;color:#4b5563;">Please make sure to be ready on time.</p>` +
              `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Facility</p>` +
              `</td></tr></table></td></tr></table></div>`,
          });
          console.log(`Trainer reminder sent to ${trainerEmail} for slot ${slotDoc.id}`);
        } catch (e) {
          console.error("Failed to send trainer reminder:", e.message);
        }
      }
    }

    return null;
  });

/* =============================================================================
   AUTOMATION 1 — Plan Expiry
   Runs daily at 9 AM Central.
   • Sends a reminder 7 days before a subscription expires.
   • Deactivates subscriptions whose endDate has passed.
   • Deactivates purchases with 0 remaining sessions.
============================================================================= */
exports.checkPlanExpiry = functions
  .runWith({ memory: "256MB", timeoutSeconds: 120 })
  .pubsub.schedule("every day 09:00")
  .timeZone("America/Chicago")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();
    const in7Days = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

    // ── 1. 7-day expiry reminders ──────────────────────────────────────────
    const expiringSoon = await db
      .collection("client_subscriptions")
      .where("isActive", "==", true)
      .where("status", "==", "active")
      .where("endDate", ">=", admin.firestore.Timestamp.fromDate(now))
      .where("endDate", "<=", admin.firestore.Timestamp.fromDate(in7Days))
      .get();

    for (const doc of expiringSoon.docs) {
      const data = doc.data();
      if (!data.userId || data.expiryReminderSent) continue;

      const userDoc = await db.collection("users").doc(data.userId).get();
      if (!userDoc.exists) continue;
      const fcmToken = userDoc.data().fcm_token;

      const daysLeft = Math.max(
        1,
        Math.ceil((data.endDate.toDate() - now) / (1000 * 60 * 60 * 24))
      );
      const planName = data.planName || "your plan";

      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "Plan Expiring Soon",
            body: `${planName} expires in ${daysLeft} day${daysLeft !== 1 ? "s" : ""}. Renew now to keep your sessions.`,
          },
          data: { type: "plan_expiry_reminder", daysLeft: String(daysLeft) },
          android: {
            priority: "high",
            notification: { channelId: "flex_high_importance", priority: "high", sound: "default" },
          },
          apns: { payload: { aps: { sound: "default", badge: 1 } } },
        }).catch((e) => console.error("Expiry reminder FCM error:", e.message));
      }

      // Chat message: plan expiring soon
      await sendSystemChatMessage(
        data.userId,
        `⚠️ Your plan is expiring soon!\n📋 Plan: ${planName}\n📅 Expires in ${daysLeft} day${daysLeft !== 1 ? "s" : ""}\n\nRenew from Plans to keep booking sessions.`,
        "plan_expiring"
      );

      await doc.ref.update({ expiryReminderSent: true });
      console.log(`Expiry reminder sent: user=${data.userId} plan=${planName} daysLeft=${daysLeft}`);
    }

    // ── 2. Auto-deactivate expired subscriptions ───────────────────────────
    const expired = await db
      .collection("client_subscriptions")
      .where("isActive", "==", true)
      .where("endDate", "<", admin.firestore.Timestamp.fromDate(now))
      .get();

    if (!expired.empty) {
      const batch = db.batch();
      for (const doc of expired.docs) {
        batch.update(doc.ref, {
          isActive: false,
          status: "expired",
          expiredAt: admin.firestore.FieldValue.serverTimestamp(),
          expiryReminderSent: false,
        });
        console.log(`Subscription expired: ${doc.id}`);
      }
      await batch.commit();
    }

    // ── 3. Auto-deactivate purchases with 0 sessions left ─────────────────
    const depleted = await db
      .collection("client_purchases")
      .where("isActive", "==", true)
      .where("remainingSessions", "<=", 0)
      .get();

    if (!depleted.empty) {
      const batch2 = db.batch();
      for (const doc of depleted.docs) {
        batch2.update(doc.ref, {
          isActive: false,
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Purchase completed (0 sessions): ${doc.id}`);
      }
      await batch2.commit();
    }

    console.log(
      `checkPlanExpiry — reminders=${expiringSoon.size} expired=${expired.size} depleted=${depleted.size}`
    );
    return null;
  });

/* =============================================================================
   AUTOMATION 2 — Client Re-engagement
   Runs every Monday at 9 AM Central.
   • Finds active clients with a plan who have NOT booked in 14 days.
   • Pushes a nudge to the client.
   • Alerts the trainer with a summary of at-risk clients.
============================================================================= */
exports.checkClientEngagement = functions
  .runWith({ memory: "256MB", timeoutSeconds: 180 })
  .pubsub.schedule("every monday 09:00")
  .timeZone("America/Chicago")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();
    const cutoff = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);

    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
    const trainerSnap = await db
      .collection("users")
      .where("email", "==", trainerEmail)
      .limit(1)
      .get();
    const trainerFcm = trainerSnap.empty
      ? null
      : trainerSnap.docs[0].data().fcm_token || null;

    const clientsSnap = await db
      .collection("users")
      .where("role", "==", "client")
      .where("isActive", "==", true)
      .get();

    const atRisk = [];

    for (const clientDoc of clientsSnap.docs) {
      const uid = clientDoc.id;
      const cData = clientDoc.data();

      // Skip if no active plan — no point nudging
      const planSnap = await db
        .collection("client_purchases")
        .where("userId", "==", uid)
        .where("isActive", "==", true)
        .limit(1)
        .get();
      if (planSnap.empty) continue;

      // Skip if booked recently
      const recentSnap = await db
        .collection("trainer_slots")
        .where("booked_by", "array-contains", uid)
        .where("date", ">=", admin.firestore.Timestamp.fromDate(cutoff))
        .limit(1)
        .get();
      if (!recentSnap.empty) continue;

      atRisk.push(cData.name || "Client");

      if (cData.fcm_token) {
        await admin.messaging().send({
          token: cData.fcm_token,
          notification: {
            title: "Miss the gym? 💪",
            body: "You have sessions available. Book your next training session now.",
          },
          data: { type: "re_engagement" },
          android: {
            priority: "high",
            notification: { channelId: "flex_high_importance", sound: "default" },
          },
          apns: { payload: { aps: { sound: "default", badge: 1 } } },
        }).catch((e) => console.error(`Re-engagement FCM failed uid=${uid}:`, e.message));
        console.log(`Re-engagement push sent: ${uid}`);
      }
    }

    if (atRisk.length > 0 && trainerFcm) {
      const names = atRisk.join(", ");
      await admin.messaging().send({
        token: trainerFcm,
        notification: {
          title: `${atRisk.length} client${atRisk.length > 1 ? "s" : ""} inactive for 14+ days`,
          body: names.length > 120 ? names.substring(0, 120) + "…" : names,
        },
        data: { type: "at_risk_clients", count: String(atRisk.length) },
        android: {
          priority: "high",
          notification: { channelId: "flex_high_importance" },
        },
      }).catch((e) => console.error("Trainer at-risk FCM error:", e.message));
    }

    console.log(`checkClientEngagement — atRisk=${atRisk.length}`);
    return null;
  });

/* =============================================================================
   AUTOMATION 3 — Waitlist Auto-fill
   Fires whenever a trainer_slots document is updated.
   • Detects a cancellation (booked_by array shrinks).
   • Sends a push to the first person on the waitlist.
   • Removes them from the waitlist (15-min window to claim the slot).
============================================================================= */
exports.handleWaitlistOnCancellation = functions
  .runWith({ memory: "128MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    const db = admin.firestore();

    const beforeBy = before.booked_by || [];
    const afterBy = after.booked_by || [];
    const waitlist = after.waitlist || [];

    const cancelled = beforeBy.filter((uid) => !afterBy.includes(uid));
    if (cancelled.length === 0 || waitlist.length === 0) return null;

    const firstUid = waitlist[0];
    const userDoc = await db.collection("users").doc(firstUid).get();
    if (!userDoc.exists) return null;

    const uData = userDoc.data();
    const fcmToken = uData.fcm_token;
    const slotTime = after.time || "";
    const slotDate = formatSlotDateForDisplay(change.after.id, after.date ? after : before, {
      weekday: "long", month: "long", day: "numeric",
    });

    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "🎉 A spot opened up!",
          body: `${slotDate} · ${slotTime} — Tap to claim your spot.`,
        },
        data: {
          type: "waitlist_available",
          slotId: change.after.id,
          slotTime,
          slotDate,
        },
        android: {
          priority: "high",
          notification: { channelId: "flex_high_importance", priority: "high", sound: "default" },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
          headers: { "apns-priority": "10" },
        },
      }).catch((e) => console.error("Waitlist FCM error:", e.message));
      console.log(`Waitlist notification sent: uid=${firstUid} slot=${change.after.id}`);
    }

    await change.after.ref.update({
      waitlist: admin.firestore.FieldValue.arrayRemove(firstUid),
    });

    return null;
  });

/* =============================================================================
   AUTOMATION 4 — Post-Session Rating Prompts
   Runs every 15 minutes. Finds slots that ended 30–45 min ago and sends a
   rating prompt FCM to each booked client (once per slot).
============================================================================= */
exports.sendSessionRatingPrompts = functions
  .runWith({ memory: "256MB", timeoutSeconds: 120 })
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();

    // Non-overlapping 15-min window: slots that ended 30–45 min ago
    const windowStart = new Date(now.getTime() - 45 * 60 * 1000);
    const windowEnd   = new Date(now.getTime() - 30 * 60 * 1000);

    const slotsSnap = await db.collection("trainer_slots")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    if (slotsSnap.empty) return null;

    for (const slotDoc of slotsSnap.docs) {
      const slot = slotDoc.data();

      // Skip cancelled slots or already prompted
      if (slot.status === "cancelled" || slot.cancelled === true) continue;
      if (slot.ratingPromptSent === true) continue;

      const bookedEmails = slot.booked_emails || [];
      const bookedBy     = slot.booked_by     || [];
      const statusByUser = slot.status_by_user || {};
      const slotTime = slot.time || "";
      const slotDate = formatSlotDateForDisplay(slotDoc.id, slot, {
        weekday: "long", month: "long", day: "numeric",
      });

      for (let i = 0; i < bookedBy.length; i++) {
        const uid   = bookedBy[i];
        const email = bookedEmails[i];
        if (!uid) continue;

        // Skip individually cancelled clients
        if (statusByUser[uid] === "Cancelled") continue;

        try {
          const userDoc = await db.collection("users").doc(uid).get();
          if (!userDoc.exists) continue;
          const fcmToken = userDoc.data().fcm_token;
          if (!fcmToken) continue;

          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: "How was your session? ⭐",
              body: `Rate your training session on ${slotDate}`,
            },
            data: {
              type: "session_rating_prompt",
              slotId: slotDoc.id,
              slotTime,
              slotDate,
            },
            android: {
              priority: "high",
              notification: {
                channelId: "flex_high_importance",
                priority: "high",
                sound: "default",
              },
            },
            apns: {
              payload: { aps: { sound: "default", badge: 1 } },
              headers: { "apns-priority": "10" },
            },
          });
          console.log(`Rating prompt sent to ${email || uid} for slot ${slotDoc.id}`);
        } catch (e) {
          console.error(`Rating prompt failed for ${uid}:`, e.message || e);
        }
      }

      // Mark slot so prompt is not sent again
      await slotDoc.ref.update({ ratingPromptSent: true });
    }

    return null;
  });

/* =============================================================================
   NEW WORKOUT ASSIGNED — chat message when Kenny assigns a workout to a client
============================================================================= */
exports.onWorkoutAssigned = functions
  .runWith({ memory: "128MB", timeoutSeconds: 30 })
  .firestore.document("client_workouts/{workoutId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const userId = data.userId || data.clientId;
    if (!userId) return null;

    const workoutName = data.workout_name || data.name || "a new workout";
    const trainer = data.trainer || data.trainerName || "Kenny";

    await sendSystemChatMessage(
      userId,
      `💪 New workout from ${trainer}!\n🏋️ ${workoutName}\n\nOpen Workouts to view your exercises.`,
      "workout_assigned"
    );

    return null;
  });
