-- ═══════════════════════════════════════════════════════════════════════════════
-- AUTO-SETTLEMENT CRON + PHONE CONSOLIDATION
-- 1. Cron job to run lipila-settle every 5 min (auto-disburse to churches)
-- 2. pastor_phone column on churches (for tithe routing)
-- 3. SMS bundle pricing as platform_settings keys
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Auto-settlement cron: run lipila-settle every 5 minutes
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    BEGIN
      PERFORM cron.unschedule('lps-settle');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM cron.schedule(
      'lps-settle',
      '*/5 * * * *',
      'SELECT net.http_post(url := ''https://daboihiudmglwhdfvsku.supabase.co/functions/v1/lipila-settle'', headers := ''{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhYm9paGl1ZG1nbHdoZGZ2c2t1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MzY0ODgsImV4cCI6MjA5ODExMjQ4OH0.jG1-PyHH6Pa6R77M5h2uFpMsLihkxh3NSAzlX9UDA8Q","Content-Type":"application/json"'', body := ''{"action":"settle"}'')'
    );
  END IF;
END;
$$;

-- 2. Pastor phone column for tithe routing
ALTER TABLE public.churches
  ADD COLUMN IF NOT EXISTS pastor_phone TEXT,
  ADD COLUMN IF NOT EXISTS contact_phone TEXT;

-- Backfill pastor_phone from profiles where role = pastor/bishop
UPDATE public.churches c
SET pastor_phone = sub.phone_number
FROM (
  SELECT DISTINCT ON (p.tenant_id) p.tenant_id, p.phone_number
  FROM public.profiles p
  WHERE p.role IN ('pastor','bishop')
    AND p.phone_number IS NOT NULL
    AND p.tenant_id IS NOT NULL
    AND p.phone_number ~ '^\d{10,}$'
  ORDER BY p.tenant_id, p.created_at ASC
) sub
WHERE c.id::text = sub.tenant_id
  AND c.pastor_phone IS NULL;

-- Backfill treasurer_phone from contact_phone if null
UPDATE public.churches SET treasurer_phone = contact_phone
WHERE treasurer_phone IS NULL AND contact_phone IS NOT NULL;

-- 3. SMS bundle pricing as remote-config keys (COA editable)
INSERT INTO public.platform_settings (key, value)
VALUES
  ('sms_bundle_50_kwacha', '50'),
  ('sms_bundle_100_kwacha', '90'),
  ('sms_bundle_250_kwacha', '200'),
  ('sms_bundle_500_kwacha', '350'),
  ('sms_credit_cost_kwacha', '1'),
  ('sms_coa_cut_percent', '0.15')
ON CONFLICT (key) DO NOTHING;
