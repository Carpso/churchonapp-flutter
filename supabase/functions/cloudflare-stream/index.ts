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

  // ── Service mode (pg_cron) ──────────────────────────────────────────────
  // The nightly archive sweep has no user session; it authenticates with the
  // shared CRON_SECRET and may ONLY archive recordings.
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
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  // Parse the body early: the leadership gate below must be able to allow the
  // viewer-safe `refresh_live_input` action (which every authenticated member
  // may call to reconcile a stale live_streams row with Cloudflare's real
  // input status/playback URLs). All other actions stay leadership-only.
  let bodyJson: any = null;
  try {
    bodyJson = await req.json();
  } catch (_) {
    bodyJson = null;
  }
  const earlyAction = bodyJson?.action;
  const VIEWER_SAFE_ACTIONS = ["refresh_live_input"];

  // SECURITY: only church leadership may manage stream infrastructure
  // (create/delete live inputs, WHIP ingest, video deletion, analytics).
  // Viewers consume HLS directly and never invoke this function.
  let profile: { role: string; tenant_id: string | null; organization_id: string | null } | null = null;

  if (!isService) {
    const token = (authHeader ?? "").replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const { data: prof, error: profileError } = await supabaseAuth
      .from("profiles")
      .select("role, tenant_id, organization_id")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !prof) {
      return new Response(JSON.stringify({ error: "User profile not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 403,
      });
    }
    profile = prof;

    const leadershipRoles = ["superadmin", "coa_employee", "bishop", "apostle", "prophet", "general_secretary", "pastor", "admin", "leader", "department_leader"];
    const viewerSafe = VIEWER_SAFE_ACTIONS.includes(earlyAction);
    if (!leadershipRoles.includes(profile.role) && !viewerSafe) {
      return new Response(JSON.stringify({ error: "Insufficient role", role: profile.role }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 403,
      });
    }
  }

  try {
    const { action, ...params } = bodyJson ?? {};

    // Service (cron) may only resolve/archive recordings.
    if (isService && action !== "archive_recording" && action !== "resolve_recording") {
      return new Response(JSON.stringify({ error: "Service key may only archive recordings" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

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
      case "disable_live_input": {
        // Preferred over deleting: stopping ingest by DISABLING the live input
        // keeps the input (and therefore its recording list) intact, so the
        // R2 archive can still resolve the recording. Deleting the input first
        // is what made every archive attempt fail once the input was gone.
        const inputId = params?.input_id;
        if (!inputId) {
          return new Response(
            JSON.stringify({ error: "input_id is required for disable_live_input" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const ok = await ownsStream(supabaseAuth, inputId, profile);
        if (!ok) {
          return new Response(
            JSON.stringify({ error: "Not authorized to disable this stream" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return await disableLiveInput(params, corsHeaders);
      }
      case "get_live_input": {
        const inputId = params?.input_id as string | undefined;
        const streamId = params?.stream_id as string | undefined;
        // Leadership-only: a leader may inspect their own input (or any input as
        // superadmin/COA). When a stream_id is supplied we reconcile + persist
        // the authoritative playback surface on the row.
        if (inputId && !(await ownsStream(supabaseAuth, inputId, profile))) {
          return new Response(JSON.stringify({ error: "Not authorized to view this input" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        if (streamId) {
          return await refreshLiveInput(supabaseAuth, { stream_id: streamId }, corsHeaders);
        }
        if (!inputId) {
          return new Response(JSON.stringify({ error: "input_id or stream_id is required" }), {
            status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await getLiveInput(params, corsHeaders);
      }
      case "refresh_live_input": {
        // Viewer-safe: reconciles a stale live_streams row with Cloudflare's
        // real live-input status/playback URLs. Any authenticated member may
        // call it (viewers must be able to repair a stream that is genuinely
        // live but whose stored hls_url is empty/temporarily unavailable).
        return await refreshLiveInput(supabaseAuth, params, corsHeaders);
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
        const isSuper = isService ||
          ["superadmin", "coa_employee"].includes(profile?.role ?? "");

        if (streamId) {
          const { data: row } = await supabaseAuth
            .from("live_streams")
            .select("id, church_id, status, cloudflare_stream_id, cloudflare_video_id, archive_url, archive_status")
            .eq("id", streamId)
            .maybeSingle();
          if (!row) {
            return new Response(JSON.stringify({ error: "Stream not found" }), {
              status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
          if (!isSuper && row.church_id !== profile?.tenant_id) {
            return new Response(JSON.stringify({ error: "Not authorized to archive this stream" }), {
              status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
          }
          return await archiveRecording(supabaseAuth, row, videoIdParam, corsHeaders);
        }

        const { data: byVideo } = await supabaseAuth
          .from("live_streams")
          .select("id, church_id, status, cloudflare_stream_id, cloudflare_video_id, archive_url, archive_status")
          .eq("cloudflare_video_id", videoIdParam)
          .maybeSingle();
        if (!byVideo || (!isSuper && byVideo.church_id !== profile?.tenant_id)) {
          return new Response(JSON.stringify({ error: "Not authorized to archive this video" }), {
            status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        return await archiveRecording(supabaseAuth, byVideo, videoIdParam, corsHeaders);
      }
      case "resolve_recording": {
        // Resolves the Cloudflare Stream *video* uid + HLS manifest for a live
        // input's finished recording and persists it on the row. This is what
        // makes a recorded service playable: the live-input manifest
        // (`…/<input_uid>/manifest/video.m3u8`) returns 204 once the broadcast
        // ends, while the recording lives under its OWN video uid generated at
        // broadcast start. Never downloads — cheap, safe to call often.
        return await resolveAndPersistRecording(supabaseAuth, params, profile, isService, corsHeaders);
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
  // Cloudflare `meta` accepts STRING values only (max 1024 chars). Sending an
  // int/array (e.g. `max_duration` or `allowed_origins`) makes the whole
  // request invalid → 400 code 10005 "Bad Request". Coerce/clean here so no
  // client can break stream creation, and return a clear error if it still fails.
  const rawMeta =
    params?.meta && typeof params.meta === "object" && !Array.isArray(params.meta)
      ? params.meta as Record<string, unknown>
      : {};
  const meta: Record<string, string> = {};
  for (const [k, v] of Object.entries(rawMeta)) {
    if (v === null || v === undefined) continue;
    const s = Array.isArray(v) ? v.join(",") : String(v);
    if (s.length > 0) meta[k] = s.slice(0, 1024);
  }

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
        meta,
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

  // IMPORTANT — do NOT fabricate an HLS URL here.
  //
  // A Cloudflare live-input create/retrieve response has NO `playback` object;
  // the authoritative HLS/DASH manifests only exist on the input's currently
  // live VIDEO, and they are produced ONLY for RTMPS/SRT ingests. A WHIP
  // (WebRTC) broadcast is neither recorded nor published as HLS/DASH by
  // Cloudflare, so `…/<input_uid>/manifest/video.m3u8` returns HTTP 204 for the
  // entire broadcast. The old code rewrote the WebRTC playback URL into an HLS
  // URL and stored it — a URL that can never play, which is exactly why viewers
  // sat on "Stream is starting…" forever. For a WHIP broadcast the playable URL
  // is the WHEP endpoint (`webRTCPlayback.url`). Surfaced from
  // `normaliseLiveInput` / `refresh_live_input` instead.
  const result = data.result ?? {};
  return new Response(
    JSON.stringify(result),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Cloudflare live-input statuses that mean an ingest is actively connected.
const LIVE_INPUT_CONNECTED_STATUSES = [
  "connected",
  "reconnected",
  "reconnecting",
  "new_configuration_accepted",
];

function liveWhepUrl(result: any): string | undefined {
  const u = result?.webRTCPlayback?.url ?? result?.preview ?? undefined;
  return typeof u === "string" && u.length > 0 ? u : undefined;
}

// Normalises a Cloudflare live-input result into the authoritative playback
// surface. `playback` (if supplied) must come from the input's live VIDEO —
// pass it explicitly when known, otherwise HLS/DASH stay null and the caller
// must use WHEP (`whep`) for a WHIP-ingested broadcast.
function normaliseLiveInput(
  result: any,
  playback?: { hls?: string | null; dash?: string | null },
) {
  const hls = playback?.hls ?? result?.playback?.hls ?? null;
  const dash = playback?.dash ?? result?.playback?.dash ?? null;
  const whep = liveWhepUrl(result) ?? null;
  const inputStatus = (result?.status as string | undefined) ?? null;
  return {
    input_status: inputStatus,
    enabled: result?.enabled ?? null,
    connected: !!inputStatus && LIVE_INPUT_CONNECTED_STATUSES.includes(inputStatus),
    hls,
    dash,
    preview: whep,
    whep,
    // 'hls' when Cloudflare is emitting a real adaptive manifest (RTMPS/SRT
    // broadcast), 'webrtc' when the only playable transport is WHEP.
    mode: hls ? "hls" : "webrtc",
  };
}

// Fetches the live input's currently-live VIDEO. Only RTMPS/SRT broadcasts
// produce one; a WHIP broadcast is never recorded, so this returns null and the
// caller falls back to WHEP.
async function fetchLiveInputVideo(
  inputId: string,
): Promise<{ uid: string | null; hls: string | null; dash: string | null } | null> {
  try {
    const res = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${inputId}/videos`,
      { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
    );
    const j = await res.json().catch(() => null);
    const list: any[] = Array.isArray(j?.result) ? j.result : [];
    if (list.length === 0) return null;
    const live =
      list.find((v) => (v?.status?.state ?? "") === "live-inprogress") ??
      list.find((v) => v?.readyToStream);
    if (!live) return null;
    return {
      uid: live.uid ?? null,
      hls: live.playback?.hls ?? live.hls ?? null,
      dash: live.playback?.dash ?? live.dash ?? null,
    };
  } catch {
    return null;
  }
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

// Stops ingest without deleting the input (and its recordings). Cloudflare has
// no cheap "stop broadcast" call, so we flip `enabled` to false via PUT; the
// input and its recorded videos stay resolvable for archiving.
async function disableLiveInput(params: any, corsHeaders: Record<string, string>) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${params.input_id}`,
    {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ enabled: false }),
    }
  );

  const data = await response.json();
  if (!data.success) {
    const msg = data.errors?.[0]?.message || "Failed to disable live input";
    console.error(`[cloudflare-stream] disable_live_input CF API error ${response.status}: ${msg}`);
    return new Response(
      JSON.stringify({ success: false, error: msg, errors: data.errors ?? [] }),
      { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, enabled: data.result?.enabled ?? false }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Leadership read of a live input, normalised to the authoritative playback
// surface (`hls` only when Cloudflare is really emitting HLS/DASH, otherwise
// `whep` for a WHIP broadcast). Does not persist.
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
  if (!data.success) {
    const msg = data.errors?.[0]?.message || "Failed to fetch live input";
    return new Response(
      JSON.stringify({ success: false, error: msg, errors: data.errors ?? [] }),
      { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const result = data.result ?? {};
  const liveVideo = await fetchLiveInputVideo(params.input_id);
  const base = normaliseLiveInput(result, {
    hls: liveVideo?.hls ?? null,
    dash: liveVideo?.dash ?? null,
  });

  return new Response(
    JSON.stringify({ success: true, uid: result.uid ?? null, ...base }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// Reconciles a `live_streams` row with Cloudflare's real live-input state.
// The viewer calls this whenever playback fails so that:
//   - the authoritative playback surface is applied: HLS/DASH when the input's
//     live video emits them (RTMPS/SRT), otherwise the WHEP URL (WHIP) — never a
//     fabricated HLS URL that can only 204, and
//   - the real state is surfaced: connected (genuinely live), not-yet-connected
//     (starting/arming), or no input (scheduled without a Cloudflare input).
// Any authenticated member may call it; it can never mutate anything except the
// playback URLs of the referenced row.
async function refreshLiveInput(supabase: any, params: any, corsHeaders: Record<string, string>) {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const streamId = params?.stream_id;
  if (!streamId) return json({ error: "stream_id is required" }, 400);

  const { data: row } = await supabase
    .from("live_streams")
    .select("id, church_id, status, cloudflare_stream_id, cloudflare_video_id, hls_url, preview_url, dash_url, recording_hls_url, archive_url")
    .eq("id", streamId)
    .maybeSingle();
  if (!row) return json({ error: "Stream not found" }, 404);

  if (!row.cloudflare_stream_id) {
    return json({
      success: true,
      id: row.id,
      status: row.status,
      input_status: null,
      connected: false,
      hls: row.hls_url ?? null,
      dash: null,
      preview: row.preview_url ?? null,
      whep: row.preview_url ?? null,
      mode: "idle",
      reason: "no_input",
    });
  }

  let result: any = null;
  try {
    const res = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${row.cloudflare_stream_id}`,
      { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
    );
    const payload = await res.json();
    if (!res.ok || !payload?.success) {
      const msg = payload?.errors?.[0]?.message || `Live input lookup failed (HTTP ${res.status})`;
      return json({ success: false, error: msg }, 502);
    }
    result = payload.result ?? {};
  } catch (e) {
    return json({ success: false, error: e instanceof Error ? e.message : String(e) }, 502);
  }

  // The live input object itself carries no playback object. HLS/DASH exist only
  // on the input's currently-live video (RTMPS/SRT); WHIP broadcasts have none.
  const liveVideo = await fetchLiveInputVideo(row.cloudflare_stream_id);
  const base = normaliseLiveInput(result, {
    hls: liveVideo?.hls ?? null,
    dash: liveVideo?.dash ?? null,
  });

  // Persist the authoritative surface (service role) so every later viewer gets
  // a valid URL without another round-trip.
  //
  // HLS handling: `base.hls` is only set when Cloudflare is really emitting an
  // adaptive manifest (the input's live VIDEO exists). When the input is
  // CONNECTED but no live video exists, the ingest is WHIP — which Cloudflare
  // never publishes as HLS/DASH — so we CLEAR any previously stored (fabricated)
  // `hls_url`; that dead URL is exactly what made viewers never play. While the
  // input is idle/starting we keep whatever we had (we cannot yet tell the
  // ingest type apart and must not break an in-flight RTMPS stream).
  const patch: Record<string, unknown> = {};
  let finalHls = base.hls;
  if (base.hls) {
    if (base.hls !== row.hls_url) patch.hls_url = base.hls;
  } else if (base.connected && !liveVideo) {
    finalHls = null;
    if (row.hls_url) patch.hls_url = null;
  } else {
    finalHls = row.hls_url ?? null;
  }
  if (base.dash) patch.dash_url = base.dash;
  if (base.whep && base.whep !== row.preview_url) patch.preview_url = base.whep;

  // Ended/archived streams: self-heal the RECORDING. The live-input manifest
  // returns 204 once a broadcast ends, so a viewer opening a recorded service
  // must get the recording's own video manifest. Resolve it once and persist
  // `cloudflare_video_id` + `recording_hls_url`; the sermon sync trigger then
  // repairs the corresponding Recorded Service sermon.
  let recordingHls = row.recording_hls_url ?? null;
  if (
    ["ended", "archived"].includes(String(row.status ?? "")) &&
    !row.archive_url && !recordingHls
  ) {
    try {
      const rec = await resolveRecording(row);
      if (rec?.uid) {
        patch.cloudflare_video_id = rec.uid;
        if (rec.hls) {
          patch.recording_hls_url = rec.hls;
          recordingHls = rec.hls;
        }
      }
    } catch (_) {
      // Non-fatal: fall through with whatever is already stored.
    }
  }

  if (Object.keys(patch).length > 0) {
    try {
      await supabase.from("live_streams").update(patch).eq("id", row.id);
    } catch (_) {
      // Non-fatal: playback still proceeds with the freshly fetched URLs.
    }
  }

  return json({
    success: true,
    id: row.id,
    status: row.status,
    input_status: base.input_status,
    connected: base.connected,
    enabled: base.enabled,
    hls: finalHls,
    dash: base.dash,
    preview: base.whep,
    whep: base.whep,
    mode: base.connected ? (finalHls ? "hls" : "webrtc") : "idle",
    recording_hls: recordingHls,
    cloudflare_video_id: patch.cloudflare_video_id ?? row.cloudflare_video_id ?? null,
  });
}
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

  // A still-live (or scheduled) stream has no finalised recording yet. This is
  // an expected state — do NOT write `archive_status='failed'` or log a 404,
  // which made every immediate end-of-broadcast attempt look like an error.
  if (["live", "scheduled"].includes(String(row?.status ?? ""))) {
    return json(
      {
        success: false,
        reason: "still_live",
        message: "Recording is only available after the broadcast ends",
      },
      202,
    );
  }

  const rec = await resolveRecording(row, videoIdParam);
  const videoId = rec?.uid;
  if (!videoId) {
    // Cloudflare needs a little time to finalise a recording after a broadcast
    // ends. This is a normal "not ready yet" state, not a failure: mark it
    // `queued` (so the sweep retries) and return 202 instead of a 404 error.
    if (row?.id) {
      await supabase
        .from("live_streams")
        .update({ archive_status: "queued", archive_error: "recording_not_ready" })
        .eq("id", row.id);
    }
    return json({ success: false, reason: "recording_not_ready" }, 202);
  }

  // Idempotency: never re-copy (and therefore never double-charge Stream egress
  // / R2 bandwidth for) a recording that is already the permanent master.
  if (
    row?.id &&
    row.archive_status === "ready" &&
    typeof row.archive_url === "string" &&
    row.archive_url.length > 0 &&
    (row.cloudflare_video_id ?? videoId) === videoId
  ) {
    return json({
      success: true,
      already_archived: true,
      archive_url: row.archive_url,
      video_id: videoId,
    });
  }

  if (row?.id) {
    await supabase
      .from("live_streams")
      .update({
        archive_status: "processing",
        archive_error: null,
        // Persist the resolved video id + its own HLS manifest so every later
        // retry (and the nightly cron) is deterministic and no longer depends
        // on the live input. `recording_hls_url` is what the recorded-service
        // sermon plays when the R2 master is not ready yet.
        cloudflare_video_id: videoId,
        ...(rec?.hls ? { recording_hls_url: rec.hls } : {}),
      })
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
      // The recording is not downloadable yet (Stream still finalising). Mark
      // it queued so the archive sweep retries it instead of leaving a stale
      // `processing` row that nothing would ever pick up.
      if (row?.id) {
        await supabase
          .from("live_streams")
          .update({
            archive_status: "queued",
            archive_error: `recording_not_ready (${def?.status ?? "unknown"})`,
          })
          .eq("id", row.id);
      }
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

    const key = `stream-recordings/${row?.id ?? videoId}.mp4`;
    const putUrl = `${R2_ENDPOINT.replace(/\/+$/, "")}/${R2_BUCKET}/${key}`;

    const source = await fetch(downloadUrl);
    if (!source.ok || !source.body) {
      throw new Error(`Cloudflare download failed (${source.status})`);
    }

    // The body is piped straight from Stream's download URL to R2 — no
    // in-memory buffering, so multi-GB recordings do not blow the Edge heap.
    // NOTE: the Edge *wall clock* is still finite; a very long copy can be
    // killed mid-PUT. That leaves the row `processing`, which the archive sweep
    // retries (overwriting the partial object at the same key).
    const putHeaders: Record<string, string> = {
      "content-type": "video/mp4",
      // Required for a streamed (unhashable) body.
      "x-amz-content-sha256": "UNSIGNED-PAYLOAD",
    };
    const contentLength = Number(source.headers.get("content-length") ?? 0);
    if (contentLength > 0) putHeaders["content-length"] = String(contentLength);

    const put = await aws.fetch(putUrl, {
      method: "PUT",
      headers: putHeaders,
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
          archive_attempts: 0,
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

// Builds the playback manifest URL for a *video* uid on the same Stream
// customer host as the row's existing URLs. Falls back to null when no host is
// known (the recording list usually already carries `playback.hls`, so this is
// only a safety net).
function videoManifestUrl(row: any, videoId: string): string | null {
  const candidates = [row?.hls_url, row?.preview_url, row?.dash_url]
    .filter((u: unknown): u is string => typeof u === "string" && u.length > 0);
  for (const u of candidates) {
    const m = u.match(/^https?:\/\/([^/]+)\//);
    if (m) return `https://${m[1]}/${videoId}/manifest/video.m3u8`;
  }
  return null;
}

// Resolves the Cloudflare Stream *video* uid + HLS manifest for a live input's
// latest recording. Prefers the per-input video list, then falls back to the
// ACCOUNT video list filtered by `liveInput` — so resolution still works after
// an input is deleted. Returns null when the input has recorded nothing.
//
// WHY this matters: a live input's manifest (`…/<input_uid>/manifest/video.m3u8`)
// is only served while the input is live; after the broadcast it returns HTTP
// 204, which a player reports as a manifest-parsing/network error. The recording
// is a SEPARATE video uid created when the broadcast starts, and only its own
// manifest keeps working.
async function resolveRecording(
  row: any,
  videoIdParam?: string,
): Promise<{ uid: string; hls: string | null } | null> {
  const hlsOf = (v: any): string | null => v?.playback?.hls ?? v?.hls ?? null;
  const pickLatest = (list: any[]): any | null => {
    if (!Array.isArray(list) || list.length === 0) return null;
    const ready = list
      .filter((v) => v?.readyToStream)
      .sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime());
    return ready[0] ?? list[0] ?? null;
  };

  if (videoIdParam) {
    try {
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/${videoIdParam}`,
        { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
      );
      const j = await res.json().catch(() => null);
      const hls = hlsOf(j?.result) ?? videoManifestUrl(row, videoIdParam);
      return { uid: videoIdParam, hls };
    } catch (_) {
      return { uid: videoIdParam, hls: videoManifestUrl(row, videoIdParam) };
    }
  }

  if (row?.cloudflare_video_id) {
    return { uid: row.cloudflare_video_id, hls: videoManifestUrl(row, row.cloudflare_video_id) };
  }
  if (!row?.cloudflare_stream_id) return null;

  let list: any[] = [];
  try {
    const res = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${row.cloudflare_stream_id}/videos`,
      { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
    );
    const j = await res.json().catch(() => null);
    list = Array.isArray(j?.result) ? j.result : [];
  } catch (_) {
    list = [];
  }
  let chosen = pickLatest(list);

  if (!chosen?.uid) {
    // Fallback: the live input may already be gone, but its recordings survive
    // in the account and carry a `liveInput` back-reference.
    try {
      const res = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream?limit=100`,
        { headers: { Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}` } },
      );
      const j = await res.json().catch(() => null);
      const all: any[] = Array.isArray(j?.result) ? j.result : [];
      const mine = all.filter(
        (v) =>
          v?.liveInput === row.cloudflare_stream_id ||
          v?.meta?.live_input === row.cloudflare_stream_id ||
          v?.meta?.cloudflare_stream_id === row.cloudflare_stream_id,
      );
      chosen = pickLatest(mine);
    } catch (_) {
      chosen = null;
    }
  }
  if (!chosen?.uid) return null;
  return { uid: chosen.uid, hls: hlsOf(chosen) ?? videoManifestUrl(row, chosen.uid) };
}

// Resolves a recording and persists `cloudflare_video_id` + `recording_hls_url`
// on the live_streams row (without downloading anything). Also invoked
// opportunistically by the viewer-safe `refresh_live_input` so an ended stream
// self-heals into a playable recording.
async function resolveAndPersistRecording(
  supabase: any,
  params: any,
  profile: any,
  isService: boolean,
  corsHeaders: Record<string, string>,
) {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const streamId = params?.stream_id;
  if (!streamId) return json({ error: "stream_id is required" }, 400);

  const { data: row } = await supabase
    .from("live_streams")
    .select("id, church_id, status, cloudflare_stream_id, cloudflare_video_id, hls_url, preview_url, dash_url, recording_hls_url")
    .eq("id", streamId)
    .maybeSingle();
  if (!row) return json({ error: "Stream not found" }, 404);

  const isSuper = isService || ["superadmin", "coa_employee"].includes(profile?.role ?? "");
  if (!isSuper && row.church_id !== profile?.tenant_id) {
    return json({ error: "Not authorized to resolve this recording" }, 403);
  }

  const rec = await resolveRecording(row, params?.video_id);
  if (!rec) return json({ success: false, error: "No recording found for this stream yet" }, 404);

  await supabase
    .from("live_streams")
    .update({ cloudflare_video_id: rec.uid, recording_hls_url: rec.hls })
    .eq("id", streamId);

  return json({ success: true, video_id: rec.uid, hls: rec.hls });
}
