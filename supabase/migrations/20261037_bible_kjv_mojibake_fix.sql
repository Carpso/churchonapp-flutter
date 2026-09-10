-- 20261037: Fix mojibake apostrophes in KJV bible_verses
-- The KJV seed migrations had double-encoded UTF-8 producing 'â€™' where
-- a straight apostrophe ' should appear. ~1997 verses affected.
-- This is idempotent — safe to re-run.

UPDATE bible_verses
SET text = REPLACE(text, E'â€™', '''')
WHERE translation_id = (SELECT id FROM bible_translations WHERE code = 'kjv')
  AND text LIKE E'%â€™%';

UPDATE bible_verses
SET text = REPLACE(text, E'â€˜', '''')
WHERE translation_id = (SELECT id FROM bible_translations WHERE code = 'kjv')
  AND text LIKE E'%â€˜%';

UPDATE bible_verses
SET text = REPLACE(text, E'â€œ', '"')
WHERE translation_id = (SELECT id FROM bible_translations WHERE code = 'kjv')
  AND text LIKE E'%â€œ%';

UPDATE bible_verses
SET text = REPLACE(text, E'â€\x9d', '"')
WHERE translation_id = (SELECT id FROM bible_translations WHERE code = 'kjv')
  AND text LIKE E'%â€\x9d%';

-- Log affected rows count
DO $$
DECLARE affected INT;
BEGIN
  SELECT count(*) INTO affected FROM bible_verses
  WHERE translation_id = (SELECT id FROM bible_translations WHERE code = 'kjv')
    AND (text LIKE E'%â€™%' OR text LIKE E'%â€˜%' OR text LIKE E'%â€œ%');
  RAISE NOTICE 'Bible mojibake fix: % remaining affected rows', affected;
END $$;
