-- 20260909 — SECURITY HARDENING ROUND 3B: RLS-policy helper restoration + last stragglers
-- (follow-up to 20260908, live-DB verified 2026-08-17)
--
-- 1. RESTORE PUBLIC on is_super_admin() / is_church_pastor(uuid):
--    Both are referenced inside RLS policy quals (tithes, service_reports,
--    prayers, testimonies, wallet_transactions, churches, profiles, ...).
--    Policy expressions are evaluated as the querying role, so revoking
--    anon/PUBLIC EXECUTE made anon SELECTs on those tables ERROR instead of
--    returning empty rows — breaking public pages (church websites).
--    They are pure read-only predicates that return false for anon
--    (auth.uid() IS NULL), so PUBLIC EXECUTE is safe and required.
--    is_admin_or_employee() was left PUBLIC in 20260908 for the same reason.
--
-- 2. Finish the sweep for stragglers that survived round 3:
--    * increment_fundraising_raised(uuid, double precision) — PUBLIC+anon
--      reachable, no guard: anon could inflate any venture's raised total.
--      Now authenticated-only + body guard (caller: fundraising_service.dart:133).
--    * increment_redeemed_count(uuid) — PUBLIC+service_role, no guard.
--      Now authenticated + service_role only (no client caller in lib/).
--    * kids_mark_resource_completed(uuid) / kids_upsert_progress(uuid,int) —
--      PUBLIC reachable but bodies already auth-guarded. Revoke anon/PUBLIC,
--      grant authenticated (callers: kids_zone_screen.dart:55, kids service).
--    * record_streaming_minutes(uuid, integer, integer) — PUBLIC+service_role
--      (the jsonb trial-limit variant; 2-arg integer calls resolve here via
--      defaults). Now authenticated + service_role.

-- ============================================================
-- RLS-policy helpers: restore PUBLIC (required for policy eval)
-- ============================================================
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO PUBLIC, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.is_church_pastor(UUID) TO PUBLIC, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.is_admin_or_employee() TO PUBLIC, authenticated, service_role;

-- ============================================================
-- Last stragglers
-- ============================================================

CREATE OR REPLACE FUNCTION public.increment_fundraising_raised(venture_id uuid, amount double precision)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    UPDATE public.fundraising_ventures
    SET raised_amount = raised_amount + amount
    WHERE id = venture_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.increment_fundraising_raised(UUID, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_fundraising_raised(UUID, DOUBLE PRECISION) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_redeemed_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_redeemed_count(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.kids_mark_resource_completed(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.kids_mark_resource_completed(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.kids_upsert_progress(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.kids_upsert_progress(UUID, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.record_streaming_minutes(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_streaming_minutes(UUID, INTEGER, INTEGER) TO authenticated, service_role;
