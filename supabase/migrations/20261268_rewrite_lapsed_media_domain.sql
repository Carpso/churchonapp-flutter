-- 20261268: Rewrite the LAPSED media domain in every stored media URL.
--
-- `media.churchonapp.com` (custom R2 domain) no longer resolves because the
-- `churchonapp.com` domain lapsed. The bucket's public dev URL
-- (`pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev`) serves the same objects
-- (verified 200 + CORS). Rows that still store the dead domain render broken
-- images EVERYWHERE the URL is used as-is - this is why avatars were broken
-- for all users in church social + the prayer wall.
--
-- The client's read path (R2Service.resolveReadUrl) now rewrites the host at
-- render time as a belt-and-braces measure; this migration fixes the DATA so
-- stored URLs are consistent with what the write path stores today.
--
-- Idempotent: re-running is a no-op (nothing matches after the rewrite).
-- Backup tables (`_backup%`) are deliberately left untouched so incident
-- evidence keeps its original values.

DO $$
DECLARE
  r record;
  n bigint;
  total bigint := 0;
BEGIN
  FOR r IN
    SELECT c.table_schema, c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND c.data_type IN ('text', 'character varying')
      AND c.table_name NOT LIKE '\_backup%'
      -- Never touch auth/identity or code-like columns.
      AND c.column_name NOT IN ('id', 'email', 'phone', 'phone_number')
  LOOP
    EXECUTE format(
      'UPDATE public.%I SET %I = replace(%I, %L, %L) WHERE %I LIKE %L',
      r.table_name,
      r.column_name,
      r.column_name,
      'https://media.churchonapp.com',
      'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev',
      r.column_name,
      '%media.churchonapp.com%'
    );
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      total := total + n;
      RAISE NOTICE '%.%: % rows rewritten', r.table_name, r.column_name, n;
    END IF;
  END LOOP;
  RAISE NOTICE 'TOTAL rows rewritten: %', total;
END $$;
