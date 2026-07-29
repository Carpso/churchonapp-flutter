-- Ensure service_reports table exists with ministry type support
CREATE TABLE IF NOT EXISTS public.service_reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL REFERENCES public.churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  attendance INTEGER DEFAULT 0,
  offering DECIMAL(12, 2) DEFAULT 0,
  testimony TEXT DEFAULT '',
  reporter_id UUID REFERENCES auth.users(id),
  type TEXT NOT NULL DEFAULT 'service' CHECK (type IN ('service', 'announcement', 'ministry', 'ledger_entry')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_service_reports_tenant_id ON public.service_reports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_service_reports_created_at ON public.service_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_reports_type ON public.service_reports(type);

-- RLS
ALTER TABLE public.service_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_reports_select" ON public.service_reports;
DO $$ BEGIN
  CREATE POLICY "service_reports_select" ON public.service_reports
    FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND (
          tenant_id::text = service_reports.tenant_id::text OR
          role IN ('superadmin', 'employee')
        )
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DROP POLICY IF EXISTS "service_reports_insert" ON public.service_reports;
DO $$ BEGIN
  CREATE POLICY "service_reports_insert" ON public.service_reports
    FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND tenant_id::text = service_reports.tenant_id::text
          AND role IN ('admin', 'pastor', 'bishop', 'apostle', 'superadmin', 'employee')
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DROP POLICY IF EXISTS "service_reports_update" ON public.service_reports;
DO $$ BEGIN
  CREATE POLICY "service_reports_update" ON public.service_reports
    FOR UPDATE USING (reporter_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DROP POLICY IF EXISTS "service_reports_delete" ON public.service_reports;
DO $$ BEGIN
  CREATE POLICY "service_reports_delete" ON public.service_reports
    FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND tenant_id::text = service_reports.tenant_id::text
          AND role IN ('admin', 'superadmin')
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
