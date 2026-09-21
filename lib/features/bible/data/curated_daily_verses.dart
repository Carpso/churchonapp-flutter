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
  CuratedDailyVerse(
    'Exodus 15:26',
    'And said, If thou wilt diligently hearken to the voice of the LORD thy God, and wilt do that which is right in his sight, and wilt give ear to his commandments, and keep all his statutes, I will put none of these diseases upon thee, which I have brought upon the Egyptians: for I am the LORD that healeth thee.',
    'healing',
  ),
  CuratedDailyVerse(
    'Isaiah 53:5',
    'But he was wounded for our transgressions, he was bruised for our iniquities: the chastisement of our peace was upon him; and with his stripes we are healed.',
    'healing',
  ),
  CuratedDailyVerse(
    'Jeremiah 17:14',
    'Heal me, O LORD, and I shall be healed; save me, and I shall be saved: for thou art my praise.',
    'healing',
  ),
  CuratedDailyVerse(
    'Psalm 107:20',
    'He sent his word, and healed them, and delivered them from their destructions.',
    'healing',
  ),
  CuratedDailyVerse(
    'Proverbs 17:22',
    'A merry heart doeth good like a medicine: but a broken spirit drieth the bones.',
    'healing',
  ),
  CuratedDailyVerse(
    'James 5:16',
    'Confess your faults one to another, and pray one for another, that ye may be healed. The effectual fervent prayer of a righteous man availeth much.',
    'healing',
  ),
  CuratedDailyVerse(
    'Ecclesiastes 7:8',
    'Better is the end of a thing than the beginning thereof: and the patient in spirit is better than the proud in spirit.',
    'patience',
  ),
  CuratedDailyVerse(
    'Galatians 6:9',
    'And let us not be weary in well doing: for in due season we shall reap, if we faint not.',
    'patience',
  ),
  CuratedDailyVerse(
    'Psalm 37:7',
    'Rest in the LORD, and wait patiently for him: fret not thyself because of him who prospereth in his way, because of the man who bringeth wicked devices to pass.',
    'patience',
  ),
  CuratedDailyVerse(
    'Lamentations 3:26',
    'It is good that a man should both hope and quietly wait for the salvation of the LORD.',
    'patience',
  ),
  CuratedDailyVerse(
    'Hebrews 10:36',
    'For ye have need of patience, that, after ye have done the will of God, ye might receive the promise.',
    'patience',
  ),
  CuratedDailyVerse(
    'Romans 8:25',
    'But if we hope for that we see not, then do we with patience wait for it.',
    'patience',
  ),
  CuratedDailyVerse(
    'Proverbs 15:18',
    'A wrathful man stirreth up strife: but he that is slow to anger appeaseth strife.',
    'patience',
  ),
  CuratedDailyVerse(
    'Proverbs 11:17',
    'The merciful man doeth good to his own soul: but he that is cruel troubleth his own flesh.',
    'kindness',
  ),
  CuratedDailyVerse(
    'Proverbs 19:17',
    'He that hath pity upon the poor lendeth unto the LORD; and that which he hath given will he pay him again.',
    'kindness',
  ),
  CuratedDailyVerse(
    'Luke 6:35',
    'But love ye your enemies, and do good, and lend, hoping for nothing again; and your reward shall be great, and ye shall be the children of the Highest: for he is kind unto the unthankful and to the evil.',
    'kindness',
  ),
  CuratedDailyVerse(
    'Micah 6:8',
    'He hath shewed thee, O man, what is good; and what doth the LORD require of thee, but to do justly, and to love mercy, and to walk humbly with thy God?',
    'kindness',
  ),
  CuratedDailyVerse(
    'Proverbs 31:26',
    'She openeth her mouth with wisdom; and in her tongue is the law of kindness.',
    'kindness',
  ),
  CuratedDailyVerse(
    'Proverbs 12:25',
    'Heaviness in the heart of man maketh it stoop: but a good word maketh it glad.',
    'kindness',
  ),
  CuratedDailyVerse(
    'Psalm 89:1',
    'I will sing of the mercies of the LORD for ever: with my mouth will I make known thy faithfulness to all generations.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    '1 Corinthians 1:9',
    'God is faithful, by whom ye were called unto the fellowship of his Son Jesus Christ our Lord.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    '1 Thessalonians 5:24',
    'Faithful is he that calleth you, who also will do it.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    'Psalm 36:5',
    'Thy mercy, O LORD, is in the heavens; and thy faithfulness reacheth unto the clouds.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    'Matthew 25:21',
    'His lord said unto him, Well done, thou good and faithful servant: thou hast been faithful over a few things, I will make thee ruler over many things: enter thou into the joy of thy lord.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    'Psalm 100:5',
    'For the LORD is good; his mercy is everlasting; and his truth endureth to all generations.',
    'faithfulness',
  ),
  CuratedDailyVerse(
    'Proverbs 25:28',
    'He that hath no rule over his own spirit is like a city that is broken down, and without walls.',
    'self_control',
  ),
  CuratedDailyVerse(
    '1 Peter 5:8',
    'Be sober, be vigilant; because your adversary the devil, as a roaring lion, walketh about, seeking whom he may devour:',
    'self_control',
  ),
  CuratedDailyVerse(
    'Proverbs 16:32',
    'He that is slow to anger is better than the mighty; and he that ruleth his spirit than he that taketh a city.',
    'self_control',
  ),
  CuratedDailyVerse(
    '2 Timothy 2:22',
    'Flee also youthful lusts: but follow righteousness, faith, charity, peace, with them that call on the Lord out of a pure heart.',
    'self_control',
  ),
  CuratedDailyVerse(
    'Proverbs 4:23',
    'Keep thy heart with all diligence; for out of it are the issues of life.',
    'self_control',
  ),
  CuratedDailyVerse(
    'Isaiah 40:11',
    'He shall feed his flock like a shepherd: he shall gather the lambs with his arm, and carry them in his bosom, and shall gently lead those that are with young.',
    'gentleness',
  ),
  CuratedDailyVerse(
    'Matthew 11:29',
    'Take my yoke upon you, and learn of me; for I am meek and lowly in heart: and ye shall find rest unto your souls.',
    'gentleness',
  ),
  CuratedDailyVerse(
    'Proverbs 15:1',
    'A soft answer turneth away wrath: but grievous words stir up anger.',
    'gentleness',
  ),
  CuratedDailyVerse(
    'Matthew 5:5',
    'Blessed are the meek: for they shall inherit the earth.',
    'gentleness',
  ),
  CuratedDailyVerse(
    'Ephesians 4:2',
    'With all lowliness and meekness, with longsuffering, forbearing one another in love;',
    'gentleness',
  ),
  CuratedDailyVerse(
    'Colossians 3:13',
    'Forbearing one another, and forgiving one another, if any man have a quarrel against any: even as Christ forgave you, so also do ye.',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Matthew 6:14',
    'For if ye forgive men their trespasses, your heavenly Father will also forgive you:',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Luke 6:37',
    'Judge not, and ye shall not be judged: condemn not, and ye shall not be condemned: forgive, and ye shall be forgiven:',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Psalm 103:12',
    'As far as the east is from the west, so far hath he removed our transgressions from us.',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Isaiah 43:25',
    'I, even I, am he that blotteth out thy transgressions for mine own sake, and will not remember thy sins.',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Micah 7:18',
    'Who is a God like unto thee, that pardoneth iniquity, and passeth by the transgression of the remnant of his heritage? he retaineth not his anger for ever, because he delighteth in mercy.',
    'forgiveness',
  ),
  CuratedDailyVerse(
    'Joshua 1:9',
    'Have not I commanded thee? Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee whithersoever thou goest.',
    'courage',
  ),
  CuratedDailyVerse(
    'Deuteronomy 31:6',
    'Be strong and of a good courage, fear not, nor be afraid of them: for the LORD thy God, he it is that doth go with thee; he will not fail thee, nor forsake thee.',
    'courage',
  ),
  CuratedDailyVerse(
    'Proverbs 28:1',
    'The wicked flee when no man pursueth: but the righteous are bold as a lion.',
    'courage',
  ),
  CuratedDailyVerse(
    '1 Corinthians 16:13',
    'Watch ye, stand fast in the faith, quit you like men, be strong.',
    'courage',
  ),
  CuratedDailyVerse(
    'Psalm 118:6',
    'The LORD is on my side; I will not fear: what can man do unto me?',
    'courage',
  ),
  CuratedDailyVerse(
    'Psalm 23:2',
    'He maketh me to lie down in green pastures: he leadeth me beside the still waters.',
    'rest',
  ),
  CuratedDailyVerse(
    'Psalm 62:1',
    'Truly my soul waiteth upon God: from him cometh my salvation.',
    'rest',
  ),
  CuratedDailyVerse(
    'Exodus 33:14',
    'And he said, My presence shall go with thee, and I will give thee rest.',
    'rest',
  ),
  CuratedDailyVerse(
    'Matthew 11:30',
    'For my yoke is easy, and my burden is light.',
    'rest',
  ),
  CuratedDailyVerse(
    'Isaiah 43:19',
    'Behold, I will do a new thing; now it shall spring forth; shall ye not know it? I will even make a way in the wilderness, and rivers in the desert.',
    'new_beginnings',
  ),
  CuratedDailyVerse(
    'Revelation 21:5',
    'And he that sat upon the throne said, Behold, I make all things new. And he said unto me, Write: for these words are true and faithful.',
    'new_beginnings',
  ),
  CuratedDailyVerse(
    'Ezekiel 36:26',
    'A new heart also will I give you, and a new spirit will I put within you: and I will take away the stony heart out of your flesh, and I will give you an heart of flesh.',
    'new_beginnings',
  ),
  CuratedDailyVerse(
    'Romans 6:4',
    'Therefore we are buried with him by baptism into death: that like as Christ was raised up from the dead by the glory of the Father, even so we also should walk in newness of life.',
    'new_beginnings',
  ),
  CuratedDailyVerse(
    'Psalm 51:10',
    'Create in me a clean heart, O God; and renew a right spirit within me.',
    'new_beginnings',
  ),
  CuratedDailyVerse(
    'Ecclesiastes 3:1',
    'To every thing there is a season, and a time to every purpose under the heaven:',
    'seasons',
  ),
  CuratedDailyVerse(
    'Psalm 1:3',
    'And he shall be like a tree planted by the rivers of water, that bringeth forth his fruit in his season; his leaf also shall not wither; and whatsoever he doeth shall prosper.',
    'seasons',
  ),
  CuratedDailyVerse(
    'Jeremiah 17:8',
    'For he shall be as a tree planted by the waters, and that spreadeth out her roots by the river, and shall not see when heat cometh, but her leaf shall be green; and shall not be careful in the year of drought, neither shall cease from yielding fruit.',
    'seasons',
  ),
  CuratedDailyVerse(
    'Isaiah 55:10-11',
    'For as the rain cometh down, and the snow from heaven, and returneth not thither, but watereth the earth, and maketh it bring forth and bud, that it may give seed to the sower, and bread to the eater: So shall my word be that goeth forth out of my mouth: it shall not return unto me void, but it shall accomplish that which I please, and it shall prosper in the thing whereto I sent it.',
    'seasons',
  ),
  CuratedDailyVerse(
    'Hosea 10:12',
    'Sow to yourselves in righteousness, reap in mercy; break up your fallow ground: for it is time to seek the LORD, till he come and rain righteousness upon you.',
    'seasons',
  ),
  CuratedDailyVerse(
    'Psalm 92:1',
    'It is a good thing to give thanks unto the LORD, and to sing praises unto thy name, O most High:',
    'thanksgiving',
  ),
  CuratedDailyVerse(
    '2 Corinthians 9:15',
    'Thanks be unto God for his unspeakable gift.',
    'thanksgiving',
  ),
  CuratedDailyVerse(
    'Ephesians 5:20',
    'Giving thanks always for all things unto God and the Father in the name of our Lord Jesus Christ;',
    'thanksgiving',
  ),
  CuratedDailyVerse(
    'Psalm 116:12',
    'What shall I render unto the LORD for all his benefits toward me?',
    'thanksgiving',
  ),
  CuratedDailyVerse(
    '1 Chronicles 16:34',
    'O give thanks unto the LORD; for he is good; for his mercy endureth for ever.',
    'thanksgiving',
  ),
  CuratedDailyVerse(
    'Psalm 145:1-2',
    'I will extol thee, my God, O king; and I will bless thy name for ever and ever. Every day will I bless thee; and I will praise thy name for ever and ever.',
    'praise',
  ),
  CuratedDailyVerse(
    'Psalm 47:1',
    'O clap your hands, all ye people; shout unto God with the voice of triumph.',
    'praise',
  ),
  CuratedDailyVerse(
    'Psalm 100:1-2',
    'Make a joyful noise unto the LORD, all ye lands. Serve the LORD with gladness: come before his presence with singing.',
    'praise',
  ),
  CuratedDailyVerse(
    'Psalm 34:3',
    'O magnify the LORD with me, and let us exalt his name together.',
    'praise',
  ),
  CuratedDailyVerse(
    'Psalm 56:3',
    'What time I am afraid, I will trust in thee.',
    'trust',
  ),
  CuratedDailyVerse(
    'Psalm 20:7',
    'Some trust in chariots, and some in horses: but we will remember the name of the LORD our God.',
    'trust',
  ),
  CuratedDailyVerse(
    'Isaiah 26:4',
    'Trust ye in the LORD for ever: for in the LORD JEHOVAH is everlasting strength:',
    'trust',
  ),
  CuratedDailyVerse(
    'Proverbs 29:25',
    'The fear of man bringeth a snare: but whoso putteth his trust in the LORD shall be safe.',
    'trust',
  ),
  CuratedDailyVerse(
    'Psalm 62:8',
    'Trust in him at all times; ye people, pour out your heart before him: God is a refuge for us. Selah.',
    'trust',
  ),
  CuratedDailyVerse(
    'Jeremiah 17:7',
    'Blessed is the man that trusteth in the LORD, and whose hope the LORD is.',
    'trust',
  ),
  CuratedDailyVerse(
    'Nahum 1:7',
    'The LORD is good, a strong hold in the day of trouble; and he knoweth them that trust in him.',
    'trust',
  ),
  CuratedDailyVerse(
    'Psalm 34:4',
    'I sought the LORD, and he heard me, and delivered me from all my fears.',
    'overcoming_fear',
  ),
  CuratedDailyVerse(
    'Psalm 23:4',
    'Yea, though I walk through the valley of the shadow of death, I will fear no evil: for thou art with me; thy rod and thy staff they comfort me.',
    'overcoming_fear',
  ),
  CuratedDailyVerse(
    'Isaiah 43:1',
    'But now thus saith the LORD that created thee, O Jacob, and he that formed thee, O Israel, Fear not: for I have redeemed thee, I have called thee by thy name; thou art mine.',
    'overcoming_fear',
  ),
  CuratedDailyVerse(
    'John 14:1',
    'Let not your heart be troubled: ye believe in God, believe also in me.',
    'overcoming_fear',
  ),
  CuratedDailyVerse(
    'Psalm 112:7',
    'He shall not be afraid of evil tidings: his heart is fixed, trusting in the LORD.',
    'overcoming_fear',
  ),
  CuratedDailyVerse(
    'James 1:12',
    'Blessed is the man that endureth temptation: for when he is tried, he shall receive the crown of life, which the Lord hath promised to them that love him.',
    'perseverance',
  ),
  CuratedDailyVerse(
    'Hebrews 12:1',
    'Wherefore seeing we also are compassed about with so great a cloud of witnesses, let us lay aside every weight, and the sin which doth so easily beset us, and let us run with patience the race that is set before us,',
    'perseverance',
  ),
  CuratedDailyVerse(
    '1 Corinthians 15:58',
    'Therefore, my beloved brethren, be ye stedfast, unmoveable, always abounding in the work of the Lord, forasmuch as ye know that your labour is not in vain in the Lord.',
    'perseverance',
  ),
  CuratedDailyVerse(
    '2 Timothy 4:7',
    'I have fought a good fight, I have finished my course, I have kept the faith:',
    'perseverance',
  ),
  CuratedDailyVerse(
    'Philippians 1:6',
    'Being confident of this very thing, that he which hath begun a good work in you will perform it until the day of Jesus Christ:',
    'perseverance',
  ),
  CuratedDailyVerse(
    'Isaiah 40:29',
    'He giveth power to the faint; and to them that have no might he increaseth strength.',
    'perseverance',
  ),
  CuratedDailyVerse(
    'Proverbs 1:7',
    'The fear of the LORD is the beginning of knowledge: but fools despise wisdom and instruction.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Proverbs 9:10',
    'The fear of the LORD is the beginning of wisdom: and the knowledge of the holy is understanding.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Proverbs 4:7',
    'Wisdom is the principal thing; therefore get wisdom: and with all thy getting get understanding.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Proverbs 3:13',
    'Happy is the man that findeth wisdom, and the man that getteth understanding.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Psalm 111:10',
    'The fear of the LORD is the beginning of wisdom: a good understanding have all they that do his commandments: his praise endureth for ever.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Proverbs 8:11',
    'For wisdom is better than rubies; and all the things that may be desired are not to be compared to it.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Psalm 90:12',
    'So teach us to number our days, that we may apply our hearts unto wisdom.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Proverbs 11:2',
    'When pride cometh, then cometh shame: but with the lowly is wisdom.',
    'wisdom',
  ),
  CuratedDailyVerse(
    'Psalm 133:1',
    'Behold, how good and how pleasant it is for brethren to dwell together in unity!',
    'unity',
  ),
  CuratedDailyVerse(
    'Ephesians 4:3',
    'Endeavouring to keep the unity of the Spirit in the bond of peace.',
    'unity',
  ),
  CuratedDailyVerse(
    'Colossians 3:14',
    'And above all these things put on charity, which is the bond of perfectness.',
    'unity',
  ),
  CuratedDailyVerse(
    'Galatians 3:28',
    'There is neither Jew nor Greek, there is neither bond nor free, there is neither male nor female: for ye are all one in Christ Jesus.',
    'unity',
  ),
  CuratedDailyVerse(
    'John 17:21',
    'That they all may be one; as thou, Father, art in me, and I in thee, that they also may be one in us: that the world may believe that thou hast sent me.',
    'unity',
  ),
  CuratedDailyVerse(
    '1 Corinthians 13:4',
    'Charity suffereth long, and is kind; charity envieth not; charity vaunteth not itself, is not puffed up,',
    'love',
  ),
  CuratedDailyVerse(
    '1 Corinthians 13:7',
    'Beareth all things, believeth all things, hopeth all things, endureth all things.',
    'love',
  ),
  CuratedDailyVerse(
    'John 13:34',
    'A new commandment I give unto you, That ye love one another; as I have loved you, that ye also love one another.',
    'love',
  ),
  CuratedDailyVerse(
    '1 John 4:7',
    'Beloved, let us love one another: for love is of God; and every one that loveth is born of God, and knoweth God.',
    'love',
  ),
  CuratedDailyVerse(
    'Romans 8:38-39',
    'For I am persuaded, that neither death, nor life, nor angels, nor principalities, nor powers, nor things present, nor things to come, Nor height, nor depth, nor any other creature, shall be able to separate us from the love of God, which is in Christ Jesus our Lord.',
    'love',
  ),
  CuratedDailyVerse(
    'Psalm 5:11',
    'But let all those that put their trust in thee rejoice: let them ever shout for joy, because thou defendest them: let them also that love thy name be joyful in thee.',
    'joy',
  ),
  CuratedDailyVerse(
    'Psalm 43:4',
    'Then will I go unto the altar of God, unto God my exceeding joy: yea, upon the harp will I praise thee, O God my God.',
    'joy',
  ),
  CuratedDailyVerse(
    'John 15:11',
    'These things have I spoken unto you, that my joy might remain in you, and that your joy might be full.',
    'joy',
  ),
  CuratedDailyVerse(
    'Isaiah 61:10',
    'I will greatly rejoice in the LORD, my soul shall be joyful in my God; for he hath clothed me with the garments of salvation, he hath covered me with the robe of righteousness, as a bridegroom decketh himself with ornaments, and as a bride adorneth herself with her jewels.',
    'joy',
  ),
  CuratedDailyVerse(
    '1 Peter 1:8',
    'Whom having not seen, ye love; in whom, though now ye see him not, yet believing, ye rejoice with joy unspeakable and full of glory:',
    'joy',
  ),
  CuratedDailyVerse(
    'Psalm 119:165',
    'Great peace have they which love thy law: and nothing shall offend them.',
    'peace',
  ),
  CuratedDailyVerse(
    'Isaiah 9:6',
    'For unto us a child is born, unto us a son is given: and the government shall be upon his shoulder: and his name shall be called Wonderful, Counsellor, The mighty God, The everlasting Father, The Prince of Peace.',
    'peace',
  ),
  CuratedDailyVerse(
    'Matthew 5:9',
    'Blessed are the peacemakers: for they shall be called the children of God.',
    'peace',
  ),
  CuratedDailyVerse(
    'Psalm 37:11',
    'But the meek shall inherit the earth; and shall delight themselves in the abundance of peace.',
    'peace',
  ),
  CuratedDailyVerse(
    'Isaiah 32:17',
    'And the work of righteousness shall be peace; and the effect of righteousness quietness and assurance for ever.',
    'peace',
  ),
  CuratedDailyVerse(
    'Psalm 146:5',
    'Happy is he that hath the God of Jacob for his help, whose hope is in the LORD his God:',
    'hope',
  ),
  CuratedDailyVerse(
    'Romans 15:4',
    'For whatsoever things were written aforetime were written for our learning, that we through patience and comfort of the scriptures might have hope.',
    'hope',
  ),
  CuratedDailyVerse(
    '1 Peter 1:3',
    'Blessed be the God and Father of our Lord Jesus Christ, which according to his abundant mercy hath begotten us again unto a lively hope by the resurrection of Jesus Christ from the dead,',
    'hope',
  ),
  CuratedDailyVerse(
    'Colossians 1:27',
    'To whom God would make known what is the riches of the glory of this mystery among the Gentiles; which is Christ in you, the hope of glory:',
    'hope',
  ),
  CuratedDailyVerse(
    'Psalm 18:32',
    'It is God that girdeth me with strength, and maketh my way perfect.',
    'strength',
  ),
  CuratedDailyVerse(
    'Psalm 28:8',
    'The LORD is their strength, and he is the saving strength of his anointed.',
    'strength',
  ),
  CuratedDailyVerse(
    'Zechariah 4:6',
    'Then he answered and spake unto me, saying, This is the word of the LORD unto Zerubbabel, saying, Not by might, nor by power, but by my spirit, saith the LORD of hosts.',
    'strength',
  ),
  CuratedDailyVerse(
    'Ephesians 3:16',
    'That he would grant you, according to the riches of his glory, to be strengthened with might by his Spirit in the inner man;',
    'strength',
  ),
  CuratedDailyVerse(
    'Matthew 6:26',
    'Behold the fowls of the air: for they sow not, neither do they reap, nor gather into barns; yet your heavenly Father feedeth them. Are ye not much better than they?',
    'provision',
  ),
  CuratedDailyVerse(
    'Matthew 7:11',
    'If ye then, being evil, know how to give good gifts unto your children, how much more shall your Father which is in heaven give good things to them that ask him?',
    'provision',
  ),
  CuratedDailyVerse(
    'Proverbs 10:22',
    'The blessing of the LORD, it maketh rich, and he addeth no sorrow with it.',
    'provision',
  ),
  CuratedDailyVerse(
    'Genesis 22:14',
    'And Abraham called the name of that place Jehovahjireh: as it is said to this day, In the mount of the LORD it shall be seen.',
    'provision',
  ),
  CuratedDailyVerse(
    'Psalm 68:19',
    'Blessed be the Lord, who daily loadeth us with benefits, even the God of our salvation. Selah.',
    'provision',
  ),
  CuratedDailyVerse(
    'Proverbs 30:5',
    'Every word of God is pure: he is a shield unto them that put their trust in him.',
    'protection',
  ),
  CuratedDailyVerse(
    'Psalm 3:3',
    'But thou, O LORD, art a shield for me; my glory, and the lifter up of mine head.',
    'protection',
  ),
  CuratedDailyVerse(
    'Psalm 27:5',
    'For in the time of trouble he shall hide me in his pavilion: in the secret of his tabernacle shall he hide me; he shall set me up upon a rock.',
    'protection',
  ),
  CuratedDailyVerse(
    'Psalm 91:14',
    'Because he hath set his love upon me, therefore will I deliver him: I will set him on high, because he hath known my name.',
    'protection',
  ),
  CuratedDailyVerse(
    'Psalm 48:14',
    'For this God is our God for ever and ever: he will be our guide even unto death.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Proverbs 16:9',
    'A man\'s heart deviseth his way: but the LORD directeth his steps.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Psalm 25:5',
    'Lead me in thy truth, and teach me: for thou art the God of my salvation; on thee do I wait all the day.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Isaiah 48:17',
    'Thus saith the LORD, thy Redeemer, the Holy One of Israel; I am the LORD thy God which teacheth thee to profit, which leadeth thee by the way that thou shouldest go.',
    'guidance',
  ),
  CuratedDailyVerse(
    'Psalm 73:24',
    'Thou shalt guide me with thy counsel, and afterward receive me to glory.',
    'guidance',
  ),
  CuratedDailyVerse(
    '1 Corinthians 15:54',
    'So when this corruptible shall have put on incorruption, and this mortal shall have put on immortality, then shall be brought to pass the saying that is written, Death is swallowed up in victory.',
    'victory',
  ),
  CuratedDailyVerse(
    'Deuteronomy 28:7',
    'The LORD shall cause thine enemies that rise up against thee to be smitten before thy face: they shall come out against thee one way, and flee before thee seven ways.',
    'victory',
  ),
  CuratedDailyVerse(
    'Exodus 15:2',
    'The LORD is my strength and song, and he is become my salvation: he is my God, and I will prepare him an habitation; my father\'s God, and I will exalt him.',
    'victory',
  ),
  CuratedDailyVerse(
    'Psalm 41:11',
    'By this I know that thou favourest me, because mine enemy doth not triumph over me.',
    'victory',
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
