// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";
import { processPendingSettlements, enqueueChurchAutoPayouts } from "../_shared/settlement.ts";

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Require authentication — only admins/employees/cron may settle
    const authHeader = req.headers.get("Authorization");
    const cronSecret = req.headers.get("x-cron-secret");
    const expectedCronSecret = Deno.env.get("CRON_SECRET") || "";

    if (!authHeader && !(cronSecret && expectedCronSecret && cronSecret === expectedCronSecret)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const { data: { user }, error: authError } = await supabase.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const { data: profile } = await supabase
        .from("profiles").select("role").eq("id", user.id).maybeSingle();
      if (!["superadmin", "coa_employee"].includes(profile?.role)) {
        return new Response(JSON.stringify({ error: "Forbidden" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Fetch pending transactions older than 2 minutes
    const twoMinutesAgo = new Date(Date.now() - 2 * 60 * 1000).toISOString();
    
    const { data: pendingPayments, error: fetchError } = await supabase
      .from("transactions")
      .select("id, reference, status, amount, user_id, tenant_id, category, created_at")
      .eq("status", "pending")
      .lt("created_at", twoMinutesAgo)
      .limit(20);

    if (fetchError) {
      throw new Error(`Error fetching pending payments: ${fetchError.message}`);
    }

    let settledCount = 0;
    let failedCount = 0;

    for (const txn of pendingPayments ?? []) {
      const ref = txn.reference;
      if (!ref) continue;

      // Check coa_payments record first
      const { data: coaPayment } = await supabase
        .from("coa_payments")
        .select("status, amount")
        .eq("payment_ref", ref)
        .maybeSingle();

      if (coaPayment) {
        const dbStatus = (coaPayment.status ?? "").toLowerCase();
        if (["approved", "completed", "confirmed", "settled"].includes(dbStatus)) {
          await supabase
            .from("transactions")
            .update({ status: "completed" })
            .eq("id", txn.id);

          await sendNotification(supabase, txn.user_id, txn.tenant_id, txn.amount, ref, true);
          settledCount++;
          continue;
        } else if (["rejected", "failed", "cancelled"].includes(dbStatus)) {
          await supabase
            .from("transactions")
            .update({ status: "failed" })
            .eq("id", txn.id);

          await sendNotification(supabase, txn.user_id, txn.tenant_id, txn.amount, ref, false);
          failedCount++;
          continue;
        }
      }

      // If pending longer than 30 minutes, auto-expire
      const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
      if (new Date(txn.created_at) < thirtyMinutesAgo) {
        await supabase
          .from("transactions")
          .update({ status: "failed" })
          .eq("id", txn.id);

        failedCount++;
      }
    }

    // ── SERVER-SIDE SETTLEMENT QUEUE ──────────────────────
    // Process queued payout_tasks whose anchors (confirmed collection,
    // completed ride/delivery) are ready. This is the reliability net for
    // anything the webhook missed, plus ride/delivery/escrow settlements.
    let payoutChecked = 0;
    let payoutPaid = 0;
    let payoutFailed = 0;
    try {
      const res = await processPendingSettlements(supabase);
      payoutChecked = res.checked;
      payoutPaid = res.paid;
      payoutFailed = res.failed;
    } catch (payoutErr) {
      console.error(`[Settle] Payout queue processing failed: ${payoutErr}`);
    }

    // ── CHURCH AUTO-PAYOUT ─────────────────────────────────
    // Enqueue aggregate treasurer payouts for churches whose withdrawable
    // balance has crossed the threshold. Safe against concurrent runs via the
    // atomic SQL enqueue + in-flight unique index.
    let churchPayoutsEnqueued = 0;
    let churchPayoutThreshold = 0;
    try {
      const res = await enqueueChurchAutoPayouts(supabase);
      churchPayoutsEnqueued = res.enqueued;
      churchPayoutThreshold = res.thresholdKwacha;
    } catch (enqueueErr) {
      console.error(`[Settle] Church auto-payout enqueue failed: ${enqueueErr}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        checked: pendingPayments?.length ?? 0,
        settled: settledCount,
        failed: failedCount,
        payoutChecked,
        payoutPaid,
        payoutFailed,
        churchPayoutsEnqueued,
        churchPayoutThreshold,
        timestamp: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function sendNotification(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tenantId: string | null,
  amount: number,
  ref: string,
  isSuccess: boolean
) {
  const formattedAmount = `K${amount.toFixed(2)}`;
  if (isSuccess) {
    await supabase.from("notifications").insert({
      user_id: userId,
      tenant_id: tenantId,
      type: "payment_success",
      reference_id: ref,
      title: "Payment Confirmed",
      body: `Your payment of ${formattedAmount} has been reconciled and confirmed. Ref: ${ref}`,
    });
  } else {
    await supabase.from("notifications").insert({
      user_id: userId,
      tenant_id: tenantId,
      type: "payment_failed",
      reference_id: ref,
      title: "Payment Expired",
      body: `Your payment attempt of ${formattedAmount} could not be confirmed. Ref: ${ref}`,
    });
  }
}
