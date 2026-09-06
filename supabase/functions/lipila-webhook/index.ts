// ═══════════════════════════════════════════════════════════════
// LIPILA WEBHOOK — dual auth (?secret= URL param OR Standard
// Webhooks HMAC header), referenceId-first resolution, disbursement
// confirmations acked without touching coa_payments, audit trail on
// every delivery (received/processed/rejected).
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
  referenceId?: string;
  reference_id?: string;
  identifier?: string;
  currency?: string;
  amount?: number;
  accountNumber?: string;
  status?: string;
  paymentType?: string;
  type?: string;
  ipAddress?: string;
  message?: string;
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

// Constant-time string comparison for the URL query secret.
function constantEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
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
  const s = (status || "").toLowerCase().trim();
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

function isPayoutLike(payload: LipilaWebhookPayload): boolean {
  const label = `${payload.type ?? ""} ${payload.paymentType ?? ""}`;
  return /disburs|payout|withdraw|settlement/i.test(label);
}

async function audit(
  action: string,
  entityId: string | null,
  details: Record<string, unknown>,
  clientIp: string,
): Promise<void> {
  try {
    // NOTE: audit_logs stores the payload in `details` (jsonb) — there is no
    // `changes`/`user_agent` column, so those inserts used to fail silently.
    await supabase.from("audit_logs").insert({
      action,
      entity_type: "coa_payments",
      entity_id: entityId || null,
      details: { ...details, user_agent: "lipila-webhook" },
      ip_address: clientIp,
    });
  } catch {
    // Non-critical
  }
}

async function processWebhook(
  payload: LipilaWebhookPayload,
  clientIp: string,
): Promise<Response> {
  const startTime = Date.now();

  // Canonical reference: Lipila echoes our referenceId back on webhooks
  // (chisomo/kingdom contract). identifier is a legacy/secondary key.
  const reference = payload.referenceId || payload.reference_id || payload.identifier || "";
  const idempotencyKey = `lipila-${reference}`;
  const status = (payload.status || "pending").toLowerCase();
  const newStatus = mapLipilaStatus(status);

  console.log(
    `[Webhook] Processing: ref=${reference}, status=${status}`,
  );

  if (!reference) {
    console.warn("[Webhook] No reference (referenceId/reference_id/identifier) in payload");
    await audit("webhook_received", null, { event: payload.type, status, reason: "no_reference" }, clientIp);
    return new Response(
      JSON.stringify({ status: "ignored", reason: "no_reference" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // ── IDEMPOTENCY / DEDUP ─────────────────────────────────
  for (const q of [
    supabase.from("coa_payments").select("id, status").eq("payment_ref", reference).maybeSingle(),
    supabase.from("coa_payments").select("id, status").eq("webhook_idempotency", idempotencyKey).maybeSingle(),
  ]) {
    const { data: hit } = await q;
    if (hit) {
      const prior = (hit.status || "").toLowerCase();
      if (prior === newStatus) {
        await audit("webhook_received", hit.id, { event: payload.type, status, reference, reason: "already_processed" }, clientIp);
        return new Response(
          JSON.stringify({ status: "already_processed", payment_id: hit.id, previous_status: hit.status }),
          { headers: { "Content-Type": "application/json" } },
        );
      }
    }
  }

  let paymentId: string | null = null;
  let userId: string | null = null;

  const { data: existing, error: existingError } = await supabase
    .from("coa_payments")
    .select("id, user_id, status")
    .eq("payment_ref", reference)
    .maybeSingle();

  if (existing && !existingError) {
    const updateData: Record<string, unknown> = {
      status: newStatus,
      updated_at: new Date().toISOString(),
    };
    if (newStatus === "settled") updateData.settled_at = new Date().toISOString();
    if (idempotencyKey) updateData.webhook_idempotency = idempotencyKey;
    if (payload.amount) updateData.amount = payload.amount;
    if (payload.accountNumber) updateData.phone_number = payload.accountNumber;
    if (payload.paymentType) updateData.network = payload.paymentType;

    const { data: updated, error: updateError } = await supabase
      .from("coa_payments")
      .update(updateData)
      .eq("payment_ref", reference)
      .select("id, user_id")
      .single();

    if (!updateError && updated) {
      paymentId = updated.id;
      userId = updated.user_id;
    } else {
      paymentId = existing.id;
      userId = existing.user_id;
    }
  } else {
    // No pre-created row. Payout/disbursement confirmations must NEVER be
    // turned into a synthetic coa_payments row (that would pollute the giving
    // ledger and could let a matched reference double-count). Ack only.
    if (isPayoutLike(payload)) {
      await audit("webhook_received", null, { event: payload.type, status, reference, reason: "payout_confirmation" }, clientIp);
      console.log(`[Webhook] Payout confirmation acked (no ledger row): ref=${reference}`);
      return new Response(
        JSON.stringify({ status: "ignored", reason: "payout_confirmation" }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // Genuine collection delivered without a pre-created row: only register it
    // when the payer can be resolved server-side by phone, else ack unknown.
    let resolvedUserId: string | null = null;
    if (payload.accountNumber) {
      const { data: profile } = await supabase
        .from("profiles")
        .select("id")
        .eq("phone", payload.accountNumber)
        .maybeSingle();
      if (profile) resolvedUserId = profile.id;
    }

    if (!resolvedUserId) {
      await audit("webhook_received", null, { event: payload.type, status, reference, reason: "unknown_reference" }, clientIp);
      return new Response(
        JSON.stringify({ status: "ignored", reason: "unknown_reference", reference }),
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
      console.error(`[Webhook] Failed to insert fallback payment: ${insertError.message}`);
      await audit("webhook_received", null, { event: payload.type, status, reference, reason: "insert_failed" }, clientIp);
      return new Response(
        JSON.stringify({ error: "Processing failed" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
    paymentId = insertData.id;
    userId = insertData.user_id;
  }

  await audit(
    "webhook_received",
    paymentId,
    { event: payload.type, status, reference, amount: payload.amount, payment_type: payload.paymentType, reason: "matched" },
    clientIp,
  );

  // ── NOTIFY USER ────────────────────────────────────────
  if (userId && newStatus === "settled") {
    await supabase.from("notifications").insert({
      user_id: userId,
      title: "Payment Successful",
      body: `Your payment of K${payload.amount ?? ""} has been confirmed.`,
      type: "payment_success",
      reference_id: reference,
    }).catch(() => {});
  }

  // ── SERVER-SIDE SETTLEMENT ─────────────────────────────
  if (newStatus === "settled" && paymentId) {
    try {
      const settle = await settleReference(supabase, reference);
      console.log(
        `[Webhook] Settlement for ref=${reference}: checked=${settle.checked}, paid=${settle.paid}, failed=${settle.failed}`,
      );
    } catch (settleErr) {
      console.error(`[Webhook] Settlement failed for ref=${reference}: ${settleErr}`);
    }

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
  await audit(
    "webhook_processed",
    paymentId,
    { event: payload.type, status, reference, processing_time_ms: elapsed },
    clientIp,
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
      { status: 429, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── REJECT if webhook secret not configured ────────────
  if (!webhookSecret) {
    console.error(
      `[Webhook] FATAL: LIPILA_WEBHOOK_SECRET not configured — rejecting request from ${clientIp}`,
    );
    return new Response(
      JSON.stringify({ error: "Webhook not configured" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  // Read body as text (needed for HMAC verification).
  const bodyText = await req.text();

  // ── AUTH — DUAL SCHEME ─────────────────────────────────
  // 1. `?secret=<LIPILA_WEBHOOK_SECRET>` appended to the callbackUrl we send
  //    ourselves (chisomo/kingdom contract — Lipila echoes the callbackUrl
  //    query string verbatim).
  // 2. Standard Webhooks HMAC headers (webhook-id / webhook-timestamp /
  //    webhook-signature). Accept x-webhook-signature as an alias.
  const url = new URL(req.url);
  const querySecret = url.searchParams.get("secret") || "";
  const signature =
    req.headers.get("webhook-signature") ||
    req.headers.get("x-webhook-signature") ||
    "";
  const webhookId = req.headers.get("webhook-id") || "";
  const webhookTimestamp = req.headers.get("webhook-timestamp") || "";

  let authed = false;
  let authMethod = "none";

  if (querySecret && constantEqual(querySecret, webhookSecret)) {
    authed = true;
    authMethod = "query";
  }
  if (!authed && signature) {
    try {
      if (await verifySignature(bodyText, signature, webhookId, webhookTimestamp)) {
        authed = true;
        authMethod = "hmac";
      }
    } catch {
      authed = false;
    }
  }

  if (!authed) {
    const provided = querySecret || signature;
    const reason = provided ? "invalid_signature" : "missing_signature";
    console.warn(`[Webhook] ${reason} from IP: ${clientIp} (authMethod=${authMethod})`);
    const res = new Response(
      JSON.stringify({ status: "ignored", reason }),
      { status: provided ? 401 : 200, headers: { "Content-Type": "application/json" } },
    );
    // Every rejected delivery is audited so a provider that authenticates
    // differently is visible in audit_logs instead of silently vanishing.
    await audit(
      "webhook_rejected",
      null,
      { reason, provided_auth: provided ? "yes" : "none", auth_method: authMethod },
      clientIp,
    );
    return res;
  }

  let payload: LipilaWebhookPayload;
  try {
    const parsed: unknown = JSON.parse(bodyText);
    payload = (parsed && typeof parsed === "object" ? parsed : {}) as LipilaWebhookPayload;
  } catch {
    await audit("webhook_rejected", null, { reason: "invalid_json" }, clientIp).catch(() => {});
    return new Response(
      JSON.stringify({ status: "ignored", reason: "invalid_json" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const result = await processWebhook(payload, clientIp);
    console.log(`[Webhook] Responding ${result.status} (${Date.now() - startTime}ms) via ${authMethod}`);
    return result;
  } catch (err) {
    console.error(`[Webhook] Error: ${err}`);
    await audit("webhook_error", null, { message: err instanceof Error ? err.message : String(err) }, clientIp).catch(() => {});
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});