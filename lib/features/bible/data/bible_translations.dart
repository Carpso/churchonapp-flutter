class BibleTranslation {
  final String code;
  final String name;
  final String shortName;
  final String language;
  final bool isPublicDomain;
  final bool hasOldTestament;
  final bool hasNewTestament;

  const BibleTranslation({
    required this.code,
    required this.name,
    required this.shortName,
    this.language = 'en',
    this.isPublicDomain = true,
    this.hasOldTestament = true,
    this.hasNewTestament = true,
  });
}

const List<BibleTranslation> kEnglishTranslations = [
  BibleTranslation(code: 'kjv', name: 'King James Version', shortName: 'KJV'),
  BibleTranslation(code: 'nkjv', name: 'New King James Version', shortName: 'NKJV'),
  BibleTranslation(code: 'niv', name: 'New International Version', shortName: 'NIV'),
  BibleTranslation(code: 'esv', name: 'English Standard Version', shortName: 'ESV'),
  BibleTranslation(code: 'nlt', name: 'New Living Translation', shortName: 'NLT'),
  BibleTranslation(code: 'web', name: 'World English Bible', shortName: 'WEB'),
  BibleTranslation(code: 'asv', name: 'American Standard Version', shortName: 'ASV'),
  BibleTranslation(code: 'msg', name: 'The Message', shortName: 'MSG'),
  BibleTranslation(code: 'bbe', name: 'Bible in Basic English', shortName: 'BBE'),
  BibleTranslation(code: 'ylt', name: "Young's Literal Translation", shortName: 'YLT'),
  BibleTranslation(code: 'dra', name: 'Douay-Rheims American Edition', shortName: 'DRA'),
  BibleTranslation(code: 'geneva1599', name: 'Geneva Bible 1599', shortName: 'GNV'),
];

BibleTranslation? getTranslationByCode(String code) {
  for (final t in kEnglishTranslations) {
    if (t.code == code) return t;
  }
  return null;
}

String getTranslationFullName(String code) {
  final t = getTranslationByCode(code);
  return t != null ? '${t.name} (${t.shortName})' : code.toUpperCase();
}

const Map<String, String> kBookNameToMidvashSlug = {
  'Genesis': 'genesis',
  'Exodus': 'exodus',
  'Leviticus': 'leviticus',
  'Numbers': 'numbers',
  'Deuteronomy': 'deuteronomy',
  'Joshua': 'joshua',
  'Judges': 'judges',
  'Ruth': 'ruth',
  '1 Samuel': '1-samuel',
  '2 Samuel': '2-samuel',
  '1 Kings': '1-kings',
  '2 Kings': '2-kings',
  '1 Chronicles': '1-chronicles',
  '2 Chronicles': '2-chronicles',
  'Ezra': 'ezra',
  'Nehemiah': 'nehemiah',
  'Esther': 'esther',
  'Job': 'job',
  'Psalms': 'psalms',
  'Proverbs': 'proverbs',
  'Ecclesiastes': 'ecclesiastes',
  'Song of Solomon': 'song-of-solomon',
  'Isaiah': 'isaiah',
  'Jeremiah': 'jeremiah',
  'Lamentations': 'lamentations',
  'Ezekiel': 'ezekiel',
  'Daniel': 'daniel',
  'Hosea': 'hosea',
  'Joel': 'joel',
  'Amos': 'amos',
  'Obadiah': 'obadiah',
  'Jonah': 'jonah',
  'Micah': 'micah',
  'Nahum': 'nahum',
  'Habakkuk': 'habakkuk',
  'Zephaniah': 'zephaniah',
  'Haggai': 'haggai',
  'Zechariah': 'zechariah',
  'Malachi': 'malachi',
  'Matthew': 'matthew',
  'Mark': 'mark',
  'Luke': 'luke',
  'John': 'john',
  'Acts': 'acts',
  'Romans': 'romans',
  '1 Corinthians': '1-corinthians',
  '2 Corinthians': '2-corinthians',
  'Galatians': 'galatians',
  'Ephesians': 'ephesians',
  'Philippians': 'philippians',
  'Colossians': 'colossians',
  '1 Thessalonians': '1-thessalonians',
  '2 Thessalonians': '2-thessalonians',
  '1 Timothy': '1-timothy',
  '2 Timothy': '2-timothy',
  'Titus': 'titus',
  'Philemon': 'philemon',
  'Hebrews': 'hebrews',
  'James': 'james',
  '1 Peter': '1-peter',
  '2 Peter': '2-peter',
  '1 John': '1-john',
  '2 John': '2-john',
  '3 John': '3-john',
  'Jude': 'jude',
  'Revelation': 'revelation',
};

String bookNameToMidvashSlug(String bookName) {
  return kBookNameToMidvashSlug[bookName] ?? bookName.toLowerCase().replaceAll(' ', '-');
}
