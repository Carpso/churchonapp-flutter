// Supabase Edge Function: cloudflare-stream
// Handles all Cloudflare Stream API calls
// Deploy: supabase functions deploy cloudflare-stream

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

const CLOUDFLARE_ACCOUNT_ID = Deno.env.get("CLOUDFLARE_ACCOUNT_ID");
const CLOUDFLARE_API_TOKEN = Deno.env.get("CLOUDFLARE_API_TOKEN");

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  // SECURITY: only church leadership may manage stream infrastructure
  // (create/delete live inputs, WHIP ingest, video deletion, analytics).
  // Viewers consume HLS directly and never invoke this function.
  const { data: profile, error: profileError } = await supabaseAuth
    .from("profiles")
    .select("role, tenant_id, organization_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return new Response(JSON.stringify({ error: "User profile not found" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 403,
    });
  }

  const leadershipRoles = ["superadmin", "coa_employee", "bishop", "apostle", "prophet", "general_secretary", "pastor", "admin", "leader", "department_leader"];
  if (!leadershipRoles.includes(profile.role)) {
    return new Response(JSON.stringify({ error: "Insufficient role", role: profile.role }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 403,
    });
  }

  try {
    const { action, ...params } = await req.json();

    switch (action) {
      case "create_live_input": {
        const churchId = params?.meta?.church_id;
        if (!churchId) {
          return new Response(
            JSON.stringify({ error: "meta.church_id is required for create_live_input" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        // Ownership: leaders may only create streams for their own church
        // unless they are a superadmin / COA employee (network oversight).
        const isSuper = ["superadmin", "coa_employee"].includes(profile.role);
        if (!isSuper && churchId !== profile.tenant_id) {
          return new Response(
            JSON.stringify({ error: "Cannot create streams for another church" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return await createLiveInput(params, corsHeaders);
      }
      case "delete_live_input": {
        const inputId = params?.input_id;
        if (!inputId) {
          return new Response(
            JSON.stringify({ error: "input_id is required for delete_live_input" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const ok = await ownsStream(supabaseAuth, inputId, profile);
        if (!ok) {
          return new Response(
            JSON.stringify({ error: "Not authorized to delete this stream" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return await deleteLiveInput(params, corsHeaders);
      }
      case "get_live_input":
        return await getLiveInput(params, corsHeaders);
      case "get_analytics":
        return await getAnalytics(params, corsHeaders);
      case "list_videos": {
        // Tenant-scoped: return only streams belonging to the caller's church
        // (or all if superadmin/employee). Avoids the unbounded account-wide list.
        const isSuper = ["superadmin", "coa_employee"].includes(profile.role);
        let query = supabaseAuth.from("live_streams").select("*").order("started_at", { ascending: false });
        if (!isSuper) query = query.eq("church_id", profile.tenant_id);
        const { data: churchStreams, error: listErr } = await query;
        if (listErr) {
          return new Response(JSON.stringify({ error: listErr.message }), {
            status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return new Response(JSON.stringify(churchStreams ?? []), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      case "create_signed_url": {
        const key = Deno.env.get("CLOUDFLARE_STREAM_SIGNING_KEY");
        if (!key) {
          return new Response(JSON.stringify({ error: "CLOUDFLARE_STREAM_SIGNING_KEY not configured" }), {
            status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        const videoId = params?.video_id;
        if (!videoId) {
          return new Response(JSON.stringify({ error: "video_id is required" }), {
            status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await createSignedUrl(params, key, corsHeaders);
      }
      case "whip_offer": {
        // WHIP ingestion must reference a live input the caller owns.
        const inputId = params?.input_id;
        if (!inputId) {
          return new Response(
            JSON.stringify({ error: "input_id is required for whip_offer" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const ok = await ownsStream(supabaseAuth, inputId, profile);
        if (!ok) {
          return new Response(
            JSON.stringify({ error: "Not authorized to ingest to this stream" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return await whipOffer(params, corsHeaders);
      }
      case "delete_video":
        return await deleteVideo(params, corsHeaders);
      default:
        return new Response(
          JSON.stringify({ error: "Unknown action" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// Returns true if the authenticated leader owns the given Cloudflare stream
// input (or is a superadmin / COA employee with network oversight).
async function ownsStream(supabase: any, cloudflareStreamId: string, profile: any): Promise<boolean> {
  const isSuper = ["superadmin", "coa_employee"].includes(profile.role);
  if (isSuper) return true;
  try {
    const { data, error } = await supabase
      .from("live_streams")
      .select("church_id")
      .eq("cloudflare_stream_id", cloudflareStreamId)
      .maybeSingle();
    if (error) return false;
    return data?.church_id === profile.tenant_id;
  } catch {
    return false;
  }
}

async function createLiveInput(params: any, corsHeaders: Record<string, string>) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        enabled: true,
        preferLowLatency: false,
        deleteRecordingAfterDays: 90,
        meta: params.meta || {},
        recording: {
          mode: "automatic",
          requireSignedURLs: false,
          timeoutSeconds: 0,
        },
      }),
    }
  );

  const data = await response.json();

  if (!data.success) {
    const msg = data.errors?.[0]?.message || "Failed to create live input";
    console.error(`[cloudflare-stream] create_live_input CF API error ${response.status}: ${msg}`);
    return new Response(
      JSON.stringify({ success: false, error: msg, errors: data.errors ?? [] }),
      { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify(data.result),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

async function deleteLiveInput(params: any, corsHeaders: Record<string, string>) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${params.input_id}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
      },
    }
  );

  const data = await response.json();

  return new Response(
    JSON.stringify(data),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

async function getLiveInput(params: any, corsHeaders: Record<string, string>) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${params.input_id}`,
    {
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
      },
    }
  );

  const data = await response.json();

  return new Response(
    JSON.stringify(data.result),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

async function getAnalytics(params: any, corsHeaders: Record<string, string>) {
  // Cloudflare Stream analytics via GraphQL
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream-analytics`,
    {
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
      },
    }
  );

  const data = await response.json();

  return new Response(
    JSON.stringify(data),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Generate a signed URL for VOD playback. Uses Cloudflare Stream's
// signing key (SHA-256 HMAC). Token is valid for [expiresIn] hours (default 24).
// Requires CLOUDFLARE_STREAM_SIGNING_KEY env var.
async function createSignedUrl(params: any, signingKey: string, corsHeaders: Record<string, string>) {
  const videoId = params?.video_id;
  const expiresIn = params?.expires_in_hours ?? 24;

  const msInHour = 3600000;
  const expires = Math.floor(Date.now() / 1000) + expiresIn * 3600;
  const data = videoId + expires.toString();

  const encoder = new TextEncoder();
  const keyBuf = encoder.encode(signingKey);
  const dataBuf = encoder.encode(data);

  const cryptoKey = await crypto.subtle.importKey(
    "raw", keyBuf, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, dataBuf);
  const sigBytes = new Uint8Array(sig);

  // Token = base64url(byte[0..7] + signature)
  const tokenBytes = new Uint8Array(8 + sigBytes.length);
  tokenBytes.set(sigBytes.slice(0, 8), 0);
  tokenBytes.set(sigBytes, 8);

  let token = "";
  for (const b of tokenBytes) {
    token += String.fromCharCode(b);
  }
  token = btoa(token).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

  const signedUrl = `https://cloudflarestream.com/${videoId}/manifest/video.m3u8?token=${token}&expires=${expires}`;

  return new Response(JSON.stringify({ url: signedUrl, expires }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// WebRTC WHIP (WebRTC HTTP Ingestion Protocol) for phone camera streaming.
// Allows phones to push camera feed directly to Cloudflare Stream via WebRTC.
// The WHIP publish URL is the live input's `webRTC.url`
// (https://customer-<CODE>.cloudflarestream.com/<SECRET>/webRTC/publish) —
// NOT the account API. This relay resolves it server-side so the secret
// publish URL never has to live in the app.
async function whipOffer(params: any, corsHeaders: Record<string, string>) {
  const { input_id, sdp } = params;

  if (!input_id || !sdp) {
    throw new Error("input_id and sdp are required");
  }

  // Resolve the WHIP publish URL for the caller-owned live input.
  const inputRes = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${input_id}`,
    { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } }
  );
  const inputData = await inputRes.json();
  if (!inputRes.ok || !inputData?.success) {
    const msg = inputData?.errors?.[0]?.message || `Live input lookup failed`;
    console.error(`[cloudflare-stream] whip_offer CF API error ${inputRes.status}: ${msg}`);
    throw new Error(`${msg} (HTTP ${inputRes.status})`);
  }
  const whipUrl = inputData.result?.webRTC?.url;
  if (!whipUrl) {
    throw new Error("Live input does not expose a WebRTC (WHIP) publish URL");
  }

  // Send SDP offer to the WHIP endpoint. No Authorization header — the
  // publish URL itself is the credential.
  const response = await fetch(whipUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/sdp",
    },
    body: sdp,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`WHIP offer failed: ${response.status} ${errorText}`);
  }

  // Return the SDP answer
  const answerSdp = await response.text();

  return new Response(
    JSON.stringify({
      success: true,
      sdp: answerSdp,
      type: "answer",
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Delete a recorded video from Cloudflare Stream
async function deleteVideo(params: any, corsHeaders: Record<string, string>) {
  if (!params.video_id) {
    throw new Error("video_id is required");
  }

  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/${params.video_id}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
      },
    }
  );

  const data = await response.json();

  return new Response(
    JSON.stringify(data),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}
