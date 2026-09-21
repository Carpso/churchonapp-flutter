-- ============================================================================
-- Production error fixes (console log of churchonapp.com)
-- 1) churches.plan / promotion_platinum_until missing (20260730_plans_sms_billing
--    was never added to deploy.ps1, so its ALTERs never ran).
-- 2) sermon_notes -> profiles FK missing (author_id only referenced auth.users,
--    so PostgREST embed `profiles!author_id` 400'd).
-- 3) pvp_answers had NO INSERT policy -> legitimate players got 42501.
-- 4) quiz_tournaments read policy mutually recursed with
--    quiz_tournament_participants -> Postgres "infinite recursion detected in
--    policy" -> PostgREST 500.
-- ============================================================================

-- 1) Restore church plan / platinum-promotion columns -------------------------
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'silver';
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS promotion_platinum_until TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS onboarding_fee_paid BOOLEAN DEFAULT false;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS onboarding_fee_paid_at TIMESTAMPTZ;

UPDATE public.churches SET plan = 'silver' WHERE plan IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'churches_plan_check'
  ) THEN
    ALTER TABLE public.churches
      ADD CONSTRAINT churches_plan_check
      CHECK (plan IN ('silver', 'gold', 'platinum'));
  END IF;
END $$;

-- 2) sermon_notes author FK -> profiles (enables the PostgREST embed) ---------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sermon_notes_author_profile_fkey'
  ) THEN
    ALTER TABLE public.sermon_notes
      ADD CONSTRAINT sermon_notes_author_profile_fkey
      FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 3) pvp_answers: a player may insert only their own answer in a live match ---
CREATE OR REPLACE FUNCTION public.is_pvp_match_player(p_match_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pvp_matches m
    WHERE m.id = p_match_id
      AND (m.player1_id = auth.uid() OR m.player2_id = auth.uid())
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_pvp_match_player(UUID) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.is_pvp_match_player(UUID) TO authenticated;

DROP POLICY IF EXISTS pvp_answers_insert_own ON public.pvp_answers;
CREATE POLICY pvp_answers_insert_own
  ON public.pvp_answers FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id AND public.is_pvp_match_player(match_id));

-- 4) quiz_tournaments read: break the mutual RLS recursion --------------------
CREATE OR REPLACE FUNCTION public.quiz_tournament_can_read(p_tournament_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.quiz_tournaments t
    WHERE t.id = p_tournament_id AND (
      t.visibility = 'public'
      OR t.host_tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.quiz_tournament_invites i
        WHERE i.tournament_id = t.id
          AND i.tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
      )
      OR EXISTS (
        SELECT 1 FROM public.quiz_tournament_participants tp
        WHERE tp.tournament_id = t.id AND tp.user_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role = ANY (ARRAY['superadmin', 'super_admin', 'coa_employee', 'employee'])
      )
    )
  );
$$;

REVOKE EXECUTE ON FUNCTION public.quiz_tournament_can_read(UUID) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.quiz_tournament_can_read(UUID) TO authenticated;

DROP POLICY IF EXISTS quiz_tournaments_read ON public.quiz_tournaments;
CREATE POLICY quiz_tournaments_read
  ON public.quiz_tournaments FOR SELECT TO authenticated
  USING (public.quiz_tournament_can_read(id));

DROP POLICY IF EXISTS quiz_tparticipants_read ON public.quiz_tournament_participants;
CREATE POLICY quiz_tparticipants_read
  ON public.quiz_tournament_participants FOR SELECT TO authenticated
  USING (public.quiz_tournament_can_read(tournament_id));

DROP POLICY IF EXISTS quiz_tinvites_read ON public.quiz_tournament_invites;
CREATE POLICY quiz_tinvites_read
  ON public.quiz_tournament_invites FOR SELECT TO authenticated
  USING (
    tenant_id = (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid())
    OR public.quiz_tournament_can_read(tournament_id)
  );
