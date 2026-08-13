-- 20260887_support_disputes_errors.sql
-- Dedicated support tickets (previously mixed into the event `tickets` table),
-- dispute handling, app error reporting, and the COA resolution workflow.

-- ── 1. SUPPORT TICKETS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'resolved', 'closed')),
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  responder_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "support_tickets_select" ON public.support_tickets FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "support_tickets_insert" ON public.support_tickets FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "support_tickets_update" ON public.support_tickets FOR UPDATE USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_support_tickets_user ON public.support_tickets(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets(status);

-- Migrate support rows that were wrongly written into the event `tickets` table.
INSERT INTO public.support_tickets (user_id, subject, description, priority, status, tenant_id, created_at)
SELECT user_id, subject, description,
       COALESCE(priority, 'medium'),
       CASE WHEN status IN ('open', 'in_review', 'resolved', 'closed') THEN status ELSE 'open' END,
       tenant_id,
       COALESCE(created_at, now())
FROM public.tickets
WHERE subject IS NOT NULL AND description IS NOT NULL
ON CONFLICT DO NOTHING;

-- ── 2. DISPUTES ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.support_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL,
  dispute_type TEXT NOT NULL CHECK (dispute_type IN ('ride', 'delivery', 'marketplace', 'giving', 'payment', 'subscription', 'other')),
  reference_id TEXT,
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  evidence_urls JSONB DEFAULT '[]'::jsonb,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'under_review', 'resolved', 'rejected')),
  priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  responder_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

ALTER TABLE public.support_disputes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "support_disputes_select" ON public.support_disputes FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "support_disputes_insert" ON public.support_disputes FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "support_disputes_update" ON public.support_disputes FOR UPDATE USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_support_disputes_user ON public.support_disputes(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_disputes_status ON public.support_disputes(status);

-- ── 3. APP ERROR REPORTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_error_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  screen TEXT,
  error_message TEXT NOT NULL,
  stack_trace TEXT,
  app_version TEXT,
  device_info TEXT,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'resolved')),
  responder_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

ALTER TABLE public.app_error_reports ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "app_error_reports_select" ON public.app_error_reports FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "app_error_reports_insert" ON public.app_error_reports FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "app_error_reports_update" ON public.app_error_reports FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'coa_employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_app_error_reports_user ON public.app_error_reports(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_error_reports_status ON public.app_error_reports(status);
