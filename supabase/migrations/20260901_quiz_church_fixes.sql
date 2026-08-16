-- 20260901: Quiz & church fixes
-- 1. get_quiz_leaderboard: p_tenant_id was UUID but tenant ids can be TEXT
--    seed codes (zm_1 etc.) -> invalid-uuid exception -> catch -> empty
--    world rank. Recreate with TEXT param (body already compares via ::text).
-- 2. Rock of Ages Chapel Kabulonga: real treasurer + pastor phones
--    (placeholder +260975000001 was used for payouts/tithe routing).

-- ── 1. get_quiz_leaderboard (TEXT tenant id) ──────────────────────────────
DROP FUNCTION IF EXISTS public.get_quiz_leaderboard(INT, UUID, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.get_quiz_leaderboard(INTEGER, UUID, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.get_quiz_leaderboard(
  p_limit INT DEFAULT 10,
  p_tenant_id TEXT DEFAULT NULL,
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
           COUNT(*) FILTER (WHERE qq.correct_answer IS NOT NULL AND pa.selected_answer = qq.correct_answer) AS correct,
           COUNT(DISTINCT pa.match_id) AS games
    FROM public.pvp_answers pa
    LEFT JOIN public.quiz_questions qq ON qq.id = pa.question_id
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
    SELECT uid, SUM(correct)::BIGINT AS total_correct, SUM(games)::BIGINT AS total_games
    FROM merged
    GROUP BY uid
  )
  SELECT
    t.uid,
    COALESCE(p.full_name, 'Quiz Player')::TEXT AS full_name,
    COALESCE(t.total_correct, 0)::BIGINT AS correct_answers,
    COALESCE(t.total_games, 0)::BIGINT AS games_played,
    CASE WHEN t.total_games > 0
         THEN ROUND(t.total_correct::NUMERIC / t.total_games * 100, 1)
         ELSE 0 END AS best_accuracy
  FROM totals t
  LEFT JOIN public.profiles p ON p.id = t.uid
  WHERE (p_tenant_id IS NULL OR p.tenant_id::text = p_tenant_id)
  ORDER BY correct_answers DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 100);
END;
$$;
ALTER FUNCTION public.get_quiz_leaderboard(INT, TEXT, TIMESTAMPTZ) OWNER TO postgres;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, TEXT, TIMESTAMPTZ) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_quiz_leaderboard(INT, TEXT, TIMESTAMPTZ) TO authenticated;

-- ── 2. Rock of Ages Chapel Kabulonga contacts ─────────────────────────────
UPDATE public.churches
SET treasurer_phone = '+260779686480',
    pastor_phone    = '+260977745186'
WHERE slug = 'rock-of-ages-kabulonga';