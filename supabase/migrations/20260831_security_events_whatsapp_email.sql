-- ═══════════════════════════════════════════════════════════════
-- Security Events table + audit triggers + WhatsApp config
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Security Events ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.security_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'info',
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  details JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_events_type ON public.security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON public.security_events(severity);
CREATE INDEX IF NOT EXISTS idx_security_events_user ON public.security_events(user_id);
CREATE INDEX IF NOT EXISTS idx_security_events_created ON public.security_events(created_at);

ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "security_events_admin_all" ON public.security_events
  FOR ALL USING (
    auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
    OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  );

CREATE POLICY "security_events_insert_auth" ON public.security_events
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── 2. WhatsApp Configuration (superadmin-managed) ─────────
CREATE TABLE IF NOT EXISTS public.whatsapp_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled BOOLEAN DEFAULT false,
  phone_number_id TEXT,
  access_token TEXT,
  business_account_id TEXT,
  verify_token TEXT,
  webhook_url TEXT,
  app_id TEXT,
  last_updated TIMESTAMPTZ DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id)
);

ALTER TABLE public.whatsapp_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "whatsapp_config_superadmin_all" ON public.whatsapp_config
  FOR ALL USING (
    auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
  );

CREATE POLICY "whatsapp_config_read_auth" ON public.whatsapp_config
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Seed default config
INSERT INTO public.whatsapp_config (is_enabled) VALUES (false) ON CONFLICT DO NOTHING;

-- ── 3. WhatsApp Templates ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_name TEXT NOT NULL UNIQUE,
  language_code TEXT DEFAULT 'en',
  category TEXT NOT NULL DEFAULT 'utility',
  components JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "whatsapp_templates_superadmin_all" ON public.whatsapp_templates
  FOR ALL USING (
    auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
  );

-- ── 4. Email Logs ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.email_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  email_type TEXT NOT NULL,
  status TEXT DEFAULT 'sent',
  resend_id TEXT,
  error_message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_logs_type ON public.email_logs(email_type);
CREATE INDEX IF NOT EXISTS idx_email_logs_status ON public.email_logs(status);

ALTER TABLE public.email_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "email_logs_admin_read" ON public.email_logs
  FOR SELECT USING (
    auth.jwt() -> 'app_metadata' -> 'role' ? 'superadmin'
    OR auth.jwt() -> 'app_metadata' -> 'role' ? 'coa_employee'
  );

-- ── 5. Verify ──────────────────────────────────────────────
SELECT 'security_events_created' AS check, COUNT(*) FROM public.security_events;
SELECT 'whatsapp_config_created' AS check, COUNT(*) FROM public.whatsapp_config;
SELECT 'email_logs_created' AS check, COUNT(*) FROM public.email_logs;
