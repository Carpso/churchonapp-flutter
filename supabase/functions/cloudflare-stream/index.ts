// Supabase Edge Function: cloudflare-stream
// Handles all Cloudflare Stream API calls
// Deploy: supabase functions deploy cloudflare-stream

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CLOUDFLARE_ACCOUNT_ID = Deno.env.get("CLOUDFLARE_ACCOUNT_ID");
const CLOUDFLARE_API_TOKEN = Deno.env.get("CLOUDFLARE_API_TOKEN");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
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

  try {
    const { action, ...params } = await req.json();

    switch (action) {
      case "create_live_input":
        return await createLiveInput(params, req);
      case "delete_live_input":
        return await deleteLiveInput(params);
      case "get_live_input":
        return await getLiveInput(params);
      case "get_analytics":
        return await getAnalytics(params);
      case "list_videos":
        return await listVideos(req);
      case "whip_offer":
        return await whipOffer(params, req);
      case "delete_video":
        return await deleteVideo(params);
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

async function createLiveInput(params: any, req: Request) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        meta: params.meta || {},
        recording: {
          mode: "automatic",
          requireSignedURLs: false,
          allowedOrigins: ["*"],
        },
        rtmps: {
          enabled: true,
        },
        srt: {
          enabled: false,
        },
        webRTC: {
          enabled: true,
        },
      }),
    }
  );

  const data = await response.json();

  if (!data.success) {
    throw new Error(data.errors?.[0]?.message || "Failed to create live input");
  }

  return new Response(
    JSON.stringify(data.result),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

async function deleteLiveInput(params: any) {
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

async function getLiveInput(params: any) {
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

async function getAnalytics(params: any) {
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
    JSON.stringify(data.result || {}),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

async function listVideos(req: Request) {
  const url = new URL(req.url);
  const page = url.searchParams.get("page") || "1";
  const perPage = url.searchParams.get("per_page") || "20";

  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream?search=&page=${page}&per_page=${perPage}`,
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

// WebRTC WHIP (WebRTC HTTP Ingestion Protocol) for phone camera streaming
// Allows phones to push camera feed directly to Cloudflare Stream via WebRTC
async function whipOffer(params: any, req: Request) {
  const { input_id, sdp } = params;

  if (!input_id || !sdp) {
    throw new Error("input_id and sdp are required");
  }

  // Send SDP offer to Cloudflare's WHIP endpoint
  const whipUrl = `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/live_inputs/${input_id}/whip`;

  const response = await fetch(whipUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
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
async function deleteVideo(params: any) {
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
