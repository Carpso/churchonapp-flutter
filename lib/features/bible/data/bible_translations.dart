class BibleTranslation {
  final String code;
  final String name;
  final String shortName;
  final String language;
  final bool isPublicDomain;
  final bool hasOldTestament;
  final bool hasNewTestament;

  /// Whether bible-api.com (the remote fetch layer) supports this code.
  final bool remoteSupported;

  const BibleTranslation({
    required this.code,
    required this.name,
    required this.shortName,
    this.language = 'en',
    this.isPublicDomain = true,
    this.hasOldTestament = true,
    this.hasNewTestament = true,
    this.remoteSupported = false,
  });
}

const List<BibleTranslation> kEnglishTranslations = [
  BibleTranslation(code: 'kjv', name: 'King James Version', shortName: 'KJV', remoteSupported: true),
  BibleTranslation(code: 'nkjv', name: 'New King James Version', shortName: 'NKJV'),
  BibleTranslation(code: 'niv', name: 'New International Version', shortName: 'NIV'),
  BibleTranslation(code: 'esv', name: 'English Standard Version', shortName: 'ESV'),
  BibleTranslation(code: 'nlt', name: 'New Living Translation', shortName: 'NLT'),
  BibleTranslation(code: 'web', name: 'World English Bible', shortName: 'WEB', remoteSupported: true),
  BibleTranslation(code: 'asv', name: 'American Standard Version', shortName: 'ASV', remoteSupported: true),
  BibleTranslation(code: 'msg', name: 'The Message', shortName: 'MSG'),
  BibleTranslation(code: 'bbe', name: 'Bible in Basic English', shortName: 'BBE', remoteSupported: true),
  BibleTranslation(code: 'ylt', name: "Young's Literal Translation", shortName: 'YLT', remoteSupported: true),
  BibleTranslation(code: 'dra', name: 'Douay-Rheims American Edition', shortName: 'DRA', remoteSupported: true),
  BibleTranslation(code: 'geneva1599', name: 'Geneva Bible 1599', shortName: 'GNV', remoteSupported: true),
  BibleTranslation(code: 'acv', name: 'A Conservative Version', shortName: 'ACV', remoteSupported: true),
  BibleTranslation(code: 'cpdv', name: 'Catholic Public Domain Version', shortName: 'CPDV', remoteSupported: true),
  BibleTranslation(code: 'darby', name: 'Darby Bible', shortName: 'DARBY', remoteSupported: true),
  BibleTranslation(code: 'jubilee2000', name: 'Jubilee Bible 2000', shortName: 'JUB', remoteSupported: true),
  BibleTranslation(code: 'mkjv', name: 'Modern King James Version', shortName: 'MKJV', remoteSupported: true),
  BibleTranslation(code: 'nheb', name: 'New Heart English Bible', shortName: 'NHEB', remoteSupported: true),
  BibleTranslation(code: 'noyes', name: "Noyes' New Testament", shortName: 'NOYES', remoteSupported: true),
  BibleTranslation(code: 'rlt', name: 'Revised Literal Translation', shortName: 'RLT', remoteSupported: true),
  BibleTranslation(code: 'rnkjv', name: 'Restored Name King James Version', shortName: 'RNKJV', remoteSupported: true),
  BibleTranslation(code: 'rotherham', name: "Rotherham's Emphasized Bible", shortName: 'ROTH', remoteSupported: true),
  BibleTranslation(code: 'ukjv', name: 'Updated King James Version', shortName: 'UKJV', remoteSupported: true),
  BibleTranslation(code: 'webster', name: "Webster's Bible 1833", shortName: 'WEBSTER', remoteSupported: true),
  BibleTranslation(code: 'oeb', name: 'Open English Bible', shortName: 'OEB', remoteSupported: true),
  BibleTranslation(code: 'tyndale', name: "Tyndale's Bible (1526-1534)", shortName: 'TYNDALE', remoteSupported: true),
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

String getTranslationShortName(String code) {
  final t = getTranslationByCode(code);
  return t != null ? t.shortName : code.toUpperCase();
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
