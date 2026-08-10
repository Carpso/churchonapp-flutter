-- Inter-tenant events: allow events to be visible across connected churches.
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS is_inter_tenant BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS organizer_momo_phone TEXT,
  ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_events_inter_tenant ON public.events(tenant_id, is_inter_tenant, date);
CREATE INDEX IF NOT EXISTS idx_events_date ON public.events(date) WHERE date IS NOT NULL;

-- Event reminders: cron that pushes notification 24h before events
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    BEGIN PERFORM cron.unschedule('event-remind'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM cron.schedule(
      'event-remind',
      '0 */6 * * *',
      'SELECT net.http_post(url := ''https://daboihiudmglwhdfvsku.supabase.co/functions/v1/push-notifications'', headers := ''{"Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhYm9paGl1ZG1nbHdoZGZ2c2t1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MzY0ODgsImV4cCI6MjA5ODExMjQ4OH0.jG1-PyHH6Pa6R77M5h2uFpMsLihkxh3NSAzlX9UDA8Q","Content-Type":"application/json"'', body := ''{"action":"event_reminder"}'')'
    );
  END IF;
END;
$$;
