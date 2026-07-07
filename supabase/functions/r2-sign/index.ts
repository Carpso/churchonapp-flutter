import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  S3Client,
  PutObjectCommand,
} from "npm:@aws-sdk/client-s3@3.600.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.600.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 405,
    });
  }

  const accessKey = Deno.env.get("R2_ACCESS_KEY_ID");
  const secretKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const endpoint = Deno.env.get("R2_ENDPOINT");
  const bucket = Deno.env.get("R2_BUCKET") ?? "choa-sermons-vault";
  const publicDomain =
    Deno.env.get("R2_PUBLIC_DOMAIN") ?? "media.churchonapp.com";

  if (!accessKey || !secretKey || !endpoint) {
    return new Response(
      JSON.stringify({
        error: "R2 credentials not configured on server",
        hint: "Set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, and R2_ENDPOINT secrets",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }

  const authHeader = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  let userId: string | null = null;
  if (authHeader) {
    try {
      const token = authHeader.replace("Bearer ", "");
      const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
        headers: { Authorization: `Bearer ${token}`, apikey: supabaseAnonKey },
      });
      if (response.ok) {
        const userData = await response.json();
        userId = userData.id;

        if (userId) {
          const supabase = createClient(supabaseUrl, supabaseServiceKey);
          const { allowed } = await checkRateLimit(supabase, userId, "r2_upload", 20, 1);
          if (!allowed) {
            return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
              status: 429,
            });
          }
        }
      }
    } catch {
      // Auth check failed, continue without user context
    }
  }

  let body: { filename?: string; contentType?: string; folder?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  if (!body.filename || !body.contentType || !body.folder) {
    return new Response(
      JSON.stringify({
        error: "Missing required fields: filename, contentType, folder",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  const allowedTypes = [
    "image/jpeg", "image/png", "image/gif", "image/webp",
    "video/mp4", "video/quicktime", "video/webm",
    "application/pdf", "audio/mpeg", "audio/wav", "audio/ogg",
  ];
  if (!allowedTypes.includes(body.contentType)) {
    return new Response(
      JSON.stringify({ error: "File type not allowed", allowed: allowedTypes }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  if (body.folder === "kyc" && !userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required for KYC document uploads" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      }
    );
  }

  if (["kyc", "sermons", "profile"].includes(body.folder) && !userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required for this folder" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      }
    );
  }

  const key = body.folder + "/" + body.filename;
  const expiresIn = 3600;

  try {
    const s3Client = new S3Client({
      region: "auto",
      endpoint: endpoint,
      credentials: {
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
      },
      forcePathStyle: true,
    });

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: body.contentType,
    });

    const signedUrl = await getSignedUrl(s3Client, command, {
      expiresIn,
    });

    const publicUrl = `https://${publicDomain}/${key}`;

    return new Response(JSON.stringify({ signedUrl, publicUrl }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: "Failed to generate signed URL",
        detail: (error as Error).message,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
