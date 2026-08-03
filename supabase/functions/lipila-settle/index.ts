// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

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
