import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";
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

    const { newUserId, newUserName, churchId, churchName, notifyAll } = await req.json();

    if (!newUserId || !newUserName) {
      return new Response(JSON.stringify({ error: "Missing required fields: newUserId, newUserName" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // Fetch the new user's profile for display name
    const { data: newProfile } = await supabase
      .from("profiles")
      .select("full_name, display_name, avatar_url")
      .eq("id", newUserId)
      .single();

    const displayName = newProfile?.full_name || newProfile?.display_name || newUserName || "A new member";

    // Determine the notification title and body
    let title: string;
    let body: string;
    let channelId: string;

    if (churchId && churchName) {
      // Church-scoped: notify all other members of this church
      title = `${displayName} joined ${churchName}`;
      body = `Welcome! ${displayName} is now part of your church family.`;
      channelId = "coa_church_welcome";
    } else if (notifyAll) {
      // Platform-wide: notify all users
      title = `${displayName} joined Church On App`;
      body = `Welcome ${displayName} to the Church On App family!`;
      channelId = "coa_platform_welcome";
    } else {
      // Default: platform-wide welcome
      title = `${displayName} joined Church On App`;
      body = `Welcome ${displayName} to the Church On App family!`;
      channelId = "coa_platform_welcome";
    }

    // Build the list of target user IDs
    let targetUserIds: string[] = [];

    if (churchId) {
      // Get all other members of this church
      const { data: churchMembers, error: membersError } = await supabase
        .from("profiles")
        .select("id, fcm_token")
        .eq("tenant_id", churchId)
        .neq("id", newUserId)
        .not("fcm_token", "is", null);

      if (membersError) {
        console.error("Error fetching church members:", membersError);
      } else if (churchMembers) {
        targetUserIds = churchMembers.map((m: any) => m.id);
      }
    } else {
      // Platform-wide: get all users with FCM tokens (excluding the new user)
      const { data: allUsers, error: usersError } = await supabase
        .from("profiles")
        .select("id, fcm_token")
        .neq("id", newUserId)
        .not("fcm_token", "is", null);

      if (usersError) {
        console.error("Error fetching all users:", usersError);
      } else if (allUsers) {
        targetUserIds = allUsers.map((u: any) => u.id);
      }
    }

    if (targetUserIds.length === 0) {
      return new Response(JSON.stringify({ success: true, message: "No targets to notify" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    // Insert in-app notifications for all targets
    const notifications = targetUserIds.map((uid) => ({
      user_id: uid,
      title,
      body,
      is_read: false,
      type: "new_member",
      reference_id: newUserId,
      channel_id: channelId,
    }));

    const { error: notifError } = await supabase.from("notifications").insert(notifications);
    if (notifError) {
      console.error("Error inserting notifications:", notifError);
    }

    // Send FCM push notifications
    const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
    const accessToken = await getFcmAccessToken();
    const serverKey = Deno.env.get("FCM_SERVER_KEY");

    // Fetch FCM tokens for all targets
    const { data: targetProfiles } = await supabase
      .from("profiles")
      .select("fcm_token")
      .in("id", targetUserIds)
      .not("fcm_token", "is", null);

    const tokens = targetProfiles?.map((p: any) => p.fcm_token).filter(Boolean) ?? [];

    let sentCount = 0;
    let failedCount = 0;

    if (tokens.length > 0) {
      if (accessToken && projectId) {
        // Use FCM V1 API
        for (const token of tokens) {
          try {
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
                    token,
                    notification: { title, body },
                    data: {
                      type: "new_member",
                      reference_id: newUserId,
                      channel_id: channelId,
                    },
                    android: {
                      priority: "high",
                      notification: { icon: iconForChannel(channelId) },
                    },
                },
              }
            )
});

            if (fcmRes.ok) {
              sentCount++;
            } else {
              failedCount++;
              console.error(`FCM V1 send failed for token: ${fcmRes.status}`);
            }
          } catch (err) {
            failedCount++;
            console.error("FCM V1 send error:", err);
          }
        }
      } else if (serverKey) {
        // Fallback: FCM Legacy API (batch send)
        try {
          const fcmRes = await fetch("https://fcm.googleapis.com/fcm/send", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `key=${serverKey}`,
            },
            body: JSON.stringify({
              registration_ids: tokens,
              notification: { title, body },
              data: {
                type: "new_member",
                reference_id: newUserId,
                channel_id: channelId,
              },
              android: {
                priority: "high",
                notification: { icon: iconForChannel(channelId) },
              },
            }),
          });

          if (fcmRes.ok) {
            const result = await fcmRes.json();
            sentCount = result.success ?? 0;
            failedCount = result.failure ?? 0;
          } else {
            failedCount = tokens.length;
            console.error(`FCM Legacy send failed: ${fcmRes.status}`);
          }
        } catch (err) {
          failedCount = tokens.length;
          console.error("FCM Legacy send error:", err);
        }
      }
    }

    return new Response(JSON.stringify({
      success: true,
      notified: targetUserIds.length,
      push_sent: sentCount,
      push_failed: failedCount,
    }), {
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

function iconForChannel(channelId: string): string {
  switch (channelId) {
    case 'coa_church_welcome':
    case 'coa_platform_welcome':
      return 'ic_notif_general';
    default:
      return 'ic_notif_general';
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
