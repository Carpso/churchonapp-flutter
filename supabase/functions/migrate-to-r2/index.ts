import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  S3Client,
  PutObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  CopyObjectCommand,
} from "npm:@aws-sdk/client-s3@3.600.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.600.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

/**
 * migrate-to-r2 Edge Function
 *
 * Modes:
 *   - "list": Lists all files in a Supabase storage bucket (dry run audit)
 *   - "r2-list": Lists objects in an R2 bucket via S3 API
 *   - "migrate": Downloads files from Supabase Storage and uploads to R2
 *   - "update-urls": Updates bible_audio_files records to point to R2 URLs
 *   - "copy-bucket": Copies objects between two R2 buckets (for consolidation)
 *   - "r2-delete-bucket": Lists all objects in an R2 bucket for cleanup
 *
 * Body:
 *   { mode: string, bucket?: string, prefix?: string, limit?: number,
 *     sourceBucket?: string, destPrefix?: string }
 */
serve(async (req: Request) => {
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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization header" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabaseAuth = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const accessKey = Deno.env.get("R2_ACCESS_KEY_ID");
  const secretKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const endpoint = Deno.env.get("R2_ENDPOINT");
  const bucket = Deno.env.get("R2_BUCKET") ?? "choa-sermons-vault";
  const publicDomain =
    Deno.env.get("R2_PUBLIC_DOMAIN") ?? "media.churchonapp.com";

  if (!accessKey || !secretKey || !endpoint) {
    return new Response(
      JSON.stringify({
        error: "R2 credentials not configured",
        hint: "Set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, and R2_ENDPOINT secrets",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }

  let body: { mode?: string; bucket?: string; prefix?: string; limit?: number; sourceBucket?: string; destPrefix?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }

  const mode = body.mode ?? "list";
  const storageBucket = body.bucket ?? "sermons-vault";
  const prefix = body.prefix ?? "";
  const limit = body.limit ?? 100;
  const sourceBucket = body.sourceBucket ?? "";
  const destPrefix = body.destPrefix ?? "";

  const s3Client = new S3Client({
    region: "auto",
    endpoint: endpoint,
    credentials: {
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
    },
    forcePathStyle: true,
  });

  try {
    if (mode === "r2-list") {
      // List objects directly in the R2 bucket via S3 API
      const listCommand = new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefix || undefined,
        MaxKeys: limit,
      });
      const response = await s3Client.send(listCommand);
      const contents = response.Contents ?? [];
      const fileList = contents.map((obj) => ({
        key: obj.Key ?? "",
        size: obj.Size ?? 0,
        sizeHuman: formatBytes(obj.Size ?? 0),
        lastModified: obj.LastModified?.toISOString() ?? "",
      }));
      return new Response(
        JSON.stringify({
          bucket,
          prefix: prefix || "(root)",
          isTruncated: response.IsTruncated ?? false,
          nextContinuationToken: response.NextContinuationToken ?? null,
          totalFiles: fileList.length,
          totalSize: contents.reduce((sum: number, obj: any) => sum + (obj.Size ?? 0), 0),
          totalSizeHuman: formatBytes(contents.reduce((sum: number, obj: any) => sum + (obj.Size ?? 0), 0)),
          files: fileList,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    if (mode === "list") {
      // List files recursively in Supabase Storage bucket
      let filesList: Array<{ name: string; path: string; size: number; contentType: string }> = [];
      try {
        filesList = await listAllFilesRecursive(supabase, storageBucket, prefix);
      } catch (err) {
        return new Response(
          JSON.stringify({ error: "Failed to list recursive files", detail: (err as Error).message }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
        );
      }

      const fileList = filesList.map((f) => ({
        name: f.name,
        size: f.size,
        contentType: f.contentType,
        path: f.path,
        r2Url: `https://${publicDomain}/${f.path}`,
      }));

      return new Response(
        JSON.stringify({
          bucket: storageBucket,
          prefix: prefix || "(root)",
          totalFiles: fileList.length,
          files: fileList,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    if (mode === "migrate") {
      // List and migrate files recursively from Supabase Storage to R2
      let filesList: Array<{ name: string; path: string; size: number; contentType: string }> = [];
      try {
        filesList = await listAllFilesRecursive(supabase, storageBucket, prefix);
      } catch (err) {
        return new Response(
          JSON.stringify({ error: "Failed to list recursive files", detail: (err as Error).message }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
        );
      }

      const slicedFilesList = filesList.slice(0, limit);

      const results: Array<{
        path: string;
        status: string;
        r2Url?: string;
        error?: string;
        size?: number;
      }> = [];

      for (const file of slicedFilesList) {
        const filePath = file.path;

        try {
          // Download from Supabase Storage
          const { data: fileData, error: downloadError } = await supabase.storage
            .from(storageBucket)
            .download(filePath);

          if (downloadError) {
            results.push({ path: filePath, status: "download_failed", error: downloadError.message });
            continue;
          }

          const arrayBuffer = await fileData.arrayBuffer();
          const uint8Array = new Uint8Array(arrayBuffer);

          // Check if file already exists in R2
          let alreadyExists = false;
          try {
            await s3Client.send(
              new HeadObjectCommand({ Bucket: bucket, Key: filePath })
            );
            alreadyExists = true;
          } catch {
            // File doesn't exist in R2, proceed with upload
          }

          if (alreadyExists) {
            results.push({
              path: filePath,
              status: "already_exists",
              r2Url: `https://${publicDomain}/${filePath}`,
              size: uint8Array.length,
            });
            continue;
          }

          // Upload to R2
          const contentType = file.contentType ?? "application/octet-stream";
          await s3Client.send(
            new PutObjectCommand({
              Bucket: bucket,
              Key: filePath,
              Body: uint8Array,
              ContentType: contentType,
            })
          );

          results.push({
            path: filePath,
            status: "migrated",
            r2Url: `https://${publicDomain}/${filePath}`,
            size: uint8Array.length,
          });
        } catch (e) {
          results.push({ path: filePath, status: "error", error: (e as Error).message });
        }
      }

      const migrated = results.filter((r) => r.status === "migrated").length;
      const skipped = results.filter((r) => r.status === "already_exists").length;
      const failed = results.filter((r) => r.status === "error" || r.status === "download_failed").length;

      return new Response(
        JSON.stringify({
          bucket: storageBucket,
          prefix: prefix || "(root)",
          summary: { total: results.length, migrated, skipped, failed },
          results,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    if (mode === "update-urls") {
      const summary: Record<string, { total: number; updated: number }> = {};
      const detailLog: Array<{ table: string; id: string; field: string; from: string; to: string }> = [];

      // Helper function to update a text field in a table if it contains a Supabase URL
      const syncTableUrls = async (
        tableName: string,
        fields: string[]
      ) => {
        let total = 0;
        let updated = 0;

        // Fetch all rows
        const { data: rows, error } = await supabase.from(tableName).select(`id, ${fields.join(", ")}`);
        if (error) {
          console.error(`Error fetching from ${tableName}:`, error.message);
          return;
        }

        for (const row of rows || []) {
          const updatePayload: Record<string, string | null> = {};
          let needsUpdate = false;

          for (const field of fields) {
            const val = row[field];
            if (val && typeof val === "string") {
              const newVal = replaceSupabaseUrl(val, publicDomain);
              if (newVal !== val) {
                updatePayload[field] = newVal;
                needsUpdate = true;
                detailLog.push({
                  table: tableName,
                  id: row.id,
                  field,
                  from: val,
                  to: newVal ?? "",
                });
              }
            }
          }

          if (needsUpdate) {
            const { error: updateError } = await supabase
              .from(tableName)
              .update(updatePayload)
              .eq("id", row.id);
            if (!updateError) {
              updated++;
            } else {
              console.error(`Failed to update ${tableName} row ${row.id}:`, updateError.message);
            }
          }
          total++;
        }

        summary[tableName] = { total, updated };
      };

      // 1. Sync sermons (video_url, thumbnail_url)
      await syncTableUrls("sermons", ["video_url", "thumbnail_url"]);

      // 2. Sync marketplace_items (image)
      await syncTableUrls("marketplace_items", ["image"]);

      // 3. Sync profiles (avatar_url)
      await syncTableUrls("profiles", ["avatar_url"]);

      // 4. Sync kyc_documents (url)
      await syncTableUrls("kyc_documents", ["url"]);

      // 5. Sync testimonies (image_url)
      await syncTableUrls("testimonies", ["image_url"]);

      // 6. Sync news (image_url)
      await syncTableUrls("news", ["image_url"]);

      // 7. Sync kingdom_news (image_url)
      await syncTableUrls("kingdom_news", ["image_url"]);

      // 8. Legacy bible_audio_files provider sync
      const { data: baf, error: bafError } = await supabase
        .from("bible_audio_files")
        .select("id, storage_path, storage_provider")
        .eq("storage_provider", "supabase");

      if (!bafError && baf) {
        let updated = 0;
        for (const record of baf) {
          const r2Url = `https://${publicDomain}/${record.storage_path}`;
          const { error: updateError } = await supabase
            .from("bible_audio_files")
            .update({
              storage_provider: "r2",
              storage_bucket: bucket,
            })
            .eq("id", record.id);

          if (!updateError) {
            updated++;
            detailLog.push({
              table: "bible_audio_files",
              id: record.id,
              field: "storage_provider",
              from: "supabase",
              to: "r2",
            });
          }
        }
        summary["bible_audio_files"] = { total: baf.length, updated };
      }

      return new Response(
        JSON.stringify({
          summary,
          detailLog,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    if (mode === "copy-bucket") {
      // Copy objects from one R2 bucket to another (or same bucket with prefix)
      if (!sourceBucket) {
        return new Response(
          JSON.stringify({ error: "sourceBucket is required for copy-bucket mode" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
      }

      const sourceS3 = new S3Client({
        region: "auto",
        endpoint: endpoint,
        credentials: { accessKeyId: accessKey, secretAccessKey: secretKey },
        forcePathStyle: true,
      });

      const destS3 = new S3Client({
        region: "auto",
        endpoint: endpoint,
        credentials: { accessKeyId: accessKey, secretAccessKey: secretKey },
        forcePathStyle: true,
      });

      // List all objects in source bucket
      let continuationToken: string | undefined;
      const allKeys: string[] = [];

      do {
        const listCmd = new ListObjectsV2Command({
          Bucket: sourceBucket,
          Prefix: prefix || undefined,
          MaxKeys: 1000,
          ContinuationToken: continuationToken,
        });
        const listResp = await sourceS3.send(listCmd);
        for (const obj of listResp.Contents ?? []) {
          if (obj.Key) allKeys.push(obj.Key);
        }
        continuationToken = listResp.NextContinuationToken;
      } while (continuationToken);

      const results: Array<{ key: string; status: string; error?: string }> = [];

      for (const key of allKeys) {
        try {
          // Build destination key
          const destKey = destPrefix
            ? `${destPrefix}/${key.replace(prefix ? prefix + "/" : "", "")}`
            : key;

          // Check if already exists
          try {
            await destS3.send(new HeadObjectCommand({ Bucket: bucket, Key: destKey }));
            results.push({ key, status: "already_exists" });
            continue;
          } catch {
            // Doesn't exist, proceed with copy
          }

          // Copy via S3 CopyObject
          await destS3.send(
            new CopyObjectCommand({
              Bucket: bucket,
              CopySource: `${sourceBucket}/${key}`,
              Key: destKey,
            })
          );
          results.push({ key, status: "copied", error: destKey });
        } catch (e) {
          results.push({ key, status: "error", error: (e as Error).message });
        }
      }

      const copied = results.filter((r) => r.status === "copied").length;
      const skipped = results.filter((r) => r.status === "already_exists").length;
      const failed = results.filter((r) => r.status === "error").length;

      return new Response(
        JSON.stringify({
          sourceBucket,
          destBucket: bucket,
          destPrefix: destPrefix || "(root)",
          summary: { total: results.length, copied, skipped, failed },
          results,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    return new Response(
      JSON.stringify({ error: `Unknown mode: ${mode}. Use "list", "r2-list", "migrate", "update-urls", or "copy-bucket".` }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: "Migration failed", detail: (error as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}

async function listAllFilesRecursive(
  supabase: any,
  bucket: string,
  prefix: string = ""
): Promise<Array<{ name: string; path: string; size: number; contentType: string }>> {
  const allFiles: Array<{ name: string; path: string; size: number; contentType: string }> = [];

  async function traverse(currentPrefix: string) {
    const { data, error } = await supabase.storage
      .from(bucket)
      .list(currentPrefix || undefined, {
        limit: 1000,
        sortBy: { column: "name", order: "asc" },
      });

    if (error) {
      console.error(`Error listing folder ${currentPrefix}:`, error.message);
      throw error;
    }

    for (const item of data || []) {
      const itemPath = currentPrefix ? `${currentPrefix}/${item.name}` : item.name;
      // Folders do not have an ID or metadata
      if (!item.id || !item.metadata) {
        await traverse(itemPath);
      } else {
        allFiles.push({
          name: item.name,
          path: itemPath,
          size: item.metadata.size ?? 0,
          contentType: item.metadata.mimetype ?? "application/octet-stream",
        });
      }
    }
  }

  await traverse(prefix);
  return allFiles;
}

function replaceSupabaseUrl(url: string | null, publicDomain: string): string | null {
  if (!url) return null;
  // Match standard Supabase storage URLs:
  // e.g. https://[ref].supabase.co/storage/v1/object/public/[bucket]/[path]
  // or https://supabase.churchonapp.com/storage/v1/object/public/[bucket]/[path]
  const pattern = /https:\/\/[^\/]+\/storage\/v1\/object\/public\/[^\/]+\/(.+)/;
  const match = url.match(pattern);
  if (match) {
    return `https://${publicDomain}/${match[1]}`;
  }
  return url;
}
