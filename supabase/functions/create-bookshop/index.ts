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

    // Role check: superadmin/employee/bookshop_owner/vendor may create;
    // any authenticated user without a tenant may also self-register a bookshop.
    const { data: profile } = await supabase
      .from("profiles").select("role, tenant_id").eq("id", user.id).maybeSingle();
    const allowedRoles = ["superadmin", "coa_employee", "bookshop_owner", "vendor"];
    if (!allowedRoles.includes(profile?.role) && profile?.tenant_id) {
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

    // Create the tenant entry
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

    // Create the bookshop record (proper table, not marketplace_items)
    // New bookshops get a 30-day FREE trial (same as churches).
    const trialDays = Number(Deno.env.get("BOOKSHOP_TRIAL_DAYS") ?? "30");
    const trialEndsAt = new Date(Date.now() + trialDays * 24 * 60 * 60 * 1000).toISOString();
    await supabase.from("bookshops").insert({
      tenant_id: tenantId,
      name: name.trim(),
      description: description.trim(),
      contact: contact.trim(),
      location: location.trim(),
      owner_id: user.id,
      owner_name: profile?.full_name ?? (user.email ?? name),
      status: "pending",
      is_active: true,
      subscription_ends_at: trialEndsAt,
      plan: "silver",
    });

    // Assign caller as bookshop_owner and link to the new tenant
    await supabase.from("profiles").update({
      role: "bookshop_owner",
      tenant_id: tenantId,
    }).eq("id", user.id);

    // Audit trail
    await supabase.from("role_assignments").insert({
      user_id: user.id,
      role_name: "bookshop_owner",
      tenant_id: tenantId,
      assigned_by: user.id,
      status: "approved",
      created_at: new Date().toISOString(),
    });

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
