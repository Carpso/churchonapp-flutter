-- 20260899: Sermons UI metadata — category + duration_minutes columns
-- Used by the enhanced Sermons tab (hero card, category filter, metadata chips).

ALTER TABLE public.sermons
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'General',
  ADD COLUMN IF NOT EXISTS duration_minutes INT;

UPDATE public.sermons SET category = 'Worship', duration_minutes = 45 WHERE title ILIKE '%The Foundation of Faith%';
UPDATE public.sermons SET category = 'Spiritual Growth', duration_minutes = 38 WHERE title ILIKE '%Walking in the Spirit%';
UPDATE public.sermons SET category = 'Prayer', duration_minutes = 52 WHERE title ILIKE '%Power of Prayer%';
UPDATE public.sermons SET category = 'Grace', duration_minutes = 40 WHERE title ILIKE '%Grace That Transforms%';
UPDATE public.sermons SET category = 'Faith', duration_minutes = 47 WHERE title ILIKE '%Faith in Action%';
UPDATE public.sermons SET category = 'Bible Study', duration_minutes = 55 WHERE title ILIKE '%Living Word%';
UPDATE public.sermons SET category = 'Hope', duration_minutes = 44 WHERE title ILIKE '%Hope of Glory%';