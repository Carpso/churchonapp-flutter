-- ============================================================================
-- 20261221_business_meetings_real.sql
-- Makes the "Pro Business Meeting" feature actually work.
--
-- WHY: 20260718 created business_meetings / meeting_participants /
-- meeting_signaling and three RPCs, but the client sheet only pushed a screen
-- with a title and never inserted a row; join/start/end were never called and
-- signalling had no client at all (hardcoded tiles, 0 rows in every table).
--
-- THIS MIGRATION:
--   1. Extends business_meetings with schedule / recurrence / recording /
--      description / timezone / duration + reminder bookkeeping.
--   2. Adds meeting_agenda_items + meeting_rsvps (invites).
--   3. Rewrites the meeting RPCs to be auth.uid()-driven (no client-supplied
--      user ids) and status transitions real (scheduled -> live -> ended).
--   4. Enforces capacity server-side and gates recurring + recording on
--      meeting_entitlement() (fail closed: no active subscription = free tier).
--   5. Adds realtime for participants / signalling / agenda / notes / votes.
--   6. Adds reminder + recurring pg_cron sweeps (uses the established Vault
--      `private.push_to_users` pattern; secret never written to the repo).
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- ── 1. business_meetings: schedule / recurrence / recording columns ─────────
ALTER TABLE public.business_meetings
  ADD COLUMN IF NOT EXISTS description       TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS duration_minutes  INTEGER DEFAULT 60,
  ADD COLUMN IF NOT EXISTS timezone          TEXT DEFAULT 'Africa/Lusaka',
  ADD COLUMN IF NOT EXISTS is_recurring      BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS recurrence_rule   TEXT,
  ADD COLUMN IF NOT EXISTS parent_meeting_id UUID REFERENCES public.business_meetings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS recording_url     TEXT,
  ADD COLUMN IF NOT EXISTS recording_status  TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS reminder_sent_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS updated_at        TIMESTAMPTZ DEFAULT now();

-- Widen the status CHECK so `live` is a first-class value (legacy `active` kept
-- so any pre-existing row / older client expectation still validates).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema = 'public' AND table_name = 'business_meetings'
       AND constraint_name = 'business_meetings_status_check'
  ) THEN
    ALTER TABLE public.business_meetings DROP CONSTRAINT business_meetings_status_check;
  END IF;
  ALTER TABLE public.business_meetings
    ADD CONSTRAINT business_meetings_status_check
    CHECK (status IN ('scheduled', 'live', 'active', 'ended', 'cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_meetings_scheduled ON public.business_meetings(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_meetings_parent    ON public.business_meetings(parent_meeting_id);

-- ── 2. Agenda items ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.meeting_agenda_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.business_meetings(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  position   INTEGER NOT NULL DEFAULT 0,
  is_done    BOOLEAN NOT NULL DEFAULT false,
  done_at    TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_meeting_agenda_meeting ON public.meeting_agenda_items(meeting_id, position);

-- ── 3. RSVPs / invites ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.meeting_rsvps (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.business_meetings(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'accepted', 'declined')),
  invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (meeting_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_meeting_rsvps_meeting ON public.meeting_rsvps(meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_rsvps_user    ON public.meeting_rsvps(user_id);

-- ── 4. Signalling: allow end / recording / screen_share ─────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema = 'public' AND table_name = 'meeting_signaling'
       AND constraint_name = 'meeting_signaling_signal_type_check'
  ) THEN
    ALTER TABLE public.meeting_signaling DROP CONSTRAINT meeting_signaling_signal_type_check;
  END IF;
  ALTER TABLE public.meeting_signaling
    ADD CONSTRAINT meeting_signaling_signal_type_check
    CHECK (signal_type IN (
      'offer', 'answer', 'ice', 'join', 'leave',
      'mute', 'unmute', 'video_on', 'video_off',
      'end', 'recording', 'screen_share'
    ));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 5. RLS for the new tables ───────────────────────────────────────────────
ALTER TABLE public.meeting_agenda_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_rsvps        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Meeting members can read agenda" ON public.meeting_agenda_items;
CREATE POLICY "Meeting members can read agenda"
  ON public.meeting_agenda_items FOR SELECT TO authenticated
  USING (
    meeting_id IN (SELECT id FROM public.business_meetings WHERE host_id = auth.uid())
    OR meeting_id IN (SELECT meeting_id FROM public.meeting_participants WHERE user_id = auth.uid())
    OR meeting_id IN (SELECT meeting_id FROM public.meeting_rsvps WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Meeting members can read rsvps" ON public.meeting_rsvps;
CREATE POLICY "Meeting members can read rsvps"
  ON public.meeting_rsvps FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR meeting_id IN (SELECT id FROM public.business_meetings WHERE host_id = auth.uid())
    OR meeting_id IN (SELECT meeting_id FROM public.meeting_participants WHERE user_id = auth.uid())
  );

-- Invited users can see the meeting itself.
DROP POLICY IF EXISTS "Invited users can view meetings" ON public.business_meetings;
CREATE POLICY "Invited users can view meetings"
  ON public.business_meetings FOR SELECT TO authenticated
  USING (id IN (SELECT meeting_id FROM public.meeting_rsvps WHERE user_id = auth.uid()));

-- ── 6. Entitlement (fail closed) ────────────────────────────────────────────
-- Pro = an active, unexpired meeting_subscriptions row for this user or their
-- tenant. Anything else is the free tier: 5 participants, no recording, no
-- recurrence. Never trust a client-supplied plan.
CREATE OR REPLACE FUNCTION public.meeting_entitlement(p_tenant_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pro BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'pro', false, 'max_participants', 5,
      'recording', false, 'recurring', false, 'reason', 'unauthenticated');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.meeting_subscriptions s
     WHERE s.status = 'active'
       AND (s.expires_at IS NULL OR s.expires_at > now())
       AND (
         s.user_id = auth.uid()
         OR (p_tenant_id IS NOT NULL AND s.tenant_id = p_tenant_id)
       )
  ) INTO v_pro;

  RETURN jsonb_build_object(
    'pro', v_pro,
    'max_participants', CASE WHEN v_pro THEN 10 ELSE 5 END,
    'recording', v_pro,
    'recurring', v_pro
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.meeting_entitlement(UUID) FROM anon;

-- ── 7. Create + schedule a meeting (real row, real code) ────────────────────
DROP FUNCTION IF EXISTS public.create_business_meeting(text, timestamptz, int, text, text, int, bool, text, jsonb);

CREATE OR REPLACE FUNCTION public.create_business_meeting(
  p_title            TEXT,
  p_scheduled_at     TIMESTAMPTZ DEFAULT now(),
  p_duration_minutes INTEGER DEFAULT 60,
  p_description      TEXT DEFAULT NULL,
  p_timezone         TEXT DEFAULT 'Africa/Lusaka',
  p_max_participants INTEGER DEFAULT NULL,
  p_is_recurring     BOOLEAN DEFAULT false,
  p_recurrence_rule  TEXT DEFAULT NULL,
  p_agenda           JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        UUID := auth.uid();
  v_tenant     UUID;
  v_ent        JSONB;
  v_cap        INTEGER;
  v_code       TEXT;
  v_id         UUID;
  v_item       TEXT;
  v_pos        INTEGER := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'title_required');
  END IF;

  SELECT tenant_id::uuid INTO v_tenant FROM public.profiles WHERE id = v_uid;
  v_ent := public.meeting_entitlement(v_tenant);

  IF COALESCE((v_ent->>'pro')::boolean, false) = false
     AND p_is_recurring THEN
    RETURN jsonb_build_object('success', false, 'error', 'pro_required',
      'message', 'Recurring meetings require the Pro Meeting Suite.');
  END IF;

  v_cap := LEAST(
    COALESCE(NULLIF(p_max_participants, 0), (v_ent->>'max_participants')::int),
    (v_ent->>'max_participants')::int
  );
  v_cap := GREATEST(v_cap, 2);

  v_code := public.generate_meeting_code();

  INSERT INTO public.business_meetings (
    tenant_id, host_id, title, meeting_code, status, max_participants,
    description, scheduled_at, duration_minutes, timezone,
    is_recurring, recurrence_rule, agenda_items
  ) VALUES (
    v_tenant, v_uid, trim(p_title), v_code, 'scheduled', v_cap,
    p_description, COALESCE(p_scheduled_at, now()), COALESCE(p_duration_minutes, 60),
    COALESCE(p_timezone, 'Africa/Lusaka'), COALESCE(p_is_recurring, false),
    p_recurrence_rule, COALESCE(p_agenda, '[]'::jsonb)
  )
  RETURNING id INTO v_id;

  -- Normalise the agenda into real rows.
  IF p_agenda IS NOT NULL AND jsonb_typeof(p_agenda) = 'array' THEN
    FOR v_item IN SELECT jsonb_array_elements_text(p_agenda) LOOP
      IF length(trim(v_item)) > 0 THEN
        INSERT INTO public.meeting_agenda_items (meeting_id, title, position, created_by)
        VALUES (v_id, trim(v_item), v_pos, v_uid);
        v_pos := v_pos + 1;
      END IF;
    END LOOP;
  END IF;

  -- Host is a participant from the outset.
  INSERT INTO public.meeting_participants (meeting_id, user_id, role, is_muted, is_video_off)
  VALUES (v_id, v_uid, 'host', false, false)
  ON CONFLICT (meeting_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'meeting_code', v_code,
                            'max_participants', v_cap);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_business_meeting(text, timestamptz, int, text, text, int, bool, text, jsonb) FROM anon;

-- ── 8. Join / leave (capacity enforced server-side) ─────────────────────────
DROP FUNCTION IF EXISTS public.join_business_meeting(uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.join_business_meeting(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_meeting RECORD;
  v_count   INTEGER;
  v_existing RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_meeting.status IN ('ended', 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ended',
      'message', 'This meeting has already ended.');
  END IF;

  SELECT * INTO v_existing
    FROM public.meeting_participants
   WHERE meeting_id = p_meeting_id AND user_id = v_uid;

  -- Rejoining someone who already holds a seat must not be capacity-blocked.
  IF v_existing IS NULL THEN
    SELECT count(*) INTO v_count
      FROM public.meeting_participants
     WHERE meeting_id = p_meeting_id AND left_at IS NULL;

    IF v_count >= v_meeting.max_participants THEN
      RETURN jsonb_build_object('success', false, 'error', 'full',
        'message', 'Meeting is full (' || v_meeting.max_participants || ' participants max).');
    END IF;

    INSERT INTO public.meeting_participants (meeting_id, user_id, role)
    VALUES (p_meeting_id, v_uid,
            CASE WHEN v_meeting.host_id = v_uid THEN 'host' ELSE 'participant' END)
    RETURNING id INTO v_existing;
  ELSE
    UPDATE public.meeting_participants
       SET left_at = NULL, joined_at = now()
     WHERE id = v_existing.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'participant_id', v_existing.id,
    'meeting_code', v_meeting.meeting_code,
    'host_id', v_meeting.host_id,
    'status', v_meeting.status,
    'max_participants', v_meeting.max_participants);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_business_meeting(UUID) FROM anon;

CREATE OR REPLACE FUNCTION public.leave_business_meeting(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  UPDATE public.meeting_participants
     SET left_at = now()
   WHERE meeting_id = p_meeting_id AND user_id = v_uid AND left_at IS NULL;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.leave_business_meeting(UUID) FROM anon;

-- ── 9. Status transitions (host only) ───────────────────────────────────────
DROP FUNCTION IF EXISTS public.start_business_meeting(uuid, uuid);
DROP FUNCTION IF EXISTS public.end_business_meeting(uuid, uuid);

CREATE OR REPLACE FUNCTION public.start_business_meeting(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only',
      'message', 'Only the host can start the meeting.');
  END IF;

  UPDATE public.business_meetings
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         updated_at = now()
   WHERE id = p_meeting_id;

  INSERT INTO public.meeting_signaling (meeting_id, sender_id, signal_type, payload)
  VALUES (p_meeting_id, v_uid, 'join', jsonb_build_object('started', true));

  RETURN jsonb_build_object('success', true, 'status', 'live');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.start_business_meeting(UUID) FROM anon;

CREATE OR REPLACE FUNCTION public.end_business_meeting(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only',
      'message', 'Only the host can end the meeting.');
  END IF;

  UPDATE public.business_meetings
     SET status = 'ended', ended_at = now(), updated_at = now()
   WHERE id = p_meeting_id;
  UPDATE public.meeting_participants
     SET left_at = now()
   WHERE meeting_id = p_meeting_id AND left_at IS NULL;

  INSERT INTO public.meeting_signaling (meeting_id, sender_id, signal_type, payload)
  VALUES (p_meeting_id, v_uid, 'end', jsonb_build_object('ended', true));

  RETURN jsonb_build_object('success', true, 'status', 'ended');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.end_business_meeting(UUID) FROM anon;

CREATE OR REPLACE FUNCTION public.cancel_business_meeting(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only',
      'message', 'Only the host can cancel the meeting.');
  END IF;

  UPDATE public.business_meetings
     SET status = 'cancelled', cancelled_at = now(), updated_at = now()
   WHERE id = p_meeting_id;
  UPDATE public.meeting_participants
     SET left_at = COALESCE(left_at, now())
   WHERE meeting_id = p_meeting_id AND left_at IS NULL;

  RETURN jsonb_build_object('success', true, 'status', 'cancelled');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cancel_business_meeting(UUID) FROM anon;

-- ── 10. Media state (mute / video) + host mute-all ──────────────────────────
CREATE OR REPLACE FUNCTION public.set_meeting_media(
  p_meeting_id  UUID,
  p_is_muted    BOOLEAN,
  p_is_video_off BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  UPDATE public.meeting_participants
     SET is_muted = p_is_muted, is_video_off = p_is_video_off
   WHERE meeting_id = p_meeting_id AND user_id = v_uid;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_meeting_media(UUID, BOOLEAN, BOOLEAN) FROM anon;

CREATE OR REPLACE FUNCTION public.mute_all_meeting_participants(p_meeting_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only');
  END IF;

  UPDATE public.meeting_participants
     SET is_muted = true
   WHERE meeting_id = p_meeting_id AND left_at IS NULL AND user_id <> v_uid;

  INSERT INTO public.meeting_signaling (meeting_id, sender_id, signal_type, payload)
  VALUES (p_meeting_id, v_uid, 'mute', jsonb_build_object('all', true));

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mute_all_meeting_participants(UUID) FROM anon;

-- ── 11. Recording (Pro-gated, host only) ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_meeting_recording(
  p_meeting_id UUID,
  p_url        TEXT,
  p_status     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_host UUID;
  v_ent  JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only');
  END IF;

  v_ent := public.meeting_entitlement(NULL);
  IF COALESCE((v_ent->>'recording')::boolean, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'pro_required',
      'message', 'Recording requires the Pro Meeting Suite.');
  END IF;

  UPDATE public.business_meetings
     SET recording_url = p_url,
         recording_status = COALESCE(p_status, 'none'),
         updated_at = now()
   WHERE id = p_meeting_id;

  INSERT INTO public.meeting_signaling (meeting_id, sender_id, signal_type, payload)
  VALUES (p_meeting_id, v_uid, 'recording',
          jsonb_build_object('status', COALESCE(p_status, 'none'), 'url', p_url));

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_meeting_recording(UUID, TEXT, TEXT) FROM anon;

-- ── 12. Agenda RPCs ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.add_meeting_agenda_item(
  p_meeting_id UUID,
  p_title      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
  v_pos INTEGER;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid AND NOT EXISTS (
    SELECT 1 FROM public.meeting_participants
     WHERE meeting_id = p_meeting_id AND user_id = v_uid AND left_at IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_a_member');
  END IF;
  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'title_required');
  END IF;

  SELECT COALESCE(max(position), -1) + 1 INTO v_pos
    FROM public.meeting_agenda_items WHERE meeting_id = p_meeting_id;

  INSERT INTO public.meeting_agenda_items (meeting_id, title, position, created_by)
  VALUES (p_meeting_id, trim(p_title), v_pos, v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'position', v_pos);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_meeting_agenda_item(UUID, TEXT) FROM anon;

CREATE OR REPLACE FUNCTION public.update_meeting_agenda_item(
  p_item_id UUID,
  p_title   TEXT DEFAULT NULL,
  p_is_done BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_meeting UUID;
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT meeting_id INTO v_meeting FROM public.meeting_agenda_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = v_meeting;
  IF v_host <> v_uid AND NOT EXISTS (
    SELECT 1 FROM public.meeting_participants
     WHERE meeting_id = v_meeting AND user_id = v_uid AND left_at IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_a_member');
  END IF;

  UPDATE public.meeting_agenda_items
     SET title   = COALESCE(NULLIF(trim(p_title), ''), title),
         is_done = COALESCE(p_is_done, is_done),
         done_at = CASE
                     WHEN p_is_done IS TRUE  THEN now()
                     WHEN p_is_done IS FALSE THEN NULL
                     ELSE done_at
                   END
   WHERE id = p_item_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_meeting_agenda_item(UUID, TEXT, BOOLEAN) FROM anon;

CREATE OR REPLACE FUNCTION public.delete_meeting_agenda_item(p_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_meeting UUID;
  v_host UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT meeting_id INTO v_meeting FROM public.meeting_agenda_items WHERE id = p_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = v_meeting;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only');
  END IF;
  DELETE FROM public.meeting_agenda_items WHERE id = p_item_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_meeting_agenda_item(UUID) FROM anon;

CREATE OR REPLACE FUNCTION public.reorder_meeting_agenda_items(
  p_meeting_id UUID,
  p_item_ids   UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_host UUID;
  v_id UUID;
  v_pos INTEGER := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  SELECT host_id INTO v_host FROM public.business_meetings WHERE id = p_meeting_id;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only');
  END IF;

  FOREACH v_id IN ARRAY p_item_ids LOOP
    UPDATE public.meeting_agenda_items
       SET position = v_pos
     WHERE id = v_id AND meeting_id = p_meeting_id;
    v_pos := v_pos + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reorder_meeting_agenda_items(UUID, UUID[]) FROM anon;

-- ── 13. Invites (searchable picker is client-side; invite is server-side) ────
CREATE OR REPLACE FUNCTION public.invite_meeting_participants(
  p_meeting_id UUID,
  p_user_ids   UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_host   UUID;
  v_title  TEXT;
  v_when   TIMESTAMPTZ;
  v_uid_i  UUID;
  v_added  INTEGER := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT host_id, title, scheduled_at
    INTO v_host, v_title, v_when
    FROM public.business_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_host <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'host_only',
      'message', 'Only the host can invite people.');
  END IF;

  FOREACH v_uid_i IN ARRAY p_user_ids LOOP
    IF v_uid_i IS NULL OR v_uid_i = v_uid THEN CONTINUE; END IF;

    INSERT INTO public.meeting_rsvps (meeting_id, user_id, status, invited_by)
    VALUES (p_meeting_id, v_uid_i, 'invited', v_uid)
    ON CONFLICT (meeting_id, user_id) DO NOTHING;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_uid_i,
      'Meeting invitation',
      'You are invited to "' || v_title || '"' ||
        CASE WHEN v_when IS NOT NULL
             THEN ' on ' || to_char(v_when, 'Dy DD Mon at HH24:MI')
             ELSE '' END || '.',
      'meeting',
      p_meeting_id::text
    );
    v_added := v_added + 1;
  END LOOP;

  -- Push is best-effort and must never roll back the in-app notification rows.
  BEGIN
    PERFORM private.push_to_users(
      p_user_ids,
      'Meeting invitation',
      'You are invited to "' || v_title || '".',
      'meeting',
      'coa_events',
      p_meeting_id::text);
  EXCEPTION WHEN undefined_table OR undefined_function THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'invited', v_added);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.invite_meeting_participants(UUID, UUID[]) FROM anon;

CREATE OR REPLACE FUNCTION public.respond_meeting_rsvp(
  p_meeting_id UUID,
  p_status     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  IF p_status NOT IN ('invited', 'accepted', 'declined') THEN
    RETURN jsonb_build_object('success', false, 'error', 'bad_status');
  END IF;

  INSERT INTO public.meeting_rsvps (meeting_id, user_id, status)
  VALUES (p_meeting_id, v_uid, p_status)
  ON CONFLICT (meeting_id, user_id)
  DO UPDATE SET status = p_status, updated_at = now();

  RETURN jsonb_build_object('success', true, 'status', p_status);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.respond_meeting_rsvp(UUID, TEXT) FROM anon;

-- ── 14. Reminders (cron) ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.push_meeting_reminders(p_lead_minutes INT DEFAULT 15)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_row     RECORD;
  v_uids    UUID[];
  v_n       INT := 0;
BEGIN
  FOR v_row IN
    SELECT b.id, b.title, b.host_id, b.scheduled_at, b.meeting_code
      FROM public.business_meetings b
     WHERE b.status = 'scheduled'
       AND b.scheduled_at IS NOT NULL
       AND b.scheduled_at > now()
       AND b.scheduled_at <= now() + make_interval(mins => p_lead_minutes)
       AND b.reminder_sent_at IS NULL
  LOOP
    SELECT array_agg(DISTINCT uid) INTO v_uids FROM (
      SELECT v_row.host_id AS uid
      UNION
      SELECT r.user_id FROM public.meeting_rsvps r
       WHERE r.meeting_id = v_row.id AND r.status <> 'declined'
    ) t WHERE uid IS NOT NULL;

    IF v_uids IS NOT NULL AND array_length(v_uids, 1) > 0 THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      SELECT uid, 'Meeting starting soon',
             v_row.title || ' starts at ' || to_char(v_row.scheduled_at, 'HH24:MI') || '.',
             'meeting', v_row.id::text
        FROM unnest(v_uids) AS uid;

      PERFORM private.push_to_users(
        v_uids,
        'Meeting starting soon',
        v_row.title || ' starts at ' || to_char(v_row.scheduled_at, 'HH24:MI') || '.',
        'meeting',
        'coa_events',
        v_row.id::text);
    END IF;

    UPDATE public.business_meetings
       SET reminder_sent_at = now()
     WHERE id = v_row.id;
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.push_meeting_reminders(INT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.push_meeting_reminders(INT) FROM authenticated;

-- ── 15. Recurring generation (cron, Pro rows only) ──────────────────────────
CREATE OR REPLACE FUNCTION public.generate_recurring_meetings()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row RECORD;
  v_root UUID;
  v_next TIMESTAMPTZ;
  v_interval INTERVAL;
  v_new_id UUID;
  v_n INT := 0;
BEGIN
  FOR v_row IN
    SELECT b.*
      FROM public.business_meetings b
     WHERE b.status = 'scheduled'
       AND b.is_recurring
       AND COALESCE(b.recurrence_rule, '') <> ''
       AND b.scheduled_at IS NOT NULL
       AND b.scheduled_at <= now()
  LOOP
    v_root := COALESCE(v_row.parent_meeting_id, v_row.id);

    -- Only roll forward if no future occurrence already exists.
    IF EXISTS (
      SELECT 1 FROM public.business_meetings c
       WHERE COALESCE(c.parent_meeting_id, c.id) = v_root
         AND c.scheduled_at > v_row.scheduled_at
    ) THEN
      CONTINUE;
    END IF;

    v_interval := CASE
      WHEN v_row.recurrence_rule ILIKE 'daily%'    THEN interval '1 day'
      WHEN v_row.recurrence_rule ILIKE 'biweekly%' THEN interval '14 days'
      WHEN v_row.recurrence_rule ILIKE 'monthly%'  THEN interval '1 month'
      WHEN v_row.recurrence_rule ILIKE 'weekly%'   THEN interval '7 days'
      ELSE NULL
    END;
    IF v_interval IS NULL THEN CONTINUE; END IF;

    v_next := v_row.scheduled_at + v_interval;
    IF v_next <= now() THEN
      v_next := now() + interval '10 minutes';
    END IF;

    INSERT INTO public.business_meetings (
      tenant_id, host_id, title, meeting_code, status, max_participants,
      description, scheduled_at, duration_minutes, timezone,
      is_recurring, recurrence_rule, parent_meeting_id, agenda_items
    ) VALUES (
      v_row.tenant_id, v_row.host_id, v_row.title, public.generate_meeting_code(),
      'scheduled', v_row.max_participants, v_row.description, v_next,
      v_row.duration_minutes, v_row.timezone, true, v_row.recurrence_rule,
      v_root, v_row.agenda_items
    )
    RETURNING id INTO v_new_id;

    INSERT INTO public.meeting_agenda_items (meeting_id, title, position, created_by)
    SELECT v_new_id, a.title, a.position, v_row.host_id
      FROM public.meeting_agenda_items a
     WHERE a.meeting_id = v_row.id;

    -- Carry accepted invitees forward.
    INSERT INTO public.meeting_rsvps (meeting_id, user_id, status, invited_by)
    SELECT v_new_id, r.user_id, 'invited', v_row.host_id
      FROM public.meeting_rsvps r
     WHERE r.meeting_id = v_row.id AND r.status = 'accepted'
    ON CONFLICT (meeting_id, user_id) DO NOTHING;

    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_recurring_meetings() FROM anon;
REVOKE EXECUTE ON FUNCTION public.generate_recurring_meetings() FROM authenticated;

-- ── 16. Realtime ────────────────────────────────────────────────────────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'business_meetings', 'meeting_participants', 'meeting_signaling',
    'meeting_agenda_items', 'meeting_notes', 'meeting_votes', 'meeting_rsvps'
  ] LOOP
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
      END IF;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
  END LOOP;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

-- ── 17. Schedule the sweeps ─────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'meeting-reminder-push') THEN
      PERFORM cron.unschedule('meeting-reminder-push');
    END IF;
    PERFORM cron.schedule(
      'meeting-reminder-push',
      '*/5 * * * *',
      $cron$SELECT public.push_meeting_reminders(15);$cron$
    );

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'meeting-recurring-generate') THEN
      PERFORM cron.unschedule('meeting-recurring-generate');
    END IF;
    PERFORM cron.schedule(
      'meeting-recurring-generate',
      '10 5 * * *',
      $cron$SELECT public.generate_recurring_meetings();$cron$
    );
  END IF;
EXCEPTION WHEN undefined_table OR undefined_function THEN
  NULL;
END $$;
