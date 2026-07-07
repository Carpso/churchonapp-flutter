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

const CHUNK_SIZE = 1000;
const BACKUP_TIMEOUT_MS = 55000;

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

    const startTime = Date.now();
    const backup: Record<string, unknown[]> = {};

    for (const table of TABLES) {
      if (Date.now() - startTime > BACKUP_TIMEOUT_MS) {
        backup["_truncated"] = true;
        break;
      }

      backup[table] = [];
      let from = 0;
      let hasMore = true;

      while (hasMore) {
        if (Date.now() - startTime > BACKUP_TIMEOUT_MS) {
          backup["_truncated"] = true;
          break;
        }

        const { data } = await supabase
          .from(table)
          .select("*")
          .range(from, from + CHUNK_SIZE - 1)
          .order("id", { ascending: true });

        if (data && data.length > 0) {
          backup[table] = [...backup[table], ...data];
          from += data.length;
          hasMore = data.length === CHUNK_SIZE;
        } else {
          hasMore = false;
        }
      }
    }

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    await supabase.from("admin_audit_log").insert({
      admin_id: user.id,
      admin_email: user.email,
      action: "system_backup",
      entity_type: "system",
      details: {
        tables: Object.keys(backup).filter((k) => !k.startsWith("_")),
        record_count: Object.values(backup).reduce((s, t) => s + (Array.isArray(t) ? t.length : 0), 0),
        truncated: backup["_truncated"] === true,
        elapsed_ms: Date.now() - startTime,
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
