import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 405,
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { allowed } = await checkRateLimit(supabase, user.id, "lipila_payout", 10, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Role gate: ADMIN-ONLY ─────────────────────────────────────────
    // All automatic payouts (giving, orders, rides, deliveries, escrow) now
    // flow through the server-side settlement engine (payout_tasks, triggered
    // by the Lipila webhook / lps-settle cron). This function is reserved for
    // manual disbursements by platform admins. No other role may move money.
    const { data: profile } = await supabase
      .from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (!["superadmin", "coa_employee"].includes(profile?.role)) {
      return new Response(JSON.stringify({ error: "Forbidden: direct payouts are admin-only" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { accountNumber, amount, narration, referenceId } = await req.json();

    if (!accountNumber || !amount || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid payout parameters" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!/^260\d{9}$/.test(accountNumber)) {
      return new Response(JSON.stringify({ error: "Invalid mobile money number. Must be a valid Zambian number (260XXXXXXXXX)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payoutRef = referenceId ?? crypto.randomUUID();

    const apiKey = Deno.env.get("LIPILA_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Lipila API key not configured on server" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const baseUrl = apiKey.startsWith("lsk_")
      ? "https://blz.lipila.io/api"
      : "https://api.lipila.dev/api";

    const callbackUrl = Deno.env.get("LIPILA_PAYOUT_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;

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
        amount,
        narration: narration ?? "COA payout",
        accountNumber,
        currency: "ZMW",
        email: "payouts@churchonapp.com",
      }),
    });

    const payoutData = await payoutRes.json();

    if (!payoutRes.ok) {
      console.error("Lipila payout failed:", payoutData);
      return new Response(JSON.stringify({ error: "Payout failed", details: payoutData }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, reference: payoutRef, data: payoutData }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
