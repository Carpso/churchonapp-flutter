/// Chapter-range to R2 audio file mapping for the LibriVox KJV (Complete 2001) recording.
/// Each entry lists [startChapter, endChapter, fileNumber] triples; audio lives at
/// https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_NNN.mp3
const Map<String, List<List<int>>> kjvChapterFileRanges = {
  'Genesis': [[1,14,1], [15,24,2], [25,32,3], [33,43,4], [44,50,5]],
  'Exodus': [[1,10,6], [11,22,7], [23,33,8], [34,40,9]],
  'Leviticus': [[1,11,10], [12,22,11], [23,27,12]],
  'Numbers': [[1,9,13], [10,20,14], [21,30,15], [31,36,16]],
  'Deuteronomy': [[1,11,17], [12,25,18], [25,34,19]],
  'Joshua': [[1,10,20], [11,21,21], [22,24,22]],
  'Judges': [[1,8,23], [9,18,24], [19,21,25]],
  'Ruth': [[1,4,26]],
  '1 Samuel': [[1,9,27], [10,17,28], [18,25,29], [26,31,30]],
  '2 Samuel': [[1,11,31], [12,18,32], [19,24,33]],
  '1 Kings': [[1,7,34], [8,14,35], [15,21,36], [22,22,37]],
  '2 Kings': [[1,8,38], [9,17,39], [18,25,40]],
  '1 Chronicles': [[1,9,41], [10,22,42], [23,29,43]],
  '2 Chronicles': [[1,16,44], [17,28,45], [29,36,46]],
  'Ezra': [[1,10,47]],
  'Nehemiah': [[1,13,48]],
  'Esther': [[1,10,49]],
  'Job': [[1,22,50], [23,42,51]],
  'Psalms': [[1,32,52], [33,57,53], [58,80,54], [81,106,55], [107,137,56], [138,150,57]],
  'Proverbs': [[1,18,58], [19,31,59]],
  'Ecclesiastes': [[1,12,60]],
  'Song of Solomon': [[1,8,61]],
  'Isaiah': [[1,15,62], [16,32,63], [33,44,64], [45,59,65], [60,66,66]],
  'Jeremiah': [[1,11,67], [12,24,68], [25,35,69], [36,48,70], [49,52,71]],
  'Lamentations': [[1,5,72]],
  'Ezekiel': [[1,14,73], [15,24,74], [25,36,75], [37,48,76]],
  'Daniel': [[1,8,77], [9,12,78]],
  'Hosea': [[1,14,79]],
  'Joel': [[1,3,80]],
  'Amos': [[1,9,81]],
  'Obadiah': [[1,1,82]],
  'Jonah': [[1,4,83]],
  'Micah': [[1,7,84]],
  'Nahum': [[1,3,85]],
  'Habakkuk': [[1,3,86]],
  'Zephaniah': [[1,3,87]],
  'Haggai': [[1,2,88]],
  'Zechariah': [[1,14,89]],
  'Malachi': [[1,4,90]],
  'Matthew': [[1,12,91], [13,22,92], [23,28,93]],
  'Mark': [[1,9,94], [10,16,95]],
  'Luke': [[1,8,96], [9,16,97], [17,24,98]],
  'John': [[1,8,99], [9,18,100], [19,21,101]],
  'Acts': [[1,10,102], [10,20,103], [21,28,104]],
  'Romans': [[1,16,105]],
  '1 Corinthians': [[1,16,106]],
  '2 Corinthians': [[1,13,107]],
  'Galatians': [[1,6,108]],
  'Ephesians': [[1,6,109]],
  'Philippians': [[1,4,110]],
  'Colossians': [[1,4,111]],
  '1 Thessalonians': [[1,5,112]],
  '2 Thessalonians': [[1,3,113]],
  '1 Timothy': [[1,6,114]],
  '2 Timothy': [[1,4,115]],
  'Titus': [[1,3,116]],
  'Philemon': [[1,1,117]],
  'Hebrews': [[1,13,118]],
  'James': [[1,5,119]],
  '1 Peter': [[1,5,120]],
  '2 Peter': [[1,3,121]],
  '1 John': [[1,5,122]],
  '2 John': [[1,1,123]],
  '3 John': [[1,1,124]],
  'Jude': [[1,1,125]],
  'Revelation': [[1,17,126], [18,22,127]],
};

const String kjvR2BaseUrl = 'https://media.churchonapp.com/bible-audio/kjv-dramatized/bible_';

/// Returns the R2 audio URL for [book] [chapter], or null if not mapped.
String? kjvR2AudioUrlFor(String book, int chapter) {
  final ranges = kjvChapterFileRanges[_normalizeBook(book)];
  if (ranges == null) return null;
  for (final range in ranges) {
    if (chapter >= range[0] && chapter <= range[1]) {
      return '$kjvR2BaseUrl${range[2].toString().padLeft(3, '0')}.mp3';
    }
  }
  return null;
}

/// Returns the R2 audio URL for [book], starting at chapter 1.
String? kjvR2BookUrl(String book) => kjvR2AudioUrlFor(book, 1);

/// Normalizes a book name to the canonical map key ("Psalm" → "Psalms").
String _normalizeBook(String book) {
  if (book == 'Psalm') return 'Psalms';
  return book;
}

/// Parses a scripture reference like "John 3:16", "Psalm 23:1",
/// "1 Samuel 17:50" or "Exodus 7-12" into (book, chapter).
({String? book, int? chapter}) parseScriptureReference(String reference) {
  final trimmed = reference.trim();
  if (trimmed.isEmpty) return (book: null, chapter: null);
  // Find the last token that is a chapter/verse pair (e.g. "17:50", "3:16", "7-12").
  final match = RegExp(r'^(.*?)\s+(\d+)(?::\d+)?(?:\s*-\s*\d+)?$').firstMatch(trimmed);
  if (match == null) return (book: null, chapter: null);
  final book = match.group(1)?.trim();
  final chapter = int.tryParse(match.group(2) ?? '');
  if (book == null || chapter == null) return (book: null, chapter: null);
  return (book: _normalizeBook(book), chapter: chapter);
}

/// Returns the R2 KJV audio URL for a scripture reference string
/// (e.g. "John 3:16" → the R2 range file containing John 3).
String? kjvR2AudioUrlForReference(String reference) {
  final parsed = parseScriptureReference(reference);
  if (parsed.book == null || parsed.chapter == null) return null;
  return kjvR2AudioUrlFor(parsed.book!, parsed.chapter!);
}
