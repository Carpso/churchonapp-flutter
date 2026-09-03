-- 20261004: Include Solo/Free practice answers in the global CC leaderboard.
--
-- The Global Church Coin Leaderboard (get_quiz_cc_leaderboard, created 20260904)
-- only counted PvP + daily-challenge answers, so players who only play Solo
-- practice "games" showed "0 correct . 0 games" no matter how well they answered.
--
-- This recreates the function to ALSO count Solo play from
-- user_answered_questions (rows where match_id IS NULL AND event_id IS NULL).
-- A single solo game is inserted as one batch that shares the same answered_at
-- timestamp (INSERT uses DEFAULT now()), so COUNT(DISTINCT answered_at) is a
-- reliable proxy for "games played".

CREATE OR REPLACE FUNCTION public.get_quiz_cc_leaderboard(
  p_limit INT DEFAULT 50,
  p_min_coins INT DEFAULT 0
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  avatar_url TEXT,
  church_name TEXT,
  coins BIGINT,
  correct_answers BIGINT,
  games_played BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
BEGIN
  RETURN QUERY
  WITH activity AS (
    -- PvP answers (one row per answered question)
    SELECT pa.player_id AS uid,
           COUNT(*) FILTER (WHERE qq.correct_answer IS NOT NULL
                             AND pa.selected_answer = qq.correct_answer) AS correct,
           COUNT(DISTINCT pa.match_id) AS games
    FROM public.pvp_answers pa
    LEFT JOIN public.quiz_questions qq ON qq.id = pa.question_id
    GROUP BY pa.player_id
    UNION ALL
    -- Daily challenge results
    SELECT dc.user_id AS uid,
           COALESCE(SUM(dc.correct_count), 0)::BIGINT AS correct,
           COUNT(*) AS games
    FROM public.daily_challenge_results dc
    GROUP BY dc.user_id
    UNION ALL
    -- Solo / free-practice answers (no match, no event). A single solo game is
    -- inserted as one batch sharing the same answered_at, so distinct
    -- answered_at = games played.
    SELECT ua.user_id AS uid,
           COUNT(*) FILTER (WHERE ua.is_correct) AS correct,
           COUNT(DISTINCT ua.answered_at) AS games
    FROM public.user_answered_questions ua
    WHERE ua.match_id IS NULL AND ua.event_id IS NULL
    GROUP BY ua.user_id
  ),
  totals AS (
    SELECT uid,
           SUM(correct)::BIGINT AS correct,
           SUM(games)::BIGINT AS games
    FROM activity
    GROUP BY uid
  )
  SELECT
    p.id AS user_id,
    COALESCE(p.full_name, 'Quiz Player')::TEXT AS full_name,
    COALESCE(p.avatar_url, '')::TEXT AS avatar_url,
    COALESCE(t.name, '')::TEXT AS church_name,
    COALESCE(p.coins, 0)::BIGINT AS coins,
    COALESCE(a.correct, 0)::BIGINT AS correct_answers,
    COALESCE(a.games, 0)::BIGINT AS games_played
  FROM public.profiles p
  LEFT JOIN public.tenants t ON t.id::text = p.tenant_id::text
  LEFT JOIN totals a ON a.uid = p.id
  WHERE p.tenant_id IS NOT NULL
    AND COALESCE(p.coins, 0) >= COALESCE(p_min_coins, 0)
    AND NOT COALESCE(p.hide_from_leaderboard, false)
  ORDER BY p.coins DESC, a.correct DESC NULLS LAST, p.full_name ASC
  LIMIT v_limit;
END;
$$;
ALTER FUNCTION public.get_quiz_cc_leaderboard(INT, INT) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_quiz_cc_leaderboard(INT, INT) TO authenticated;
