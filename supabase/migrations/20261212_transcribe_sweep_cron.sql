-- ============================================================================
-- 20261212_transcribe_sweep_cron.sql
-- Schedules the Whisper transcription sweep (`transcribe-media?sweep=1`).
--
-- WHY: `transcribe-media` chunk-resumes long recordings from
-- `media_transcripts.chunk_index`, but a single invocation can hit the Edge
-- wall clock and leave a row `processing`. Nothing resumed those rows, so long
-- services never finished. The Edge Function already accepts the shared cron
-- secret on its sweep path (`x-cron-secret`, in addition to platform staff).
--
-- HOW: the established cron-secret pattern (see 20261145): the secret is read
-- from Supabase Vault via `private.get_cron_secret()` and posted through
-- pg_net. It is NEVER written into this repo / cron.job as a hardcoded JWT.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_transcribe_pending()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, private
AS $$
DECLARE
  v_secret  text := private.get_cron_secret();
  v_pending int := 0;
BEGIN
  IF v_secret IS NULL THEN
    RETURN 0;
  END IF;

  SELECT count(*) INTO v_pending
    FROM public.media_transcripts
   WHERE status = 'pending'
      OR (status = 'processing' AND updated_at < now() - interval '3 minutes');

  -- Nothing queued: don't wake the Edge Function.
  IF v_pending = 0 THEN
    RETURN 0;
  END IF;

  PERFORM net.http_post(
    url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/transcribe-media?sweep=1',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    body := jsonb_build_object('action', 'sweep')
  );

  RETURN v_pending;
EXCEPTION WHEN undefined_function OR undefined_table THEN
  RETURN 0; -- pg_net / vault unavailable
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_transcribe_pending() FROM anon;
REVOKE EXECUTE ON FUNCTION public.auto_transcribe_pending() FROM authenticated;

-- Schedule every 5 minutes (idempotent: unschedule first if it exists).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'transcribe-media-sweep') THEN
      PERFORM cron.unschedule('transcribe-media-sweep');
    END IF;
    PERFORM cron.schedule(
      'transcribe-media-sweep',
      '*/5 * * * *',
      $cron$SELECT public.auto_transcribe_pending();$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
