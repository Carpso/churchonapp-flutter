-- Fix quiz world rank: daily_challenge_results was created earlier without
-- the is_correct column, so get_quiz_leaderboard errored (42703) and the app
-- showed "N/A". Also makes the leaderboard weekly-scoped ("new winners every
-- Monday") and counts games as distinct matches, not individual answers.

-- 1. Ensure daily_challenge_results has the columns the aggregator reads.
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS is_correct BOOLEAN DEFAULT false;
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS score INT DEFAULT 0;
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS correct_count INT DEFAULT 0;
ALTER TABLE public.daily_challenge_results
  ADD COLUMN IF NOT EXISTS total_questions INT DEFAULT 0;

-- 2. Rebuild the leaderboard RPC: weekly window + distinct-match game count.
DROP FUNCTION IF EXISTS public.get_quiz_leaderboard(INT, UUID);

CREATE OR REPLACE FUNCTION public.get_quiz_leaderboard(
  p_limit INT DEFAULT 10,
  p_tenant_id UUID DEFAULT NULL,
  p_since TIMESTAMPTZ DEFAULT NULL
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
  WITH pvp AS (
    SELECT pa.player_id AS uid,
           COUNT(*) FILTER (WHERE pa.is_correct) AS correct,
           COUNT(DISTINCT pa.match_id) AS games
    FROM public.pvp_answers pa
    WHERE (p_since IS NULL OR pa.created_at >= p_since)
    GROUP BY pa.player_id
  ),
  challenge AS (
    SELECT dc.user_id AS uid,
           COALESCE(SUM(dc.correct_count), 0)::BIGINT AS correct,
           COUNT(*) AS games
    FROM public.daily_challenge_results dc
    WHERE (p_since IS NULL OR dc.completed_at >= p_since)
    GROUP BY dc.user_id
  ),
  merged AS (
    SELECT uid, correct, games FROM pvp
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
    CASE WHEN t.total_games > 0
         THEN ROUND(t.total_correct::NUMERIC / t.total_games * 100, 1)
         ELSE 0 END AS best_accuracy
  FROM totals t
  LEFT JOIN public.profiles p ON p.id = t.uid
  WHERE (p_tenant_id IS NULL OR p.tenant_id::text = p_tenant_id::text)
  ORDER BY correct_answers DESC
  LIMIT p_limit;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ) TO authenticated;
