import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

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
    const { amount, narration, reference, firstName, lastName, email, phone } = body;

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

    const callbackUrl = Deno.env.get("LIPILA_WEBHOOK_URL")
      ?? `${supabaseUrl}/functions/v1/lipila-webhook`;

    const referenceId = reference ?? crypto.randomUUID();

    // Format phone for Lipila (must be 260XXXXXXXXX format)
    let accountNumber: string = phone ?? "";
    if (accountNumber.length > 0) {
      accountNumber = accountNumber.replace(/\D/g, '');
      if (accountNumber.startsWith('0')) accountNumber = '260' + accountNumber.substring(1);
      if (accountNumber.startsWith('9') && accountNumber.length == 9) accountNumber = '260' + accountNumber;
      if (accountNumber.length == 9) accountNumber = '260' + accountNumber;
    }

    const cardRes = await fetch(`${baseUrl}/v1/collections/card`, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify({
        customerInfo: {
          firstName,
          lastName,
          phoneNumber: accountNumber,
          city: "Lusaka",
          country: "Zambia",
          address: "N/A",
          email: email || "payments@churchonapp.com",
          zip: "10101",
        },
        collectionRequest: {
          referenceId,
          amount,
          narration: narration ?? "COA card payment",
          accountNumber: accountNumber,
          currency: "ZMW",
          backUrl: "https://churchonapp.com/payment-complete",
          callbackUrl,
          referenceData: narration ?? "Card payment via COA",
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

    // Lipila returns a URL for card entry (3DS flow)
    const redirectUrl = cardData.url || cardData.data?.url || cardData.redirectUrl || cardData.data?.redirectUrl;

    return new Response(JSON.stringify({
      success: true,
      reference: referenceId,
      url: redirectUrl,
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
