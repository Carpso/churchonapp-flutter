import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TABLES = [
  "profiles", "churches", "transactions", "wallet_transactions",
  "events", "event_registrations", "social_posts", "prayers",
  "testimonies", "klips", "ride_requests", "delivery_requests",
  "service_reports", "notifications", "platform_settings",
  "admin_audit_log", "radio_stations", "daily_bible_verses",
  "marketplace_items", "quiz_events", "quiz_participants", "quiz_passes",
];

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceRole);

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (!profile || !["superadmin", "employee"].includes(profile.role)) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    const backup: Record<string, unknown[]> = {};
    for (const table of TABLES) {
      const { data } = await supabase.from(table).select("*");
      backup[table] = data ?? [];
    }

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    await supabase.from("admin_audit_log").insert({
      admin_id: user.id,
      admin_email: user.email,
      action: "system_backup",
      entity_type: "system",
      details: {
        tables: TABLES,
        record_count: Object.values(backup).reduce((s, t) => s + t.length, 0),
      },
    });

    return new Response(JSON.stringify(backup, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="churchonapp_backup_${timestamp}.json"`,
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
