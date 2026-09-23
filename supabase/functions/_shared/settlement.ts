// ═══════════════════════════════════════════════════════════════
// SHARED SERVER-SIDE SETTLEMENT ENGINE
// Used by lipila-webhook (on confirmed collection) and lipila-settle
// (cron retry). Moves money OUT only when the settlement can be
// anchored to server-side facts:
//   giving    -> payer's church treasurer_phone, gross capped by confirmed
//                collection amount
//   event     -> organizer_momo_phone (validated), fallback to church chain,
//                gross capped by confirmed amount, platform takes
//                event_commission_percent (10% except Conference)
//   order     -> seller profile phone (recipient_user_id), gross capped by
//                confirmed collection amount
//   ride      -> ride_requests.driver_id (owner check) + offered_fare*(1-cut)
//   delivery  -> delivery_requests.driver_id + offered_fare*(1-cut)
//   escrow    -> delivery_requests.vendor_phone + item_price
//   manual    -> explicit recipient_phone (superadmin/coa_employee only)
//   church_payout -> church_withdrawals ledger row (server-enqueued aggregate
//                treasurer payout). Gross capped by the ledger's gross_amount.
// ═══════════════════════════════════════════════════════════════

// @ts-ignore Deno global declaration for non-Deno IDEs
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface SettlementConfig {
  disbFeePercent: number;
  coaPayoutFeePercent: number;
  minFeeKwacha: number;
  businessCutPercent: number;
  retryBackoffMinutes: number;
}

export interface SettlementResult {
  taskId: string;
  ok: boolean;
  retry: boolean;
  error?: string;
}

const CONFIRMED = ["approved", "completed", "confirmed", "settled"];

export async function loadSettlementConfig(
  supabase: ReturnType<typeof createClient>,
): Promise<SettlementConfig> {
  const cfg: SettlementConfig = {
    disbFeePercent: 0.015,
    coaPayoutFeePercent: 0.01,
    minFeeKwacha: 3.0,
    businessCutPercent: 0.1,
    retryBackoffMinutes: 30,
  };
  const { data } = await supabase.from("platform_settings").select("key, value");
  for (const row of data ?? []) {
    const v = Number(row.value);
    if (Number.isNaN(v)) continue;
    if (row.key === "lipila_disbursement_fee_percent") cfg.disbFeePercent = v;
    else if (row.key === "coa_payout_fee_percent") cfg.coaPayoutFeePercent = v;
    else if (row.key === "min_fee_kwacha") cfg.minFeeKwacha = v;
    else if (row.key === "business_cut_percent") cfg.businessCutPercent = v;
    else if (row.key === "payout_retry_backoff_minutes") cfg.retryBackoffMinutes = v;
  }
  return cfg;
}

const payoutNet = (gross: number, c: SettlementConfig): number =>
  gross - gross * c.disbFeePercent - Math.max(gross * c.coaPayoutFeePercent, c.minFeeKwacha);

export function normalizePhone(p: string | null | undefined): string {
  let s = (p ?? "").replace(/\D/g, "");
  if (s.startsWith("0")) s = "260" + s.slice(1);
  else if (s.startsWith("9") && s.length === 9) s = "260" + s;
  else if (s.length === 9) s = "260" + s;
  return s;
}

interface Task {
  id: string;
  user_id: string;
  source: string;
  source_ref: string | null;
  payment_ref: string | null;
  recipient_user_id: string | null;
  recipient_phone: string | null;
  recipient_role: string | null;
  gross_amount: number;
  attempt_count: number;
  payout_ref?: string | null;
}

// Roles that may legitimately receive church money (tithes/offerings).
const LEADERSHIP_ROLES = new Set([
  "apostle",
  "prophet",
  "pastor",
  "bishop",
  "general_secretary",
  "general_treasurer",
  "treasurer",
  "admin",
]);

function validRecipientPhone(p: string | null | undefined): string | null {
  const phone = normalizePhone(p);
  return /^260\d{9}$/.test(phone) ? phone : null;
}

async function loadProfilePhone(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string | null> {
  // NOTE: profiles only has `phone_number` (there is no `phone` column) —
  // selecting a missing column makes PostgREST error and silently yields null.
  const { data } = await supabase
    .from("profiles")
    .select("phone_number")
    .eq("id", userId)
    .maybeSingle();
  return validRecipientPhone(data?.phone_number as string);
}

// Resolve a leadership payout phone inside a tenant. Returns the preferred
// role's number when present, otherwise the first church leader with a valid
// mobile money number. Never trusts a client-supplied number.
async function loadLeadershipPhone(
  supabase: ReturnType<typeof createClient>,
  tenantId: string,
  preferredRole?: string | null,
): Promise<string | null> {
  const { data: profiles } = await supabase
    .from("profiles")
    .select("phone_number, role")
    .eq("tenant_id", tenantId)
    .limit(100);

  const rows = (profiles ?? []) as Array<{ phone_number?: string; role?: string }>;

  if (preferredRole) {
    const exact = rows.find((r) => r.role === preferredRole);
    const exactPhone = validRecipientPhone(exact?.phone_number);
    if (exactPhone) return exactPhone;
  }

  const priority = [
    "treasurer",
    "general_treasurer",
    "pastor",
    "bishop",
    "general_secretary",
    "apostle",
    "prophet",
    "admin",
  ];
  for (const role of priority) {
    const match = rows.find((r) => r.role === role);
    const phone = validRecipientPhone(match?.phone_number);
    if (phone) return phone;
  }
  return null;
}

// Church receiving chain for tithes/offerings (never hard-fails):
// designated tithe leader -> elected tithe role -> treasurer_phone ->
// contact_phone -> pastor_phone -> any leadership profile phone -> wait.
async function resolveChurchRecipient(
  supabase: ReturnType<typeof createClient>,
  tenantId: string | null | undefined,
  task: Task,
): Promise<{ recipient: string | null; retry: boolean }> {
  if (!tenantId) return { recipient: null, retry: true };

  // 1. A designated tithe recipient (pastor/bishop/treasurer) chosen by the
  //    giver — revalidated server-side: must be leadership in the SAME tenant.
  if (task.recipient_user_id) {
    const { data: designated } = await supabase
      .from("profiles")
      .select("phone_number, role, tenant_id")
      .eq("id", task.recipient_user_id)
      .maybeSingle();
    if (designated && (designated.tenant_id as string) === tenantId &&
        LEADERSHIP_ROLES.has((designated.role as string) ?? "")) {
      const phone = validRecipientPhone(designated.phone_number as string);
      if (phone) return { recipient: phone, retry: false };
    }
  }

  // 2. Elected tithe role (e.g. "Bishop"/"Pastor"/"Treasurer") when no named
  //    recipient was resolved.
  if (task.recipient_role) {
    const byRole = await loadLeadershipPhone(supabase, tenantId, task.recipient_role);
    if (byRole) return { recipient: byRole, retry: false };
  }

  // 3. Church contact numbers, in treasury-first order.
  let { data: church } = await supabase
    .from("churches")
    .select("treasurer_phone, contact_phone, pastor_phone")
    .eq("id", tenantId)
    .maybeSingle();
  if (!church) {
    const fallback = await supabase
      .from("churches")
      .select("treasurer_phone, contact_phone, pastor_phone")
      .eq("tenant_id", tenantId)
      .maybeSingle();
    church = fallback.data;
  }
  if (church) {
    for (const candidate of [
      church.treasurer_phone as string | null,
      church.contact_phone as string | null,
      church.pastor_phone as string | null,
    ]) {
      const phone = validRecipientPhone(candidate);
      if (phone) return { recipient: phone, retry: false };
    }
  }

  // 4. Last resort inside the tenant: any leader with a valid number.
  const anyLeader = await loadLeadershipPhone(supabase, tenantId);
  if (anyLeader) return { recipient: anyLeader, retry: false };

  // 5. Nothing configured yet — leave the task pending so it is retried once a
  //    phone is set. Money is never dropped and never marked failed here.
  return { recipient: null, retry: true };
}

// Resolve (recipientPhone, gross) from server-side facts. Returns
// { retry: true } when the anchor isn't ready yet (leave task pending).
async function resolveSettlement(
  supabase: ReturnType<typeof createClient>,
  task: Task,
  cfg: SettlementConfig,
): Promise<{ recipient: string; gross: number; retry?: boolean; error?: string }> {
  switch (task.source) {
    case "giving":
    case "order": {
      if (!task.payment_ref) return { error: "missing_payment_ref", recipient: "", gross: 0 };
      const { data: payment } = await supabase
        .from("coa_payments")
        .select("status, amount, user_id")
        .eq("payment_ref", task.payment_ref)
        .maybeSingle();
      if (!payment || !CONFIRMED.includes((payment.status ?? "").toLowerCase())) {
        return { retry: true, recipient: "", gross: 0 };
      }
      const confirmedAmount = Number(payment.amount);
      if (!(confirmedAmount > 0)) return { error: "unconfirmed_amount", recipient: "", gross: 0 };

      let recipient: string | null = null;
      if (task.source === "order") {
        if (!task.recipient_user_id) return { error: "missing_recipient_user", recipient: "", gross: 0 };
        recipient = await loadProfilePhone(supabase, task.recipient_user_id);
      } else {
        // giving: resolve the payer's church receiving account server-side.
        const { data: payer } = await supabase
          .from("profiles")
          .select("tenant_id")
          .eq("id", payment.user_id)
          .maybeSingle();
        const resolved = await resolveChurchRecipient(
          supabase,
          payer?.tenant_id as string | null | undefined,
          task,
        );
        // No usable number yet (church/leader has none on file) => stay pending
        // and retry later instead of failing the task permanently.
        if (resolved.retry || !resolved.recipient) {
          return { retry: true, recipient: "", gross: 0 };
        }
        recipient = resolved.recipient;
      }
      if (!recipient) return { error: "no_recipient", recipient: "", gross: 0 };

      // Gross is capped by the webhook-confirmed collection amount.
      const gross = Math.min(Number(task.gross_amount), confirmedAmount);
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "event": {
      if (!task.payment_ref) return { error: "missing_payment_ref", recipient: "", gross: 0 };
      const { data: payment } = await supabase
        .from("coa_payments")
        .select("status, amount, user_id")
        .eq("payment_ref", task.payment_ref)
        .maybeSingle();
      if (!payment || !CONFIRMED.includes((payment.status ?? "").toLowerCase())) {
        return { retry: true, recipient: "", gross: 0 };
      }
      const confirmedAmount = Number(payment.amount);
      if (!(confirmedAmount > 0)) return { error: "unconfirmed_amount", recipient: "", gross: 0 };

      // Prefer organizer's phone (passed as recipient_phone), fallback to church chain.
      let recipient: string | null = validRecipientPhone(task.recipient_phone);
      if (!recipient) {
        const { data: payer } = await supabase
          .from("profiles")
          .select("tenant_id")
          .eq("id", payment.user_id)
          .maybeSingle();
        const resolved = await resolveChurchRecipient(
          supabase,
          payer?.tenant_id as string | null | undefined,
          task,
        );
        if (resolved.retry || !resolved.recipient) {
          return { retry: true, recipient: "", gross: 0 };
        }
        recipient = resolved.recipient;
      }
      if (!recipient) return { error: "no_recipient", recipient: "", gross: 0 };

      const gross = Math.min(Number(task.gross_amount), confirmedAmount);
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "ride": {
      if (!task.source_ref) return { error: "missing_source_ref", recipient: "", gross: 0 };
      const { data: ride } = await supabase
        .from("ride_requests")
        .select("status, rider_id, driver_id, offered_fare, negotiated_fare, payment_status, payment_ref")
        .eq("id", task.source_ref)
        .maybeSingle();
      if (!ride || (ride.status ?? "").toLowerCase() !== "completed") {
        return { retry: true, recipient: "", gross: 0 };
      }
      // Only a ride that was actually paid may pay the driver.
      if ((ride.payment_status ?? "unpaid") !== "paid") {
        return { retry: true, recipient: "", gross: 0 };
      }
      const { data: ridePayment } = await supabase
        .from("coa_payments")
        .select("status, amount, user_id")
        .eq("payment_ref", ride.payment_ref)
        .eq("user_id", ride.rider_id)
        .maybeSingle();
      if (!ridePayment || !CONFIRMED.includes((ridePayment.status ?? "").toLowerCase())) {
        return { retry: true, recipient: "", gross: 0 };
      }
      // Owner check: only the driver assigned to this ride may be paid for it.
      if (ride.driver_id !== task.user_id) return { error: "not_ride_owner", recipient: "", gross: 0 };
      const recipient = await loadProfilePhone(supabase, task.user_id);
      if (!recipient) return { error: "no_recipient", recipient: "", gross: 0 };
      const fare = Number(ride.negotiated_fare ?? ride.offered_fare);
      const gross = fare - fare * cfg.businessCutPercent;
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "delivery": {
      if (!task.source_ref) return { error: "missing_source_ref", recipient: "", gross: 0 };
      const { data: delivery } = await supabase
        .from("delivery_requests")
        .select("status, sender_id, driver_id, offered_fare, negotiated_fare, payment_status, payment_ref")
        .eq("id", task.source_ref)
        .maybeSingle();
      if (!delivery || (delivery.status ?? "").toLowerCase() !== "delivered") {
        return { retry: true, recipient: "", gross: 0 };
      }
      if ((delivery.payment_status ?? "unpaid") !== "paid") {
        return { retry: true, recipient: "", gross: 0 };
      }
      const { data: deliveryPayment } = await supabase
        .from("coa_payments")
        .select("status, amount, user_id")
        .eq("payment_ref", delivery.payment_ref)
        .eq("user_id", delivery.sender_id)
        .maybeSingle();
      if (!deliveryPayment || !CONFIRMED.includes((deliveryPayment.status ?? "").toLowerCase())) {
        return { retry: true, recipient: "", gross: 0 };
      }
      if (delivery.driver_id !== task.user_id) return { error: "not_delivery_owner", recipient: "", gross: 0 };
      const recipient = await loadProfilePhone(supabase, task.user_id);
      if (!recipient) return { error: "no_recipient", recipient: "", gross: 0 };
      const fare = Number(delivery.negotiated_fare ?? delivery.offered_fare);
      const gross = fare - fare * cfg.businessCutPercent;
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "ride_cut":
    case "delivery_cut": {
      // The COA platform cut of every Carpso ride/delivery is paid to the
      // platform payout number set by superadmin/coa_employee. Tenants never
      // touch ride money. Stays pending (retry) until the number is set.
      if (!task.source_ref) return { error: "missing_source_ref", recipient: "", gross: 0 };
      const table = task.source === "ride_cut" ? "ride_requests" : "delivery_requests";
      const doneStatus = task.source === "ride_cut" ? "completed" : "delivered";
      const { data: request } = await supabase
        .from(table)
        .select("status, offered_fare, negotiated_fare, payment_status")
        .eq("id", task.source_ref)
        .maybeSingle();
      if (!request || (request.status ?? "").toLowerCase() !== doneStatus) {
        return { retry: true, recipient: "", gross: 0 };
      }
      if ((request.payment_status ?? "unpaid") !== "paid") {
        return { retry: true, recipient: "", gross: 0 };
      }
      const fare = Number(request.negotiated_fare ?? request.offered_fare);
      const platformCut = Math.round(fare * cfg.businessCutPercent * 100) / 100;
      if (!(platformCut > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      const { data: setting } = await supabase
        .from("platform_settings")
        .select("value")
        .eq("key", "ride_payout_mobile")
        .maybeSingle();
      const recipient = normalizePhone(setting?.value as string | null | undefined);
      if (!/^260\d{9}$/.test(recipient)) {
        return { retry: true, recipient: "", gross: 0 }; // number not set yet
      }
      const gross = Math.min(Number(task.gross_amount), platformCut);
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "escrow": {
      if (!task.source_ref) return { error: "missing_source_ref", recipient: "", gross: 0 };
      const { data: delivery } = await supabase
        .from("delivery_requests")
        .select("status, driver_id, vendor_phone, item_price")
        .eq("id", task.source_ref)
        .maybeSingle();
      if (!delivery || (delivery.status ?? "").toLowerCase() !== "delivered") {
        return { retry: true, recipient: "", gross: 0 };
      }
      // Only the courier that completed the delivery may trigger its escrow.
      if (delivery.driver_id !== task.user_id) return { error: "not_delivery_owner", recipient: "", gross: 0 };
      const recipient = normalizePhone(delivery.vendor_phone);
      if (!/^260\d{9}$/.test(recipient)) return { error: "no_recipient", recipient: "", gross: 0 };
      const gross = Number(delivery.item_price);
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "manual": {
      // Manual disbursements: only superadmin / coa_employee queued tasks.
      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", task.user_id)
        .maybeSingle();
      if (!["superadmin", "coa_employee"].includes(profile?.role)) {
        return { error: "not_authorized", recipient: "", gross: 0 };
      }
      const recipient = normalizePhone(task.recipient_phone);
      if (!/^260\d{9}$/.test(recipient)) return { error: "no_recipient", recipient: "", gross: 0 };
      const gross = Number(task.gross_amount);
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    case "church_payout": {
      // Aggregate treasurer payout. The authoritative amount is the server-side
      // church_withdrawals ledger row referenced by source_ref.
      if (!task.source_ref) return { error: "missing_source_ref", recipient: "", gross: 0 };
      const { data: withdrawal } = await supabase
        .from("church_withdrawals")
        .select("status, gross_amount, recipient_phone")
        .eq("id", task.source_ref)
        .maybeSingle();
      if (!withdrawal) return { error: "withdrawal_not_found", recipient: "", gross: 0 };
      if (withdrawal.status === "paid" || withdrawal.status === "cancelled") {
        return { retry: true, recipient: "", gross: 0 }; // handled elsewhere
      }
      if (withdrawal.status === "failed") {
        return { error: "withdrawal_failed", recipient: "", gross: 0 };
      }
      const recipient = normalizePhone(withdrawal.recipient_phone);
      if (!/^260\d{9}$/.test(recipient)) return { error: "no_recipient", recipient: "", gross: 0 };
      const gross = Math.min(Number(task.gross_amount), Number(withdrawal.gross_amount));
      if (!(gross > 0)) return { error: "invalid_gross", recipient: "", gross: 0 };
      return { recipient, gross };
    }

    default:
      return { error: "unknown_source", recipient: "", gross: 0 };
  }
}

async function disburse(
  supabase: ReturnType<typeof createClient>,
  task: Task,
  recipient: string,
  gross: number,
  cfg: SettlementConfig,
): Promise<SettlementResult> {
  const lipilaFee = Math.round(gross * cfg.disbFeePercent * 100) / 100;
  const coaFee = Math.round(Math.max(gross * cfg.coaPayoutFeePercent, cfg.minFeeKwacha) * 100) / 100;
  const net = Math.round((gross - lipilaFee - coaFee) * 100) / 100;
  if (net <= 0) {
    return { taskId: task.id, ok: false, retry: false, error: "net_zero" };
  }

  // Reuse one reference across retries. A network timeout after Lipila accepts
  // a payout must never create a second disbursement on the next cron pass.
  const payoutRef = task.payout_ref || task.id;
  const nowIso = new Date().toISOString();

  // Atomic claim — 'pending' -> 'processing' guards against double payment.
  const { data: claimed } = await supabase
    .from("payout_tasks")
    .update({
      status: "processing",
      payout_ref: payoutRef,
      net_amount: net,
      recipient_phone: recipient,
      attempt_count: (task.attempt_count ?? 0) + 1,
      updated_at: nowIso,
    })
    .eq("id", task.id)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();

  if (!claimed) {
    return { taskId: task.id, ok: true, retry: false }; // already handled elsewhere
  }

  if (task.source === "church_payout") {
    await syncWithdrawal(supabase, task, { status: "processing", updated_at: nowIso });
  }

  const apiKey = Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) {
    await markTaskFailed(supabase, task, "no_api_key", net, cfg.retryBackoffMinutes);
    return { taskId: task.id, ok: false, retry: true, error: "no_api_key" };
  }

  const baseUrl = apiKey.startsWith("lsk_")
    ? "https://blz.lipila.io/api"
    : "https://api.lipila.dev/api";

  // chisomo/kingdom contract: ship the webhook secret on the callback URL so
  // the payout confirmation authenticates at lipila-webhook.
  const callbackBase = Deno.env.get("LIPILA_PAYOUT_WEBHOOK_URL")
    ?? `${Deno.env.get("SUPABASE_URL")}/functions/v1/lipila-webhook`;
  const payoutSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
  const callbackUrl = payoutSecret
    ? `${callbackBase}?secret=${encodeURIComponent(payoutSecret)}`
    : callbackBase;

  try {
    const payoutRes = await fetch(`${baseUrl}/v1/payouts/mobile-money`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        callbackUrl,
        referenceId: payoutRef,
        amount: net,
        narration: `COA settlement (${task.source})`,
        accountNumber: recipient,
        currency: "ZMW",
        email: "payouts@churchonapp.com",
      }),
    });

    const payoutData = await payoutRes.json();

    if (!payoutRes.ok) {
      const msg = (payoutData as Record<string, unknown>)?.error
        ? JSON.stringify(payoutData)
        : `lipila_http_${payoutRes.status}`;
      await markTaskFailed(supabase, task, msg.slice(0, 400), net, cfg.retryBackoffMinutes);
      return { taskId: task.id, ok: false, retry: true, error: msg.slice(0, 400) };
    }

    await supabase
      .from("payout_tasks")
      .update({
        // Lipila's HTTP acceptance is not final settlement. The webhook moves
        // this task to paid/failed using the stable payout_ref.
        status: "processing",
        updated_at: nowIso,
      })
      .eq("id", task.id);

    if (task.source === "church_payout") {
      await syncWithdrawal(supabase, task, {
        status: "processing",
        lipila_fee: lipilaFee,
        coa_fee: coaFee,
        net_amount: net,
        lipila_reference: payoutRef,
        updated_at: nowIso,
      });
    }

    return { taskId: task.id, ok: true, retry: true };
  } catch (err) {
    const msg = err instanceof Error ? err.message : "network_error";
    await markTaskFailed(supabase, task, msg.slice(0, 400), net);
    return { taskId: task.id, ok: false, retry: true, error: msg.slice(0, 400) };
  }
}

async function markTaskFailed(
  supabase: ReturnType<typeof createClient>,
  task: Task,
  error: string,
  netAmount: number,
  backoffMinutes = 30,
): Promise<void> {
  const nowIso = new Date().toISOString();
  const shouldRetry = (task.attempt_count ?? 0) < 5;
  // chisomo retry policy: back off before the next attempt so a failing payout
  // is never hammered (a transient MNO/API issue usually clears within 30 min).
  const nextAttempt = shouldRetry
    ? new Date(Date.now() + Math.max(1, backoffMinutes) * 60_000).toISOString()
    : null;
  await supabase
    .from("payout_tasks")
    .update({
      status: shouldRetry ? "pending" : "failed",
      net_amount: netAmount,
      last_error: error,
      next_attempt_at: nextAttempt,
      updated_at: nowIso,
    })
    .eq("id", task.id);

  if (task.source === "church_payout") {
    // Release the in-flight slot so the next enqueue can retry the balance.
    await syncWithdrawal(supabase, task, {
      status: "failed",
      last_error: error,
      updated_at: nowIso,
    });
  }
}
// Mirrors a payout task's lifecycle onto its church_withdrawals ledger row.
async function syncWithdrawal(
  supabase: ReturnType<typeof createClient>,
  task: Task,
  fields: Record<string, unknown>,
): Promise<void> {
  if (!task.source_ref) return;
  await supabase
    .from("church_withdrawals")
    .update(fields)
    .eq("id", task.source_ref);
}

// Settle every pending task for a confirmed payment reference
// (called by the webhook when a collection is confirmed).
export async function settleReference(
  supabase: ReturnType<typeof createClient>,
  reference: string,
): Promise<{ checked: number; paid: number; failed: number }> {
  if (!reference) return { checked: 0, paid: 0, failed: 0 };
  const cfg = await loadSettlementConfig(supabase);

  const { data: tasks } = await supabase
    .from("payout_tasks")
    .select("id, user_id, source, source_ref, payment_ref, recipient_user_id, recipient_phone, recipient_role, gross_amount, attempt_count, payout_ref, next_attempt_at")
    .eq("payment_ref", reference)
    .eq("status", "pending")
    // Honour the retry backoff so a task that just failed is not hammered.
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${new Date().toISOString()}`)
    .limit(20);

  let paid = 0;
  let failed = 0;
  for (const task of tasks ?? []) {
    const result = await settleTask(supabase, task, cfg);
    if (result.ok) paid++;
    else if (!result.retry) failed++;
  }
  return { checked: tasks?.length ?? 0, paid, failed };
}

// Settle a single task (shared by webhook + cron).
export async function settleTask(
  supabase: ReturnType<typeof createClient>,
  task: Task,
  cfg: SettlementConfig,
): Promise<SettlementResult> {
  const resolved = await resolveSettlement(supabase, task, cfg);
  if (resolved.error) {
    // Recipient configuration can be added after a task is created. Keep
    // these tasks pending so the next settlement pass can resolve again.
    if (["no_recipient", "withdrawal_not_found"].includes(resolved.error)) {
      await supabase.from("payout_tasks").update({
        status: "pending",
        last_error: resolved.error,
        updated_at: new Date().toISOString(),
      }).eq("id", task.id);
      return { taskId: task.id, ok: false, retry: true, error: resolved.error };
    }
    // Permanent failure — mark failed so it is visible to admins.
    await markTaskFailed(supabase, task, resolved.error, 0);
    return { taskId: task.id, ok: false, retry: false, error: resolved.error };
  }
  if (resolved.retry) {
    return { taskId: task.id, ok: false, retry: true };
  }
  return disburse(supabase, task, resolved.recipient, resolved.gross, cfg);
}

// Cron entrypoint: process pending tasks whose anchors are ready.
export async function processPendingSettlements(
  supabase: ReturnType<typeof createClient>,
): Promise<{ checked: number; paid: number; failed: number; retried: number }> {
  const cfg = await loadSettlementConfig(supabase);

  const { data: tasks } = await supabase
    .from("payout_tasks")
    .select("id, user_id, source, source_ref, payment_ref, recipient_user_id, recipient_phone, recipient_role, gross_amount, attempt_count, payout_ref, next_attempt_at")
    .eq("status", "pending")
    // chisomo retry policy: skip anything still inside its backoff window.
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${new Date().toISOString()}`)
    .order("created_at", { ascending: true })
    .limit(20);

  let paid = 0;
  let failed = 0;
  let retried = 0;
  for (const task of tasks ?? []) {
    const result = await settleTask(supabase, task, cfg);
    if (result.ok) paid++;
    else if (result.retry) retried++;
    else failed++;
  }
  return { checked: tasks?.length ?? 0, paid, failed, retried };
}

// Enqueue automatic church treasurer payouts: any church whose server-side
// withdrawable balance (confirmed giving minus committed/failed payouts minus
// in-flight withdrawals) crosses `church_payout_min_kwacha` gets a
// church_withdrawals ledger row + a payout_tasks('church_payout') task, which
// the shared settlement engine then disburses to the church treasurer phone.
// Safe to call from cron + webhook concurrently — the SQL enqueue is atomic and
// the in-flight unique index prevents double-enqueuing a church.
export async function enqueueChurchAutoPayouts(
  supabase: ReturnType<typeof createClient>,
): Promise<{ enqueued: number; thresholdKwacha: number }> {
  let thresholdKwacha = 100;
  const { data: setting } = await supabase
    .from("platform_settings")
    .select("value")
    .eq("key", "church_payout_min_kwacha")
    .maybeSingle();
  if (setting?.value) {
    const n = Number(setting.value);
    if (!Number.isNaN(n) && n > 0) thresholdKwacha = n;
  }

  try {
    const { data, error } = await supabase.rpc("enqueue_church_auto_payouts", {
      p_min_kwacha: thresholdKwacha,
    });
    if (error) {
      console.error(`[ChurchAutoPayout] enqueue failed: ${error.message}`);
      return { enqueued: 0, thresholdKwacha };
    }
    return { enqueued: data?.length ?? 0, thresholdKwacha };
  } catch (err) {
    const msg = err instanceof Error ? err.message : "unknown_error";
    console.error(`[ChurchAutoPayout] enqueue error: ${msg}`);
    return { enqueued: 0, thresholdKwacha };
  }
}

// ── Lipila base URL (chisomo/kingdom contract) ────────────────────────────────
function lipilaApiBase(apiKey: string): string {
  return apiKey.startsWith("lsk_")
    ? "https://blz.lipila.io/api"
    : "https://api.lipila.dev/api";
}

// Poll Lipila's disbursement status for a payout reference. Mirrors the
// chisomo `checkDisbursementStatus` contract, trying the known endpoint shapes.
async function checkPayoutStatus(
  apiKey: string,
  reference: string,
): Promise<string | null> {
  const base = lipilaApiBase(apiKey);
  const candidates = [
    `${base}/v1/payouts/check-status?referenceId=${encodeURIComponent(reference)}`,
    `${base}/v1/disbursements/check-status?referenceId=${encodeURIComponent(reference)}`,
    `${base}/v1/payouts/mobile-money/${encodeURIComponent(reference)}`,
  ];
  for (const url of candidates) {
    try {
      const res = await fetch(url, {
        headers: { accept: "application/json", "x-api-key": apiKey },
      });
      const raw = await res.text().catch(() => "");
      if (!res.ok) continue;
      let data: Record<string, unknown> = {};
      try { data = JSON.parse(raw); } catch { /* ignore */ }
      const inner = (data.data ?? data) as Record<string, unknown>;
      const status = inner.status ?? data.status;
      if (typeof status === "string" && status) return status;
    } catch {
      // try next endpoint shape
    }
  }
  return null;
}

// chisomo's `runWithdrawalStatusChecks`: a payout that Lipila ACCEPTED but whose
// webhook was lost used to stay `processing` forever (the cron only selected
// `pending`). Re-check in-flight tasks against Lipila and finalise them.
export async function reconcileInFlightPayouts(
  supabase: ReturnType<typeof createClient>,
): Promise<{ checked: number; paid: number; failed: number }> {
  const apiKey = Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) return { checked: 0, paid: 0, failed: 0 };

  const { data: tasks } = await supabase
    .from("payout_tasks")
    .select("id, source, source_ref, payout_ref, attempt_count")
    .eq("status", "processing")
    .not("payout_ref", "is", null)
    .order("updated_at", { ascending: true })
    .limit(50);

  let paid = 0;
  let failed = 0;
  const now = new Date().toISOString();

  for (const task of tasks ?? []) {
    const ref = task.payout_ref as string | null;
    if (!ref) continue;
    try {
      const status = await checkPayoutStatus(apiKey, ref);
      const s = (status ?? "").toLowerCase();
      if (["success", "successful", "complete", "completed", "settled", "paid"].includes(s)) {
        const { data: claimed } = await supabase
          .from("payout_tasks")
          .update({ status: "paid", processed_at: now, updated_at: now, last_error: null })
          .eq("id", task.id)
          .eq("status", "processing")
          .select("id")
          .maybeSingle();
        if (claimed) {
          paid++;
          if (task.source === "church_payout" && task.source_ref) {
            await supabase.from("church_withdrawals").update({
              status: "paid", processed_at: now, updated_at: now, lipila_reference: ref,
            }).eq("id", task.source_ref);
          }
        }
      } else if (["failed", "cancelled", "rejected", "declined", "error", "timeout"].includes(s)) {
        const { data: claimed } = await supabase
          .from("payout_tasks")
          .update({
            status: (task.attempt_count ?? 0) < 5 ? "pending" : "failed",
            last_error: `lipila_${status}`,
            next_attempt_at: (task.attempt_count ?? 0) < 5
              ? new Date(Date.now() + 30 * 60_000).toISOString()
              : null,
            updated_at: now,
          })
          .eq("id", task.id)
          .eq("status", "processing")
          .select("id")
          .maybeSingle();
        if (claimed) {
          failed++;
          if (task.source === "church_payout" && task.source_ref) {
            await supabase.from("church_withdrawals").update({
              status: "failed", last_error: `lipila_${status}`, updated_at: now,
            }).eq("id", task.source_ref);
          }
        }
      }
      // Unknown/pending: leave it in-flight for the next pass.
    } catch (err) {
      console.error(`[Reconcile] payout ${ref} status check failed: ${err}`);
    }
  }
  return { checked: tasks?.length ?? 0, paid, failed };
}

// chisomo's `settlePlatformFees`/`runFeeSweep`: the COA payout cut earned on
// every completed church withdrawal is netted off the host amount but never
// tracked or swept. This settles it to the platform settlement number. The
// amount is re-derived server-side from the ledger, never supplied by a client.
export async function sweepPlatformFees(
  supabase: ReturnType<typeof createClient>,
): Promise<{ swept: number; amount: number }> {
  const apiKey = Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) return { swept: 0, amount: 0 };

  // Config: settlement phone + minimum sweep threshold.
  let phone = "";
  let minKwacha = 50;
  const { data: settings } = await supabase
    .from("platform_settings")
    .select("key, value")
    .in("key", ["coa_settlement_phone", "platform_fee_sweep_min_kwacha"]);
  for (const row of settings ?? []) {
    if (row.key === "coa_settlement_phone") phone = normalizePhone(row.value as string);
    else if (row.key === "platform_fee_sweep_min_kwacha") {
      const n = Number(row.value);
      if (!Number.isNaN(n) && n >= 0) minKwacha = n;
    }
  }
  if (!/^260\d{9}$/.test(phone)) return { swept: 0, amount: 0 };

  // Pending = payout fees earned (church withdrawals processing/paid) minus
  // already-committed sweeps (pending/success), so a missed webhook can never
  // cause the same fees to be swept twice.
  const { data: earnedRows } = await supabase
    .from("church_withdrawals")
    .select("coa_fee")
    .in("status", ["processing", "paid"]);
  const earned = (earnedRows ?? []).reduce((s, r) => s + Number(r.coa_fee ?? 0), 0);

  const { data: settledRows } = await supabase
    .from("fee_sweeps")
    .select("amount")
    .in("status", ["pending", "success"]);
  const settled = (settledRows ?? []).reduce((s, r) => s + Number(r.amount ?? 0), 0);

  const due = Math.round((earned - settled) * 100) / 100;
  if (due < minKwacha || due <= 0) return { swept: 0, amount: 0 };

  const ref = `SWEEP-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const { error: insertError } = await supabase.from("fee_sweeps").insert({
    kind: "payout_fee",
    amount: due,
    lipila_reference: ref,
    status: "pending",
  });
  if (insertError) {
    console.error(`[FeeSweep] ledger insert failed: ${insertError.message}`);
    return { swept: 0, amount: 0 };
  }

  const callbackBase = Deno.env.get("LIPILA_PAYOUT_WEBHOOK_URL")
    ?? `${Deno.env.get("SUPABASE_URL")}/functions/v1/lipila-webhook`;
  const secret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
  const callbackUrl = secret
    ? `${callbackBase}?secret=${encodeURIComponent(secret)}`
    : callbackBase;

  try {
    const res = await fetch(`${lipilaApiBase(apiKey)}/v1/payouts/mobile-money`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify({
        callbackUrl,
        referenceId: ref,
        amount: due,
        narration: "COA platform fee settlement",
        accountNumber: phone,
        currency: "ZMW",
        email: "payouts@churchonapp.com",
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      await supabase.from("fee_sweeps").update({
        status: "failed", last_error: body.slice(0, 400), updated_at: new Date().toISOString(),
      }).eq("lipila_reference", ref);
      return { swept: 0, amount: 0 };
    }
    return { swept: 1, amount: due };
  } catch (err) {
    await supabase.from("fee_sweeps").update({
      status: "failed",
      last_error: err instanceof Error ? err.message.slice(0, 400) : "network_error",
      updated_at: new Date().toISOString(),
    }).eq("lipila_reference", ref);
    return { swept: 0, amount: 0 };
  }
}
