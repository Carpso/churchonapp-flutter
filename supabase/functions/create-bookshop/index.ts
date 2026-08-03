// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
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

    // Role check: only superadmin, employee, or existing bookshop_owner can create bookshops
    const { data: profile } = await supabase
      .from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (!["superadmin", "coa_employee", "bookshop_owner", "vendor"].includes(profile?.role)) {
      return new Response(JSON.stringify({ error: "Forbidden: insufficient permissions" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { name, description, contact, location } = await req.json();
    if (!name || !description || !contact || !location) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check for duplicate bookshop name
    const existing = await supabase
      .from("tenants").select("id").ilike("name", name.trim()).maybeSingle();
    if (existing?.data) {
      return new Response(JSON.stringify({ error: "A bookshop with this name already exists" }), {
        status: 409,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const tenantRes = await supabase.from("tenants").insert({
      name: name.trim(),
      type: "bookshop",
    }).select("id").single();
    const tenantId = tenantRes.data?.id;
    if (!tenantId) {
      return new Response(JSON.stringify({ error: "Failed to create tenant" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await supabase.from("marketplace_items").insert({
      name: name.trim(),
      description: description.trim(),
      contact: contact.trim(),
      location: location.trim(),
      category: "bookshop",
      vendor_id: user.id,
      tenant_id: tenantId,
      created_at: new Date().toISOString(),
    });

    await supabase.from("profiles").update({
      role: "vendor",
      tenant_id: tenantId,
    }).eq("id", user.id);

    return new Response(JSON.stringify({ success: true, tenantId }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
