import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";
import { sanitizeNarration, sanitizeAccountNumber } from "../_shared/sanitize.ts";

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

    const { allowed } = await checkRateLimit(supabase, user.id, "lipila_card_collect", 10, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { amount, narration, reference, firstName, lastName, email, phone, metadata } = body;

    if (!amount || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid amount" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!firstName || !lastName) {
      return new Response(JSON.stringify({ error: "firstName and lastName are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("LIPILA_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Lipila API key not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const baseUrl = apiKey.startsWith("lsk_")
      ? "https://blz.lipila.io/api"
      : "https://api.lipila.dev/api";

    // Same dual scheme as lipila-collect: the webhook secret travels in the
    // callbackUrl query string so Lipila echoes it back on delivery.
    const callbackBase = Deno.env.get("LIPILA_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;
    const webhookSecret = Deno.env.get("LIPILA_WEBHOOK_SECRET") || "";
    const callbackUrl = webhookSecret
      ? `${callbackBase}?secret=${encodeURIComponent(webhookSecret)}`
      : callbackBase;

    const referenceId = reference ?? crypto.randomUUID();

    // Format phone for Lipila (must be 260XXXXXXXXX format)
    let accountNumber: string = phone ?? "";
    if (accountNumber.length > 0) {
      accountNumber = accountNumber.replace(/\D/g, "");
      if (accountNumber.startsWith("0")) accountNumber = "260" + accountNumber.substring(1);
      if (accountNumber.startsWith("9") && accountNumber.length == 9) accountNumber = "260" + accountNumber;
      if (accountNumber.length == 9) accountNumber = "260" + accountNumber;
    }

    // ── PENDING PAYMENT ANCHOR (same as lipila-collect) ──────────────────
    // Card payments must land in coa_payments BEFORE the provider round-trip
    // so the client poller finds the row, metadata survives settlement, and
    // the settlement engine can confirm/deny it later. ON CONFLICT DO NOTHING
    // keeps any server-pre-created (e.g. RPC-anchored) row authoritative.
    const rawMeta: Record<string, unknown> =
      metadata && typeof metadata === "object" && !Array.isArray(metadata)
        ? metadata as Record<string, unknown>
        : {};
    const meta: Record<string, unknown> = { ...rawMeta, channel: "card" };
    if (!meta.user_id && user.id) meta.user_id = user.id;
    const { error: insertError } = await supabase
      .from("coa_payments")
      .upsert({
        user_id: user.id,
        service_type: typeof rawMeta.service_type === "string"
          ? rawMeta.service_type
          : "lipila_card",
        amount: amount,
        payment_ref: referenceId,
        status: "pending",
        phone_number: accountNumber || null,
        category: typeof rawMeta.category === "string" ? rawMeta.category : null,
        metadata: Object.keys(meta).length > 0 ? meta : null,
      }, { onConflict: "payment_ref", ignoreDuplicates: true });
    if (insertError) {
      console.error(`[lipila-card-collect] Could not pre-create coa_payments row: ${insertError.message}`);
      return new Response(JSON.stringify({ error: "Could not create payment anchor" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Cardholder is returned to our SPA with the reference so the poller can
    // resume (the old bare /payment-complete 404'd — it has no route).
    const backUrl = `https://churchonapp.com/payment-complete?ref=${encodeURIComponent(referenceId)}`;

    // chisomo contract: for card collections accountNumber is the customer's
    // email, and every free-text field is narration-sanitized (Lipila rejects
    // anything outside letters/digits/spaces).
    const safeEmail = email || "payments@churchonapp.com";
    const cardRes = await fetch(`${baseUrl}/v1/collections/card`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        customerInfo: {
          firstName: sanitizeNarration(firstName),
          lastName: sanitizeNarration(lastName),
          phoneNumber: sanitizeAccountNumber(accountNumber),
          city: "Lusaka",
          country: "Zambia",
          address: "N/A",
          email: safeEmail,
          zip: "10101",
        },
        collectionRequest: {
          referenceId,
          amount,
          narration: sanitizeNarration(narration ?? "") || "COA card payment",
          accountNumber: safeEmail,
          currency: "ZMW",
          backUrl,
          callbackUrl,
          referenceData: sanitizeNarration(narration ?? "") || "Card payment via COA",
        },
      }),
    });

    const cardData = await cardRes.json();

    if (!cardRes.ok) {
      console.error("Lipila card collection failed:", cardData);
      return new Response(JSON.stringify({ error: "Card collection failed", details: cardData }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Lipila returns the hosted-checkout URL (3DS flow) as `cardRedirectionUrl`
    // (chisomo's field); older/other shapes use url/redirectUrl.
    const redirectUrl =
      cardData.cardRedirectionUrl ||
      cardData.data?.cardRedirectionUrl ||
      cardData.url ||
      cardData.data?.url ||
      cardData.redirectUrl ||
      cardData.data?.redirectUrl;

    return new Response(JSON.stringify({
      success: true,
      reference: referenceId,
      url: redirectUrl,
      cardRedirectionUrl: redirectUrl,
      data: cardData,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Card collection error:", error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
