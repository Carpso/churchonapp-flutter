import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { sanitizeNarration } from "../_shared/sanitize.ts";
import { settleReference, enqueueChurchAutoPayouts } from "../_shared/settlement.ts";
import {
  reconcileCollection,
  CONFIRMED_STATUSES,
  DECLINED_STATUSES,
} from "../_shared/collection-reconcile.ts";

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

      // ── OWNERSHIP (H3) ───────────────────────────────────────────────────
      // This used to look the payment up by `payment_ref` alone and hand back
      // Lipila's raw check-status body. Lipila's payload contains
      // `accountNumber` - the PAYER'S PHONE NUMBER - plus amount and
      // paymentType. Any logged-in user who learned or guessed a reference could
      // therefore read another member's phone number and amount, and could
      // force a `settled` write on someone else's row.
      //
      // chisomo returns only `{referenceId, id, status, amountCents}` from the
      // equivalent endpoint for exactly this reason. We now do the same.
      const { data: owned, error: ownedErr } = await supabase
        .from("coa_payments")
        .select("id, user_id, status")
        .eq("payment_ref", reference)
        .maybeSingle();

      if (ownedErr) {
        console.error(`[lipila-collect] ownership lookup failed: ${ownedErr.message}`);
        return new Response(JSON.stringify({ error: "Status check failed" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (!owned) {
        // Same shape as "not yours" for both cases so the endpoint cannot be
        // used to probe which references exist.
        return new Response(JSON.stringify({ error: "Not found" }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", user.id)
        .maybeSingle();
      const role = String(profile?.role ?? "").toLowerCase();
      const isStaff = ["superadmin", "super_admin", "coa_employee", "employee"]
        .includes(role);
      if (owned.user_id !== user.id && !isStaff) {
        return new Response(JSON.stringify({ error: "Not found" }), {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Reconciliation itself is shared with the `lps-settle` cron so the
      // interactive path and the background sweep can never disagree.
      const { outcome, status: providerStatus } = await reconcileCollection(
        supabase,
        reference,
        { kind: "momo" },
      );

      const finalStatus = String(owned.status ?? "").toLowerCase();
      const resolved = CONFIRMED_STATUSES.includes(finalStatus)
        ? "confirmed"
        : DECLINED_STATUSES.includes(finalStatus)
        ? "declined"
        : outcome;

      // Minimal response ONLY - never Lipila's raw payload, so the payer's
      // phone number can never leak to another member.
      return new Response(
        JSON.stringify({
          reference,
          status: resolved,
          provider_status: providerStatus,
          outcome,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
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
    // Idempotent anchor create: a server-side RPC (e.g.
    // request_meeting_subscription) may have ALREADY pre-created this row with
    // the same reference and a server-derived amount. ON CONFLICT DO NOTHING
    // keeps that authoritative row intact instead of 500ing the collection.
    const { error: insertError } = await supabase
      .from("coa_payments")
      .upsert({
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
      }, { onConflict: "payment_ref", ignoreDuplicates: true });
    if (insertError) {
      // Never initiate a collection without its server-side anchor. A later
      // webhook must not have to infer ownership or amount from a phone number.
      console.error(`[lipila-collect] Could not pre-create coa_payments row: ${insertError.message}`);
      return new Response(JSON.stringify({ error: "Could not create payment anchor" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
        narration: sanitizeNarration(narration ?? "") || "COA payment",
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
