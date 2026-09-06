-- ═══════════════════════════════════════════════════════════════
-- Atomic engagement counters for Connect (Klips + Feed)
-- Replaces client-side read-modify-write updates, which lost concurrent
-- updates (two people tapping Amen at once = one Amen recorded) and let a
-- stale local count overwrite the server value.
-- Deltas are clamped to +/-1 and counts never go below zero.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.increment_klip_amen(p_klip_id UUID, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_delta IS NULL OR p_delta NOT IN (-1, 1) THEN
    RAISE EXCEPTION 'Invalid delta';
  END IF;

  UPDATE public.klips
     SET amen_count = GREATEST(0, COALESCE(amen_count, 0) + p_delta)
   WHERE id = p_klip_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_klip_comments(p_klip_id UUID, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_delta IS NULL OR p_delta NOT IN (-1, 1) THEN
    RAISE EXCEPTION 'Invalid delta';
  END IF;

  UPDATE public.klips
     SET comments_count = GREATEST(0, COALESCE(comments_count, 0) + p_delta)
   WHERE id = p_klip_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_post_likes(p_post_id UUID, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_delta IS NULL OR p_delta NOT IN (-1, 1) THEN
    RAISE EXCEPTION 'Invalid delta';
  END IF;

  UPDATE public.social_posts
     SET likes_count = GREATEST(0, COALESCE(likes_count, 0) + p_delta)
   WHERE id = p_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_post_comments(p_post_id UUID, p_delta INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_delta IS NULL OR p_delta NOT IN (-1, 1) THEN
    RAISE EXCEPTION 'Invalid delta';
  END IF;

  UPDATE public.social_posts
     SET comments_count = GREATEST(0, COALESCE(comments_count, 0) + p_delta)
   WHERE id = p_post_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_klip_amen(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_klip_comments(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_post_likes(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_post_comments(UUID, INT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.increment_klip_amen(UUID, INT) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_klip_comments(UUID, INT) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_post_likes(UUID, INT) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_post_comments(UUID, INT) FROM anon, PUBLIC;
