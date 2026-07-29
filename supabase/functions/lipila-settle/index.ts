// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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

    return new Response(
      JSON.stringify({
        success: true,
        checked: pendingPayments?.length ?? 0,
        settled: settledCount,
        failed: failedCount,
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
