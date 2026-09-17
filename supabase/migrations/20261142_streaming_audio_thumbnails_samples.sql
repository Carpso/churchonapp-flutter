-- ============================================================================
-- 20261142_streaming_audio_thumbnails_samples.sql
-- Audio-only live streams + thumbnails, realtime for notes, verse_notes
-- uniqueness, marketplace delete-policy guard, and PLAYABLE sample sermons.
--
-- WHY:
--   * Live streams had no thumbnail (list items were text-only) and no way to
--     broadcast audio-only.
--   * `verse_notes` / `user_notes` were never added to the realtime publication,
--     so highlight/delete changes never propagated to the UI.
--   * The sample sermons were YouTube URLs which many owners block from
--     embedding → they did not play in-app (and the only escape was leaving to
--     YouTube, losing view tracking). They are replaced with self-hosted,
--     publicly-playable MP4 samples on R2 (`media.churchonapp.com/sermons/`).
-- ============================================================================

-- ── 1. live_streams: thumbnail + audio-only ─────────────────────────────────
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS thumbnail_url text,
  ADD COLUMN IF NOT EXISTS is_audio_only boolean NOT NULL DEFAULT false;

-- 20261109 revoked table-level SELECT and granted an explicit column list.
-- New columns must be added to that list or viewers cannot read them.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'live_streams'
  ) THEN
    REVOKE SELECT ON public.live_streams FROM anon, authenticated;
    GRANT SELECT (
      id, church_id, title, description, status, streaming_backend,
      scheduled_at, started_at, ended_at, hls_url, dash_url, preview_url,
      viewer_count, created_at, cloudflare_video_id,
      thumbnail_url, is_audio_only
    ) ON public.live_streams TO anon, authenticated;
  END IF;
END $$;

-- ── 2. Realtime for note/highlight tables ───────────────────────────────────
ALTER TABLE public.verse_notes REPLICA IDENTITY FULL;
ALTER TABLE public.user_notes  REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.verse_notes;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notes;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END $$;

-- ── 3. verse_notes: one row per (user, book, chapter, verse) ────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'ux_verse_notes_user_book_chapter_verse'
  ) AND NOT EXISTS (
    SELECT 1 FROM public.verse_notes
    GROUP BY user_id, book_id, chapter, verse
    HAVING count(*) > 1
  ) THEN
    CREATE UNIQUE INDEX ux_verse_notes_user_book_chapter_verse
      ON public.verse_notes (user_id, book_id, chapter, verse);
  END IF;
END $$;

-- ── 4. Marketplace: ensure the vendor DELETE policy exists ──────────────────
-- 20260878 created it WITHOUT a DROP guard and deploy.ps1 continues after a
-- failed migration, so if that file ever aborted the policy is missing and a
-- vendor can never delete their own listing. Recreate idempotently.
DROP POLICY IF EXISTS "Vendors can delete own items" ON public.marketplace_items;
CREATE POLICY "Vendors can delete own items" ON public.marketplace_items
  FOR DELETE TO authenticated
  USING (auth.uid() = vendor_id);

-- ── 5. Replace unplayable YouTube sample sermons with self-hosted samples ───
ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS viewer_count integer DEFAULT 0;
ALTER TABLE public.sermons ADD COLUMN IF NOT EXISTS description text;

-- Remove the global (church-less) YouTube samples.
DELETE FROM public.sermons
 WHERE church_id IS NULL
   AND (video_url LIKE '%youtube.com%' OR video_url LIKE '%youtu.be%');

-- Seed playable samples hosted on R2 (public, CORS-enabled).
INSERT INTO public.sermons
  (title, preacher, speaker, description, video_url, thumbnail_url, category,
   is_live, viewer_count, duration_minutes, created_at)
SELECT v.title, v.preacher, v.preacher, v.descr, v.video_url, v.thumb,
       v.category, false, 0, v.dur, now() - (v.days || ' day')::interval
FROM (VALUES
  ('Welcome to Church On App', 'Church On App Team',
   'A short sample sermon so you can see how sermons look and play in the app.',
   'https://media.churchonapp.com/sermons/sample_welcome.mp4',
   'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800',
   'Getting Started', 1, 1),
  ('Sunday Celebration — Sample', 'Church On App Team',
   'A sample Sunday celebration sermon. Replace with your own uploads.',
   'https://media.churchonapp.com/sermons/sample_sunday.mp4',
   'https://images.unsplash.com/photo-1544427920-c49ccfb85579?w=800',
   'Apostolic Teaching', 1, 2),
  ('Bible Study — Sample', 'Church On App Team',
   'A sample Bible study session. Replace with your own uploads.',
   'https://media.churchonapp.com/sermons/sample_bible_study.mp4',
   'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=800',
   'Bible Study', 1, 3)
) AS v(title, preacher, descr, video_url, thumb, category, dur, days)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sermons s
  WHERE s.church_id IS NULL AND s.title = v.title
);
