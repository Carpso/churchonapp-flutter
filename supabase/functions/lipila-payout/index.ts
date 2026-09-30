import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { sanitizeNarration } from "../_shared/sanitize.ts";

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

  // Read-only auth diagnostic (?health=lipila): probes the SAME key against
  // the disbursement and collection status endpoints. Returns HTTP statuses
  // only — NEVER the key. Used to tell "key lacks disbursement permission"
  // (401 on disbursements, not on collections) apart from a payload bug.
  const healthMode = new URL(req.url).searchParams.get("health");
  if (healthMode === "lipila") {
    try {
      const apiKey = Deno.env.get("LIPILA_API_KEY") ?? "";
      const baseUrl = apiKey.startsWith("lsk_")
        ? "https://blz.lipila.io/api"
        : "https://api.lipila.dev/api";
      const probeRef = `diag-${Date.now()}`;
      const [disbRes, collRes] = await Promise.all([
        fetch(`${baseUrl}/v1/disbursements/check-status?referenceId=${probeRef}`, {
          headers: { accept: "application/json", "x-api-key": apiKey },
        }),
        fetch(`${baseUrl}/v1/collections/check-status?referenceId=${probeRef}`, {
          headers: { accept: "application/json", "x-api-key": apiKey },
        }),
      ]);
      const bodyOf = async (r: Response) => {
        const t = await r.text();
        return t.slice(0, 300);
      };
      // Safe POST probes: accountNumber/amount are OMITTED, so Lipila can
      // only answer 401 (auth) or 400 (validation) — never create a payout.
      const safePost = async (url: string) => {
        try {
          const r = await fetch(url, {
            method: "POST",
            headers: { accept: "application/json", "x-api-key": apiKey, "Content-Type": "application/json" },
            body: JSON.stringify({ referenceId: probeRef }),
          });
          return { http: r.status, body: await bodyOf(r) };
        } catch (e) {
          return { http: 0, body: String(e).slice(0, 200) };
        }
      };
      const [disbPost, collPost, disbPostSandbox] = await Promise.all([
        safePost(`${baseUrl}/v1/disbursements/mobile-money`),
        safePost(`${baseUrl}/v1/collections/mobile-money`),
        safePost(`https://api.lipila.dev/api/v1/disbursements/mobile-money`),
      ]);
      return new Response(
        JSON.stringify({
          status: "ok",
          environment: apiKey.startsWith("lsk_") ? "production" : "sandbox",
          key_configured: apiKey.length > 0,
          probes: {
            disbursements_check_status: {
              http: disbRes.status,
              body: await bodyOf(disbRes),
            },
            collections_check_status: {
              http: collRes.status,
              body: await bodyOf(collRes),
            },
            disbursements_post_safe: disbPost,
            collections_post_safe: collPost,
            disbursements_post_sandbox: disbPostSandbox,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    } catch (e) {
      return new Response(
        JSON.stringify({ status: "error", message: String(e) }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }
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

    const callbackBase = Deno.env.get("LIPILA_PAYOUT_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;
    // Dual webhook auth: the secret travels in the callbackUrl query string so
    // lipila-webhook can authenticate payout callbacks without HMAC headers
    // (HMAC `x-webhook-signature` remains accepted as the secondary scheme).
    const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
    const callbackUrl = webhookSecret
      ? `${callbackBase}?secret=${encodeURIComponent(webhookSecret)}`
      : callbackBase;

    // chisomo contract (src/lipila.ts createDisbursement): disbursements live
    // at /v1/disbursements/mobile-money — /v1/payouts/... 404s with an empty
    // body ("Unexpected end of JSON input" seen live on every payout task).
    const payoutRes = await fetch(`${baseUrl}/v1/disbursements/mobile-money`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
        // chisomo passes the callback on the header; body copy kept as well.
        callbackUrl,
      },
      body: JSON.stringify({
        callbackUrl,
        referenceId: payoutRef,
        amount,
        narration: sanitizeNarration(narration ?? "") || "COA payout",
        accountNumber,
        currency: "ZMW",
        email: "payouts@churchonapp.com",
      }),
    });

    // Empty/non-JSON bodies (404 HTML) must not throw — report the status.
    let payoutData: unknown = null;
    try {
      payoutData = await payoutRes.json();
    } catch {
      payoutData = null;
    }

    if (!payoutRes.ok) {
      console.error("Lipila payout failed:", payoutRes.status, payoutData);
      return new Response(
        JSON.stringify({
          error: "Payout failed",
          status: payoutRes.status,
          details: payoutData ?? `lipila_http_${payoutRes.status}`,
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
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
