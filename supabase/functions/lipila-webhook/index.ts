import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, webhook-id, webhook-timestamp, webhook-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_WEBHOOK_AGE_SEC = 300;
const LEADER_ROLES = ["admin", "pastor", "bishop", "leader", "general_treasurer", "general_secretary", "superadmin"];

interface LipilaCallback {
  referenceId: string;
  currency: string;
  amount: number;
  accountNumber?: string;
  status: string;
  paymentType?: string;
  type: "Collection" | "Disbursement";
  ipAddress?: string;
  identifier: string;
  message?: string;
  externalId?: string;
  referenceData?: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 405,
    });
  }

  const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return new Response(
      JSON.stringify({ error: "Webhook secret not configured" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }

  const webhookId = req.headers.get("webhook-id");
  const webhookTimestamp = req.headers.get("webhook-timestamp");
  const webhookSignature = req.headers.get("webhook-signature");

  if (!webhookId || !webhookTimestamp || !webhookSignature) {
    return new Response(
      JSON.stringify({ error: "Missing required webhook headers" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
    );
  }

  const timestamp = parseInt(webhookTimestamp, 10);
  const now = Math.floor(Date.now() / 1000);
  if (now - timestamp > MAX_WEBHOOK_AGE_SEC) {
    return new Response(
      JSON.stringify({ error: "Webhook too old — possible replay attack" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
    );
  }

  const rawBody = await req.text();
  const signedPayload = `${webhookId}.${webhookTimestamp}.${rawBody}`;

  const keyBytes = base64Decode(webhookSecret);
  const expectedSig = await hmacSha256Base64(keyBytes, signedPayload);
  const expectedHeader = `v1,${expectedSig}`;

  const receivedSignatures = webhookSignature.split(" ");
  const valid = receivedSignatures.some((sig) =>
    constantTimeEqual(
      new TextEncoder().encode(expectedHeader),
      new TextEncoder().encode(sig.trim())
    )
  );

  if (!valid) {
    return new Response(
      JSON.stringify({ error: "Invalid webhook signature" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
    );
  }

  let payload: LipilaCallback;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  if (!payload.identifier) {
    return new Response(
      JSON.stringify({ error: "Missing identifier (internal reference)" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  const processed = await supabase
    .from("payment_logs")
    .select("id")
    .eq("metadata->>webhook_id", webhookId)
    .maybeSingle();

  if (processed?.data) {
    return new Response(JSON.stringify({ received: true, idempotent: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  }

  try {
    const result = payload.type === "Disbursement"
      ? await handleDisbursement(supabase, payload, webhookId)
      : await handleCollection(supabase, payload, webhookId);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("Webhook handler error:", error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

async function handleCollection(
  supabase: ReturnType<typeof createClient>,
  payload: LipilaCallback,
  webhookId: string
) {
  const { data: transaction } = await supabase
    .from("transactions")
    .select("id, user_id, amount, category, tenant_id, platform_fee")
    .eq("reference", payload.identifier)
    .maybeSingle();

  if (!transaction) {
    console.error(`No transaction found for reference: ${payload.identifier}`);
    return { received: true, warning: "Transaction not found" };
  }

  const category = transaction.category ?? "giving";
  const cutPercent = category === "event" ? 0.10 : 0.05;
  const amount = payload.amount;
  const platformFee = transaction.platform_fee ?? (amount * cutPercent > 5.0 ? amount * cutPercent : 5.0);
  const netPayout = amount - platformFee;
  const isSuccess = payload.status === "Successful";

  const metadata: Record<string, unknown> = {
    type: "collection",
    paymentType: payload.paymentType,
    accountNumber: payload.accountNumber,
    externalId: payload.externalId,
    referenceData: payload.referenceData,
    message: payload.message,
    identifier: payload.identifier,
    webhook_id: webhookId,
  };

  await supabase.from("payment_logs").insert({
    user_id: transaction.user_id,
    amount,
    currency: payload.currency ?? "ZMW",
    provider: "lipila",
    status: isSuccess ? "completed" : "failed",
    tx_ref: payload.referenceId,
    tenant_id: transaction.tenant_id,
    platform_fee: platformFee,
    net_payout: netPayout,
    metadata,
  });

  if (isSuccess) {
    const { error: updateError } = await supabase
      .from("transactions")
      .update({ status: "completed" })
      .eq("reference", payload.identifier)
      .eq("status", "pending");

    if (updateError) console.error("Failed to update transaction:", updateError);

    const platformFeeInt = Math.floor(platformFee);
    if (platformFeeInt > 0) {
      const treasuryId = Deno.env.get("TREASURY_ID");
      if (treasuryId) {
        const { data: treasury } = await supabase
          .from("profiles")
          .select("coins")
          .eq("id", treasuryId)
          .maybeSingle();

        if (treasury) {
          const currentCoins = (treasury.coins as number) || 0;
          await supabase
            .from("profiles")
            .update({ coins: currentCoins + platformFeeInt })
            .eq("id", treasuryId);
        }
      }
    }

    await notifyCollectionParties(supabase, transaction, amount, payload);
  } else {
    await notifyFailedPaymentParties(supabase, transaction, amount, payload);
  }

  return { received: true, status: payload.status };
}

async function handleDisbursement(
  supabase: ReturnType<typeof createClient>,
  payload: LipilaCallback,
  webhookId: string
) {
  const isSuccess = payload.status === "Successful";
  const metadata: Record<string, unknown> = {
    type: "disbursement",
    paymentType: payload.paymentType,
    accountNumber: payload.accountNumber,
    externalId: payload.externalId,
    referenceData: payload.referenceData,
    message: payload.message,
    identifier: payload.identifier,
    webhook_id: webhookId,
  };

  await supabase.from("payment_logs").insert({
    user_id: null,
    amount: payload.amount,
    currency: payload.currency ?? "ZMW",
    provider: "lipila",
    status: "completed",
    tx_ref: payload.referenceId,
    disbursement_status: isSuccess ? "completed" : "failed",
    disbursement_tx_ref: payload.referenceId,
    metadata,
  });

  const newStatus = isSuccess ? "payout_completed" : "payout_failed";
  const { error: updateError } = await supabase
    .from("transactions")
    .update({ status: newStatus })
    .eq("reference", payload.identifier);

  if (updateError) console.error("Failed to update payout status:", updateError);

  if (isSuccess) {
    await notifySuccessfulPayout(supabase, payload);
  }

  return { received: true, status: payload.status };
}

async function notifyCollectionParties(
  supabase: ReturnType<typeof createClient>,
  transaction: { id: string; user_id: string; tenant_id: string | null; amount: number; category: string },
  amount: number,
  payload: LipilaCallback
) {
  const churchName = await getChurchName(supabase, transaction.tenant_id);
  const formattedAmount = `K${amount.toFixed(2)}`;
  const ref = payload.identifier;

  await supabase.from("notifications").insert({
    user_id: transaction.user_id,
    tenant_id: transaction.tenant_id,
    type: "payment_success",
    reference_id: ref,
    title: "Payment Successful",
    body: `Your payment of ${formattedAmount} to ${churchName} was successful. Reference: ${ref}`,
  });

  if (!transaction.tenant_id) return;

  const { data: leaders } = await supabase
    .from("profiles")
    .select("id, full_name, role")
    .eq("tenant_id", transaction.tenant_id)
    .in("role", LEADER_ROLES);

  if (leaders) {
    const leaderNotifications = leaders
      .filter((l) => l.id !== transaction.user_id)
      .map((leader) => ({
        user_id: leader.id,
        tenant_id: transaction.tenant_id,
        type: "payment_received" as const,
        reference_id: ref,
        title: "Payment Received",
        body: `A payment of ${formattedAmount} was received from a member. ${transaction.category.toUpperCase()} - Ref: ${ref}`,
      }));

    for (const n of leaderNotifications) {
      await supabase.from("notifications").insert(n);
    }
  }
}

async function notifyFailedPaymentParties(
  supabase: ReturnType<typeof createClient>,
  transaction: { id: string; user_id: string; tenant_id: string | null; amount: number; category: string },
  amount: number,
  payload: LipilaCallback
) {
  const churchName = await getChurchName(supabase, transaction.tenant_id);
  const formattedAmount = `K${amount.toFixed(2)}`;
  const ref = payload.identifier;

  await supabase.from("notifications").insert({
    user_id: transaction.user_id,
    tenant_id: transaction.tenant_id,
    type: "payment_failed",
    reference_id: ref,
    title: "Payment Failed",
    body: `Your payment of ${formattedAmount} to ${churchName} was not completed. ${payload.message ?? ""} Ref: ${ref}`,
  });

  if (!transaction.tenant_id) return;

  const { data: leaders } = await supabase
    .from("profiles")
    .select("id")
    .eq("tenant_id", transaction.tenant_id)
    .in("role", LEADER_ROLES);

  if (leaders) {
    for (const leader of leaders) {
      if (leader.id === transaction.user_id) continue;
      await supabase.from("notifications").insert({
        user_id: leader.id,
        tenant_id: transaction.tenant_id,
        type: "payment_failed",
        reference_id: ref,
        title: "Payment Failed",
        body: `A payment attempt of ${formattedAmount} failed. ${payload.message ?? ""} Ref: ${ref}`,
      });
    }
  }
}

async function notifySuccessfulPayout(
  supabase: ReturnType<typeof createClient>,
  payload: LipilaCallback
) {
  const formattedAmount = `K${payload.amount.toFixed(2)}`;
  const ref = payload.identifier;

  await supabase.from("notifications").insert({
    user_id: null,
    tenant_id: null,
    type: "payout_completed",
    reference_id: ref,
    title: "Payout Completed",
    body: `A payout of ${formattedAmount} has been completed. Ref: ${ref}`,
  });
}

async function getChurchName(
  supabase: ReturnType<typeof createClient>,
  tenantId: string | null
): Promise<string> {
  if (!tenantId) return "Church";
  const { data } = await supabase
    .from("churches")
    .select("name")
    .eq("id", tenantId)
    .maybeSingle();
  return data?.name ?? "Church";
}

function base64Decode(str: string): Uint8Array {
  const binStr = atob(str);
  const bytes = new Uint8Array(binStr.length);
  for (let i = 0; i < binStr.length; i++) {
    bytes[i] = binStr.charCodeAt(i);
  }
  return bytes;
}

async function hmacSha256Base64(key: Uint8Array, data: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(data));
  const buf = new Uint8Array(sig);
  let binary = "";
  for (let i = 0; i < buf.length; i++) {
    binary += String.fromCharCode(buf[i]);
  }
  return btoa(binary);
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result === 0;
}
