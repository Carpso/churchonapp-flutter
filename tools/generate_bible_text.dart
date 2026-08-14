// Generates per-book KJV JSON files (chapter -> verses) from bible-api.com.
// Output: build/bible-text/kjv/<Book>.json  (uploaded to R2 via bible-text-upload)
// Usage: dart run tools/generate_bible_text.dart
import 'dart:convert';
import 'dart:io';

const books = [
  'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy', 'Joshua',
  'Judges', 'Ruth', '1 Samuel', '2 Samuel', '1 Kings', '2 Kings',
  '1 Chronicles', '2 Chronicles', 'Ezra', 'Nehemiah', 'Esther', 'Job',
  'Psalms', 'Proverbs', 'Ecclesiastes', 'Song of Solomon', 'Isaiah',
  'Jeremiah', 'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel', 'Amos',
  'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk', 'Zephaniah', 'Haggai',
  'Zechariah', 'Malachi', 'Matthew', 'Mark', 'Luke', 'John', 'Acts',
  'Romans', '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
  'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
  '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews', 'James',
  '1 Peter', '2 Peter', '1 John', '2 John', '3 John', 'Jude', 'Revelation',
];

const chapterCounts = {
  'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36,
  'Deuteronomy': 34, 'Joshua': 24, 'Judges': 21, 'Ruth': 4, '1 Samuel': 31,
  '2 Samuel': 24, '1 Kings': 22, '2 Kings': 25, '1 Chronicles': 29,
  '2 Chronicles': 36, 'Ezra': 10, 'Nehemiah': 13, 'Esther': 10, 'Job': 42,
  'Psalms': 150, 'Proverbs': 31, 'Ecclesiastes': 12, 'Song of Solomon': 8,
  'Isaiah': 66, 'Jeremiah': 52, 'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12,
  'Hosea': 14, 'Joel': 3, 'Amos': 9, 'Obadiah': 1, 'Jonah': 4, 'Micah': 7,
  'Nahum': 3, 'Habakkuk': 3, 'Zephaniah': 3, 'Haggai': 2, 'Zechariah': 14,
  'Malachi': 4, 'Matthew': 28, 'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28,
  'Romans': 16, '1 Corinthians': 16, '2 Corinthians': 13, 'Galatians': 6,
  'Ephesians': 6, 'Philippians': 4, 'Colossians': 4, '1 Thessalonians': 5,
  '2 Thessalonians': 3, '1 Timothy': 6, '2 Timothy': 4, 'Titus': 3,
  'Philemon': 1, 'Hebrews': 13, 'James': 5, '1 Peter': 5, '2 Peter': 3,
  '1 John': 5, '2 John': 1, '3 John': 1, 'Jude': 1, 'Revelation': 22,
};

Future<Map<String, dynamic>?> fetchChapter(String book, int chapter) async {
  final url = 'https://bible-api.com/${Uri.encodeComponent(book)}+$chapter?translation=kjv';
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'churchonapp-bible-tool');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final data = json.decode(body);
    final verses = (data['verses'] as List).map((v) => {
      'chapter': v['chapter'],
      'verse': v['verse'],
      'text': v['text'],
    }).toList();
    return {chapter.toString(): verses};
  } catch (e) {
    stderr.writeln('FAIL $book $chapter: $e');
    return null;
  } finally {
    client.close();
  }
}

Future<void> main() async {
  final outDir = Directory('build/bible-text/kjv');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  var totalChapters = 0;
  var totalVerses = 0;
  for (final book in books) {
    final count = chapterCounts[book] ?? 1;
    final outPath = '${outDir.path}/${book.replaceAll(' ', '_')}.json';
    if (File(outPath).existsSync() && File(outPath).lengthSync() > 1000) {
      stdout.writeln('$book: skipped (already generated)');
      continue;
    }
    final merged = <String, dynamic>{};
    for (var chapter = 1; chapter <= count; chapter++) {
      Map<String, dynamic>? data;
      for (var attempt = 0; attempt < 4 && data == null; attempt++) {
        data = await fetchChapter(book, chapter);
        if (data == null) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
      if (data != null) merged.addAll(data);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    final jsonStr = const JsonEncoder.withIndent(' ').convert({'book': book, 'chapters': merged});
    File(outPath).writeAsStringSync(jsonStr);
    final verses = merged.values.fold<int>(0, (sum, list) => sum + (list as List).length);
    totalChapters += merged.length;
    totalVerses += verses;
    stdout.writeln('$book: ${merged.length}/$count chapters, $verses verses');
  }
  stdout.writeln('TOTAL: $totalChapters chapters, $totalVerses verses -> ${outDir.path}');
}