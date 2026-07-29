-- Seed bible_books (66 books) and bible_audio_files (1189 R2 paths)
-- Paste this into Supabase Dashboard SQL Editor

-- Step 1: Insert all 66 Bible books
INSERT INTO bible_books (name, abbreviation, testament, book_order, testament_order, chapters) VALUES
('Genesis', 'Gen', 'OT', 1, 'OT', 50),
('Exodus', 'Exod', 'OT', 2, 'OT', 40),
('Leviticus', 'Lev', 'OT', 3, 'OT', 27),
('Numbers', 'Num', 'OT', 4, 'OT', 36),
('Deuteronomy', 'Deut', 'OT', 5, 'OT', 34),
('Joshua', 'Josh', 'OT', 6, 'OT', 24),
('Judges', 'Judg', 'OT', 7, 'OT', 21),
('Ruth', 'Ruth', 'OT', 8, 'OT', 4),
('1 Samuel', '1 Sam', 'OT', 9, 'OT', 31),
('2 Samuel', '2 Sam', 'OT', 10, 'OT', 24),
('1 Kings', '1 Kgs', 'OT', 11, 'OT', 22),
('2 Kings', '2 Kgs', 'OT', 12, 'OT', 25),
('1 Chronicles', '1 Chr', 'OT', 13, 'OT', 29),
('2 Chronicles', '2 Chr', 'OT', 14, 'OT', 36),
('Ezra', 'Ezra', 'OT', 15, 'OT', 10),
('Nehemiah', 'Neh', 'OT', 16, 'OT', 13),
('Esther', 'Esth', 'OT', 17, 'OT', 10),
('Job', 'Job', 'OT', 18, 'OT', 42),
('Psalms', 'Ps', 'OT', 19, 'OT', 150),
('Proverbs', 'Prov', 'OT', 20, 'OT', 31),
('Ecclesiastes', 'Eccl', 'OT', 21, 'OT', 12),
('Song of Solomon', 'Song', 'OT', 22, 'OT', 8),
('Isaiah', 'Isa', 'OT', 23, 'OT', 66),
('Jeremiah', 'Jer', 'OT', 24, 'OT', 52),
('Lamentations', 'Lam', 'OT', 25, 'OT', 5),
('Ezekiel', 'Ezek', 'OT', 26, 'OT', 48),
('Daniel', 'Dan', 'OT', 27, 'OT', 12),
('Hosea', 'Hos', 'OT', 28, 'OT', 14),
('Joel', 'Joel', 'OT', 29, 'OT', 3),
('Amos', 'Amos', 'OT', 30, 'OT', 9),
('Obadiah', 'Obad', 'OT', 31, 'OT', 1),
('Jonah', 'Jonah', 'OT', 32, 'OT', 4),
('Micah', 'Mic', 'OT', 33, 'OT', 7),
('Nahum', 'Nah', 'OT', 34, 'OT', 3),
('Habakkuk', 'Hab', 'OT', 35, 'OT', 3),
('Zephaniah', 'Zeph', 'OT', 36, 'OT', 3),
('Haggai', 'Hag', 'OT', 37, 'OT', 2),
('Zechariah', 'Zech', 'OT', 38, 'OT', 14),
('Malachi', 'Mal', 'OT', 39, 'OT', 4),
('Matthew', 'Matt', 'NT', 40, 'NT', 28),
('Mark', 'Mark', 'NT', 41, 'NT', 16),
('Luke', 'Luke', 'NT', 42, 'NT', 24),
('John', 'John', 'NT', 43, 'NT', 21),
('Acts', 'Acts', 'NT', 44, 'NT', 28),
('Romans', 'Rom', 'NT', 45, 'NT', 16),
('1 Corinthians', '1 Cor', 'NT', 46, 'NT', 16),
('2 Corinthians', '2 Cor', 'NT', 47, 'NT', 13),
('Galatians', 'Gal', 'NT', 48, 'NT', 6),
('Ephesians', 'Eph', 'NT', 49, 'NT', 6),
('Philippians', 'Phil', 'NT', 50, 'NT', 4),
('Colossians', 'Col', 'NT', 51, 'NT', 4),
('1 Thessalonians', '1 Thess', 'NT', 52, 'NT', 5),
('2 Thessalonians', '2 Thess', 'NT', 53, 'NT', 3),
('1 Timothy', '1 Tim', 'NT', 54, 'NT', 6),
('2 Timothy', '2 Tim', 'NT', 55, 'NT', 4),
('Titus', 'Titus', 'NT', 56, 'NT', 3),
('Philemon', 'Phlm', 'NT', 57, 'NT', 1),
('Hebrews', 'Heb', 'NT', 58, 'NT', 13),
('James', 'Jas', 'NT', 59, 'NT', 5),
('1 Peter', '1 Pet', 'NT', 60, 'NT', 5),
('2 Peter', '2 Pet', 'NT', 61, 'NT', 3),
('1 John', '1 John', 'NT', 62, 'NT', 5),
('2 John', '2 John', 'NT', 63, 'NT', 1),
('3 John', '3 John', 'NT', 64, 'NT', 1),
('Jude', 'Jude', 'NT', 65, 'NT', 1),
('Revelation', 'Rev', 'NT', 66, 'NT', 22)
ON CONFLICT (name) DO NOTHING;

-- Step 2: Insert all 1189 audio file records
-- This uses a cross join between KJV translation and all books with generate_series for chapters
INSERT INTO bible_audio_files (translation_id, book_id, chapter, storage_provider, storage_bucket, storage_path, format, generation_status)
SELECT 
    t.id AS translation_id,
    b.id AS book_id,
    ch.chapter,
    'r2' AS storage_provider,
    'choa-sermons-vault' AS storage_bucket,
    'audio/kjv/' || b.name || '/' || lpad(ch.chapter::text, 3, '0') || '.mp3' AS storage_path,
    'mp3' AS format,
    'completed' AS generation_status
FROM bible_translations t
CROSS JOIN bible_books b
CROSS JOIN LATERAL generate_series(1, b.chapters) AS ch(chapter)
WHERE t.code = 'kjv'
ON CONFLICT (translation_id, book_id, chapter, storage_provider) DO NOTHING;
