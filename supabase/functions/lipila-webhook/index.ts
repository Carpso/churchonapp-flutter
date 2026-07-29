// ═══════════════════════════════════════════════════════════════
// LIPILA WEBHOOK - Production Hardened with Idempotency
// ═══════════════════════════════════════════════════════════════

// @ts-ignore Deno global declaration for non-Deno IDEs
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

// @ts-ignore URL import resolution for Supabase Edge Functions
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore URL import resolution for Supabase Edge Functions
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface WebhookPayload {
  event: string;
  reference?: string;
  transactionRef?: string;
  amount?: number;
  phone?: string;
  network?: string;
  status?: string;
  idempotencyKey?: string;
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Rate limiting: simple in-memory (per IP, 60 req/min)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 60; // requests
const RATE_WINDOW_MS = 60_000; // 1 minute

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

// Verify webhook signature
async function verifySignature(payload: string, signature: string): Promise<boolean> {
  if (!webhookSecret) {
    console.warn("[Webhook] No webhook secret configured — skipping signature verification");
    return true;
  }
  const encoder = new TextEncoder();
  const keyBytes = encoder.encode(webhookSecret);
  const msgBytes = encoder.encode(payload);

  // HMAC-SHA256 verification
  const cryptoKey = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "HMAC", hash: "SHA-256" },
    false, ["verify"]
  );
  const sigBytes = hexToBytes(signature);
  return await crypto.subtle.verify(
    "HMAC",
    cryptoKey,
    sigBytes.buffer as ArrayBuffer,
    msgBytes.buffer as ArrayBuffer
  );
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

async function processWebhook(payload: WebhookPayload): Promise<Response> {
  const startTime = Date.now();
  const reference = payload.reference || payload.transactionRef || "";
  const idempotencyKey = payload.idempotencyKey || `webhook-${reference}-${payload.event}`;

  console.log(`[Webhook] Processing: event=${payload.event}, ref=${reference}`);

  // ── IDEMPOTENCY CHECK ──────────────────────────────────────
  // Check if this webhook was already processed
  const existing = await supabase
    .from("coa_payments")
    .select("id, status, webhook_idempotency")
    .eq("webhook_idempotency", idempotencyKey)
    .maybeSingle();

  if (existing?.data) {
    console.log(`[Webhook] Idempotent call — already processed event=${payload.event}, ref=${reference}`);
    return new Response(JSON.stringify({
      status: "already_processed",
      payment_id: existing.data.id,
      previous_status: existing.data.status
    }), { headers: { "Content-Type": "application/json" } });
  }

  // ── MAP EVENT TO STATUS ────────────────────────────────────
  let newStatus = "";
  let statusMessage = "";

  switch (payload.event?.toLowerCase()) {
    case "payment.success":
    case "collection.completed":
    case "transaction.successful":
      newStatus = "settled";
      statusMessage = "Payment completed and settled";
      break;
    case "payment.failed":
    case "collection.failed":
    case "transaction.failed":
      newStatus = "failed";
      statusMessage = "Payment failed";
      break;
    case "payment.pending":
    case "transaction.pending":
      newStatus = "pending";
      statusMessage = "Payment pending";
      break;
    case "payment.refunded":
      newStatus = "refunded";
      statusMessage = "Payment refunded";
      break;
    default:
      // Try to infer from status field
      const rawStatus = (payload.status || "").toLowerCase();
      if (["successful", "paid", "completed", "settled", "success", "approved", "accepted", "confirmed"].includes(rawStatus)) {
        newStatus = "settled";
        statusMessage = "Payment completed";
      } else if (["failed", "cancelled", "rejected", "declined", "error", "timeout"].includes(rawStatus)) {
        newStatus = "failed";
        statusMessage = "Payment " + rawStatus;
      } else {
        newStatus = "pending";
        statusMessage = "Payment status: " + rawStatus;
      }
  }

  // ── UPDATE PAYMENT RECORD ──────────────────────────────────
  const updateData: Record<string, unknown> = {
    status: newStatus,
    webhook_idempotency: idempotencyKey,
    updated_at: new Date().toISOString(),
  };

  if (newStatus === "settled") {
    updateData.settled_at = new Date().toISOString();
  }
  if (payload.amount) updateData.amount = payload.amount;
  if (payload.network) updateData.network = payload.network;
  if (payload.phone) updateData.phone_number = payload.phone;

  let paymentId: string | null = null;

  if (reference) {
    // Update existing payment
    const { data, error } = await supabase
      .from("coa_payments")
      .update(updateData)
      .eq("payment_ref", reference)
      .select("id, user_id, amount, category, metadata")
      .single();

    if (error) {
      console.error(`[Webhook] Failed to update payment: ${error.message}`);
      // Try inserting a new record
      const { data: insertData, error: insertError } = await supabase
        .from("coa_payments")
        .insert({
          payment_ref: reference,
          amount: payload.amount || 0,
          status: newStatus,
          webhook_idempotency: idempotencyKey,
          settled_at: newStatus === "settled" ? new Date().toISOString() : null,
        })
        .select("id")
        .single();

      if (insertError) {
        console.error(`[Webhook] Failed to insert fallback payment: ${insertError.message}`);
        return new Response(JSON.stringify({ error: "Processing failed" }), {
          status: 500, headers: { "Content-Type": "application/json" }
        });
      }
      paymentId = insertData.id;
    } else {
      paymentId = data?.id || null;

      // ── NOTIFY USER ────────────────────────────────────────
      if (data?.user_id && newStatus === "settled") {
        await supabase.from("notifications").insert({
          user_id: data.user_id,
          title: "Payment Successful",
          body: `Your payment of K${data.amount} has been confirmed.`,
          type: "payment_success",
          reference_id: reference,
        });
      }
    }
  }

  const elapsed = Date.now() - startTime;
  console.log(`[Webhook] Completed in ${elapsed}ms: event=${payload.event}, ref=${reference}, status=${newStatus}`);

  return new Response(JSON.stringify({
    status: "processed",
    payment_id: paymentId,
    new_status: newStatus,
    processing_time_ms: elapsed
  }), { headers: { "Content-Type": "application/json" } });
}

serve(async (req: Request) => {
  const startTime = Date.now();
  const clientIp = req.headers.get("x-forwarded-for") || req.headers.get("cf-connecting-ip") || "unknown";

  // ── RATE LIMIT CHECK ───────────────────────────────────────
  if (!checkRateLimit(clientIp)) {
    console.warn(`[Webhook] Rate limit exceeded for IP: ${clientIp}`);
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429, headers: { "Content-Type": "application/json" }
    });
  }

  // ── AUTH CHECK (HMAC signature required) ───────────────────
  const signature = req.headers.get("x-webhook-signature") || "";

  if (webhookSecret && !signature) {
    console.warn(`[Webhook] Missing HMAC signature from IP: ${clientIp}`);
    return new Response(JSON.stringify({ error: "Unauthorized: missing signature" }), {
      status: 401, headers: { "Content-Type": "application/json" }
    });
  }

  try {
    let payload: WebhookPayload;

    if (webhookSecret) {
      // Read body as text for signature verification
      const bodyText = await req.text();
      const isValid = await verifySignature(bodyText, signature);
      if (!isValid) {
        console.warn(`[Webhook] Invalid HMAC signature from IP: ${clientIp}`);
        return new Response(JSON.stringify({ error: "Invalid signature" }), {
          status: 403, headers: { "Content-Type": "application/json" }
        });
      }
      payload = JSON.parse(bodyText);
    } else {
      payload = await req.json();
    }

    const result = await processWebhook(payload);

    // ── AUDIT LOG ────────────────────────────────────────────
    const elapsed = Date.now() - startTime;
    await supabase.from("audit_logs").insert({
      action: "webhook_processed",
      entity_type: "coa_payments",
      entity_id: payload.reference || payload.transactionRef,
      changes: { event: payload.event, status: payload.status, processing_time_ms: elapsed },
      ip_address: clientIp,
      user_agent: "lipila-webhook",
    }).catch(() => { }); // Non-critical

    return result;
  } catch (err) {
    console.error(`[Webhook] Error: ${err}`);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500, headers: { "Content-Type": "application/json" }
    });
  }
});