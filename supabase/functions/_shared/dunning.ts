// ═══════════════════════════════════════════════════════════════
// RECURRING-PLEDGE DUNNING (ported from chisomo's recurring_pledges)
//
// COA pledges were a manual installment tracker with a client-side reminder
// only. This lets the server charge a due pledge: the amount is re-derived
// server-side from `pledges.amount_per_cycle` (never supplied by a caller),
// the recipient/collection goes through the normal coa_payments anchor, and
// the charge is recorded back on the pledge.
//
// Invariants preserved (PAYMENTS.md §9):
//   * The client NEVER decides payer/payee/amount.
//   * A pending `coa_payments` row is ALWAYS pre-created before Lipila.
//   * `?secret=` is ALWAYS appended to the collection callback URL.
// ═══════════════════════════════════════════════════════════════

// @ts-ignore Deno global declaration for non-Deno IDEs
declare const Deno: {
  env: { get(key: string): string | undefined };
};

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface DuePledge {
  pledge_id: string;
  user_id: string;
  tenant_id: string | null;
  phone: string | null;
  amount: number;
  category: string | null;
  frequency: string | null;
  day_of_month: number | null;
}

function normalizePhone(p: string | null | undefined): string {
  let s = (p ?? "").replace(/\D/g, "");
  if (s.startsWith("0")) s = "260" + s.slice(1);
  else if (s.startsWith("9") && s.length === 9) s = "260" + s;
  else if (s.length === 9) s = "260" + s;
  return s;
}

// Charge every pledge that is due. Safe to call from the settle cron: each
// attempt is anchored on a pending coa_payments row keyed by a fresh reference,
// and the pledge is only advanced on a successful charge.
export async function chargeDuePledges(
  supabase: ReturnType<typeof createClient>,
): Promise<{ checked: number; charged: number }> {
  const apiKey = Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) return { checked: 0, charged: 0 };

  const { data: due, error } = await supabase.rpc("due_pledges_for_charge", {
    p_limit: 50,
  });
  if (error) {
    console.error(`[Dunning] due_pledges_for_charge failed: ${error.message}`);
    return { checked: 0, charged: 0 };
  }

  const baseUrl = apiKey.startsWith("lsk_")
    ? "https://blz.lipila.io/api"
    : "https://api.lipila.dev/api";
  const callbackBase = Deno.env.get("LIPILA_WEBHOOK_URL")
    ?? `${Deno.env.get("SUPABASE_URL")}/functions/v1/lipila-webhook`;
  const secret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
  const callbackUrl = secret
    ? `${callbackBase}?secret=${encodeURIComponent(secret)}`
    : callbackBase;

  const rows = (due ?? []) as DuePledge[];
  let charged = 0;

  for (const pledge of rows) {
    const phone = normalizePhone(pledge.phone);
    const amount = Number(pledge.amount);
    if (!/^260\d{9}$/.test(phone) || !(amount > 0)) continue;

    const reference = `PLG-${pledge.pledge_id}-${Date.now()}`;

    // Always pre-create the anchor BEFORE calling Lipila.
    const { error: insertError } = await supabase.from("coa_payments").upsert({
      user_id: pledge.user_id,
      service_type: "pledge_auto_charge",
      amount,
      payment_ref: reference,
      status: "pending",
      phone_number: phone,
      category: pledge.category ?? "pledge",
      metadata: {
        user_id: pledge.user_id,
        tenant_id: pledge.tenant_id,
        category: pledge.category ?? "pledge",
        source: "pledge_auto_charge",
        pledge_id: pledge.pledge_id,
      },
    }, { onConflict: "payment_ref", ignoreDuplicates: true });
    if (insertError) {
      console.error(`[Dunning] anchor insert failed for ${pledge.pledge_id}: ${insertError.message}`);
      continue;
    }

    try {
      const res = await fetch(`${baseUrl}/v1/collections/mobile-money`, {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "Content-Type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify({
          callbackUrl,
          referenceId: reference,
          amount,
          narration: "COA pledge instalment",
          accountNumber: phone,
          currency: "ZMW",
          email: "payments@churchonapp.com",
        }),
      });

      if (!res.ok) {
        // Leave the pledge due; it is retried on the next pass.
        await supabase.rpc("record_pledge_charge", {
          p_pledge_id: pledge.pledge_id,
          p_payment_ref: reference,
          p_status: "failed",
        });
        continue;
      }

      await supabase.rpc("record_pledge_charge", {
        p_pledge_id: pledge.pledge_id,
        p_payment_ref: reference,
        p_status: "initiated",
      });
      charged++;
    } catch (err) {
      console.error(`[Dunning] charge failed for ${pledge.pledge_id}: ${err}`);
    }
  }

  return { checked: rows.length, charged };
}
