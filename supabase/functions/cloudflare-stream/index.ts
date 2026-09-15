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
      case "get_live_input": {
        if (!params?.input_id || !(await ownsStream(supabaseAuth, params.input_id, profile))) {
          return new Response(JSON.stringify({ error: "Not authorized to view this input" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await getLiveInput(params, corsHeaders);
      }
      case "get_analytics": {
        if (params?.input_id && !(await ownsStream(supabaseAuth, params.input_id, profile))) {
          return new Response(JSON.stringify({ error: "Not authorized to view analytics" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await getAnalytics(params, corsHeaders);
      }
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
        if (params?.stream_id && !(await ownsLocalStream(supabaseAuth, params.stream_id, videoId, profile))) {
          return new Response(JSON.stringify({ error: "Not authorized to sign this video" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
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
        if (!(await ownsLocalStream(supabaseAuth, params?.stream_id, params?.video_id, profile))) {
          return new Response(JSON.stringify({ error: "Not authorized to delete this video" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await deleteVideo(params, corsHeaders);
      case "create_upload_url": {
        // VOD (sermon) upload via Cloudflare Stream Direct Creator Upload. The
        // client PUTs the file straight to Cloudflare, which transcodes it into
        // an adaptive-bitrate HLS ladder (up to the source resolution) + auto
        // thumbnail. Leadership-only (enforced above); church ownership is
        // enforced here when meta.church_id is supplied.
        const churchId = params?.meta?.church_id;
        if (churchId) {
          const isSuper = ["superadmin", "coa_employee"].includes(profile.role);
          if (!isSuper && churchId !== profile.tenant_id) {
            return new Response(
              JSON.stringify({ error: "Cannot upload video for another church" }),
              { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
          }
        }
        return await createDirectUpload(params, corsHeaders);
      }
      case "get_video": {
        const videoId = params?.video_id;
        if (!videoId) {
          return new Response(
            JSON.stringify({ error: "video_id is required for get_video" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return await getVideo(videoId, corsHeaders);
      }
      case "archive_recording": {
        // Copy a finished Cloudflare Stream recording into R2 (the cheap master
        // copy) by STREAMING it — no buffering, no VPS. Optionally pass
        // `video_id` directly; otherwise the recording is resolved from the
        // live input's video list.
        const streamId = params?.stream_id as string | undefined;
        const videoIdParam = params?.video_id as string | undefined;
        if (!streamId && !videoIdParam) {
          return new Response(
            JSON.stringify({ error: "stream_id or video_id is required for archive_recording" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const isSuper = ["superadmin", "coa_employee"].includes(profile.role);

        if (streamId) {
          const { data: row } = await supabaseAuth
            .from("live_streams")
            .select("id, church_id, cloudflare_stream_id, cloudflare_video_id")
            .eq("id", streamId)
            .maybeSingle();
          if (!row) {
            return new Response(JSON.stringify({ error: "Stream not found" }), {
              status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
          if (!isSuper && row.church_id !== profile.tenant_id) {
            return new Response(JSON.stringify({ error: "Not authorized to archive this stream" }), {
              status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
          return await archiveRecording(supabaseAuth, row, videoIdParam, corsHeaders);
        }

        const { data: byVideo } = await supabaseAuth
          .from("live_streams")
          .select("id, church_id, cloudflare_stream_id, cloudflare_video_id")
          .eq("cloudflare_video_id", videoIdParam)
          .maybeSingle();
        if (!byVideo || (!isSuper && byVideo.church_id !== profile.tenant_id)) {
          return new Response(JSON.stringify({ error: "Not authorized to archive this video" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await archiveRecording(supabaseAuth, byVideo, videoIdParam, corsHeaders);
      }
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

async function ownsLocalStream(supabase: any, streamId: string | undefined, videoId: string | undefined, profile: any): Promise<boolean> {
  if (!streamId || !videoId) return false;
  if (["superadmin", "coa_employee"].includes(profile.role)) return true;
  const { data, error } = await supabase
    .from("live_streams")
    .select("church_id, cloudflare_video_id")
    .eq("id", streamId)
    .maybeSingle();
  return !error && data?.church_id === profile.tenant_id && data?.cloudflare_video_id === videoId;
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

  // Live input responses may omit playback.hls even though the input exposes
  // a WebRTC playback URL. Derive the standard HLS manifest when possible so
  // OBS/RTMPS streams remain watchable by every tenant's viewer path.
  const result = data.result ?? {};
  const playbackUrl = result.webRTCPlayback?.url as string | undefined;
  if (!result.playback?.hls && !result.hls && playbackUrl) {
    result.hls = playbackUrl
      .replace('/webRTC/playback', '/manifest/video.m3u8')
      .replace('/webRTC', '/manifest/video.m3u8');
  }

  return new Response(
    JSON.stringify(result),
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
    JSON.stringify(data),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Creates a Cloudflare Stream Direct Creator Upload URL. The caller PUTs the
// raw video bytes to `uploadURL`; Cloudflare then transcodes to adaptive HLS.
async function createDirectUpload(params: any, corsHeaders: Record<string, string>) {
  // Cloudflare caps VOD duration per upload. Default 4h, hard-capped at 8h.
  const requested = Number(params?.max_duration_seconds ?? 14400);
  const maxDurationSeconds = Math.min(Math.max(requested || 14400, 60), 28800);

  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        maxDurationSeconds,
        requireSignedURLs: false,
        meta: params?.meta ?? {},
      }),
    }
  );

  const data = await response.json();
  if (!data.success) {
    const msg = data.errors?.[0]?.message || "Failed to create upload URL";
    console.error(`[cloudflare-stream] direct_upload CF API error ${response.status}: ${msg}`);
    return new Response(
      JSON.stringify({ success: false, error: msg, errors: data.errors ?? [] }),
      { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      uploadURL: data.result?.uploadURL,
      uid: data.result?.uid,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Fetches a Stream video's processing status + playback URLs.
async function getVideo(videoId: string, corsHeaders: Record<string, string>) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/${videoId}`,
    { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } }
  );

  const data = await response.json();
  if (!data.success) {
    const msg = data.errors?.[0]?.message || "Failed to fetch video";
    return new Response(
      JSON.stringify({ success: false, error: msg, errors: data.errors ?? [] }),
      { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const r = data.result ?? {};
  return new Response(
    JSON.stringify({
      success: true,
      uid: r.uid,
      readyToStream: r.readyToStream === true,
      status: r.status?.state ?? null,
      hls: r.playback?.hls ?? null,
      dash: r.playback?.dash ?? null,
      thumbnail: r.thumbnail ?? null,
      duration: r.duration ?? 0,
    }),
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

// ── Recording archive (Cloudflare Stream -> R2) ─────────────────────────────
// Streams the recording straight into R2 with a SigV4-signed PUT (aws4fetch),
// so multi-GB recordings never have to be buffered in the Edge runtime. The
// `live_streams` row is updated with the archive URL + status.
async function archiveRecording(
  supabase: any,
  row: any,
  videoIdParam: string | undefined,
  corsHeaders: Record<string, string>,
) {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const R2_ENDPOINT = Deno.env.get("R2_ENDPOINT");
  const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID");
  const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const R2_BUCKET = Deno.env.get("R2_BUCKET");
  const R2_PUBLIC_DOMAIN = Deno.env.get("R2_PUBLIC_DOMAIN");

  if (!R2_ENDPOINT || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY || !R2_BUCKET) {
    return json({ error: "R2 archive is not configured (R2_ENDPOINT/keys/bucket)" }, 500);
  }

  const videoId = await resolveRecordingVideoId(row, videoIdParam);
  if (!videoId) {
    if (row?.id) {
      await supabase
        .from("live_streams")
        .update({ archive_status: "failed", archive_error: "No recording found for this stream yet" })
        .eq("id", row.id);
    }
    return json({ error: "No recording found for this stream yet" }, 404);
  }

  if (row?.id) {
    await supabase
      .from("live_streams")
      .update({ archive_status: "archiving", archive_error: null })
      .eq("id", row.id);
  }

  try {
    // Ask Cloudflare to prepare a downloadable MP4, then read its URL.
    await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/${videoId}/downloads`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
          "Content-Type": "application/json",
        },
      },
    ).catch(() => {});

    const dlRes = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/${videoId}/downloads`,
      { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
    );
    const dlJson = await dlRes.json().catch(() => null);
    const def = dlJson?.result?.default;
    const downloadUrl = def?.url as string | undefined;
    if (!downloadUrl) {
      return json(
        { error: "Recording download is not ready yet", status: def?.status ?? "unknown" },
        409,
      );
    }

    const { AwsClient } = await import("https://esm.sh/aws4fetch@1.0.20");
    const aws = new AwsClient({
      accessKeyId: R2_ACCESS_KEY_ID,
      secretAccessKey: R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });

    const key = `stream-archive/${videoId}.mp4`;
    const putUrl = `${R2_ENDPOINT.replace(/\/+$/, "")}/${R2_BUCKET}/${key}`;

    const source = await fetch(downloadUrl);
    if (!source.ok || !source.body) {
      throw new Error(`Cloudflare download failed (${source.status})`);
    }

    const put = await aws.fetch(putUrl, {
      method: "PUT",
      headers: {
        "content-type": "video/mp4",
        // Required for a streamed (unhashable) body.
        "x-amz-content-sha256": "UNSIGNED-PAYLOAD",
      },
      body: source.body,
    });
    if (!put.ok) {
      const t = await put.text().catch(() => "");
      throw new Error(`R2 PUT failed (${put.status}) ${t.slice(0, 200)}`);
    }

    const archiveUrl = R2_PUBLIC_DOMAIN
      ? `https://${R2_PUBLIC_DOMAIN}/${key}`
      : key;

    if (row?.id) {
      await supabase
        .from("live_streams")
        .update({
          archive_url: archiveUrl,
          archive_status: "ready",
          archived_at: new Date().toISOString(),
          archive_error: null,
        })
        .eq("id", row.id);
    }

    return json({ success: true, archive_url: archiveUrl, video_id: videoId });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (row?.id) {
      await supabase
        .from("live_streams")
        .update({ archive_status: "failed", archive_error: msg.slice(0, 300) })
        .eq("id", row.id);
    }
    return json({ error: msg }, 500);
  }
}

// Finds the Cloudflare Stream video uid for a live input's latest recording.
async function resolveRecordingVideoId(
  row: any,
  videoIdParam: string | undefined,
): Promise<string | null> {
  if (videoIdParam) return videoIdParam;
  if (row?.cloudflare_video_id) return row.cloudflare_video_id;
  if (!row?.cloudflare_stream_id) return null;

  const res = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${row.cloudflare_stream_id}/videos`,
    { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
  );
  const j = await res.json().catch(() => null);
  const list: any[] = Array.isArray(j?.result) ? j.result : [];
  if (list.length === 0) return null;

  const ready = list
    .filter((v) => v?.readyToStream)
    .sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime());
  const chosen = ready[0] ?? list[0];
  return chosen?.uid ?? null;
}
