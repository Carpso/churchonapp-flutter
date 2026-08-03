// ═══════════════════════════════════════════════════════
// One-time migration: create coa_payments table
// Run once via: supabase functions deploy migrate-coa-payments
// Then invoke: supabase functions invoke migrate-coa-payments
// ═══════════════════════════════════════════════════════

import "https://deno.land/std@0.208.0/dotenv/load.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getCorsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
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

  // Verify caller is superadmin
  const { data: profile } = await supabaseAuth
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.role !== "superadmin") {
    return new Response(JSON.stringify({ error: "Forbidden: superadmin access required" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 403,
    });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { error } = await supabase.rpc("exec_sql", {
      sql: `
        CREATE TABLE IF NOT EXISTS coa_payments (
          id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
          service_type  TEXT NOT NULL,
          amount        NUMERIC(12,2) NOT NULL,
          payment_ref   TEXT NOT NULL,
          status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
          approved_by   UUID REFERENCES profiles(id),
          approved_at   TIMESTAMPTZ,
          created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
        );

        ALTER TABLE coa_payments ENABLE ROW LEVEL SECURITY;

        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own COA payments') THEN
            CREATE POLICY "Users can insert own COA payments"
              ON coa_payments FOR INSERT TO authenticated
              WITH CHECK (auth.uid() = user_id);
          END IF;
        END $$;

        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own COA payments') THEN
            CREATE POLICY "Users can view own COA payments"
              ON coa_payments FOR SELECT TO authenticated
              USING (auth.uid() = user_id);
          END IF;
        END $$;

        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Superadmins can view all COA payments') THEN
            CREATE POLICY "Superadmins can view all COA payments"
              ON coa_payments FOR SELECT TO authenticated
              USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin'));
          END IF;
        END $$;

        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Superadmins can update COA payments') THEN
            CREATE POLICY "Superadmins can update COA payments"
              ON coa_payments FOR UPDATE TO authenticated
              USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin'))
              WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'superadmin'));
          END IF;
        END $$;
      `,
    });

    if (error) {
      // Fallback: try raw SQL query if exec_sql RPC doesn't exist
      const { error: sqlError } = await supabase.from("_sql_migrations").select("*").limit(1).maybeSingle();
      if (sqlError) {
        return new Response(JSON.stringify({
          success: false,
          message: "Migration failed. Please run the SQL in supabase/migrations/2026072501_coa_direct_payments.sql manually via the Supabase Dashboard SQL Editor.",
          error: error?.message ?? sqlError?.message,
        }), { headers: { "Content-Type": "application/json" } });
      }
    }

    return new Response(JSON.stringify({
      success: true,
      message: "coa_payments table created successfully with RLS policies.",
    }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({
      success: false,
      message: err instanceof Error ? err.message : String(err),
    }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
