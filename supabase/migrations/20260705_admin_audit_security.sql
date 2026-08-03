-- 1. Admin Audit Log Table
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    admin_email TEXT,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    details JSONB DEFAULT '{}',
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Superadmins and employees can view audit logs" ON public.admin_audit_log;
CREATE POLICY "Superadmins and employees can view audit logs"
    ON public.admin_audit_log FOR SELECT
    USING (
        auth.jwt() ->> 'role' IN ('superadmin', 'employee')
    );

DROP POLICY IF EXISTS "Service can insert audit logs" ON public.admin_audit_log;
CREATE POLICY "Service can insert audit logs"
    ON public.admin_audit_log FOR INSERT
    WITH CHECK (auth.uid() = admin_id);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_id ON public.admin_audit_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_entity ON public.admin_audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_created_at ON public.admin_audit_log(created_at DESC);

-- Enable Realtime for admin_audit_log
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'admin_audit_log'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE admin_audit_log;
  END IF;
END $$;

-- 2. Fix RLS on platform_settings — only superadmin/employee can modify
DROP POLICY IF EXISTS "Admins can update platform settings" ON public.platform_settings;
DROP POLICY IF EXISTS "Superadmin employees can update platform settings" ON public.platform_settings;
CREATE POLICY "Superadmin employees can update platform settings"
    ON public.platform_settings FOR ALL
    USING (
        auth.jwt() ->> 'role' IN ('superadmin', 'employee')
    );

-- 3. Fix RLS on radio_stations — only superadmin/employee can modify
DROP POLICY IF EXISTS "Admins can manage radio stations" ON public.radio_stations;
DROP POLICY IF EXISTS "Superadmin employees can manage radio stations" ON public.radio_stations;
CREATE POLICY "Superadmin employees can manage radio stations"
    ON public.radio_stations FOR ALL
    USING (
        auth.jwt() ->> 'role' IN ('superadmin', 'employee')
    );

-- 4. Enable RLS on transactions and wallet_transactions
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own transactions" ON public.transactions;
CREATE POLICY "Users can view own transactions"
    ON public.transactions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own wallet transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own wallet transactions"
    ON public.wallet_transactions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert transactions" ON public.transactions;
CREATE POLICY "System can insert transactions"
    ON public.transactions FOR INSERT
    WITH CHECK (true);

DROP POLICY IF EXISTS "System can insert wallet transactions" ON public.wallet_transactions;
CREATE POLICY "System can insert wallet transactions"
    ON public.wallet_transactions FOR INSERT
    WITH CHECK (true);

-- 5. Fix service_reports — tenant-scoped access
DROP POLICY IF EXISTS "Anyone can view service reports" ON public.service_reports;
DROP POLICY IF EXISTS "Tenant members can view service reports" ON public.service_reports;
CREATE POLICY "Tenant members can view service reports"
    ON public.service_reports FOR SELECT
    USING (
        tenant_id IS NULL OR
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND tenant_id = service_reports.tenant_id::text
        )
    );

DROP POLICY IF EXISTS "Anyone can insert service reports" ON public.service_reports;
DROP POLICY IF EXISTS "Authenticated users can insert service reports" ON public.service_reports;
CREATE POLICY "Authenticated users can insert service reports"
    ON public.service_reports FOR INSERT
    WITH CHECK (auth.uid() = reporter_id);

-- 6. Add is_verified column to profiles if not exists
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'unverified';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id);
