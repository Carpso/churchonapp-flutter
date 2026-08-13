-- ═══════════════════════════════════════════════════════════════════════════════
-- DEDUPLICATE kids_zone_resources
-- Seed migrations left multiple copies of each kids story/resource. This keeps
-- exactly one row per (title, category), preferring self-hosted R2 audio URLs
-- (media.churchonapp.com) over external links.
-- ═══════════════════════════════════════════════════════════════════════════════

DELETE FROM public.kids_zone_resources
WHERE id NOT IN (
  SELECT id FROM (
    SELECT DISTINCT ON (title, category) id
    FROM public.kids_zone_resources
    ORDER BY
      title,
      category,
      CASE WHEN content_url LIKE '%media.churchonapp.com%' THEN 0 ELSE 1 END,
      id DESC
  ) keepers
);
