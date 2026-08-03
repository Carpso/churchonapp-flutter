import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
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

    const { allowed } = await checkRateLimit(supabase, user.id, "push_notification", 60, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 429,
      });
    }

    const { userId, userIds, title, body, imageUrl, avatarUrl, data } = await req.json();

    const targetUserIds: string[] = [];
    if (userId) targetUserIds.push(userId);
    if (userIds && Array.isArray(userIds)) targetUserIds.push(...userIds);

    if (targetUserIds.length === 0 || !title || !body) {
      return new Response(JSON.stringify({ error: "Missing required fields: userId or userIds, title, body" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    let sentCount = 0;

    for (const targetUserId of targetUserIds) {
      try {
        // Skip duplicates: if an identical UNREAD notification already exists
        // for this user within the last 5 minutes, don't double-send.
        const { data: existing } = await supabase
          .from("notifications")
          .select("id")
          .eq("user_id", targetUserId)
          .eq("title", title)
          .eq("body", body)
          .eq("is_read", false)
          .gte("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
          .limit(1);

        if (existing && existing.length > 0) continue;

        const { data: profile } = await supabase
          .from("profiles")
          .select("fcm_token")
          .eq("id", targetUserId)
          .single();

        await supabase.from("notifications").insert({
          user_id: targetUserId,
          title,
          body,
          is_read: false,
          type: data?.type ?? "general",
          reference_id: data?.reference_id ?? null,
        });

        if (profile?.fcm_token) {
          const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
          const notifImage = imageUrl || avatarUrl || undefined;

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
                      notification: {
                        title,
                        body,
                        ...(notifImage ? { image: notifImage } : {}),
                      },
                      data: data ?? {},
                      android: {
                        // Collapse key + TTL stop the offline flood: while the
                        // device is offline FCM queues pushes, then delivers
                        // them ALL at once on reconnect. With a per-type
                        // collapse key only the LATEST queued message per type
                        // is delivered, and nothing older than the TTL is kept.
                        collapseKey: data?.type ?? "general",
                        ttl: "43200s",
                        priority: "high",
                        notification: {
                          color: "#FFDA03",
                          icon: iconForType(data?.type),
                          ...(notifImage ? { image: notifImage } : {}),
                          notification_priority: "PRIORITY_MAX",
                          visibility: "VISIBILITY_PUBLIC",
                        },
                      },
                      apns: {
                        headers: {
                          "apns-collapse-id": data?.type ?? "general",
                          "apns-expiration": "43200",
                        },
                        payload: {
                          aps: {
                            "mutable-content": 1,
                            alert: { title, body },
                          },
                        },
                        fcm_options: {
                          ...(notifImage ? { image: notifImage } : {}),
                        },
                      },
                    },
                  }),
                }
              );

              if (fcmRes.ok) sentCount++;
              else console.error(`FCM V1 send failed: ${fcmRes.status}`);
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
                    notification: {
                      title,
                      body,
                      color: "#FFDA03",
                      icon: iconForType(data?.type),
                      ...(notifImage ? { image: notifImage } : {}),
                    },
                    data: data ?? {},
                    collapse_key: data?.type ?? "general",
                    time_to_live: 43200,
                    android: { priority: "high" },
                  }),
                });

                if (fcmRes.ok) sentCount++;
                else console.error(`FCM Legacy send failed: ${fcmRes.status}`);
              }
            }
          }
        }

        if (targetUserIds.length > 1) {
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      } catch (err) {
        console.error(`Failed to send to ${targetUserId}:`, err);
      }
    }

    return new Response(JSON.stringify({ success: true, sentCount, totalTargets: targetUserIds.length }), {
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

function iconForType(type?: string): string {
  switch (type) {
    case 'chat': return 'ic_notif_chat';
    case 'post': return 'ic_notif_chat';
    case 'payment': return 'ic_notif_payment';
    case 'order': return 'ic_notif_payment';
    case 'event': return 'ic_notif_event';
    case 'prayer': return 'ic_notif_prayer';
    case 'testimony': return 'ic_notif_prayer';
    case 'fasting': return 'ic_notif_prayer';
    case 'klip': return 'ic_notif_klip';
    case 'quiz': return 'ic_notif_quiz';
    case 'volunteer': return 'ic_notif_volunteers';
    case 'role': return 'ic_notif_role';
    case 'job': return 'ic_notif_job';
    case 'ride': return 'ic_notif_ride';
    case 'worship': return 'ic_notif_worship';
    default: return 'ic_notif_general';
  }
}

async function getFcmAccessToken(): Promise<string | null> {
  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saJson) return null;

  try {
    const sa = JSON.parse(saJson);
    const now = Math.floor(Date.now() / 1000);

    const privateKey = await importPKCS8(sa.private_key, "RS256");

    const jwt = await new SignJWT({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: "https://oauth2.googleapis.com/token",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256", typ: "JWT", kid: sa.private_key_id })
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .sign(privateKey);

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
  } catch (err) {
    console.error("FCM token generation failed:", err);
    return null;
  }
}
