-- ============================================================================
-- 20261210_notifications_autopush.sql
-- Safety net: any notification row written by a DATABASE function (i.e. not by
-- the mobile client, which pushes separately via the push-notifications Edge
-- Function) also emits an FCM push, so it rings on a locked screen instead of
-- only showing in the in-app bell.
--
-- WHY: `award_tournament_*` (20261205) and `award_promo_code` (20261206) insert
-- in-app notifications directly and never pushed, so quiz prizes / promo code
-- awards were silent when the app was backgrounded or killed.
--
-- HOW: an AFTER INSERT trigger on public.notifications that delegates to the
-- existing private.push_to_users() helper (shared secret -> Edge Function in
-- service mode). Guarded to:
--   * only NEW.type IS NULL  -> client + Edge inserts always set `type`, so a
--     type'd insert never double-pushes;
--   * only non-client sessions -> the one client path that inserts without a
--     type (tithe reminders) pushes itself, so it is skipped here.
-- ============================================================================

CREATE OR REPLACE FUNCTION private.notifications_autopush()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  -- Client-originated inserts push from the app; only DB sessions are bridged.
  IF current_user IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS NULL OR NEW.title IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM private.push_to_users(
    ARRAY[NEW.user_id],
    NEW.title,
    COALESCE(NEW.body, ''),
    COALESCE(NULLIF(NEW.type, ''), 'general'),
    'coa_announcements',
    NEW.reference_id
  );

  RETURN NEW;
EXCEPTION WHEN undefined_function OR undefined_table OR undefined_column THEN
  RETURN NEW; -- pg_net / helper unavailable -> in-app row still stands
END;
$$;

REVOKE ALL ON FUNCTION private.notifications_autopush() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_notifications_autopush ON public.notifications;
CREATE TRIGGER trg_notifications_autopush
AFTER INSERT ON public.notifications
FOR EACH ROW
WHEN (NEW.type IS NULL)
EXECUTE FUNCTION private.notifications_autopush();
