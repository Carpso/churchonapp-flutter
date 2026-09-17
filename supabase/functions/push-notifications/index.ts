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

  // Health probe: confirm the FCM credentials are wired WITHOUT returning any
  // secret material. `GET .../push-notifications?health=fcm`
  if (new URL(req.url).searchParams.get("health") === "fcm") {
    const pid = Deno.env.get("FCM_PROJECT_ID") ?? "";
    const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";
    let parses = false;
    let projectMatches = false;
    try {
      const sa = JSON.parse(saRaw);
      parses = !!sa.client_email && !!sa.private_key;
      projectMatches = sa.project_id === pid;
    } catch {
      parses = false;
    }
    return new Response(
      JSON.stringify({
        fcm_project_id_set: pid.length > 0,
        fcm_service_account_set: saRaw.length > 0,
        service_account_parses: parses,
        project_ids_match: projectMatches,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  }

  try {
    const authHeader = req.headers.get("Authorization");

    // ── Service mode ────────────────────────────────────────────────────────
    // DB triggers / pg_cron have NO user session, so they authenticate with the
    // shared CRON_SECRET (the same secret lps-settle/event crons use). Without
    // this, every notification created inside SQL (role approved, writer
    // approved, role change, trial expiry) could never produce a push.
    const cronSecret = Deno.env.get("CRON_SECRET");
    const providedSecret = req.headers.get("x-cron-secret");
    const isService = !!cronSecret && !!providedSecret && providedSecret === cronSecret;

    if (!isService && !authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let actorId = "00000000-0000-0000-0000-000000000000";
    if (!isService) {
      const token = (authHeader ?? "").replace("Bearer ", "");
      const { data: { user }, error: authError } = await supabase.auth.getUser(token);
      if (authError || !user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        });
      }
      actorId = user.id;
    }

    const payload = await req.json();
    const {
      userId, title, body, imageUrl, avatarUrl, data,
      type: topType,
      referenceId: topRef,
      channelId: topChannel,
      action,
      tenantId: broadcastTenantId,
      skipInApp,
    } = payload;
    const userIds = payload.userIds;

    // Normalize routing fields. Many callers historically passed `type` /
    // `referenceId` / `channelId` at the TOP level instead of inside `data`,
    // which silently downgraded every push to type "general" and dropped the
    // reference id (so a tap went to the wrong screen).
    const effType = (data?.type ?? topType ?? "general").toString();
    const effRef = data?.reference_id ?? topRef ?? null;
    const outData: Record<string, unknown> = { ...(data ?? {}), type: effType };
    if (effRef) outData.reference_id = effRef;
    if (topChannel) outData.channel_id = topChannel;

    const isBroadcast = action === "broadcast" && !!broadcastTenantId;

    const { allowed } = isBroadcast
      ? await checkRateLimit(supabase, actorId, "push_broadcast", isService ? 600 : 10, 1)
      : await checkRateLimit(supabase, actorId, "push_notification", isService ? 600 : 60, 1);
    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 429,
      });
    }

    const targetUserIds: string[] = [];
    if (isBroadcast) {
      // Server-side fan-out: resolve the church's members in ONE call so a
      // sermon/news/klip broadcast doesn't hit the per-caller rate limit after
      // ~60 recipients (which previously silently dropped the rest).
      const { data: members } = await supabase
        .from("profiles")
        .select("id")
        .eq("tenant_id", broadcastTenantId)
        .limit(2000);
      for (const m of members ?? []) {
        const id = m?.id?.toString();
        if (id && id !== actorId) targetUserIds.push(id);
      }
    } else {
      if (userId) targetUserIds.push(userId);
      if (userIds && Array.isArray(userIds)) targetUserIds.push(...userIds);
    }

    if (targetUserIds.length === 0 || !title || !body) {
      return new Response(JSON.stringify({ error: "Missing required fields: userId/userIds (or action:broadcast + tenantId), title, body" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    let sentCount = 0;
    const skipped: Record<string, number> = {};
    const bump = (k: string) => {
      skipped[k] = (skipped[k] ?? 0) + 1;
    };

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

        // `skipInApp` is set by DB triggers/cron that have ALREADY inserted the
        // in-app row (avoids a duplicate bell entry) and only need the push.
        if (skipInApp !== true) {
          await supabase.from("notifications").insert({
            user_id: targetUserId,
            title,
            body,
            is_read: false,
            type: effType,
            reference_id: effRef,
          });
        }

        if (profile?.fcm_token) {
          const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
          const notifImage = imageUrl || avatarUrl || undefined;

          if (!projectId) {
            console.warn("FCM_PROJECT_ID not set, skipping push");
            bump("no_project_id");
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
                      data: outData,
                      android: {
                        // Collapse key + TTL stop the offline flood: while the
                        // device is offline FCM queues pushes, then delivers
                        // them ALL at once on reconnect. With a per-type
                        // collapse key only the LATEST queued message per type
                        // is delivered, and nothing older than the TTL is kept.
                        collapseKey: effType,
                        ttl: "43200s",
                        priority: "high",
                        notification: {
                          channelId: channelForType(effType),
                          color: "#FFDA03",
                          icon: iconForType(effType),
                          ...(notifImage ? { image: notifImage } : {}),
                          sound: "default",
                          defaultSound: true,
                          defaultVibrateTimings: true,
                          defaultLightSettings: true,
                          visibility: "VISIBILITY_PUBLIC",
                          notificationPriority: "PRIORITY_MAX",
                          // Legacy snake_case for backward compat — FCM ignores unknown but keep both.
                          notification_priority: "PRIORITY_MAX" as unknown as string,
                          priority: "PRIORITY_MAX" as unknown as string,
                        },
                      },
                      apns: {
                        headers: {
                          "apns-collapse-id": effType,
                          "apns-priority": "10",
                          "apns-expiration": "43200",
                        },
                        payload: {
                          aps: {
                            "mutable-content": 1,
                            sound: "default",
                            badge: 1,
                            category: effType === "ride" ? "RIDE_CATEGORY" : undefined,
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

              if (fcmRes.ok) {
                sentCount++;
              } else {
                const errText = await fcmRes.text().catch(() => "");
                console.error(`FCM V1 send failed: ${fcmRes.status} ${errText.slice(0, 300)}`);
                // Dead/rotated token → clear it so the next send skips this device
                // instead of silently failing forever.
                if (/UNREGISTERED|NOT_FOUND|INVALID_ARGUMENT|SENDER_ID_MISMATCH/.test(errText)) {
                  await supabase
                    .from("profiles")
                    .update({ fcm_token: null })
                    .eq("id", targetUserId);
                  bump("invalid_token_cleared");
                } else {
                  bump("fcm_error");
                }
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
                    notification: {
                      title,
                      body,
                      color: "#FFDA03",
                      icon: iconForType(effType),
                      ...(notifImage ? { image: notifImage } : {}),
                    },
                    data: outData,
                    collapse_key: effType,
                    time_to_live: 43200,
                    android: { priority: "high" },
                  }),
                });

                if (fcmRes.ok) sentCount++;
                else bump("fcm_legacy_error");
              } else {
                bump("no_credentials");
              }
            }
          }
        } else {
          bump("no_token");
        }

        if (targetUserIds.length > 1) {
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      } catch (err) {
        console.error(`Failed to send to ${targetUserId}:`, err);
      }
    }

    return new Response(JSON.stringify({ success: true, sentCount, skipped, totalTargets: targetUserIds.length }), {
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
    case 'sermon': return 'ic_notif_general';
    case 'incoming_call': return 'ic_notif_ride';
    case 'driver_approval': return 'ic_notif_role';
    case 'pvp_invite': return 'ic_notif_quiz';
    case 'pvp_match': return 'ic_notif_quiz';
    case 'pvp_result': return 'ic_notif_quiz';
    case 'pvp_rematch': return 'ic_notif_quiz';
    case 'bible_study': return 'ic_notif_prayer';
    case 'fundraising': return 'ic_notif_payment';
    case 'group_contribution': return 'ic_notif_payment';
    case 'pledge_completed': return 'ic_notif_payment';
    case 'baptism': return 'ic_notif_prayer';
    case 'missions_donation': return 'ic_notif_payment';
    case 'sos_alert': return 'ic_notif_general';
    case 'church_approved': return 'ic_notif_role';
    case 'kyc_approved': return 'ic_notif_role';
    case 'kyc_rejected': return 'ic_notif_role';
    default: return 'ic_notif_general';
  }
}

function channelForType(type?: string): string {
  switch (type) {
    case 'chat': return 'coa_chat_v2';
    case 'post': return 'coa_posts_v2';
    case 'payment': return 'coa_payments_v2';
    case 'order': return 'coa_orders_v2';
    case 'event': return 'coa_events_v2';
    case 'prayer': return 'coa_prayers_v2';
    case 'testimony': return 'coa_testimonies_v2';
    case 'fasting': return 'coa_fasting_v2';
    case 'klip': return 'coa_klips_v2';
    case 'quiz': return 'coa_quiz_v2';
    case 'volunteer': return 'coa_volunteers_v2';
    case 'role': return 'coa_roles_v2';
    case 'job': return 'coa_jobs_v2';
    case 'ride': return 'coa_rides_v2';
    case 'worship': return 'coa_worship_v2';
    case 'sermon': return 'coa_announcements_v2';
    case 'incoming_call': return 'coa_rides_v2';
    case 'driver_approval': return 'coa_roles_v2';
    case 'pvp_invite': return 'coa_quiz_v2';
    case 'pvp_match': return 'coa_quiz_v2';
    case 'pvp_result': return 'coa_quiz_v2';
    case 'pvp_rematch': return 'coa_quiz_v2';
    case 'bible_study': return 'coa_prayers_v2';
    case 'fundraising': return 'coa_payments_v2';
    case 'group_contribution': return 'coa_payments_v2';
    case 'pledge_completed': return 'coa_payments_v2';
    case 'baptism': return 'coa_prayers_v2';
    case 'missions_donation': return 'coa_payments_v2';
    case 'sos_alert': return 'coa_announcements_v2';
    case 'church_approved': return 'coa_roles_v2';
    case 'kyc_approved': return 'coa_roles_v2';
    case 'kyc_rejected': return 'coa_roles_v2';
    default: return 'coa_announcements_v2';
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
