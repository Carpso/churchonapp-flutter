-- ============================================================================
-- 20261264 — EVENTS AUDIT: DEDUPLICATE SEED EVENTS
--
-- The seed data created 4 duplicate groups (18 rows, 14 excess):
--   "Zambia Shall Be Saved Conference" x5 in one tenant/date and x4 in another
--   "Night of Miracles"                x5 and x4
-- Duplicate events made the hub show the same event repeated and inflated
-- attendee counts. Keep the EARLIEST created row per group (the canonical
-- seed), archive the rest to a backup table, then delete them — all child
-- rows (registrations, ticket tiers, RSVPs, check-ins…) are ON DELETE
-- CASCADE except legacy `tickets` (SET NULL), so cleanup is automatic.
-- Explicitly requested by the owner ("fix … duplicates").
-- ============================================================================

CREATE TABLE IF NOT EXISTS public._backup_dup_events_20261264 AS
SELECT * FROM public.events WHERE false;

INSERT INTO public._backup_dup_events_20261264
SELECT e.*
FROM public.events e
WHERE e.id IN (
  SELECT x.id FROM (
    SELECT e2.*,
           row_number() OVER (
             PARTITION BY lower(btrim(e2.title)), COALESCE(e2.tenant_id::text, '-'), e2.date::date
             ORDER BY e2.created_at ASC, e2.id ASC
           ) AS rn
    FROM public.events e2
    WHERE EXISTS (
      SELECT 1 FROM public.events e3
       WHERE lower(btrim(e3.title)) = lower(btrim(e2.title))
         AND COALESCE(e3.tenant_id::text, '-') = COALESCE(e2.tenant_id::text, '-')
         AND e3.date::date = e2.date::date
    )
  ) x
  WHERE x.rn > 1
);

DELETE FROM public.events
WHERE id IN (SELECT id FROM public._backup_dup_events_20261264);

-- Verification: no duplicate title/tenant/date groups may remain.
DO $$
DECLARE
  v_dupes integer;
  v_backed integer;
BEGIN
  SELECT count(*) INTO v_dupes FROM (
    SELECT 1 FROM public.events
     GROUP BY lower(btrim(title)), COALESCE(tenant_id::text, '-'), date::date
    HAVING count(*) > 1
  ) x;
  SELECT count(*) INTO v_backed FROM public._backup_dup_events_20261264;
  IF v_dupes > 0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: % duplicate group(s) remain', v_dupes;
  END IF;
  RAISE NOTICE 'events deduped: % rows archived to _backup_dup_events_20261264', v_backed;
END;
$$;
