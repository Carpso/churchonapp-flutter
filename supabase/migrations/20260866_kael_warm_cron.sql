-- Kael HuggingFace warm-up cron (pg_cron + pg_net must be enabled).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    -- Drop old job if it exists, then recreate (idempotent).
    BEGIN
      PERFORM cron.unschedule('kael-keep-warm');
    EXCEPTION WHEN OTHERS THEN
      NULL; -- job didn't exist yet
    END;
    PERFORM cron.schedule(
      'kael-keep-warm',
      '*/10 * * * *',
      'SELECT net.http_post(url := ''https://daboihiudmglwhdfvsku.supabase.co/functions/v1/hf-keep-warm'', headers := ''{"Content-Type":"application/json"}'', body := ''{"ping":true}'')'
    );
  END IF;
END;
$$;
