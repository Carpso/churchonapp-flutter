-- 20261234: repair the dead `lps-settle` cron job.
--
-- WHAT IS BROKEN
-- The scheduled command for job `lps-settle` (jobid 6) stores its SQL with
-- DOUBLED quotes around every JSON key/value:
--   net.http_post(url := '...', headers := '{""x-cron-secret"":""...""}', ...)
-- pg_net therefore fails to parse the headers value:
--   ERROR: invalid input syntax for type json
--   DETAIL: Token "x" is invalid.
-- Every run of `lps-settle` has failed since it was scheduled (verified live in
-- cron.job_run_details: all runs status=failed), so `processPendingSettlements`
-- never executed and EVERY payout_tasks row stayed `pending` forever.
--
-- FIX
-- Rebuild the command with correctly-quoted JSON. The cron secret is read from
-- Supabase Vault (never from this repo) with a fallback that scrapes the intact
-- secret out of the existing broken job command before dropping it.
--
-- pg_net signature on this project:
--   net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout int)
-- `headers`/`body` are jsonb, and format() returns text, so explicit ::jsonb
-- casts are required (text does not implicitly coerce to jsonb).
--
-- Idempotent: re-running only replaces the job with an equivalent one.

DO $$
DECLARE
  v_secret text;
  v_cmd    text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'lps-settle repair skipped: pg_cron not installed';
    RETURN;
  END IF;

  -- 1. Secret from the private helper (20261145) or directly from the Vault.
  BEGIN
    IF to_regprocedure('private.get_cron_secret()') IS NOT NULL THEN
      EXECUTE 'SELECT private.get_cron_secret()' INTO v_secret;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_secret := NULL;
  END;

  IF v_secret IS NULL THEN
    BEGIN
      SELECT decrypted_secret INTO v_secret
        FROM vault.decrypted_secrets
       WHERE name = 'cron_secret'
       ORDER BY created_at DESC
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_secret := NULL;
    END;
  END IF;

  -- 2. Fallback: the secret value itself is intact inside the broken command.
  IF v_secret IS NULL THEN
    SELECT substring(command FROM 'x-cron-secret[^0-9a-zA-Z]*([0-9a-zA-Z]{16,})')
      INTO v_secret
      FROM cron.job
     WHERE command LIKE '%lipila-settle%'
       AND command LIKE '%x-cron-secret%'
     LIMIT 1;
  END IF;

  IF v_secret IS NULL THEN
    RAISE WARNING 'lps-settle repair aborted: cron secret not found (Vault empty and no existing job to scrape)';
    RETURN;
  END IF;

  -- 3. Rebuild the command with valid JSON.
  v_cmd := format(
    $cmd$SELECT net.http_post(url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/lipila-settle', headers := %L::jsonb, body := '{"action":"settle"}'::jsonb)$cmd$,
    jsonb_build_object(
      'x-cron-secret', v_secret,
      'Content-Type',  'application/json'
    )::text
  );

  -- 4. Replace the broken job (same name/schedule, fixed SQL).
  BEGIN
    PERFORM cron.unschedule('lps-settle');
  EXCEPTION WHEN OTHERS THEN
    NULL; -- no existing job (first run on a fresh environment)
  END;

  PERFORM cron.schedule('lps-settle', '*/5 * * * *', v_cmd);

  RAISE NOTICE 'lps-settle rescheduled with valid headers jsonb';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'lps-settle repair failed: %', SQLERRM;
END $$;
