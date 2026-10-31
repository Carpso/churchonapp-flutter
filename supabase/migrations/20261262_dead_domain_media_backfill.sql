-- ============================================================================
-- 20261262 — DEAD-DOMAIN MEDIA BACKFILL
--
-- Root cause of "church social posts not showing pictures": every stored media
-- URL points at https://media.churchonapp.com — the custom domain that LAPSED.
-- The objects are intact in R2 (bucket choa-sermons-vault) and the enabled
-- dev domain https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev serves the
-- same bucket-root keys (verified HTTP 200 on sampled posts, flyers, klips).
--
-- Fix: rewrite the host in every stored URL. Paired with:
--  * server secret R2_PUBLIC_DOMAIN repointed to the r2.dev domain, so
--    r2-sign returns working publicUrls for all FUTURE uploads;
--  * client R2Service rewriting both legacy hosts as belt-and-braces.
--
-- When the churchonapp.com domain is restored, only the secret/.env need
-- flipping back — these rewritten rows keep working either way is NOT true
-- (they point at r2.dev), so restoring the custom domain does not require
-- another backfill: r2.dev keeps serving regardless.
-- ============================================================================

-- Text columns (exact-host prefix replace; YouTube/CF-Stream/other URLs untouched)
UPDATE public.social_posts   SET media_url      = replace(media_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE media_url LIKE '%media.churchonapp.com%';
UPDATE public.profiles       SET avatar_url     = replace(avatar_url,     'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE avatar_url LIKE '%media.churchonapp.com%';
UPDATE public.sermons        SET thumbnail_url  = replace(thumbnail_url,  'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE thumbnail_url LIKE '%media.churchonapp.com%';
UPDATE public.sermons        SET video_url      = replace(video_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE video_url LIKE '%media.churchonapp.com%';
UPDATE public.sermons        SET archive_url    = replace(archive_url,    'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE archive_url LIKE '%media.churchonapp.com%';
UPDATE public.sermons        SET audio_url      = replace(audio_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE audio_url LIKE '%media.churchonapp.com%';
UPDATE public.marketplace_items SET image       = replace(image,          'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE image LIKE '%media.churchonapp.com%';
UPDATE public.events         SET image_url      = replace(image_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE image_url LIKE '%media.churchonapp.com%';
UPDATE public.churches       SET logo           = replace(logo,           'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE logo LIKE '%media.churchonapp.com%';
UPDATE public.churches       SET logo_url       = replace(logo_url,       'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE logo_url LIKE '%media.churchonapp.com%';
UPDATE public.churches       SET banner_url     = replace(banner_url,     'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE banner_url LIKE '%media.churchonapp.com%';
UPDATE public.klips          SET video_url      = replace(video_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE video_url LIKE '%media.churchonapp.com%';
UPDATE public.klips          SET thumbnail_url  = replace(thumbnail_url,  'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE thumbnail_url LIKE '%media.churchonapp.com%';
UPDATE public.klips          SET user_avatar    = replace(user_avatar,    'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE user_avatar LIKE '%media.churchonapp.com%';
UPDATE public.kingdom_news   SET image_url      = replace(image_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE image_url LIKE '%media.churchonapp.com%';
UPDATE public.special_offers SET image_url      = replace(image_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE image_url LIKE '%media.churchonapp.com%';
UPDATE public.partner_offers SET image_url      = replace(image_url,      'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE image_url LIKE '%media.churchonapp.com%';
UPDATE public.partner_tenants SET logo_url      = replace(logo_url,       'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE logo_url LIKE '%media.churchonapp.com%';
UPDATE public.bookshops      SET logo_url       = replace(logo_url,       'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE logo_url LIKE '%media.churchonapp.com%';
UPDATE public.live_streams   SET thumbnail_url  = replace(thumbnail_url,  'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE thumbnail_url LIKE '%media.churchonapp.com%';
UPDATE public.live_streams   SET overlay_logo_url = replace(overlay_logo_url, 'https://media.churchonapp.com', 'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev') WHERE overlay_logo_url LIKE '%media.churchonapp.com%';

-- images text[] (element-wise host replace)
UPDATE public.social_posts
   SET images = (
     SELECT coalesce(array_agg(replace(x, 'https://media.churchonapp.com',
                                        'https://pub-21d3ac216bf140caa31c8dbd2241eb61.r2.dev')), '{}')
       FROM unnest(images) AS x
   )
 WHERE images IS NOT NULL AND images::text LIKE '%media.churchonapp.com%';

-- Verification: zero dead-domain references may remain in any audited column.
DO $$
DECLARE
  v_left integer := 0;
BEGIN
  SELECT (SELECT count(*) FROM social_posts WHERE media_url LIKE '%media.churchonapp.com%' OR images::text LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM profiles WHERE avatar_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM sermons WHERE thumbnail_url LIKE '%media.churchonapp.com%' OR video_url LIKE '%media.churchonapp.com%' OR archive_url LIKE '%media.churchonapp.com%' OR audio_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM marketplace_items WHERE image LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM events WHERE image_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM churches WHERE logo LIKE '%media.churchonapp.com%' OR logo_url LIKE '%media.churchonapp.com%' OR banner_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM klips WHERE video_url LIKE '%media.churchonapp.com%' OR thumbnail_url LIKE '%media.churchonapp.com%' OR user_avatar LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM kingdom_news WHERE image_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM special_offers WHERE image_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM partner_offers WHERE image_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM partner_tenants WHERE logo_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM bookshops WHERE logo_url LIKE '%media.churchonapp.com%')
       + (SELECT count(*) FROM live_streams WHERE thumbnail_url LIKE '%media.churchonapp.com%' OR overlay_logo_url LIKE '%media.churchonapp.com%')
    INTO v_left;
  IF v_left > 0 THEN
    RAISE EXCEPTION 'VERIFICATION FAILED: % dead-domain URL(s) remain', v_left;
  END IF;
  RAISE NOTICE 'dead-domain media backfill complete: 0 references remain';
END;
$$;
