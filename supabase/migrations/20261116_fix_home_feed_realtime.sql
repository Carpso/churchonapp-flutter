-- Fix home-feed realtime: kingdom_news was never added to the realtime
-- publication, so the Writers section (which uses a realtime .stream()) always
-- rendered empty even though 10 published rows exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'kingdom_news'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kingdom_news;
  END IF;
END $$;

-- Realtime RLS-filtered streams need full row replica identity so updates
-- carry the full row (status/author_id) for the SELECT policy to evaluate.
ALTER TABLE public.kingdom_news REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'sermons'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sermons;
  END IF;
END $$;

ALTER TABLE public.sermons REPLICA IDENTITY FULL;
ALTER TABLE public.events REPLICA IDENTITY FULL;
ALTER TABLE public.marketplace_items REPLICA IDENTITY FULL;
