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

    const { church_id } = await req.json();
    if (!church_id) {
      return new Response(JSON.stringify({ error: "church_id is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Verify user is admin/pastor/bishop of this church
    const { data: profile } = await supabase
      .from("profiles")
      .select("role, tenant_id")
      .eq("id", user.id)
      .single();

    if (!profile || !["superadmin", "coa_employee", "bishop", "pastor", "admin"].includes(profile.role)) {
      return new Response(JSON.stringify({ error: "Insufficient permissions" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Superadmin can export any church; others only their own
    if (!["superadmin", "coa_employee"].includes(profile.role) && profile.tenant_id !== church_id) {
      return new Response(JSON.stringify({ error: "You can only export data for your own church" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { allowed } = await checkRateLimit(supabase, user.id, "export_church_data", 5, 60);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const startTime = Date.now();

    const [membersRes, transactionsRes, eventsRes, postsRes, prayersRes, testimoniesRes] = await Promise.all([
      supabase.from("profiles").select("id, full_name, role, phone_number, created_at").eq("tenant_id", church_id).order("full_name"),
      supabase.from("transactions").select("*").eq("tenant_id", church_id).order("created_at", { ascending: false }),
      supabase.from("events").select("*").eq("church_id", church_id).order("created_at", { ascending: false }),
      supabase.from("social_posts").select("*").eq("church_id", church_id).order("created_at", { ascending: false }),
      supabase.from("prayers").select("*").eq("church_id", church_id).order("created_at", { ascending: false }),
      supabase.from("testimonies").select("*").eq("church_id", church_id).order("created_at", { ascending: false }),
    ]);

    const churchData = {
      _metadata: {
        exported_at: new Date().toISOString(),
        church_id: church_id,
        exported_by: user.id,
        exported_by_email: user.email,
        export_version: "1.0",
      },
      members: membersRes.data || [],
      transactions: transactionsRes.data || [],
      events: eventsRes.data || [],
      social_posts: postsRes.data || [],
      prayers: prayersRes.data || [],
      testimonies: testimoniesRes.data || [],
    };

    // Log the export
    await supabase.from("admin_audit_log").insert({
      admin_id: user.id,
      admin_email: user.email,
      action: "church_data_export",
      entity_type: "church",
      entity_id: church_id,
      details: {
        record_count: Object.values(churchData).reduce((s: number, v) => s + (Array.isArray(v) ? v.length : 0), 0),
        elapsed_ms: Date.now() - startTime,
      },
    });

    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    return new Response(JSON.stringify(churchData, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="churchonapp_church_${timestamp}.json"`,
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
