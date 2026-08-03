import "https://deno.land/std@0.177.0/dotenv.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json();
    const { eventType, severity, userId, details, ipAddress } = body;

    await supabase.from("security_events").insert({
      event_type: eventType,
      severity: severity || "info",
      user_id: userId,
      details: details || {},
      ip_address: ipAddress,
    });

    if (severity === "critical" || severity === "high") {
      const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");
      const TELEGRAM_CHAT_ID = Deno.env.get("TELEGRAM_CHAT_ID");

      if (TELEGRAM_BOT_TOKEN && TELEGRAM_CHAT_ID) {
        const message = `🚨 *Security Alert*\n\n*Type:* ${eventType}\n*Severity:* ${severity?.toUpperCase()}\n*User:* ${userId || 'Unknown'}\n*IP:* ${ipAddress || 'Unknown'}\n*Details:* ${JSON.stringify(details || {})}\n*Time:* ${new Date().toISOString()}`;

        await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            chat_id: TELEGRAM_CHAT_ID,
            text: message,
            parse_mode: "Markdown",
          }),
        });
      }

      const ADMIN_EMAILS = Deno.env.get("SECURITY_ALERT_EMAILS")?.split(",") || [];
      const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

      if (RESEND_API_KEY && ADMIN_EMAILS.length > 0) {
        for (const email of ADMIN_EMAILS) {
          await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${RESEND_API_KEY}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              from: "Church On App Security <security@churchonapp.com>",
              to: [email.trim()],
              subject: `🚨 Security Alert: ${eventType}`,
              html: `
                <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">
                  <div style="background:#DC2626;color:white;padding:20px;text-align:center;">
                    <h1>Security Alert</h1>
                  </div>
                  <div style="padding:20px;background:white;">
                    <p><strong>Event:</strong> ${eventType}</p>
                    <p><strong>Severity:</strong> ${severity?.toUpperCase()}</p>
                    <p><strong>User ID:</strong> ${userId || 'Unknown'}</p>
                    <p><strong>IP Address:</strong> ${ipAddress || 'Unknown'}</p>
                    <p><strong>Details:</strong></p>
                    <pre style="background:#f4f4f4;padding:10px;border-radius:5px;overflow-x:auto;">${JSON.stringify(details || {}, null, 2)}</pre>
                    <p><strong>Time:</strong> ${new Date().toISOString()}</p>
                  </div>
                </div>
              `,
            }),
          });
        }
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Security alert error:", error);
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
