import "https://deno.land/std@0.177.0/dotenv.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
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

    const body = await req.json();

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
