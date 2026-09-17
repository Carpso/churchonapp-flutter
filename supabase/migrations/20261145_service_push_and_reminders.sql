-- ============================================================================
-- 20261145_service_push_and_reminders.sql
-- Server-originated push notifications (DB triggers + pg_cron) and two
-- automations that previously had none.
--
-- WHY: `push-notifications` requires a user JWT. Anything that creates the
-- in-app notification inside SQL (role approved, writer approved, role change,
-- trial expiry) could therefore NEVER push. There was also no event reminder
-- timer (the old event-remind cron was deleted) and no automatic R2 archive of
-- stream recordings.
--
-- HOW: a shared secret (already used by lps-settle) is read from Supabase Vault
-- and sent as `x-cron-secret`; the Edge Functions accept it in "service mode".
-- The secret is copied into Vault from the existing cron job — it is NEVER
-- written into this repo.
-- ============================================================================

-- ── 1. Private schema + secret access ───────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS private;

DO $$
DECLARE
  v_secret text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'vault')
     AND NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'cron_secret') THEN
    SELECT substring(command FROM 'x-cron-secret[^0-9a-zA-Z]*([0-9a-zA-Z]{16,})')
      INTO v_secret
      FROM cron.job
     WHERE command LIKE '%x-cron-secret%'
     LIMIT 1;

    IF v_secret IS NOT NULL THEN
      PERFORM vault.create_secret(
        v_secret,
        'cron_secret',
        'Shared secret for service -> Edge Function calls (cron/triggers)'
      );
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

CREATE OR REPLACE FUNCTION private.get_cron_secret()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, vault
AS $$
  SELECT decrypted_secret
    FROM vault.decrypted_secrets
   WHERE name = 'cron_secret'
   ORDER BY created_at DESC
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.get_cron_secret() FROM PUBLIC;

-- ── 2. Push helper (uses the Edge Function in service mode) ─────────────────
CREATE OR REPLACE FUNCTION private.push_to_users(
  p_user_ids     uuid[],
  p_title        text,
  p_body         text,
  p_type         text,
  p_channel      text DEFAULT NULL,
  p_reference_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, private
AS $$
DECLARE
  v_secret text := private.get_cron_secret();
BEGIN
  IF v_secret IS NULL
     OR p_user_ids IS NULL
     OR array_length(p_user_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  -- `skipInApp` — the caller already wrote the in-app notification row.
  PERFORM net.http_post(
    url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    body := jsonb_build_object(
      'userIds', to_jsonb(p_user_ids),
      'title', p_title,
      'body', p_body,
      'skipInApp', true,
      'data', jsonb_strip_nulls(jsonb_build_object(
        'type', p_type,
        'channel_id', p_channel,
        'reference_id', p_reference_id
      ))
    )
  );
EXCEPTION WHEN undefined_function OR undefined_table OR undefined_column THEN
  NULL; -- pg_net / vault unavailable → in-app row still stands
END;
$$;

REVOKE ALL ON FUNCTION private.push_to_users(uuid[], text, text, text, text, text) FROM PUBLIC;

-- ── 3. Trigger notifications now ALSO push ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_role_approved()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Role Approved',
            'Your role as ' || NEW.role_name || ' has been approved.',
            'role_change',
            NEW.id::text
        );
        PERFORM private.push_to_users(
            ARRAY[NEW.user_id], 'Role Approved',
            'Your role as ' || NEW.role_name || ' has been approved.',
            'role', 'coa_announcements', NEW.id::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.notify_writer_approved()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
        UPDATE public.profiles SET role = 'writer' WHERE id = NEW.user_id;

        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Writer Status Approved',
            'Congratulations! Your writer application has been approved. You can now publish articles.',
            'writer_approved',
            NEW.id::text
        );
        PERFORM private.push_to_users(
            ARRAY[NEW.user_id], 'Writer Status Approved',
            'Congratulations! Your writer application has been approved.',
            'writer_approved', 'coa_announcements', NEW.id::text);
    ELSIF NEW.status = 'rejected' AND (OLD IS NULL OR OLD.status != 'rejected') THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Writer Application Update',
            'Your writer application was not approved. Reason: ' || COALESCE(NEW.rejection_reason, 'Not specified'),
            'writer_rejected',
            NEW.id::text
        );
        PERFORM private.push_to_users(
            ARRAY[NEW.user_id], 'Writer Application Update',
            'Your writer application was not approved.',
            'writer_approved', 'coa_announcements', NEW.id::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.notify_profile_role_change()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
    IF OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.id,
            'Role Updated',
            'Your platform role has been updated to: ' || NEW.role,
            'role_change',
            NEW.id::text
        );
        PERFORM private.push_to_users(
            ARRAY[NEW.id], 'Role Updated',
            'Your platform role has been updated to: ' || NEW.role,
            'role', 'coa_announcements', NEW.id::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 4. Trial-expiry reminders now push to the owners ────────────────────────
CREATE OR REPLACE FUNCTION public.notify_trial_expiry(p_days int DEFAULT 7)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_owner record;
  v_n int := 0;
BEGIN
  FOR v_row IN
    SELECT * FROM public.get_tenancy_payment_reminders(p_days)
  LOOP
    FOR v_owner IN
      SELECT (o->>'user_id')::uuid AS uid
      FROM jsonb_array_elements(v_row.owners) o
    LOOP
      IF v_owner.uid IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, title, body, type, created_at)
        VALUES (
          v_owner.uid,
          'Church subscription due',
          v_row.church_name || ' has ' || v_row.days_left ||
            ' day(s) left on its trial. Please settle the subscription to keep all features on.',
          'subscription_due',
          now()
        );
        PERFORM private.push_to_users(
          ARRAY[v_owner.uid],
          'Church subscription due',
          v_row.church_name || ' has ' || v_row.days_left ||
            ' day(s) left on its trial. Please settle the subscription.',
          'subscription_due',
          'coa_payments',
          NULL);
        v_n := v_n + 1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notify_trial_expiry(int) FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_trial_expiry(int) FROM authenticated;

-- ── 5. Event reminders (tomorrow's events) + push ───────────────────────────
CREATE OR REPLACE FUNCTION public.push_event_reminders()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event record;
  v_uids  uuid[];
  v_n     int := 0;
BEGIN
  FOR v_event IN
    SELECT e.id, e.title
      FROM public.events e
     WHERE e.date IS NOT NULL
       AND e.date::date = (CURRENT_DATE + 1)
  LOOP
    SELECT array_agg(DISTINCT r.user_id)
      INTO v_uids
      FROM public.event_rsvps r
     WHERE r.event_id = v_event.id
       AND COALESCE(r.status, '') NOT IN ('cancelled', 'declined');

    IF v_uids IS NOT NULL AND array_length(v_uids, 1) > 0 THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      SELECT uid, 'Event tomorrow', v_event.title || ' is tomorrow. Don''t miss it!',
             'event_reminder', v_event.id::text
        FROM unnest(v_uids) AS uid;

      PERFORM private.push_to_users(
        v_uids,
        'Event tomorrow',
        v_event.title || ' is tomorrow. Don''t miss it!',
        'event',
        'coa_events',
        v_event.id::text);

      v_n := v_n + array_length(v_uids, 1);
    END IF;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.push_event_reminders() FROM anon;
REVOKE EXECUTE ON FUNCTION public.push_event_reminders() FROM authenticated;

-- ── 6. Automatic R2 archive of ended stream recordings ──────────────────────
CREATE OR REPLACE FUNCTION public.auto_archive_stream_recordings()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, private
AS $$
DECLARE
  v_row record;
  v_n   int := 0;
  v_secret text := private.get_cron_secret();
BEGIN
  IF v_secret IS NULL THEN
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT id FROM public.live_streams
     WHERE status IN ('ended', 'archived')
       AND cloudflare_stream_id IS NOT NULL
       AND COALESCE(archive_status, 'none') IN ('none', 'failed')
       AND COALESCE(ended_at, created_at) < now() - interval '15 minutes'
     ORDER BY COALESCE(ended_at, created_at) DESC
     LIMIT 5
  LOOP
    PERFORM net.http_post(
      url := 'https://daboihiudmglwhdfvsku.supabase.co/functions/v1/cloudflare-stream',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', v_secret
      ),
      body := jsonb_build_object('action', 'archive_recording', 'stream_id', v_row.id)
    );
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
EXCEPTION WHEN undefined_function OR undefined_table THEN
  RETURN 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_archive_stream_recordings() FROM anon;
REVOKE EXECUTE ON FUNCTION public.auto_archive_stream_recordings() FROM authenticated;

-- ── 7. Schedule the two automations ─────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('event-reminder-push')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'event-reminder-push');
    PERFORM cron.schedule(
      'event-reminder-push',
      '0 17 * * *',
      $cron$SELECT public.push_event_reminders();$cron$
    );

    PERFORM cron.unschedule('stream-archive-sweep')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'stream-archive-sweep');
    PERFORM cron.schedule(
      'stream-archive-sweep',
      '*/30 * * * *',
      $cron$SELECT public.auto_archive_stream_recordings();$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
