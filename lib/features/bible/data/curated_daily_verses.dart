/// Curated, uplifting Verse-of-the-Day fallback set (KJV).
///
/// The authoritative daily rotation lives in the `daily_verse_pool` table and
/// is served by the `get_verse_of_the_day(p_date)` RPC. This compact, offline
/// copy is used ONLY when the RPC is unreachable (no network / not signed in).
/// It is deliberately small and every entry is a COMPLETE KJV sentence or
/// thought — never a contextless fragment — and deterministic per calendar day.
class CuratedDailyVerse {
  final String reference;
  final String text;
  final String theme;

  const CuratedDailyVerse(this.reference, this.text, this.theme);
}

const List<CuratedDailyVerse> kCuratedDailyVerses = [
  CuratedDailyVerse(
    'Jeremiah 29:11',
    'For I know the thoughts that I think toward you, saith the LORD, thoughts of peace, and not of evil, to give you an expected end.',
    'hope',
  ),
  CuratedDailyVerse(
    'John 3:16',
    'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
    'love',
  ),
  CuratedDailyVerse(
    'Philippians 4:13',
    'I can do all things through Christ which strengtheneth me.',
    'strength',
  ),
  CuratedDailyVerse(
    'Psalm 23:1',
    'The LORD is my shepherd; I shall not want.',
    'provision',
  ),
  CuratedDailyVerse(
    'John 14:27',
    'Peace I leave with you, my peace I give unto you: not as the world giveth, give I unto you. Let not your heart be troubled, neither let it be afraid.',
    'peace',
  ),
  CuratedDailyVerse(
    'Romans 8:28',
    'And we know that all things work together for good to them that love God, to them who are the called according to his purpose.',
    'hope',
  ),
  CuratedDailyVerse(
    'Psalm 46:1',
    'God is our refuge and strength, a very present help in trouble.',
    'strength',
  ),
  CuratedDailyVerse(
    '1 Corinthians 15:57',
    'But thanks be to God, which giveth us the victory through our Lord Jesus Christ.',
    'victory',
  ),
  CuratedDailyVerse(
    'Philippians 4:19',
    'But my God shall supply all your need according to his riches in glory by Christ Jesus.',
    'provision',
  ),
  CuratedDailyVerse(
    'Psalm 30:5',
    'For his anger endureth but a moment; in his favour is life: weeping may endure for a night, but joy cometh in the morning.',
    'joy',
  ),
  CuratedDailyVerse(
    'Isaiah 40:31',
    'But they that wait upon the LORD shall renew their strength; they shall mount up with wings as eagles; they shall run, and not be weary; and they shall walk, and not faint.',
    'strength',
  ),
  CuratedDailyVerse(
    '1 Thessalonians 5:18',
    'In every thing give thanks: for this is the will of God in Christ Jesus concerning you.',
    'gratitude',
  ),
  CuratedDailyVerse(
    'Proverbs 3:5-6',
    'Trust in the LORD with all thine heart; and lean not unto thine own understanding. In all thy ways acknowledge him, and he shall direct thy paths.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Isaiah 41:10',
    'Fear thou not; for I am with thee: be not dismayed; for I am thy God: I will strengthen thee; yea, I will help thee; yea, I will uphold thee with the right hand of my righteousness.',
    'strength',
  ),
  CuratedDailyVerse(
    'Galatians 5:22-23',
    'But the fruit of the Spirit is love, joy, peace, longsuffering, gentleness, goodness, faith, Meekness, temperance: against such there is no law.',
    'fruit_of_spirit',
  ),
  CuratedDailyVerse(
    'Psalm 91:1-2',
    'He that dwelleth in the secret place of the most High shall abide under the shadow of the Almighty. I will say of the LORD, He is my refuge and my fortress: my God; in him will I trust.',
    'protection',
  ),
  CuratedDailyVerse(
    'Matthew 11:28',
    'Come unto me, all ye that labour and are heavy laden, and I will give you rest.',
    'comfort',
  ),
  CuratedDailyVerse(
    'Romans 15:13',
    'Now the God of hope fill you with all joy and peace in believing, that ye may abound in hope, through the power of the Holy Ghost.',
    'hope',
  ),
  CuratedDailyVerse(
    'Psalm 34:8',
    'O taste and see that the LORD is good: blessed is the man that trusteth in him.',
    'faith',
  ),
  CuratedDailyVerse(
    'Philippians 4:6',
    'Be careful for nothing; but in every thing by prayer and supplication with thanksgiving let your requests be made known unto God.',
    'gratitude',
  ),
  CuratedDailyVerse(
    'Hebrews 13:5',
    'Let your conversation be without covetousness; and be content with such things as ye have: for he hath said, I will never leave thee, nor forsake thee.',
    'promise',
  ),
  CuratedDailyVerse(
    'Psalm 121:7-8',
    'The LORD shall preserve thee from all evil: he shall preserve thy soul. The LORD shall preserve thy going out and thy coming in from this time forth, and even for evermore.',
    'protection',
  ),
  CuratedDailyVerse(
    'Romans 12:12',
    'Rejoicing in hope; patient in tribulation; continuing instant in prayer;',
    'hope',
  ),
  CuratedDailyVerse(
    '2 Corinthians 5:7',
    'For we walk by faith, not by sight.',
    'faith',
  ),
  CuratedDailyVerse(
    'Psalm 100:4',
    'Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.',
    'gratitude',
  ),
  CuratedDailyVerse(
    'Isaiah 26:3',
    'Thou wilt keep him in perfect peace, whose mind is stayed on thee: because he trusteth in thee.',
    'peace',
  ),
  CuratedDailyVerse(
    'Psalm 118:24',
    'This is the day which the LORD hath made; we will rejoice and be glad in it.',
    'joy',
  ),
  CuratedDailyVerse(
    'Romans 8:37',
    'Nay, in all these things we are more than conquerors through him that loved us.',
    'victory',
  ),
  CuratedDailyVerse(
    'Psalm 119:105',
    'Thy word is a lamp unto my feet, and a light unto my path.',
    'guidance',
  ),
  CuratedDailyVerse(
    '1 John 1:9',
    'If we confess our sins, he is faithful and just to forgive us our sins, and to cleanse us from all unrighteousness.',
    'salvation',
  ),
  CuratedDailyVerse(
    'Psalm 143:8',
    'Cause me to hear thy lovingkindness in the morning; for in thee do I trust: cause me to know the way wherein I should walk; for I lift up my soul unto thee.',
    'morning',
  ),
  CuratedDailyVerse(
    'Proverbs 3:24',
    'When thou liest down, thou shalt not be afraid: yea, thou shalt lie down, and thy sleep shall be sweet.',
    'evening',
  ),
  CuratedDailyVerse(
    'Psalm 27:1',
    'The LORD is my light and my salvation; whom shall I fear? the LORD is the strength of my life; of whom shall I be afraid?',
    'strength',
  ),
  CuratedDailyVerse(
    'Ephesians 2:8',
    'For by grace are ye saved through faith; and that not of yourselves: it is the gift of God:',
    'salvation',
  ),
  CuratedDailyVerse(
    'Isaiah 43:2',
    'When thou passest through the waters, I will be with thee; and through the rivers, they shall not overflow thee: when thou walkest through the fire, thou shalt not be burned; neither shall the flame kindle upon thee.',
    'protection',
  ),
  CuratedDailyVerse(
    'Psalm 37:4',
    'Delight thyself also in the LORD; and he shall give thee the desires of thine heart.',
    'joy',
  ),
  CuratedDailyVerse(
    'John 16:33',
    'These things I have spoken unto you, that in me ye might have peace. In the world ye shall have tribulation: but be of good cheer; I have overcome the world.',
    'peace',
  ),
  CuratedDailyVerse(
    'Psalm 147:3',
    'He healeth the broken in heart, and bindeth up their wounds.',
    'comfort',
  ),
  CuratedDailyVerse(
    'Lamentations 3:22-23',
    'It is of the LORD\'s mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness.',
    'morning',
  ),
  CuratedDailyVerse(
    '1 Peter 5:7',
    'Casting all your care upon him; for he careth for you.',
    'comfort',
  ),
  CuratedDailyVerse(
    'Psalm 103:2',
    'Bless the LORD, O my soul, and forget not all his benefits:',
    'gratitude',
  ),
  CuratedDailyVerse(
    'Isaiah 12:2',
    'Behold, God is my salvation; I will trust, and not be afraid: for the LORD JEHOVAH is my strength and my song; he also is become my salvation.',
    'strength',
  ),
  CuratedDailyVerse(
    'Matthew 6:33',
    'But seek ye first the kingdom of God, and his righteousness; and all these things shall be added unto you.',
    'provision',
  ),
  CuratedDailyVerse(
    'Hebrews 11:1',
    'Now faith is the substance of things hoped for, the evidence of things not seen.',
    'faith',
  ),
  CuratedDailyVerse(
    'Psalm 5:3',
    'My voice shalt thou hear in the morning, O LORD; in the morning will I direct my prayer unto thee, and will look up.',
    'morning',
  ),
  CuratedDailyVerse(
    'Psalm 4:8',
    'I will both lay me down in peace, and sleep: for thou, LORD, only makest me dwell in safety.',
    'evening',
  ),
  CuratedDailyVerse(
    'Nehemiah 8:10',
    'Then he said unto them, Go your way, eat the fat, and drink the sweet, and send portions unto them for whom nothing is prepared: for this day is holy unto our Lord: neither be ye sorry; for the joy of the LORD is your strength.',
    'joy',
  ),
  CuratedDailyVerse(
    'Isaiah 41:13',
    'For I the LORD thy God will hold thy right hand, saying unto thee, Fear not; I will help thee.',
    'comfort',
  ),
  CuratedDailyVerse(
    'Psalm 34:18',
    'The LORD is nigh unto them that are of a broken heart; and saveth such as be of a contrite spirit.',
    'comfort',
  ),
  CuratedDailyVerse(
    'Hebrews 6:19',
    'Which hope we have as an anchor of the soul, both sure and stedfast, and which entereth into that within the veil;',
    'hope',
  ),
  CuratedDailyVerse(
    '2 Timothy 1:7',
    'For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.',
    'strength',
  ),
  CuratedDailyVerse(
    'Psalm 27:14',
    'Wait on the LORD: be of good courage, and he shall strengthen thine heart: wait, I say, on the LORD.',
    'strength',
  ),
  CuratedDailyVerse(
    'Psalm 28:7',
    'The LORD is my strength and my shield; my heart trusted in him, and I am helped: therefore my heart greatly rejoiceth; and with my song will I praise him.',
    'strength',
  ),
  CuratedDailyVerse(
    '1 John 5:4',
    'For whatsoever is born of God overcometh the world: and this is the victory that overcometh the world, even our faith.',
    'victory',
  ),
  CuratedDailyVerse(
    'John 15:13',
    'Greater love hath no man than this, that a man lay down his life for his friends.',
    'love',
  ),
  CuratedDailyVerse(
    'Psalm 71:14',
    'But I will hope continually, and will yet praise thee more and more.',
    'hope',
  ),
  CuratedDailyVerse(
    'Psalm 19:14',
    'Let the words of my mouth, and the meditation of my heart, be acceptable in thy sight, O LORD, my strength, and my redeemer.',
    'praise',
  ),
  CuratedDailyVerse(
    'James 1:5',
    'If any of you lack wisdom, let him ask of God, that giveth to all men liberally, and upbraideth not; and it shall be given him.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Numbers 6:24-26',
    'The LORD bless thee, and keep thee: The LORD make his face shine upon thee, and be gracious unto thee: The LORD lift up his countenance upon thee, and give thee peace.',
    'peace',
  ),
  CuratedDailyVerse(
    'Psalm 37:5',
    'Commit thy way unto the LORD; trust also in him; and he shall bring it to pass.',
    'guidance',
  ),
];

/// Deterministic offline fallback: same verse for everyone all day.
CuratedDailyVerse curatedVerseForDate(DateTime date) {
  final day = DateTime(date.year, date.month, date.day)
      .difference(DateTime(2024, 1, 1))
      .inDays;
  final n = kCuratedDailyVerses.length;
  final idx = ((day % n) + n) % n;
  return kCuratedDailyVerses[idx];
}
