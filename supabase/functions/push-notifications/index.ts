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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const { userId, title, body, data } = await req.json();

    const { data: profile } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", userId)
      .single();

    await supabase.from("notifications").insert({
      user_id: userId,
      title,
      body,
      is_read: false,
      type: data?.type ?? "general",
      reference_id: data?.reference_id ?? null,
    });

    if (profile?.fcm_token) {
      const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";

      if (!projectId) {
        console.warn("FCM_PROJECT_ID not set, skipping push");
      } else {
        const accessToken = await getFcmAccessToken();
        if (accessToken) {
          const fcmRes = await fetch(
            `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${accessToken}`,
              },
              body: JSON.stringify({
                message: {
                  token: profile.fcm_token,
                  notification: { title, body },
                  data: data ?? {},
                  android: { priority: "high" },
                },
              }),
            }
          );

          if (!fcmRes.ok) {
            console.error(`FCM V1 send failed: ${fcmRes.status} ${await fcmRes.text()}`);
          }
        } else {
          const serverKey = Deno.env.get("FCM_SERVER_KEY");
          if (serverKey) {
            const fcmRes = await fetch("https://fcm.googleapis.com/fcm/send", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `key=${serverKey}`,
              },
              body: JSON.stringify({
                to: profile.fcm_token,
                notification: { title, body },
                data: data ?? {},
                android: { priority: "high" },
              }),
            });

            if (!fcmRes.ok) {
              console.error(`FCM Legacy send failed: ${fcmRes.status} ${await fcmRes.text()}`);
            }
          }
        }
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});

async function getFcmAccessToken(): Promise<string | null> {
  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saJson) return null;

  const sa = JSON.parse(saJson);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT", kid: sa.private_key_id };
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const b64 = (obj: Record<string, unknown>) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const sign = async (data: string) => {
    const key = await crypto.subtle.importKey(
      "pkcs8",
      new TextEncoder().encode(sa.private_key).buffer as ArrayBuffer,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );
    const sig = await crypto.subtle.sign(
      { name: "RSASSA-PKCS1-v1_5" },
      key,
      new TextEncoder().encode(data)
    );
    return btoa(String.fromCharCode(...new Uint8Array(sig)))
      .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  };

  const message = `${b64(header)}.${b64(payload)}`;
  const signature = await sign(message);
  const jwt = `${message}.${signature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    console.error("OAuth2 token error:", await tokenRes.text());
    return null;
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}
