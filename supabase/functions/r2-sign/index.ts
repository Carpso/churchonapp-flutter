import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from "npm:@aws-sdk/client-s3@3.600.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.600.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate-limit.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));
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
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const token = authHeader.replace("Bearer ", "");
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const userId = user.id;

  const supabase = createClient(supabaseUrl, supabaseServiceKey);
  const { allowed } = await checkRateLimit(supabase, userId, "r2_upload", 20, 1);
  if (!allowed) {
    return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 429,
    });
  }

  let body: { action?: string; filename?: string; contentType?: string; folder?: string; key?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  body.action ??= "upload";

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

  // P2-30: Restrict path traversal and enforce user-scoped folders
  if (body.filename && body.filename.includes("..")) {
    return new Response(
      JSON.stringify({ error: "Path traversal not allowed in filename" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  }

  // User-scoped folders: only the user's own subfolder is allowed
  const userScopedFolders = ["profile", "driver-documents", "kyc"];
  if (body.action !== "read" && body.action !== "download" && userScopedFolders.includes(body.folder)) {
    const expectedPrefix = `${body.folder}/${userId}`;
    const requestedKey = `${body.folder}/${body.filename}`;
    if (!requestedKey.startsWith(expectedPrefix)) {
      return new Response(
        JSON.stringify({ error: `Can only upload to your own ${body.folder} folder (${expectedPrefix}/...)` }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 403 }
      );
    }
  }

  if (body.action === "read" || body.action === "download") {
    if (!body.key) {
      return new Response(
        JSON.stringify({ error: "Missing required field: key" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 400,
        }
      );
    }
  } else {
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
  }

  const key = body.action === "read" || body.action === "download"
    ? body.key!
    : body.folder + "/" + body.filename;
  const expiresIn = body.action === "download" ? 86400 : 3600;

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

    const command = body.action === "read" || body.action === "download"
      ? new GetObjectCommand({ Bucket: bucket, Key: key })
      : new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: body.contentType! });

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
