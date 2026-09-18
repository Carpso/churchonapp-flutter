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

  let body: { action?: string; filename?: string; contentType?: string; folder?: string; key?: string; bucket?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  // Reads just mint a presigned URL (no storage cost/burn); give them a far
  // higher limit than uploads so cold feed loads of many images don't 429.
  // The client caches resolved URLs, so this is a safety cap, not a workload.
  const isRead = body.action === "read" || body.action === "download";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);
  const { allowed } = isRead
    ? await checkRateLimit(supabase, userId, "r2_read", 300, 1)
    : await checkRateLimit(supabase, userId, "r2_upload", 20, 1);
  if (!allowed) {
    return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again later." }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 429,
    });
  }

  body.action ??= "upload";

  // SECURITY: the media bucket (R2_BUCKET / choa-sermons-vault) is PUBLIC
  // (media.churchonapp.com). Sensitive material must never land there. Callers
  // may target the PRIVATE KYC bucket instead; any other bucket is rejected.
  const PRIVATE_BUCKETS = ["choa-kyc-vault"];
  const SERVICE_BUCKETS = ["choa-sermons-vault", "choa-kyc-vault"];
  if (body.bucket && !SERVICE_BUCKETS.includes(body.bucket)) {
    return new Response(
      JSON.stringify({ error: "Bucket not allowed" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  }
  const targetBucket = body.bucket ?? bucket;
  const isPrivateBucket = PRIVATE_BUCKETS.includes(targetBucket);

  // Must stay in sync with R2Service._allowedExtensions on the client, or
  // legitimate uploads fail with 400 "File type not allowed" (this previously
  // broke KYC docs + chat attachments, which use application/octet-stream).
  const allowedTypes = [
    // images
    "image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp",
    "image/heic", "image/heif",
    // video
    "video/mp4", "video/quicktime", "video/webm",
    "video/x-msvideo", "video/x-matroska",
    // audio
    "audio/mpeg", "audio/wav", "audio/ogg", "audio/aac",
    "audio/mp4", "audio/x-m4a", "audio/webm",
    // documents
    "application/pdf", "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    // plain-text documents (quiz question papers, CSV imports)
    "text/plain", "text/csv", "text/markdown",
    // encrypted KYC blobs + unknown-but-authenticated binaries. Uploads are
    // already gated by auth + the folder allowlist below, so this is safe.
    "application/octet-stream",
  ];
  const isReadAction = body.action === "read" || body.action === "download";
  if (!isReadAction && body.contentType && !allowedTypes.includes(body.contentType)) {
    return new Response(
      JSON.stringify({ error: "File type not allowed", allowed: allowedTypes }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }

  // Folder allowlist — every upload must land under a known prefix, so a bug
  // (or a bad key) can never scatter objects into an unexpected location.
  const allowedFolders = [
    "avatars", "products", "social", "chat", "klips", "kyc", "events",
    "marketplace", "sermons", "ventures", "flyers", "delivery-proof",
    "profile", "driver-documents", "churches", "church-logos",
    "church-banners", "church-website-logos", "church-website-banners",
    "special-offers", "audio", "quiz-questions", "stream-posters",
  ];
  if (!isReadAction && body.folder && !allowedFolders.includes(body.folder)) {
    return new Response(
      JSON.stringify({ error: "Folder not allowed", allowed: allowedFolders }),
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

  // User-scoped folders: only the user's own subfolder is allowed.
  //
  // EXCEPTION — reads from the PRIVATE KYC bucket: a user may read their own
  // documents, and COA staff / superadmins may read ANY user's (that is the
  // whole point of KYC verification for drivers and other verified users).
  const userScopedFolders = ["profile", "driver-documents", "kyc"];
  const requestedKey = body.action === "read" || body.action === "download"
    ? (body.key ?? "")
    : `${body.folder}/${body.filename ?? ""}`;
  const scopedFolder = userScopedFolders.find((f) => requestedKey.startsWith(`${f}/`));
  if (scopedFolder) {
    const expectedPrefix = `${scopedFolder}/${userId}`;
    if (!requestedKey.startsWith(expectedPrefix)) {
      const reviewerRead = isReadAction && isPrivateBucket && scopedFolder === "kyc";
      let allowed = false;
      if (reviewerRead) {
        const { data: prof } = await supabaseAuth
          .from("profiles")
          .select("role")
          .eq("id", userId)
          .maybeSingle();
        allowed = ["superadmin", "coa_employee"].includes(prof?.role ?? "");
      }
      if (!allowed) {
        return new Response(
          JSON.stringify({ error: `Can only access your own ${scopedFolder} folder (${expectedPrefix}/...)` }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 403 }
        );
      }
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
      ? new GetObjectCommand({ Bucket: targetBucket, Key: key })
      : new PutObjectCommand({ Bucket: targetBucket, Key: key, ContentType: body.contentType! });

    const signedUrl = await getSignedUrl(s3Client, command, {
      expiresIn,
    });

    // Private buckets have no public URL — return an `r2://` reference instead
    // so the client never stores a (non-working) public link for KYC files.
    const publicUrl = isPrivateBucket
      ? `r2://${targetBucket}/${key}`
      : `https://${publicDomain}/${key}`;

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
