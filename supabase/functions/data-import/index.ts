// Supabase Edge Function: data-import
// Enterprise-grade data import for Church On App.
// Supports CSV/JSON uploads, per-tenant column mapping presets, document
// extraction (via kael-ai), and 3rd-party ChMS imports (Breeze, Planning
// Center, Rock, FellowshipOne, mobile-money statements).
//
// Security model:
//  - Bearer JWT required + leadership role gate.
//  - Tenant ownership enforced: non-network leaders may only import into their
//    own tenant; superadmins/COA employees may target any tenant.
//  - Sensitive columns (role, coins, balances) are rejected by the server-side
//    sp_validate_import_columns RPC — never client-trusted.
//  - tenant_id is force-overwritten server-side to prevent tenant-hopping.
//  - All mutations go through the service-role client (privileged), because the
//    caller has already been authorized above.
//
// Deploy: supabase functions deploy data-import

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

const leadershipRoles = ["superadmin", "coa_employee", "bishop", "general_secretary", "pastor", "admin"];
const networkRoles = ["superadmin", "coa_employee"];

// Importable entities only. Anything else is rejected outright.
const allowedEntities = ["profiles", "transactions", "events", "ministries", "service_reports"];

// Entities whose rows carry a tenant_id scoping column (all of them today).
const tenantScoped = new Set(["profiles", "transactions", "events", "ministries", "service_reports"]);

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req.headers.get("Origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const ok = (body: any, status = 200) =>
    new Response(JSON.stringify(body), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status,
    });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return ok({ error: "Missing authorization header" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);
  if (authError || !user) return ok({ error: "Unauthorized" }, 401);

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role, tenant_id, organization_id")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || !profile) return ok({ error: "User profile not found" }, 403);
  if (!leadershipRoles.includes(profile.role)) {
    return ok({ error: `Insufficient role: ${profile.role}`, role: profile.role }, 403);
  }

  const selfTenant: string | null = profile.tenant_id ?? null;
  const isNetwork = networkRoles.includes(profile.role);

  // Non-network leaders are pinned to their own tenant; network leaders may
  // target any tenant (with explicit tenant_id) — otherwise default to own.
  function resolveTenant(requested: string | null): string | null {
    if (!requested) return selfTenant;
    if (isNetwork) return requested;
    return requested === selfTenant ? selfTenant : null;
  }

  try {
    const { action, ...params } = await req.json();

    switch (action) {
      case "import": {
        return await runImport(supabase, user.id, profile, selfTenant, isNetwork, resolveTenant, ok, params);
      }
      case "list_templates": {
        const entity = params?.entity_type ?? "profiles";
        if (!allowedEntities.includes(entity)) return ok({ error: "Invalid entity_type" }, 400);
        const tenantId = resolveTenant(params?.tenant_id ?? null);
        if (!tenantId) return ok({ error: "Cannot list templates for another tenant" }, 403);
        const { data, error } = await supabase
          .from("import_templates")
          .select("*")
          .eq("entity_type", entity)
          .eq("tenant_id", tenantId)
          .order("name");
        if (error) return ok({ error: error.message }, 500);
        return ok({ templates: data ?? [] });
      }
      case "save_template": {
        const { name, entity_type, system_name, mappings, conflict_on } = params;
        if (!name || !allowedEntities.includes(entity_type)) {
          return ok({ error: "name and valid entity_type are required" }, 400);
        }
        const tenantId = resolveTenant(params?.tenant_id ?? selfTenant) ?? selfTenant;
        if (params?.tenant_id && params.tenant_id !== selfTenant && !isNetwork) {
          return ok({ error: "Cannot save templates for another tenant" }, 403);
        }
        const { data, error } = await supabase.from("import_templates").upsert({
          tenant_id: tenantId,
          name,
          entity_type: entity_type,
          system_name,
          mappings: mappings ?? {},
          conflict_on,
          created_by: user.id,
        }).select().single();
        if (error) return ok({ error: error.message }, 500);
        return ok({ template: data });
      }
      case "extract_document": {
        return await extractDocument(supabase, user, params, ok);
      }
      default:
        return ok({ error: "Unknown action" }, 400);
    }
  } catch (error: any) {
    return ok({ error: error.message }, 500);
  }
});

async function runImport(
  supabase: any,
  userId: string,
  profile: any,
  selfTenant: string | null,
  isNetwork: boolean,
  resolveTenant: (t: string | null) => string | null,
  ok: (body: any, status?: number) => Response,
  params: any,
) {
  const entity = params?.entity_type;
  if (!allowedEntities.includes(entity)) {
    return ok({ error: `entity_type must be one of: ${allowedEntities.join(", ")}` }, 400);
  }

  const rows: any[] = Array.isArray(params?.rows) ? params.rows : [];
  if (rows.length === 0) return ok({ error: "rows is required and must be non-empty" }, 400);
  if (rows.length > 5000) {
    return ok({ error: "import exceeds 5000-row safety limit; split into batches" }, 400);
  }

  const targetTenant = isNetwork ? (params?.tenant_id ?? selfTenant) : selfTenant;
  if (!targetTenant) return ok({ error: "No tenant resolved for this import" }, 403);
  if (params?.tenant_id && params.tenant_id !== selfTenant && !isNetwork) {
    return ok({ error: "Cannot import into another tenant" }, 403);
  }

  const columns: string[] = Array.isArray(params?.columns) ? params.columns : [];
  if (columns.length === 0) return ok({ error: "columns is required" }, 400);

  // Server-side column validation (authoritative blocklist lives in the DB).
  const { data: validation, error: vErr } = await supabase.rpc("sp_validate_import_columns", {
    p_table: entity,
    p_columns: columns,
  });
  if (vErr) return ok({ error: `column validation failed: ${vErr.message}` }, 500);
  const invalid = (validation ?? []).filter((c: any) => c.valid === false);
  if (invalid.length > 0) return ok({ error: `invalid columns: ${JSON.stringify(invalid)}` }, 400);

  const mapping: Record<string, string> = params?.mapping ?? {};
  const conflictOn: string | null = params?.conflict_on ?? null;
  const fileName: string | null = params?.file_name ?? null;
  const sourceSystem: string | null = params?.source_system ?? null;

  // Audit log: create a data_imports row.
  const { data: importLog, error: logErr } = await supabase.from("data_imports").insert({
    tenant_id: targetTenant,
    entity_type: entity,
    source_system: sourceSystem,
    file_name: fileName,
    conflict_on: conflictOn,
    status: "processing",
    total_rows: rows.length,
    created_by: userId,
  }).select().single();
  if (logErr) return ok({ error: `failed to start import log: ${logErr.message}` }, 500);

  let importedRows = 0;
  let failedRows = 0;
  const errorBatches: any[] = [];

  for (let i = 0; i < rows.length; i++) {
    const src = rows[i];
    const target: Record<string, unknown> = {};
    for (const col of columns) {
      const srcKey = mapping[col] ?? col;
      if (Object.prototype.hasOwnProperty.call(src, srcKey)) {
        target[col] = src[srcKey];
      }
    }
    if (tenantScoped.has(entity)) {
      target.tenant_id = targetTenant;
    }

    try {
      const opts = conflictOn ? { onConflict: conflictOn } : undefined;
      const { error: upErr } = await supabase.from(entity).upsert(target, opts as any);
      if (upErr) throw upErr;
      importedRows++;
    } catch (e: any) {
      failedRows++;
      errorBatches.push({
        data_import_id: importLog.id,
        row_number: i + 1,
        payload: target,
        errors: [{ column: "_row", message: e.message }],
      });
    }
  }

  // Persist row-level errors (batched).
  if (errorBatches.length > 0) {
    await supabase.from("import_errors").insert(errorBatches);
  }

  const innerStatus = failedRows === 0 ? "completed" : (importedRows > 0 ? "completed" : "failed");
  await supabase.from("data_imports").update({
    imported_rows: importedRows,
    failed_rows: failedRows,
    status: innerStatus,
    completed_at: new Date().toISOString(),
  }).eq("id", importLog.id);

  return ok({
    import_id: importLog.id,
    entity_type: entity,
    total_rows: rows.length,
    imported: importedRows,
    failed: failedRows,
    status: innerStatus,
  });
}

// Document extraction via kael-ai. Accepts { file_url, text, entity_type }.
// Returns a JSON array of structured rows parsed from the document text.
async function extractDocument(supabase: any, user: any, params: any, ok: (body: any, status?: number) => Response) {
  const entity = params?.entity_type;
  if (!allowedEntities.includes(entity)) {
    return ok({ error: `entity_type must be one of: ${allowedEntities.join(", ")}` }, 400);
  }

  let text = params?.text ?? null;
  if (!text && params?.file_url) {
    const res = await fetch(params.file_url);
    if (!res.ok) return ok({ error: `could not fetch document: ${res.status}` }, 400);
    text = await res.text();
  }
  if (!text) return ok({ error: "text or file_url is required" }, 400);

  const prompt = params?.prompt ??
    `Extract the data in this document as a JSON array of objects matching the "${entity}" table columns. ` +
    `Only include rows that map cleanly. Return ONLY valid JSON, no markdown fences.`;

  const { data, error } = await supabase.functions.invoke("kael-ai", {
    body: { action: "summary", prompt, document: text, user_id: user.id },
  });
  if (error) return ok({ error: `document extraction failed: ${error.message}` }, 500);

  const responseText = typeof data?.response === "string" ? data.response : null;
  let rows: any[] = [];
  if (responseText) {
    try { rows = JSON.parse(responseText); } catch { rows = []; }
  }
  return ok({ entity_type: entity, rows });
}
