-- Business Meetings: real WebRTC video meetings, paywalled by participant count
-- Tables: business_meetings, meeting_participants, meeting_signaling

-- 1. Business meetings table
CREATE TABLE IF NOT EXISTS public.business_meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  host_id UUID NOT NULL REFERENCES auth.users(id),
  title TEXT NOT NULL DEFAULT 'Business Meeting',
  meeting_code TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'active', 'ended', 'cancelled')),
  max_participants INTEGER NOT NULL DEFAULT 5,
  is_recorded BOOLEAN DEFAULT false,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Meeting participants
CREATE TABLE IF NOT EXISTS public.meeting_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.business_meetings(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  role TEXT NOT NULL DEFAULT 'participant' CHECK (role IN ('host', 'co_host', 'participant')),
  is_muted BOOLEAN DEFAULT true,
  is_video_off BOOLEAN DEFAULT true,
  is_screen_sharing BOOLEAN DEFAULT false,
  joined_at TIMESTAMPTZ DEFAULT now(),
  left_at TIMESTAMPTZ,
  UNIQUE(meeting_id, user_id)
);

-- 3. Meeting signaling (WebRTC offer/answer/ICE via Supabase Realtime)
CREATE TABLE IF NOT EXISTS public.meeting_signaling (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id UUID NOT NULL REFERENCES public.business_meetings(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  receiver_id UUID REFERENCES auth.users(id),
  signal_type TEXT NOT NULL CHECK (signal_type IN ('offer', 'answer', 'ice', 'join', 'leave', 'mute', 'unmute', 'video_on', 'video_off')),
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE public.business_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_signaling ENABLE ROW LEVEL SECURITY;

-- business_meetings policies
DROP POLICY IF EXISTS "Users can view meetings they host or participate in" ON public.business_meetings;
CREATE POLICY "Users can view meetings they host or participate in"
  ON public.business_meetings FOR SELECT
  USING (
    host_id = auth.uid()
    OR id IN (SELECT meeting_id FROM public.meeting_participants WHERE user_id = auth.uid())
    OR tenant_id = (SELECT tenant_id::uuid FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Hosts can create meetings" ON public.business_meetings;
CREATE POLICY "Hosts can create meetings"
  ON public.business_meetings FOR INSERT
  WITH CHECK (host_id = auth.uid());

DROP POLICY IF EXISTS "Hosts can update their meetings" ON public.business_meetings;
CREATE POLICY "Hosts can update their meetings"
  ON public.business_meetings FOR UPDATE
  USING (host_id = auth.uid());

-- meeting_participants policies
DROP POLICY IF EXISTS "Participants can view meeting members" ON public.meeting_participants;
CREATE POLICY "Participants can view meeting members"
  ON public.meeting_participants FOR SELECT
  USING (
    meeting_id IN (SELECT id FROM public.business_meetings WHERE host_id = auth.uid())
    OR user_id = auth.uid()
    OR meeting_id IN (SELECT meeting_id FROM public.meeting_participants WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Users can join meetings" ON public.meeting_participants;
CREATE POLICY "Users can join meetings"
  ON public.meeting_participants FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own participation" ON public.meeting_participants;
CREATE POLICY "Users can update their own participation"
  ON public.meeting_participants FOR UPDATE
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Hosts can remove participants" ON public.meeting_participants;
CREATE POLICY "Hosts can remove participants"
  ON public.meeting_participants FOR DELETE
  USING (
    meeting_id IN (SELECT id FROM public.business_meetings WHERE host_id = auth.uid())
    OR user_id = auth.uid()
  );

-- meeting_signaling policies
DROP POLICY IF EXISTS "Participants can read signaling for their meetings" ON public.meeting_signaling;
CREATE POLICY "Participants can read signaling for their meetings"
  ON public.meeting_signaling FOR SELECT
  USING (
    meeting_id IN (
      SELECT meeting_id FROM public.meeting_participants WHERE user_id = auth.uid()
      UNION
      SELECT id FROM public.business_meetings WHERE host_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Participants can send signaling" ON public.meeting_signaling;
CREATE POLICY "Participants can send signaling"
  ON public.meeting_signaling FOR INSERT
  WITH CHECK (sender_id = auth.uid());

-- Indexes
CREATE INDEX IF NOT EXISTS idx_meetings_tenant ON public.business_meetings(tenant_id);
CREATE INDEX IF NOT EXISTS idx_meetings_host ON public.business_meetings(host_id);
CREATE INDEX IF NOT EXISTS idx_meetings_code ON public.business_meetings(meeting_code);
CREATE INDEX IF NOT EXISTS idx_meetings_status ON public.business_meetings(status);
CREATE INDEX IF NOT EXISTS idx_participants_meeting ON public.meeting_participants(meeting_id);
CREATE INDEX IF NOT EXISTS idx_participants_user ON public.meeting_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_signaling_meeting ON public.meeting_signaling(meeting_id);
CREATE INDEX IF NOT EXISTS idx_signaling_receiver ON public.meeting_signaling(receiver_id);

-- RPC: Join a meeting (checks max_participants limit)
CREATE OR REPLACE FUNCTION public.join_business_meeting(
  p_meeting_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'participant'
)
RETURNS JSONB AS $$
DECLARE
  v_meeting RECORD;
  v_participant_count INTEGER;
  v_existing RECORD;
BEGIN
  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
  END IF;

  IF v_meeting.status = 'ended' OR v_meeting.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting has ended');
  END IF;

  SELECT COUNT(*) INTO v_participant_count
  FROM public.meeting_participants
  WHERE meeting_id = p_meeting_id AND left_at IS NULL;

  IF v_participant_count >= v_meeting.max_participants THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting is full (' || v_meeting.max_participants || ' participants max)');
  END IF;

  SELECT * INTO v_existing
  FROM public.meeting_participants
  WHERE meeting_id = p_meeting_id AND user_id = p_user_id;

  IF v_existing IS NOT NULL THEN
    UPDATE public.meeting_participants SET left_at = NULL WHERE id = v_existing.id;
    RETURN jsonb_build_object('success', true, 'participant_id', v_existing.id, 'rejoined', true);
  END IF;

  INSERT INTO public.meeting_participants (meeting_id, user_id, role)
  VALUES (p_meeting_id, p_user_id, p_role)
  RETURNING id INTO v_existing;

  RETURN jsonb_build_object('success', true, 'participant_id', v_existing.id, 'rejoined', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Generate a unique meeting code
CREATE OR REPLACE FUNCTION public.generate_meeting_code()
RETURNS TEXT AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  LOOP
    v_code := 'MTG-' || upper(substr(md5(random()::text), 1, 6));
    SELECT EXISTS(SELECT 1 FROM public.business_meetings WHERE meeting_code = v_code AND status != 'ended' AND status != 'cancelled') INTO v_exists;
    EXIT WHEN NOT v_exists;
  END LOOP;
  RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Start a meeting (host only)
CREATE OR REPLACE FUNCTION public.start_business_meeting(p_meeting_id UUID, p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_meeting RECORD;
BEGIN
  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
  END IF;
  IF v_meeting.host_id != p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the host can start the meeting');
  END IF;
  UPDATE public.business_meetings SET status = 'active', started_at = now() WHERE id = p_meeting_id;
  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: End a meeting (host only)
CREATE OR REPLACE FUNCTION public.end_business_meeting(p_meeting_id UUID, p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_meeting RECORD;
BEGIN
  SELECT * INTO v_meeting FROM public.business_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Meeting not found');
  END IF;
  IF v_meeting.host_id != p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only the host can end the meeting');
  END IF;
  UPDATE public.business_meetings SET status = 'ended', ended_at = now() WHERE id = p_meeting_id;
  UPDATE public.meeting_participants SET left_at = now() WHERE meeting_id = p_meeting_id AND left_at IS NULL;
  RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
