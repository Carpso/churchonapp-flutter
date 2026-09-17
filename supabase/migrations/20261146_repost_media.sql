-- ============================================================================
-- 20261146_repost_media.sql
-- Reposts dropped the post's picture/media: `repost_post` inserted only
-- (user_id, content, tenant_id, repost_of), so a reposted post rendered with
-- no image. Copy the media columns from the original.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.repost_post(p_post_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_tenant    uuid;
  v_original  public.social_posts%ROWTYPE;
  v_existing  uuid;
  v_new_id    uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_original FROM public.social_posts WHERE id = p_post_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Post not found'; END IF;

  IF v_original.user_id = v_uid THEN
    RAISE EXCEPTION 'You cannot repost your own post';
  END IF;

  SELECT id INTO v_existing
    FROM public.social_posts
   WHERE repost_of = p_post_id AND user_id = v_uid
   LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT tenant_id::uuid INTO v_tenant FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.social_posts
    (user_id, content, tenant_id, repost_of, media_url, media_type, images)
  VALUES
    (v_uid, NULL, v_tenant, p_post_id,
     v_original.media_url, v_original.media_type, v_original.images)
  RETURNING id INTO v_new_id;

  UPDATE public.social_posts
     SET repost_count = COALESCE(repost_count, 0) + 1
   WHERE id = p_post_id;

  RETURN v_new_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.repost_post(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.repost_post(uuid) TO authenticated;
