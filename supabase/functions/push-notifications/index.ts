import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const { userId, title, body, data } = await req.json();

        const supabaseClient = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
        );

        // 1. Resolve FCM token from Profile
        const { data: profile, error: profileError } = await supabaseClient
            .from("profiles")
            .select("fcm_token")
            .eq("id", userId)
            .single();

        if (profileError || !profile?.fcm_token) {
            // Fallback: If no FCM token, at least insert into internal notifications table
            await supabaseClient.from('notifications').insert({
                user_id: userId,
                title,
                body,
                is_read: false
            });
            return new Response(JSON.stringify({ success: true, message: "Logged to internal table (no push token)" }), {
                headers: { ...corsHeaders, "Content-Type": "application/json" },
                status: 200,
            });
        }

        // 2. Prepare FCM v1 Send (Prototype)
        // Note: To fully send, you need a Google Service Account JSON and token generation logic.
        // This serves as the structural endpoint for Supabase Webhooks.

        const fcmPayload = {
            message: {
                token: profile.fcm_token,
                notification: { title, body },
                data: data ?? {},
                android: { priority: "high" },
            }
        };

        console.log(`[PUSH] Dispatching to ${userId}: ${title}`);

        // For now, we also log to the notifications table so the active-session stream picks it up
        await supabaseClient.from('notifications').insert({
            user_id: userId,
            title,
            body,
            is_read: false
        });

        return new Response(JSON.stringify({ success: true, fcmPayload }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
        });
    } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 400,
        });
    }
});
