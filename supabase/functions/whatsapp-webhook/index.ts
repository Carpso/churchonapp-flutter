import { getCorsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const url = new URL(req.url);
    const method = req.method;

    if (method === "GET") {
      const mode = url.searchParams.get("hub.mode");
      const token = url.searchParams.get("hub.verify_token");
      const challenge = url.searchParams.get("hub.challenge");

      if (mode === "subscribe") {
        const { data: config } = await supabase
          .from("whatsapp_config")
          .select("verify_token")
          .eq("is_enabled", true)
          .single();

        if (config && config.verify_token === token) {
          console.log("WhatsApp webhook verified");
          return new Response(challenge, { headers: corsHeaders });
        }
      }

      return new Response("Forbidden", { status: 403, headers: corsHeaders });
    }

    // HMAC-SHA256 signature verification (X-Hub-Signature-256).
    const rawBody = await req.text();
    const signature = req.headers.get("X-Hub-Signature-256") ?? "";
    const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");

    if (appSecret) {
      if (!signature.startsWith("sha256=")) {
        console.warn("WhatsApp webhook: missing or malformed X-Hub-Signature-256");
        return new Response("Forbidden", { status: 403, headers: corsHeaders });
      }
      const encoder = new TextEncoder();
      const key = await crypto.subtle.importKey(
        "raw",
        encoder.encode(appSecret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const hmac = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
      const expected = "sha256=" + Array.from(new Uint8Array(hmac))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      if (signature !== expected) {
        console.warn("WhatsApp webhook: signature mismatch");
        return new Response("Forbidden", { status: 403, headers: corsHeaders });
      }
    } else {
      console.warn("WHATSAPP_APP_SECRET not configured — webhook accepted without signature verification");
    }

    const body = JSON.parse(rawBody);

    if (body.object === "whatsapp_business_account") {
      for (const entry of body.entry || []) {
        for (const change of entry.changes || []) {
          if (change.field === "messages") {
            const value = change.value;

            if (value.messages) {
              for (const message of value.messages) {
                await supabase.from("security_events").insert({
                  event_type: "whatsapp_message_received",
                  severity: "info",
                  details: {
                    from: message.from,
                    type: message.type,
                    message_id: message.id,
                    timestamp: message.timestamp,
                  },
                });
              }
            }

            if (value.statuses) {
              for (const status of value.statuses) {
                console.log("WhatsApp status update:", status.id, status.status);
              }
            }
          }
        }
      }
    }

    return new Response("OK", { headers: corsHeaders });
  } catch (error) {
    console.error("WhatsApp webhook error:", error);
    return new Response("OK", { headers: corsHeaders });
  }
});
