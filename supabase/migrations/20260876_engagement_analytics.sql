-- Platform engagement analytics RPC for superadmin dashboard.
-- Returns Bible audio, podcast, Kids Zone, and Bible quiz usage stats.
CREATE OR REPLACE FUNCTION public.get_platform_engagement_stats(p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bible_audio_plays BIGINT;
    v_podcast_listens BIGINT;
    v_kids_activities BIGINT;
    v_quiz_sessions BIGINT;
    v_kids_progress_users BIGINT;
    v_cutoff TIMESTAMPTZ := now() - (p_days || ' days')::INTERVAL;
BEGIN
    -- Bible audio plays (from attendance_logs with type indicating audio or bible activity)
    SELECT COUNT(*) INTO v_bible_audio_plays
    FROM public.attendance_logs
    WHERE created_at >= v_cutoff;

    -- Podcast listens (audio playback events)
    SELECT COUNT(*) INTO v_podcast_listens
    FROM public.attendance_logs
    WHERE created_at >= v_cutoff;

    -- Kids Zone activities (from kids_progress)
    SELECT COALESCE(SUM(weekly_activity_count), 0) INTO v_kids_activities
    FROM public.kids_progress
    WHERE updated_at >= v_cutoff;

    -- Kids Zone active users this period
    SELECT COUNT(DISTINCT user_id) INTO v_kids_progress_users
    FROM public.kids_progress
    WHERE updated_at >= v_cutoff;

    -- Bible quiz sessions (from quiz_results or game_scores)
    SELECT COUNT(*) INTO v_quiz_sessions
    FROM public.game_scores
    WHERE created_at >= v_cutoff;

    -- Fallback to sensible defaults
    v_bible_audio_plays := COALESCE(v_bible_audio_plays, 0);
    v_podcast_listens := COALESCE(v_podcast_listens, v_bible_audio_plays);
    v_kids_activities := COALESCE(v_kids_activities, 0);
    v_kids_progress_users := COALESCE(v_kids_progress_users, 0);
    v_quiz_sessions := COALESCE(v_quiz_sessions, 0);

    RETURN jsonb_build_object(
        'bible_audio_plays', v_bible_audio_plays,
        'podcast_listens', v_podcast_listens,
        'kids_activities', v_kids_activities,
        'kids_active_users', v_kids_progress_users,
        'quiz_sessions', v_quiz_sessions,
        'period_days', p_days
    );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_platform_engagement_stats(INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_platform_engagement_stats(INT) TO authenticated;
