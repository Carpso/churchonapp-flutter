-- 20260896 Quiz tournament gates: peer-visible event leaderboards, join caps,
-- paid-pass enforcement, and status gating for quiz events.
-- (Sprint: Bible quiz security hardening follow-up — "massive tournaments" readiness.)

-- =====================================================
-- 1. Helper (SECURITY DEFINER) to test event participation without RLS recursion.
-- =====================================================

CREATE OR REPLACE FUNCTION public._is_quiz_event_participant(p_uid UUID, p_event_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE user_id = p_uid AND event_id = p_event_id
  );
$$;

REVOKE ALL ON FUNCTION public._is_quiz_event_participant(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._is_quiz_event_participant(UUID, UUID) FROM anon;

-- =====================================================
-- 2. Peer visibility: participants of the same event can see each other's
--    scores (the old own-rows-only policy made tournament leaderboards show
--    a single row).
-- =====================================================

DROP POLICY IF EXISTS "quiz_event_participants_peer_view" ON public.quiz_event_participants;
CREATE POLICY "quiz_event_participants_peer_view"
  ON public.quiz_event_participants
  FOR SELECT
  USING (
    public._is_quiz_event_participant(auth.uid(), quiz_event_participants.event_id)
  );

-- =====================================================
-- 3. Server-side join gate: status + paid pass + max_participants cap.
-- =====================================================

CREATE OR REPLACE FUNCTION public.join_quiz_event(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_event RECORD;
  v_count INT;
  v_paid BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT status, pass_price, max_participants
    INTO v_event
    FROM public.quiz_events
   WHERE id = p_event_id
   LIMIT 1;

  IF v_event.status IS NULL THEN
    RETURN jsonb_build_object('error', 'Event not found');
  END IF;

  IF v_event.status NOT IN ('upcoming', 'active') THEN
    RETURN jsonb_build_object('error', 'Event is not open for joining');
  END IF;

  -- Already a participant? Idempotent rejoin.
  IF EXISTS (
    SELECT 1 FROM public.quiz_event_participants
    WHERE user_id = v_uid AND event_id = p_event_id
  ) THEN
    RETURN jsonb_build_object('success', true, 'already_joined', true);
  END IF;

  -- Paid-pass events require a confirmed pass before joining.
  IF COALESCE(v_event.pass_price, 0) > 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM public.quiz_passes
      WHERE event_id = p_event_id AND user_id = v_uid AND status = 'paid'
    ) INTO v_paid;
    IF NOT COALESCE(v_paid, false) THEN
      RETURN jsonb_build_object('error', 'Paid pass required');
    END IF;
  END IF;

  -- Cap enforcement (default 100 like the schema default).
  SELECT count(*) INTO v_count
    FROM public.quiz_event_participants
   WHERE event_id = p_event_id;

  IF v_count >= COALESCE(v_event.max_participants, 100) THEN
    RETURN jsonb_build_object('error', 'Event is full');
  END IF;

  INSERT INTO public.quiz_event_participants (event_id, user_id)
  VALUES (p_event_id, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('success', true, 'joined', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_quiz_event(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_quiz_event(UUID) TO authenticated;