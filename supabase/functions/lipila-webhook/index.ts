// ═══════════════════════════════════════════════════════════════
// LIPILA WEBHOOK — Fixed per Lipila Standard Webhooks spec
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
// @ts-ignore shared module import
import { settleReference, enqueueChurchAutoPayouts } from "../_shared/settlement.ts";

interface LipilaWebhookPayload {
  referenceId: string;
  identifier: string;
  currency: string;
  amount: number;
  accountNumber: string;
  status: string;
  paymentType: string;
  type: string;
  ipAddress: string;
  message: string;
  externalId?: string;
  referenceData?: string;
  narration?: string;
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Rate limiting: simple in-memory (per IP, 60 req/min)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 60;
const RATE_WINDOW_MS = 60_000;

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

// Verify Lipila webhook signature per Standard Webhooks spec
// Signature = v1,<base64(HMAC-SHA256(secret, webhookId + "." + webhookTimestamp + "." + rawBody))>
async function verifySignature(
  bodyText: string,
  signatureHeader: string,
  webhookId: string,
  webhookTimestamp: string,
): Promise<boolean> {
  if (!webhookSecret) {
    console.error("[Webhook] FATAL: No webhook secret configured — rejecting all requests");
    return false;
  }

  // Reject if timestamp is older than 5 minutes (replay attack prevention)
  const timestamp = parseInt(webhookTimestamp, 10);
  if (isNaN(timestamp) || Math.abs(Date.now() / 1000 - timestamp) > 300) {
    console.warn(`[Webhook] Timestamp too old or invalid: ${webhookTimestamp}`);
    return false;
  }

  // Construct the signed payload per Lipila spec
  const signedPayload = `${webhookId}.${webhookTimestamp}.${bodyText}`;

  // Base64-decode the secret to get raw 32-byte key
  let keyBytes: Uint8Array;
  try {
    keyBytes = Uint8Array.from(atob(webhookSecret), (c) => c.charCodeAt(0));
  } catch {
    console.error("[Webhook] Failed to base64-decode webhook secret");
    return false;
  }

  // Compute HMAC-SHA256
  const cryptoKey = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "HMAC", hash: "SHA-256" },
    false, ["verify"],
  );
  const msgBytes = new TextEncoder().encode(signedPayload);
  const expectedSig = "v1," + btoa(
    String.fromCharCode(...new Uint8Array(
      await crypto.subtle.sign("HMAC", cryptoKey, msgBytes)
    ))
  );

  // Parse space-delimited signatures from the header (supports key rotation)
  const signatures = signatureHeader.split(" ");
  for (const sig of signatures) {
    const trimmed = sig.trim();
    if (trimmed === expectedSig) return true;
    // Also compare without v1, prefix in case Lipila sends it differently
    if (trimmed.startsWith("v1,") && trimmed.slice(3) === expectedSig.slice(3)) return true;
  }

  return false;
}

function mapLipilaStatus(status: string): string {
  const s = status.toLowerCase().trim();
  switch (s) {
    case "successful":
    case "paid":
    case "completed":
    case "settled":
    case "success":
    case "approved":
    case "accepted":
    case "confirmed":
      return "settled";
    case "failed":
    case "cancelled":
    case "rejected":
    case "declined":
    case "error":
    case "timeout":
      return "failed";
    case "pending":
    case "processing":
      return "pending";
    default:
      return "pending";
  }
}

async function processWebhook(payload: LipilaWebhookPayload): Promise<Response> {
  const startTime = Date.now();

  // Use identifier (our internal reference) to look up the payment
  const reference = payload.identifier || "";
  const lipilaReferenceId = payload.referenceId || "";
  const idempotencyKey = `lipila-${lipilaReferenceId}`;

  console.log(
    `[Webhook] Processing: ref=${reference}, lipilaRef=${lipilaReferenceId}, status=${payload.status}`,
  );

  if (!reference) {
    console.warn("[Webhook] No identifier in payload — cannot match payment");
    return new Response(
      JSON.stringify({ status: "ignored", reason: "no_identifier" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // ── IDEMPOTENCY CHECK ──────────────────────────────────
  const newStatus = mapLipilaStatus(payload.status);

  const existing = await supabase
    .from("coa_payments")
    .select("id, status, webhook_idempotency")
    .eq("payment_ref", reference)
    .maybeSingle();

  if (existing?.data) {
    const currentStatus = (existing.data.status || "").toLowerCase();
    if (currentStatus === newStatus) {
      console.log(
        `[Webhook] Idempotent — already ${currentStatus} for ref=${reference}`,
      );
      return new Response(
        JSON.stringify({
          status: "already_processed",
          payment_id: existing.data.id,
          previous_status: existing.data.status,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }
  }

  // Stronger dedup: the same Lipila reference delivered twice with the same
  // status must be processed exactly once, regardless of the internal ref.
  if (idempotencyKey) {
    const { data: byKey } = await supabase
      .from("coa_payments")
      .select("id, status")
      .eq("webhook_idempotency", idempotencyKey)
      .maybeSingle();
    if (byKey && (byKey.status || "").toLowerCase() === newStatus) {
      console.log(
        `[Webhook] Idempotent (webhook_idempotency) — already ${newStatus} for key=${idempotencyKey}`,
      );
      return new Response(
        JSON.stringify({
          status: "already_processed",
          payment_id: byKey.id,
          previous_status: byKey.status,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }
  }

  // ── MAP STATUS ─────────────────────────────────────────
  const statusMessage =
    newStatus === "settled"
      ? "Payment completed and settled"
      : newStatus === "failed"
        ? "Payment failed"
        : `Payment status: ${payload.status}`;

  // ── UPDATE PAYMENT RECORD ──────────────────────────────
  const updateData: Record<string, unknown> = {
    status: newStatus,
    updated_at: new Date().toISOString(),
  };

  if (newStatus === "settled") {
    updateData.settled_at = new Date().toISOString();
  }
  if (idempotencyKey) updateData.webhook_idempotency = idempotencyKey;
  if (payload.amount) updateData.amount = payload.amount;
  if (payload.accountNumber) updateData.phone_number = payload.accountNumber;
  if (payload.paymentType) updateData.network = payload.paymentType;

  let paymentId: string | null = null;
  let userId: string | null = null;

  // Try to update existing payment
  const { data: existingData, error: updateError } = await supabase
    .from("coa_payments")
    .update(updateData)
    .eq("payment_ref", reference)
    .select("id, user_id, amount")
    .single();

  if (!updateError && existingData) {
    paymentId = existingData.id;
    userId = existingData.user_id;
  } else {
    console.warn(
      `[Webhook] No existing payment found for ref=${reference}, inserting new record`,
    );

    // Fallback: insert a new payment record
    // We need user_id — try to find it via profiles table using phone number
    let resolvedUserId: string | null = null;
    if (payload.accountNumber) {
      const { data: profile } = await supabase
        .from("profiles")
        .select("id")
        .eq("phone", payload.accountNumber)
        .maybeSingle();
      if (profile) {
        resolvedUserId = profile.id;
      }
    }

    if (!resolvedUserId) {
      console.error(
        `[Webhook] Cannot insert payment record: no user_id for ref=${reference} and phone=${payload.accountNumber}`,
      );
      return new Response(
        JSON.stringify({
          status: "error",
          reason: "cannot_resolve_user",
          reference,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    const { data: insertData, error: insertError } = await supabase
      .from("coa_payments")
      .insert({
        user_id: resolvedUserId,
        payment_ref: reference,
        amount: payload.amount || 0,
        status: newStatus,
        settled_at: newStatus === "settled" ? new Date().toISOString() : null,
        webhook_idempotency: idempotencyKey || null,
        phone_number: payload.accountNumber || null,
        network: payload.paymentType || null,
      })
      .select("id, user_id")
      .single();

    if (insertError) {
      console.error(
        `[Webhook] Failed to insert fallback payment: ${insertError.message}`,
      );
      return new Response(
        JSON.stringify({ error: "Processing failed" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
    paymentId = insertData.id;
    userId = insertData.user_id;
  }

  // ── NOTIFY USER ────────────────────────────────────────
  if (userId && newStatus === "settled") {
    await supabase.from("notifications").insert({
      user_id: userId,
      title: "Payment Successful",
      body: `Your payment of K${payload.amount} has been confirmed.`,
      type: "payment_success",
      reference_id: reference,
    });
  }

  // ── SERVER-SIDE SETTLEMENT ─────────────────────────────
  // On a confirmed collection, disburse any queued payout_tasks for this
  // reference (giving / order settlements). Ride/delivery/escrow tasks and
  // anything enqueued after this webhook are picked up by the lps-settle cron.
  // Settlement failure here is non-fatal — the cron retries.
  if (newStatus === "settled" && paymentId) {
    try {
      const settle = await settleReference(supabase, reference);
      console.log(
        `[Webhook] Settlement for ref=${reference}: checked=${settle.checked}, paid=${settle.paid}, failed=${settle.failed}`,
      );
    } catch (settleErr) {
      console.error(`[Webhook] Settlement failed for ref=${reference}: ${settleErr}`);
    }

    // ── CHURCH AUTO-PAYOUT ────────────────────────────────
    // A fresh confirmed collection may push a church's withdrawable balance
    // over the threshold — enqueue its aggregate treasurer payout now so the
    // church doesn't wait up to 5 minutes for the cron. Idempotent + atomic.
    try {
      const enqueued = await enqueueChurchAutoPayouts(supabase);
      if (enqueued.enqueued > 0) {
        console.log(
          `[Webhook] Church auto-payout: enqueued=${enqueued.enqueued} churches (threshold K${enqueued.thresholdKwacha})`,
        );
      }
    } catch (enqueueErr) {
      console.error(`[Webhook] Church auto-payout enqueue failed: ${enqueueErr}`);
    }
  }

  const elapsed = Date.now() - startTime;
  console.log(
    `[Webhook] Completed in ${elapsed}ms: ref=${reference}, status=${newStatus}`,
  );

  return new Response(
    JSON.stringify({
      status: "processed",
      payment_id: paymentId,
      new_status: newStatus,
      processing_time_ms: elapsed,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
}

serve(async (req: Request) => {
  const startTime = Date.now();
  const clientIp =
    req.headers.get("x-forwarded-for") ||
    req.headers.get("cf-connecting-ip") ||
    "unknown";

  // ── RATE LIMIT CHECK ───────────────────────────────────
  if (!checkRateLimit(clientIp)) {
    console.warn(`[Webhook] Rate limit exceeded for IP: ${clientIp}`);
    return new Response(
      JSON.stringify({ error: "Too many requests" }),
      {
        status: 429,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  // ── REJECT if webhook secret not configured ────────────
  if (!webhookSecret) {
    console.error(
      `[Webhook] FATAL: LIPILA_WEBHOOK_SECRET not configured — rejecting request from ${clientIp}`,
    );
    return new Response(
      JSON.stringify({ error: "Webhook not configured" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  // ── AUTH CHECK (HMAC signature required) ───────────────
  // Lipila sends the signature in `webhook-signature` (standard webhooks
  // convention). Accept `x-webhook-signature` as a fallback for providers
  // that prefix the header. Header lookups are case-insensitive.
  const signature =
    req.headers.get("webhook-signature") ||
    req.headers.get("x-webhook-signature") ||
    "";

  if (!signature) {
    console.warn(`[Webhook] Missing webhook-signature header from IP: ${clientIp}`);
    return new Response(
      JSON.stringify({ status: "ignored", reason: "missing_signature" }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  try {
    // Read body as text for signature verification
    const bodyText = await req.text();

    // Extract Lipila webhook headers
    const webhookId = req.headers.get("webhook-id") || "";
    const webhookTimestamp = req.headers.get("webhook-timestamp") || "";

    const isValid = await verifySignature(
      bodyText,
      signature,
      webhookId,
      webhookTimestamp,
    );

    if (!isValid) {
      console.warn(`[Webhook] Invalid HMAC signature from IP: ${clientIp}`);
      return new Response(
        JSON.stringify({ status: "ignored", reason: "invalid_signature" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const payload: LipilaWebhookPayload = JSON.parse(bodyText);

    const result = await processWebhook(payload);

    // ── AUDIT LOG ──────────────────────────────────────────
    const elapsed = Date.now() - startTime;
    await supabase
      .from("audit_logs")
      .insert({
        action: "webhook_processed",
        entity_type: "coa_payments",
        entity_id: payload.identifier || payload.referenceId,
        changes: {
          event: payload.type,
          status: payload.status,
          reference: payload.identifier,
          processing_time_ms: elapsed,
        },
        ip_address: clientIp,
        user_agent: "lipila-webhook",
      })
      .catch(() => {}); // Non-critical

    return result;
  } catch (err) {
    console.error(`[Webhook] Error: ${err}`);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});