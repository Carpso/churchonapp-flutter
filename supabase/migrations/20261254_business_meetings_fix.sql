-- ============================================================================
-- 20261254_business_meetings_fix.sql
-- Repairs the Pro Business Meeting feature (schema drift that made it unusable).
--
-- EVIDENCE (verified against the live DB, 2026-10-03):
--   * business_meetings has NO `agenda_items` column, but the LIVE bodies of
--     create_business_meeting and generate_recurring_meetings both INSERT it:
--         SQLSTATE 42703 / column "agenda_items" of relation
--         "business_meetings" does not exist
--     => creating ANY meeting raised 42703; `business_meetings` had 0 rows.
--   * meeting_entitlement(p_user_id uuid DEFAULT auth.uid()) (the live
--     signature, from 20261221_pro_meeting_payments_entitlement) returns the
--     keys `is_pro` / `can_record` / `can_recur`. Two older RPCs were still
--     written against the pre-20261221 shape:
--       create_business_meeting : called meeting_entitlement(v_tenant)  [tenant
--         id bound as a USER id -> nobody is ever Pro] and read
--         v_ent->>'pro'           [never returned -> NULL]
--       set_meeting_recording   : called meeting_entitlement(NULL)
--         [always free] and read v_ent->>'recording' [never returned -> NULL]
--     => recurring meetings AND recording were rejected for every user,
--        including the one active meeting_subscriptions row.
--   * meeting_votes had INSERT + SELECT policies only. The client votes with
--     `.upsert(...)` = INSERT ... ON CONFLICT DO UPDATE, which needs an UPDATE
--     policy -> 42501 on the second vote.
--
-- Idempotent: safe to re-run. Nothing is dropped or deleted.
-- ============================================================================

-- ── 1. The column the live RPCs already write to ───────────────────────────
-- Keeps `create_business_meeting` and `generate_recurring_meetings` (which both
-- write and read it) working without rewriting their bodies.
ALTER TABLE public.business_meetings
  ADD COLUMN IF NOT EXISTS agenda_items JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ── 2. Helper: one entitlement read that tolerates both response shapes ───
CREATE OR REPLACE FUNCTION public.meeting_entitlement_flag(p_ent JSONB, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT COALESCE(
           (p_ent ->> CASE p_key WHEN 'pro'      THEN 'is_pro'
                                 WHEN 'recording' THEN 'can_record'
                                 WHEN 'recurring' THEN 'can_recur'
                                 ELSE p_key END)::boolean,
           (p_ent ->> p_key)::boolean,
           false);
$fn$;

COMMENT ON FUNCTION public.meeting_entitlement_flag(JSONB, TEXT) IS
  'Reads a Pro Meeting entitlement flag from meeting_entitlement() output, '
  'accepting both the legacy (pro/recording/recurring) and current '
  '(is_pro/can_record/can_recur) key names.';

-- ── 3. create_business_meeting: ask for the CALLER's entitlement ───────────
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

  -- Was: public.meeting_entitlement(v_tenant) -> bound the TENANT id to the
  -- p_user_id parameter, so every host looked like the free tier.
  -- meeting_subscriptions is user-scoped, so ask for the caller themselves.
  v_ent := public.meeting_entitlement();

  IF NOT public.meeting_entitlement_flag(v_ent, 'pro')
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

-- ── 4. set_meeting_recording: same two bugs ────────────────────────────────
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

  -- Was: public.meeting_entitlement(NULL) -> always the free tier.
  v_ent := public.meeting_entitlement();
  -- Was: v_ent->>'recording' -> the live RPC returns 'can_record'.
  IF NOT public.meeting_entitlement_flag(v_ent, 'recording') THEN
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

-- ── 5. meeting_votes: the client votes with an upsert ─────────────────────
-- INSERT ... ON CONFLICT (meeting_id, voter_id) DO UPDATE needs an UPDATE
-- policy; without it every vote after the first returned 42501.
DROP POLICY IF EXISTS "Users can change their own vote" ON public.meeting_votes;
CREATE POLICY "Users can change their own vote"
  ON public.meeting_votes FOR UPDATE TO authenticated
  USING (auth.uid() = voter_id)
  WITH CHECK (auth.uid() = voter_id);
