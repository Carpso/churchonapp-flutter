import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

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

    const userId = user.id;

    const { allowed } = await checkRateLimit(supabase, user.id, "export_user_data", 5, 60);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const startTime = Date.now();

    // Fetch all user-owned data
    const [profileRes, postsRes, messagesRes, prayersRes, notesRes, transactionsRes, quizzesRes, fastingRes] = await Promise.all([
      supabase.from("profiles").select("*").eq("id", userId).single(),
      supabase.from("social_posts").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
      supabase.from("messages").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
      supabase.from("prayers").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
      supabase.from("notes").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
      supabase.from("transactions").select("*").eq("user_id", userId).order("created_at", { ascending: false }),
      supabase.from("quiz_participants").select("*").eq("user_id", userId),
      supabase.from("user_fasts").select("*").eq("user_id", userId),
    ]);

    const exportData = {
      _metadata: {
        exported_at: new Date().toISOString(),
        user_id: userId,
        user_email: user.email,
        export_version: "1.0",
      },
      profile: profileRes.data,
      social_posts: postsRes.data || [],
      messages: messagesRes.data || [],
      prayers: prayersRes.data || [],
      notes: notesRes.data || [],
      transactions: transactionsRes.data || [],
      quiz_data: quizzesRes.data || [],
      fasting_data: fastingRes.data || [],
    };

    // Log the export
    await supabase.from("admin_audit_log").insert({
      admin_id: userId,
      admin_email: user.email,
      action: "data_export",
      entity_type: "profile",
      entity_id: userId,
      details: {
        record_count: Object.values(exportData).reduce((s: number, v) => s + (Array.isArray(v) ? v.length : 0), 0),
        elapsed_ms: Date.now() - startTime,
      },
    });

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    return new Response(JSON.stringify(exportData, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="churchonapp_my_data_${timestamp}.json"`,
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
