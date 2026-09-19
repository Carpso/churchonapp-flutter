-- ============================================================================
-- 20261201_daily_verse_pool.sql
-- Verse of the Day — curated, thematic rotation.
--
-- WHY:
--   * The old VOTD picked a pseudo-random row from `bible_verses` by index
--     (dayIndex % 31102). That surfaced contextless fragments ("And he said…")
--     and genealogies, so the daily verse often read as nonsense.
--   * `daily_bible_verses` was never seeded and `postDailyVerse` was a no-op.
--
-- FIX:
--   * `daily_verse_pool` — a real, curated dataset of complete, uplifting KJV
--     verses grouped by theme (hope / love / joy / peace / strength /
--     protection / victory / gratitude / morning / evening / fruit of the
--     Spirit / comfort / provision / faith / guidance / salvation / praise).
--   * `get_verse_of_the_day(p_date)` rotates deterministically: the same verse
--     for everyone all day, and because the pool is >= 120 entries the full
--     cycle is longer than 60 days (no verse repeats within ~60 days).
--   * The client consumes the RPC and falls back to a small built-in uplifting
--     set when offline — never to random `bible_verses` rows.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.daily_verse_pool (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference  text NOT NULL UNIQUE,
  verse_text text NOT NULL,
  theme      text NOT NULL DEFAULT 'hope',
  book       text,
  chapter    integer,
  verse      integer,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_daily_verse_pool_active
  ON public.daily_verse_pool (theme) WHERE is_active;

ALTER TABLE public.daily_verse_pool ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone reads daily verse pool" ON public.daily_verse_pool;
CREATE POLICY "Anyone reads daily verse pool" ON public.daily_verse_pool
  FOR SELECT TO anon, authenticated USING (true);

GRANT SELECT ON public.daily_verse_pool TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- Seed: complete, uplifting KJV verses (idempotent by reference)
-- ---------------------------------------------------------------------------
INSERT INTO public.daily_verse_pool (reference, verse_text, theme, book, chapter, verse) VALUES
-- HOPE
('Jeremiah 29:11', $v$For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.$v$, 'hope', 'Jeremiah', 29, 11),
('Romans 15:13', $v$Now the God of hope fill you with all joy and peace in believing, that ye may abound in hope, through the power of the Holy Ghost.$v$, 'hope', 'Romans', 15, 13),
('Psalm 42:11', $v$Why art thou cast down, O my soul? and why art thou disquieted within me? hope thou in God: for I shall yet praise him, who is the health of my countenance, and my God.$v$, 'hope', 'Psalm', 42, 11),
('Lamentations 3:22-23', $v$It is of the LORD's mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness.$v$, 'hope', 'Lamentations', 3, 22),
('Hebrews 6:19', $v$Which hope we have as an anchor of the soul, both sure and stedfast, and which entereth into that within the veil;$v$, 'hope', 'Hebrews', 6, 19),
('Psalm 71:14', $v$But I will hope continually, and will yet praise thee more and more.$v$, 'hope', 'Psalm', 71, 14),
('Romans 8:28', $v$And we know that all things work together for good to them that love God, to them who are the called according to his purpose.$v$, 'hope', 'Romans', 8, 28),
('Titus 2:13', $v$Looking for that blessed hope, and the glorious appearing of the great God and our Saviour Jesus Christ;$v$, 'hope', 'Titus', 2, 13),
('Proverbs 23:18', $v$For surely there is an end; and thine expectation shall not be cut off.$v$, 'hope', 'Proverbs', 23, 18),
('Psalm 130:5', $v$I wait for the LORD, my soul doth wait, and in his word do I hope.$v$, 'hope', 'Psalm', 130, 5),
('Romans 5:5', $v$And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the Holy Ghost which is given unto us.$v$, 'hope', 'Romans', 5, 5),
('Psalm 39:7', $v$And now, Lord, what wait I for? my hope is in thee.$v$, 'hope', 'Psalm', 39, 7),
-- LOVE
('John 3:16', $v$For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.$v$, 'love', 'John', 3, 16),
('1 John 4:8', $v$He that loveth not knoweth not God; for God is love.$v$, 'love', '1 John', 4, 8),
('1 John 4:18', $v$There is no fear in love; but perfect love casteth out fear: because fear hath torment. He that feareth is not made perfect in love.$v$, 'love', '1 John', 4, 18),
('Romans 5:8', $v$But God commendeth his love toward us, in that, while we were yet sinners, Christ died for us.$v$, 'love', 'Romans', 5, 8),
('John 15:13', $v$Greater love hath no man than this, that a man lay down his life for his friends.$v$, 'love', 'John', 15, 13),
('1 Corinthians 13:13', $v$And now abideth faith, hope, charity, these three; but the greatest of these is charity.$v$, 'love', '1 Corinthians', 13, 13),
('1 Peter 4:8', $v$And above all things have fervent charity among yourselves: for charity shall cover the multitude of sins.$v$, 'love', '1 Peter', 4, 8),
('Jeremiah 31:3', $v$The LORD hath appeared of old unto me, saying, Yea, I have loved thee with an everlasting love: therefore with lovingkindness have I drawn thee.$v$, 'love', 'Jeremiah', 31, 3),
('Ephesians 3:19', $v$And to know the love of Christ, which passeth knowledge, that ye might be filled with all the fulness of God.$v$, 'love', 'Ephesians', 3, 19),
('Psalm 136:1', $v$O give thanks unto the LORD; for he is good: for his mercy endureth for ever.$v$, 'love', 'Psalm', 136, 1),
-- JOY
('Nehemiah 8:10', $v$Then he said unto them, Go your way, eat the fat, and drink the sweet, and send portions unto them for whom nothing is prepared: for this day is holy unto our Lord: neither be ye sorry; for the joy of the LORD is your strength.$v$, 'joy', 'Nehemiah', 8, 10),
('Psalm 30:5', $v$For his anger endureth but a moment; in his favour is life: weeping may endure for a night, but joy cometh in the morning.$v$, 'joy', 'Psalm', 30, 5),
('Psalm 16:11', $v$Thou wilt shew me the path of life: in thy presence is fulness of joy; at thy right hand there are pleasures for evermore.$v$, 'joy', 'Psalm', 16, 11),
('John 16:22', $v$And ye now therefore have sorrow: but I will see you again, and your heart shall rejoice, and your joy no man taketh from you.$v$, 'joy', 'John', 16, 22),
('Philippians 4:4', $v$Rejoice in the Lord alway: and again I say, Rejoice.$v$, 'joy', 'Philippians', 4, 4),
('Psalm 118:24', $v$This is the day which the LORD hath made; we will rejoice and be glad in it.$v$, 'joy', 'Psalm', 118, 24),
('Isaiah 12:3', $v$Therefore with joy shall ye draw water out of the wells of salvation.$v$, 'joy', 'Isaiah', 12, 3),
('Habakkuk 3:18', $v$Yet I will rejoice in the LORD, I will joy in the God of my salvation.$v$, 'joy', 'Habakkuk', 3, 18),
('Psalm 126:3', $v$The LORD hath done great things for us; whereof we are glad.$v$, 'joy', 'Psalm', 126, 3),
('Isaiah 55:12', $v$For ye shall go out with joy, and be led forth with peace: the mountains and the hills shall break forth before you into singing, and all the trees of the field shall clap their hands.$v$, 'joy', 'Isaiah', 55, 12),
('Psalm 33:1', $v$Rejoice in the LORD, O ye righteous: for praise is comely for the upright.$v$, 'joy', 'Psalm', 33, 1),
-- PEACE
('John 14:27', $v$Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid.$v$, 'peace', 'John', 14, 27),
('Philippians 4:7', $v$And the peace of God, which passeth all understanding, shall keep your hearts and minds through Christ Jesus.$v$, 'peace', 'Philippians', 4, 7),
('Isaiah 26:3', $v$Thou wilt keep him in perfect peace, whose mind is stayed on thee: because he trusteth in thee.$v$, 'peace', 'Isaiah', 26, 3),
('Psalm 4:8', $v$I will both lay me down in peace, and sleep: for thou, LORD, only makest me dwell in safety.$v$, 'peace', 'Psalm', 4, 8),
('Romans 5:1', $v$Therefore being justified by faith, we have peace with God through our Lord Jesus Christ:$v$, 'peace', 'Romans', 5, 1),
('Colossians 3:15', $v$And let the peace of God rule in your hearts, to the which also ye are called in one body; and be ye thankful.$v$, 'peace', 'Colossians', 3, 15),
('Numbers 6:24-26', $v$The LORD bless thee, and keep thee: The LORD make his face shine upon thee, and be gracious unto thee: The LORD lift up his countenance upon thee, and give thee peace.$v$, 'peace', 'Numbers', 6, 24),
('Psalm 29:11', $v$The LORD will give strength unto his people; the LORD will bless his people with peace.$v$, 'peace', 'Psalm', 29, 11),
('John 16:33', $v$These things I have spoken unto you, that in me ye might have peace. In the world ye shall have tribulation: but be of good cheer; I have overcome the world.$v$, 'peace', 'John', 16, 33),
('2 Thessalonians 3:16', $v$Now the Lord of peace himself give you peace always by all means. The Lord be with you all.$v$, 'peace', '2 Thessalonians', 3, 16),
('Isaiah 54:10', $v$For the mountains shall depart, and the hills be removed; but my kindness shall not depart from thee, neither shall the covenant of my peace be removed, saith the LORD that hath mercy on thee.$v$, 'peace', 'Isaiah', 54, 10),
-- STRENGTH
('Philippians 4:13', $v$I can do all things through Christ which strengtheneth me.$v$, 'strength', 'Philippians', 4, 13),
('Isaiah 40:31', $v$But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.$v$, 'strength', 'Isaiah', 40, 31),
('Psalm 46:1', $v$God is our refuge and strength, a very present help in trouble.$v$, 'strength', 'Psalm', 46, 1),
('Isaiah 41:10', $v$Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee; yea, I will uphold thee with the right hand of my righteousness.$v$, 'strength', 'Isaiah', 41, 10),
('Psalm 27:1', $v$The LORD is my light and my salvation; whom shall I fear? the LORD is the strength of my life; of whom shall I be afraid?$v$, 'strength', 'Psalm', 27, 1),
('2 Corinthians 12:9', $v$And he said unto me, My grace is sufficient for thee: for my strength is made perfect in weakness. Most gladly therefore will I rather glory in my infirmities, that the power of Christ may rest upon me.$v$, 'strength', '2 Corinthians', 12, 9),
('Psalm 18:2', $v$The LORD is my rock, and my fortress, and my deliverer; my God, my strength, in whom I will trust; my buckler, and the horn of my salvation, and my high tower.$v$, 'strength', 'Psalm', 18, 2),
('Ephesians 6:10', $v$Finally, my brethren, be strong in the Lord, and in the power of his might.$v$, 'strength', 'Ephesians', 6, 10),
('Psalm 73:26', $v$My flesh and my heart faileth: but God is the strength of my heart, and my portion for ever.$v$, 'strength', 'Psalm', 73, 26),
('Isaiah 12:2', $v$Behold, God is my salvation; I will trust, and not be afraid: for the LORD JEHOVAH is my strength and my song; he also is become my salvation.$v$, 'strength', 'Isaiah', 12, 2),
('Habakkuk 3:19', $v$The LORD God is my strength, and he will make my feet like hinds' feet, and he will make me to walk upon mine high places.$v$, 'strength', 'Habakkuk', 3, 19),
('Psalm 28:7', $v$The LORD is my strength and my shield; my heart trusted in him, and I am helped: therefore my heart greatly rejoiceth; and with my song will I praise him.$v$, 'strength', 'Psalm', 28, 7),
('Psalm 27:14', $v$Wait on the LORD: be of good courage, and he shall strengthen thine heart: wait, I say, on the LORD.$v$, 'strength', 'Psalm', 27, 14),
('Psalm 31:24', $v$Be of good courage, and he shall strengthen your heart, all ye that hope in the LORD.$v$, 'strength', 'Psalm', 31, 24),
('2 Timothy 1:7', $v$For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.$v$, 'strength', '2 Timothy', 1, 7),
-- PROTECTION
('Psalm 91:1-2', $v$He that dwelleth in the secret place of the most High shall abide under the shadow of the Almighty. I will say of the LORD, He is my refuge and my fortress: my God; in him will I trust.$v$, 'protection', 'Psalm', 91, 1),
('Psalm 121:7-8', $v$The LORD shall preserve thee from all evil: he shall preserve thy soul. The LORD shall preserve thy going out and thy coming in from this time forth, and even for evermore.$v$, 'protection', 'Psalm', 121, 7),
('Proverbs 18:10', $v$The name of the LORD is a strong tower: the righteous runneth into it, and is safe.$v$, 'protection', 'Proverbs', 18, 10),
('Psalm 34:7', $v$The angel of the LORD encampeth round about them that fear him, and delivereth them.$v$, 'protection', 'Psalm', 34, 7),
('2 Thessalonians 3:3', $v$But the Lord is faithful, who shall stablish you, and keep you from evil.$v$, 'protection', '2 Thessalonians', 3, 3),
('Psalm 125:2', $v$As the mountains are round about Jerusalem, so the LORD is round about his people from henceforth even for ever.$v$, 'protection', 'Psalm', 125, 2),
('Isaiah 43:2', $v$When thou passest through the waters, I will be with thee; and through the rivers, they shall not overflow thee: when thou walkest through the fire, thou shalt not be burned; neither shall the flame kindle upon thee.$v$, 'protection', 'Isaiah', 43, 2),
('Psalm 32:7', $v$Thou art my hiding place; thou shalt preserve me from trouble; thou shalt compass me about with songs of deliverance. Selah.$v$, 'protection', 'Psalm', 32, 7),
('Psalm 46:10', $v$Be still, and know that I am God: I will be exalted among the heathen, I will be exalted in the earth.$v$, 'protection', 'Psalm', 46, 10),
('Psalm 91:11-12', $v$For he shall give his angels charge over thee, to keep thee in all thy ways. They shall bear thee up in their hands, lest thou dash thy foot against a stone.$v$, 'protection', 'Psalm', 91, 11),
('Deuteronomy 31:8', $v$And the LORD, he it is that doth go before thee; he will be with thee, he will not fail thee, neither forsake thee: fear not, neither be dismayed.$v$, 'protection', 'Deuteronomy', 31, 8),
-- VICTORY / TRIUMPH
('1 Corinthians 15:57', $v$But thanks be to God, which giveth us the victory through our Lord Jesus Christ.$v$, 'victory', '1 Corinthians', 15, 57),
('Romans 8:37', $v$Nay, in all these things we are more than conquerors through him that loved us.$v$, 'victory', 'Romans', 8, 37),
('2 Corinthians 2:14', $v$Now thanks be unto God, which always causeth us to triumph in Christ, and maketh manifest the savour of his knowledge by us in every place.$v$, 'victory', '2 Corinthians', 2, 14),
('1 John 5:4', $v$For whatsoever is born of God overcometh the world: and this is the victory that overcometh the world, even our faith.$v$, 'victory', '1 John', 5, 4),
('Deuteronomy 20:4', $v$For the LORD your God is he that goeth with you, to fight for you against your enemies, to save you.$v$, 'victory', 'Deuteronomy', 20, 4),
('Exodus 14:14', $v$The LORD shall fight for you, and ye shall hold your peace.$v$, 'victory', 'Exodus', 14, 14),
('2 Samuel 22:33', $v$God is my strength and power: and he maketh my way perfect.$v$, 'victory', '2 Samuel', 22, 33),
('Psalm 118:15', $v$The voice of rejoicing and salvation is in the tabernacles of the righteous: the right hand of the LORD doeth valiantly.$v$, 'victory', 'Psalm', 118, 15),
('Revelation 12:11', $v$And they overcame him by the blood of the Lamb, and by the word of their testimony; and they loved not their lives unto the death.$v$, 'victory', 'Revelation', 12, 11),
('Isaiah 54:17', $v$No weapon that is formed against thee shall prosper; and every tongue that shall rise against thee in judgment thou shalt condemn. This is the heritage of the servants of the LORD, and their righteousness is of me, saith the LORD.$v$, 'victory', 'Isaiah', 54, 17),
('Psalm 18:39', $v$For thou hast girded me with strength unto the battle: thou hast subdued under me those that rose up against me.$v$, 'victory', 'Psalm', 18, 39),
('Romans 8:31', $v$What shall we then say to these things? If God be for us, who can be against us?$v$, 'victory', 'Romans', 8, 31),
-- GRATITUDE / THANKSGIVING
('1 Thessalonians 5:18', $v$In every thing give thanks: for this is the will of God in Christ Jesus concerning you.$v$, 'gratitude', '1 Thessalonians', 5, 18),
('Psalm 100:4', $v$Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.$v$, 'gratitude', 'Psalm', 100, 4),
('Colossians 3:17', $v$And whatsoever ye do in word or deed, do all in the name of the Lord Jesus, giving thanks to God and the Father by him.$v$, 'gratitude', 'Colossians', 3, 17),
('Psalm 107:1', $v$O give thanks unto the LORD, for he is good: for his mercy endureth for ever.$v$, 'gratitude', 'Psalm', 107, 1),
('Philippians 4:6', $v$Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.$v$, 'gratitude', 'Philippians', 4, 6),
('Psalm 103:2', $v$Bless the LORD, O my soul, and forget not all his benefits:$v$, 'gratitude', 'Psalm', 103, 2),
('Psalm 34:1', $v$I will bless the LORD at all times: his praise shall continually be in my mouth.$v$, 'gratitude', 'Psalm', 34, 1),
('Psalm 136:26', $v$O give thanks unto the God of heaven: for his mercy endureth for ever.$v$, 'gratitude', 'Psalm', 136, 26),
('Colossians 2:7', $v$Rooted and built up in him, and stablished in the faith, as ye have been taught, abounding therein with thanksgiving.$v$, 'gratitude', 'Colossians', 2, 7),
-- MORNING
('Psalm 143:8', $v$Cause me to hear thy lovingkindness in the morning; for in thee do I trust: cause me to know the way wherein I should walk; for I lift up my soul unto thee.$v$, 'morning', 'Psalm', 143, 8),
('Psalm 5:3', $v$My voice shalt thou hear in the morning, O LORD; in the morning will I direct my prayer unto thee, and will look up.$v$, 'morning', 'Psalm', 5, 3),
('Psalm 59:16', $v$But I will sing of thy power; yea, I will sing aloud of thy mercy in the morning: for thou hast been my defence and refuge in the day of my trouble.$v$, 'morning', 'Psalm', 59, 16),
('Isaiah 33:2', $v$O LORD, be gracious unto us; we have waited for thee: be thou their arm every morning, our salvation also in the time of trouble.$v$, 'morning', 'Isaiah', 33, 2),
('Psalm 90:14', $v$O satisfy us early with thy mercy; that we may rejoice and be glad all our days.$v$, 'morning', 'Psalm', 90, 14),
('Psalm 141:2', $v$Let my prayer be set forth before thee as incense; and the lifting up of my hands as the evening sacrifice.$v$, 'evening', 'Psalm', 141, 2),
-- EVENING
('Psalm 63:6', $v$When I remember thee upon my bed, and meditate on thee in the night watches.$v$, 'evening', 'Psalm', 63, 6),
('Psalm 121:3-4', $v$He will not suffer thy foot to be moved: he that keepeth thee will not slumber. Behold, he that keepeth Israel shall neither slumber nor sleep.$v$, 'evening', 'Psalm', 121, 3),
('Psalm 3:5', $v$I laid me down and slept; I awaked; for the LORD sustained me.$v$, 'evening', 'Psalm', 3, 5),
('Proverbs 3:24', $v$When thou liest down, thou shalt not be afraid: yea, thou shalt lie down, and thy sleep shall be sweet.$v$, 'evening', 'Proverbs', 3, 24),
('Psalm 127:2', $v$It is vain for you to rise up early, to sit up late, to eat the bread of sorrows: for so he giveth his beloved sleep.$v$, 'evening', 'Psalm', 127, 2),
-- FRUIT OF THE SPIRIT
('Galatians 5:22-23', $v$But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith, Meekness, temperance: against such there is no law.$v$, 'fruit_of_spirit', 'Galatians', 5, 22),
('Galatians 5:25', $v$If we live in the Spirit, let us also walk in the Spirit.$v$, 'fruit_of_spirit', 'Galatians', 5, 25),
('Romans 8:6', $v$For to be carnally minded is death; but to be spiritually minded is life and peace.$v$, 'fruit_of_spirit', 'Romans', 8, 6),
('2 Corinthians 5:17', $v$Therefore if any man be in Christ, he is a new creature: old things are passed away; behold, all things are become new.$v$, 'fruit_of_spirit', '2 Corinthians', 5, 17),
('Ephesians 5:9', $v$For the fruit of the Spirit is in all goodness and righteousness and truth;$v$, 'fruit_of_spirit', 'Ephesians', 5, 9),
('Colossians 3:12', $v$Put on therefore, as the elect of God, holy and beloved, bowels of mercies, kindness, humbleness of mind, meekness, longsuffering;$v$, 'fruit_of_spirit', 'Colossians', 3, 12),
('Ephesians 4:32', $v$And be ye kind one to another, tenderhearted, forgiving one another, even as God for Christ's sake hath forgiven you.$v$, 'fruit_of_spirit', 'Ephesians', 4, 32),
('Romans 12:10', $v$Be kindly affectioned one to another with brotherly love; in honour preferring one another;$v$, 'fruit_of_spirit', 'Romans', 12, 10),
('James 3:17', $v$But the wisdom that is from above is first pure, then peaceable, gentle, and easy to be intreated, full of mercy and good fruits, without partiality, and without hypocrisy.$v$, 'fruit_of_spirit', 'James', 3, 17),
('1 Peter 1:22', $v$Seeing ye have purified your souls in obeying the truth through the Spirit unto unfeigned love of the brethren, see that ye love one another with a pure heart fervently:$v$, 'fruit_of_spirit', '1 Peter', 1, 22),
-- COMFORT
('Matthew 11:28', $v$Come unto me, all ye that labour and are heavy laden, and I will give you rest.$v$, 'comfort', 'Matthew', 11, 28),
('2 Corinthians 1:3', $v$Blessed be God, even the Father of our Lord Jesus Christ, the Father of mercies, and the God of all comfort;$v$, 'comfort', '2 Corinthians', 1, 3),
('Psalm 34:18', $v$The LORD is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.$v$, 'comfort', 'Psalm', 34, 18),
('Isaiah 41:13', $v$For I the LORD thy God will hold thy right hand, saying unto thee, Fear not; I will help thee.$v$, 'comfort', 'Isaiah', 41, 13),
('Psalm 147:3', $v$He healeth the broken in heart, and bindeth up their wounds.$v$, 'comfort', 'Psalm', 147, 3),
('Psalm 55:22', $v$Cast thy burden upon the LORD, and he shall sustain thee: he shall never suffer the righteous to be moved.$v$, 'comfort', 'Psalm', 55, 22),
('Matthew 5:4', $v$Blessed are they that mourn: for they shall be comforted.$v$, 'comfort', 'Matthew', 5, 4),
('Psalm 94:19', $v$In the multitude of my thoughts within me thy comforts delight my soul.$v$, 'comfort', 'Psalm', 94, 19),
('2 Corinthians 4:16', $v$For which cause we faint not; but though our outward man perish, yet the inward man is renewed day by day.$v$, 'comfort', '2 Corinthians', 4, 16),
('2 Corinthians 4:18', $v$While we look not at the things which are seen, but at the things which are not seen: for the things which are seen are temporal; but the things which are not seen are eternal.$v$, 'comfort', '2 Corinthians', 4, 18),
('1 Peter 5:7', $v$Casting all your care upon him; for he careth for you.$v$, 'comfort', '1 Peter', 5, 7),
-- PROVISION
('Philippians 4:19', $v$But my God shall supply all your need according to his riches in glory by Christ Jesus.$v$, 'provision', 'Philippians', 4, 19),
('Matthew 6:33', $v$But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you.$v$, 'provision', 'Matthew', 6, 33),
('Psalm 23:1', $v$The LORD is my shepherd; I shall not want.$v$, 'provision', 'Psalm', 23, 1),
('Psalm 37:25', $v$I have been young, and now am old; yet have I not seen the righteous forsaken, nor his seed begging bread.$v$, 'provision', 'Psalm', 37, 25),
('Psalm 145:15', $v$The eyes of all wait upon thee; and thou givest them their meat in due season.$v$, 'provision', 'Psalm', 145, 15),
('Isaiah 58:11', $v$And the LORD shall guide thee continually, and satisfy thy soul in drought, and make fat thy bones: and thou shalt be like a watered garden, and like a spring of water, whose waters fail not.$v$, 'provision', 'Isaiah', 58, 11),
('Malachi 3:10', $v$Bring ye all the tithes into the storehouse, that there may be meat in mine house, and prove me now herewith, saith the LORD of hosts, if I will not open you the windows of heaven, and pour you out a blessing, that there shall not be room enough to receive it.$v$, 'provision', 'Malachi', 3, 10),
('Psalm 84:11', $v$For the LORD God is a sun and shield: the LORD will give grace and glory: no good thing will he withhold from them that walk uprightly.$v$, 'provision', 'Psalm', 84, 11),
-- FAITH
('Hebrews 11:1', $v$Now faith is the substance of things hoped for, the evidence of things not seen.$v$, 'faith', 'Hebrews', 11, 1),
('2 Corinthians 5:7', $v$For we walk by faith, not by sight.$v$, 'faith', '2 Corinthians', 5, 7),
('Mark 11:24', $v$Therefore I say unto you, What things soever ye desire, when ye pray, believe that ye receive them, and ye shall have them.$v$, 'faith', 'Mark', 11, 24),
('Psalm 34:8', $v$O taste and see that the LORD is good: blessed is the man that trusteth in him.$v$, 'faith', 'Psalm', 34, 8),
('Romans 10:17', $v$So then faith cometh by hearing, and hearing by the word of God.$v$, 'faith', 'Romans', 10, 17),
('1 John 5:14', $v$And this is the confidence that we have in him, that, if we ask any thing according to his will, he heareth us:$v$, 'faith', '1 John', 5, 14),
('Proverbs 16:3', $v$Commit thy works unto the LORD, and thy thoughts shall be established.$v$, 'faith', 'Proverbs', 16, 3),
-- GUIDANCE
('Proverbs 3:5-6', $v$Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.$v$, 'guidance', 'Proverbs', 3, 5),
('Psalm 119:105', $v$Thy word is a lamp unto my feet, and a light unto my path.$v$, 'guidance', 'Psalm', 119, 105),
('Psalm 32:8', $v$I will instruct thee and teach thee in the way which thou shalt go: I will guide thee with mine eye.$v$, 'guidance', 'Psalm', 32, 8),
('James 1:5', $v$If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.$v$, 'guidance', 'James', 1, 5),
('Isaiah 30:21', $v$And thine ears shall hear a word behind thee, saying, This is the way, walk ye in it, when ye turn to the right hand, and when ye turn to the left.$v$, 'guidance', 'Isaiah', 30, 21),
('Psalm 37:5', $v$Commit thy way unto the LORD; trust also in him; and he shall bring it to pass.$v$, 'guidance', 'Psalm', 37, 5),
('Psalm 37:23', $v$The steps of a good man are ordered by the LORD: and he delighteth in his way.$v$, 'guidance', 'Psalm', 37, 23),
('John 8:12', $v$Then spake Jesus again unto them, saying, I am the light of the world: he that followeth me shall not walk in darkness, but shall have the light of life.$v$, 'guidance', 'John', 8, 12),
-- SALVATION
('Romans 10:9', $v$That if thou shalt confess with thy mouth the Lord Jesus, and shalt believe in thine heart that God hath raised him from the dead, thou shalt be saved.$v$, 'salvation', 'Romans', 10, 9),
('Ephesians 2:8', $v$For by grace are ye saved through faith; and that not of yourselves: it is the gift of God:$v$, 'salvation', 'Ephesians', 2, 8),
('John 10:10', $v$The thief cometh not, but for to steal, and to kill, and to destroy: I am come that they might have life, and that they might have it more abundantly.$v$, 'salvation', 'John', 10, 10),
('1 John 1:9', $v$If we confess our sins, he is faithful and just to forgive us our sins, and to cleanse us from all unrighteousness.$v$, 'salvation', '1 John', 1, 9),
('Isaiah 1:18', $v$Come now, and let us reason together, saith the LORD: though your sins be as scarlet, they shall be as white as snow; though they be red like crimson, they shall be as wool.$v$, 'salvation', 'Isaiah', 1, 18),
('2 Corinthians 5:21', $v$For he hath made him to be sin for us, who knew no sin; that we might be made the righteousness of God in him.$v$, 'salvation', '2 Corinthians', 5, 21),
('Acts 4:12', $v$Neither is there salvation in any other: for there is none other name under heaven given among men, whereby we must be saved.$v$, 'salvation', 'Acts', 4, 12),
('John 5:24', $v$Verily, verily, I say unto you, He that heareth my word, and believeth on him that sent me, hath everlasting life, and shall not come into condemnation; but is passed from death unto life.$v$, 'salvation', 'John', 5, 24),
-- PRAISE
('Psalm 150:1-2', $v$Praise ye the LORD. Praise God in his sanctuary: praise him in the firmament of his power. Praise him for his mighty acts: praise him according to his excellent greatness.$v$, 'praise', 'Psalm', 150, 1),
('Psalm 96:1-2', $v$O sing unto the LORD a new song: sing unto the LORD, all the earth. Sing unto the LORD, bless his name; shew forth his salvation from day to day.$v$, 'praise', 'Psalm', 96, 1),
('Psalm 150:6', $v$Let every thing that hath breath praise the LORD. Praise ye the LORD.$v$, 'praise', 'Psalm', 150, 6),
('Psalm 19:14', $v$Let the words of my mouth, and the meditation of my heart, be acceptable in thy sight, O LORD, my strength, and my redeemer.$v$, 'praise', 'Psalm', 19, 14),
('Psalm 103:8', $v$The LORD is merciful and gracious, slow to anger, and plenteous in mercy.$v$, 'praise', 'Psalm', 103, 8),
('Psalm 86:15', $v$But thou, O Lord, art a God full of compassion, and gracious, longsuffering, and plenteous in mercy and truth.$v$, 'praise', 'Psalm', 86, 15),
-- PROMISE / FAITHFULNESS
('1 Corinthians 10:13', $v$There hath no temptation taken you but such as is common to man: but God is faithful, who will not suffer you to be tempted above that ye are able; but will with the temptation also make a way to escape, that ye may be able to bear it.$v$, 'promise', '1 Corinthians', 10, 13),
('Hebrews 13:5', $v$Let your conversation be without covetousness; and be content with such things as ye have: for he hath said, I will never leave thee, nor forsake thee.$v$, 'promise', 'Hebrews', 13, 5),
('Psalm 37:4', $v$Delight thyself also in the LORD; and he shall give thee the desires of thine heart.$v$, 'promise', 'Psalm', 37, 4),
('Romans 12:12', $v$Rejoicing in hope; patient in tribulation; continuing instant in prayer;$v$, 'promise', 'Romans', 12, 12),
('Psalm 145:18', $v$The LORD is nigh unto all them that call upon him, to all that call upon him in truth.$v$, 'promise', 'Psalm', 145, 18),
('Zephaniah 3:17', $v$The LORD thy God in the midst of thee is mighty; he will save, he will rejoice over thee with joy; he will rest in his love, he will joy over thee with singing.$v$, 'promise', 'Zephaniah', 3, 17)
ON CONFLICT (reference) DO UPDATE SET
  verse_text = EXCLUDED.verse_text,
  theme = EXCLUDED.theme,
  book = EXCLUDED.book,
  chapter = EXCLUDED.chapter,
  verse = EXCLUDED.verse,
  is_active = true;

-- ---------------------------------------------------------------------------
-- Deterministic daily rotation RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_verse_of_the_day(p_date date DEFAULT CURRENT_DATE)
RETURNS TABLE (
  reference  text,
  verse_text text,
  theme      text,
  book       text,
  chapter    integer,
  verse      integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
  v_day   bigint;
  v_idx   integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.daily_verse_pool WHERE is_active;
  IF v_count = 0 THEN
    RETURN;
  END IF;

  -- Stable anchor so the same calendar day yields the same verse for everyone.
  v_day := (COALESCE(p_date, CURRENT_DATE) - DATE '2024-01-01');
  -- Guard against negative modulo for dates before the anchor.
  v_idx := ((v_day % v_count) + v_count) % v_count;

  RETURN QUERY
    SELECT p.reference, p.verse_text, p.theme, p.book, p.chapter, p.verse
      FROM public.daily_verse_pool p
     WHERE p.is_active
     ORDER BY md5(p.reference)
     OFFSET v_idx LIMIT 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_verse_of_the_day(date) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.get_verse_of_the_day(date) TO authenticated;
