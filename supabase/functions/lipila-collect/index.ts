import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { settleReference, enqueueChurchAutoPayouts } from "../_shared/settlement.ts";

serve(async (req: Request) => {
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

    const { allowed } = await checkRateLimit(supabase, user.id, "lipila_collect", 10, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { action } = body;

    if (action === "status") {
      const { reference } = body;
      if (!reference) {
        return new Response(JSON.stringify({ error: "reference is required for status check" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

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

      // chisomo/kingdom contract: /check-status?referenceId= is the primary
      // status endpoint; fall back to the path-based variants if it 404s.
      let statusData: unknown;
      let statusResp: Response | null = null;
      for (const candidate of [
        `${baseUrl}/v1/collections/check-status?referenceId=${encodeURIComponent(reference)}`,
        `${baseUrl}/v1/collections/mobile-money/status/${reference}`,
        `${baseUrl}/v1/collections/mobile-money/${reference}`,
      ]) {
        statusResp = await fetch(candidate, {
          headers: { "x-api-key": apiKey, "accept": "application/json" },
        });
        if (statusResp.ok || statusResp.status !== 404) break;
      }

      let respStatus = statusResp?.status ?? 500;
      try {
        statusData = await statusResp?.json();
      } catch {
        statusData = null;
      }

      // Server-side confirmation sync: when Lipila itself reports the
      // collection settled, write the confirmed status into coa_payments and
      // run settlement immediately. This guarantees the tenant payout is
      // anchored even if a webhook delivery is lost (belt-and-suspenders).
      const raw = statusData as Record<string, unknown>;
      const tx =
        (raw?.data as Record<string, unknown> | undefined) ??
        (raw?.transaction as Record<string, unknown> | undefined) ??
        raw;
      const lStatus = [
        tx?.["status"],
        raw?.["status"],
        tx?.["transactionStatus"],
      ]
        .find((s) => typeof s === "string")
        ?.toString()
        .toLowerCase()
        .trim() ?? "";
      const CONFIRMED = ["successful", "paid", "completed", "settled", "success", "approved", "accepted", "confirmed"];
      if (CONFIRMED.includes(lStatus)) {
        try {
          const { data: row } = await supabase
            .from("coa_payments")
            .select("id")
            .eq("payment_ref", reference)
            .maybeSingle();
          if (row) {
            await supabase
              .from("coa_payments")
              .update({
                status: "settled",
                settled_at: new Date().toISOString(),
                webhook_idempotency: `lipila-status-${reference}`,
                phone_number: tx?.["accountNumber"] ?? raw?.["accountNumber"] ?? null,
                network: tx?.["paymentType"] ?? raw?.["paymentType"] ?? null,
                updated_at: new Date().toISOString(),
              })
              .eq("payment_ref", reference);
            try {
              await settleReference(supabase, reference);
              await enqueueChurchAutoPayouts(supabase);
            } catch (settleErr) {
              console.error(`[lipila-collect] Settlement sync failed for ${reference}: ${settleErr}`);
            }
          }
        } catch (dbErr) {
          console.warn(`[lipila-collect] Status DB sync failed for ${reference}: ${dbErr}`);
        }
      }

      return new Response(JSON.stringify({ status: respStatus, data: statusData }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action !== "initiate") {
      return new Response(JSON.stringify({ error: "Invalid action. Use 'initiate' or 'status'" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { accountNumber, amount, narration, reference: providedReference, metadata } = body;

    if (!accountNumber || !amount || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid collection parameters: accountNumber and amount are required" }), {
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

    // chisomo/kingdom contract: the webhook secret travels in the callbackUrl
    // query string so Lipila echoes it back on every delivery. HMAC headers are
    // still accepted as a secondary scheme by lipila-webhook.
    const callbackBase = Deno.env.get("LIPILA_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;
    const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
    const callbackUrl = webhookSecret
      ? `${callbackBase}?secret=${encodeURIComponent(webhookSecret)}`
      : callbackBase;

    const referenceId = providedReference ?? crypto.randomUUID();

    // ── PERSIST A PENDING PAYMENT ROW (immediate, before provider round-trip)
    // This guarantees the client poller finds the row and that organization /
    // branch / user metadata survives settlement via the webhook upsert.
    const userId = user.id;
    const rawMeta: Record<string, unknown> =
      metadata && typeof metadata === "object" && !Array.isArray(metadata)
        ? metadata as Record<string, unknown>
        : {};
    const meta: Record<string, unknown> = { ...rawMeta };
    if (!meta.user_id && userId) meta.user_id = userId;
    const { error: insertError } = await supabase
      .from("coa_payments")
      .insert({
        user_id: userId,
        service_type: typeof rawMeta.service_type === "string"
          ? rawMeta.service_type
          : "lipila_collect",
        amount: amount,
        payment_ref: referenceId,
        status: "pending",
        phone_number: accountNumber,
        category: typeof rawMeta.category === "string" ? rawMeta.category : null,
        metadata: Object.keys(meta).length > 0 ? meta : null,
      });
    if (insertError) {
      // Non-fatal: the webhook can still create/resolve the row by phone
      console.warn(`[lipila-collect] Could not pre-create coa_payments row: ${insertError.message}`);
    }

    const collectRes = await fetch(`${baseUrl}/v1/collections/mobile-money`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        callbackUrl,
        referenceId,
        amount,
        narration: narration ?? "COA payment",
        accountNumber,
        currency: "ZMW",
        email: "payments@churchonapp.com",
      }),
    });

    const collectData = await collectRes.json();

    if (!collectRes.ok) {
      console.error("Lipila collection failed:", collectData);
      return new Response(JSON.stringify({ error: "Collection failed", details: collectData }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true, reference: referenceId, data: collectData }), {
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
