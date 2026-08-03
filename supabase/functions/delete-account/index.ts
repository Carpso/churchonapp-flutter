// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
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

    const { confirm_email } = await req.json();

    const { allowed } = await checkRateLimit(supabase, user.id, "delete_account", 2, 60);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (confirm_email !== user.email) {
      return new Response(JSON.stringify({ error: "Email confirmation does not match" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;

    // Check if user is the last superadmin
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .single();

    if (profile?.role === "superadmin") {
      const { count } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "superadmin");

      if (count && count <= 1) {
        return new Response(JSON.stringify({ error: "Cannot delete the last superadmin account. Promote another user first." }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Anonymize user-owned data (soft-delete pattern)
    const anonName = "Deleted User";
    const anonAvatar = "https://i.pravatar.cc/300?u=deleted";

    // 1. Anonymize profile
    await supabase.from("profiles").update({
      full_name: anonName,
      avatar_url: anonAvatar,
      phone_number: null,
      email: user.email,
      role: "member",
      is_work_mode: false,
      tenant_id: null,
      bio: null,
      settings: null,
      updated_at: new Date().toISOString(),
    }).eq("id", userId);

    // 2. Anonymize social posts
    await supabase.from("social_posts").update({
      content: "[This post has been deleted]",
      media_urls: [],
    }).eq("user_id", userId);

    // 3. Anonymize chat messages
    await supabase.from("messages").update({
      content: "[This message has been deleted]",
      media_url: null,
      sticker_id: null,
    }).eq("user_id", userId);

    // 4. Anonymize comments
    await supabase.from("social_comments").update({
      content: "[This comment has been deleted]",
    }).eq("user_id", userId);

    // 5. Delete prayers (user-owned)
    await supabase.from("prayers").delete().eq("user_id", userId);

    // 6. Delete notes (user-owned)
    await supabase.from("notes").delete().eq("user_id", userId);

    // 7. Delete AI chat sessions
    await supabase.from("ai_chat_sessions").delete().eq("user_id", userId);

    // 8. Delete quiz data
    await supabase.from("quiz_participants").delete().eq("user_id", userId);
    await supabase.from("quiz_passes").delete().eq("user_id", userId);

    // 9. Delete sermon reactions
    await supabase.from("sermon_reactions").delete().eq("user_id", userId);

    // 10. Delete fasting data
    await supabase.from("user_fasts").delete().eq("user_id", userId);

    // 11. Delete ride requests
    await supabase.from("ride_requests").delete().eq("user_id", userId);

    // 12. Delete delivery requests
    await supabase.from("delivery_requests").delete().eq("user_id", userId);

    // 13. Delete event registrations
    await supabase.from("event_registrations").delete().eq("user_id", userId);

    // 14. Delete KYC data
    await supabase.from("kyc_documents").delete().eq("user_id", userId);

    // 15. Log the deletion
    await supabase.from("admin_audit_log").insert({
      admin_id: userId,
      admin_email: user.email,
      action: "account_deletion",
      entity_type: "profile",
      entity_id: userId,
      details: { timestamp: new Date().toISOString() },
    });

    // 16. Sign out all sessions
    await supabase.auth.admin.signOut(userId);

    // 17. Delete auth user record permanently
    const { error: deleteUserError } = await supabase.auth.admin.deleteUser(userId);
    if (deleteUserError) {
      console.error("Failed to delete auth user:", deleteUserError);
    }

    return new Response(JSON.stringify({ success: true, message: "Account has been deleted. You will be signed out." }), {
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
