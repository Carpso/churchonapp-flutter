-- Quiz leaderboard by actual quiz performance (not coins).
-- Aggregates correct answers from PvP matches + daily challenges.

-- 1. Ensure daily_challenge_results exists (referenced by the app but never
-- created by any migration).
CREATE TABLE IF NOT EXISTS public.daily_challenge_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  challenge_id UUID,
  score INT DEFAULT 0,
  correct_count INT DEFAULT 0,
  is_correct BOOLEAN DEFAULT false,
  total_questions INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.daily_challenge_results ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'daily_challenge_results' AND cmd = 'SELECT') THEN
    CREATE POLICY "daily_challenge_results_select_own" ON public.daily_challenge_results
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'daily_challenge_results' AND cmd = 'INSERT') THEN
    CREATE POLICY "daily_challenge_results_insert_own" ON public.daily_challenge_results
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- 2. Aggregate RPC: returns top quiz performers by correct answers.
CREATE OR REPLACE FUNCTION public.get_quiz_leaderboard(
  p_limit INT DEFAULT 10,
  p_tenant_id UUID DEFAULT NULL
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  correct_answers BIGINT,
  games_played BIGINT,
  best_accuracy NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH correct AS (
    SELECT pa.player_id AS uid, COUNT(*) FILTER (WHERE pa.is_correct) AS correct,
           COUNT(*) AS games
    FROM public.pvp_answers pa
    GROUP BY pa.player_id
  ),
  challenge AS (
    SELECT dc.user_id AS uid,
           COUNT(*) FILTER (WHERE dc.is_correct) AS correct,
           COUNT(*) AS games
    FROM public.daily_challenge_results dc
    GROUP BY dc.user_id
  ),
  merged AS (
    SELECT uid, correct, games FROM correct
    UNION ALL
    SELECT uid, correct, games FROM challenge
  ),
  totals AS (
    SELECT uid, SUM(correct) AS total_correct, SUM(games) AS total_games
    FROM merged
    GROUP BY uid
  )
  SELECT
    t.uid,
    COALESCE(p.full_name, 'Quiz Player')::TEXT AS full_name,
    COALESCE(t.total_correct, 0) AS correct_answers,
    COALESCE(t.total_games, 0) AS games_played,
    CASE WHEN t.total_games > 0 THEN ROUND(t.total_correct::NUMERIC / t.total_games * 100, 1) ELSE 0 END AS best_accuracy
  FROM totals t
  LEFT JOIN public.profiles p ON p.id = t.uid
  WHERE (p_tenant_id IS NULL OR p.tenant_id::text = p_tenant_id::text)
  ORDER BY correct_answers DESC
  LIMIT p_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID) TO authenticated;
