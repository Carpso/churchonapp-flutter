// Repairs bible-text JSON files: fetches only missing chapters and merges them in.
// Usage: dart run tools/repair_bible_text.dart
import 'dart:convert';
import 'dart:io';

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
  var totalMissing = 0;
  var totalFixed = 0;

  for (final book in chapterCounts.keys) {
    final file = File('${outDir.path}/${book.replaceAll(' ', '_')}.json');
    if (!file.existsSync()) {
      stderr.writeln('MISSING FILE: $book');
      continue;
    }
    final parsed = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    final chapters = (parsed['chapters'] as Map<String, dynamic>?) ?? {};
    final expected = chapterCounts[book]!;
    final missing = <int>[];
    for (var c = 1; c <= expected; c++) {
      if (!chapters.containsKey('$c')) missing.add(c);
    }
    totalMissing += missing.length;
    if (missing.isEmpty) continue;

    stdout.writeln('$book: repairing ${missing.length} missing chapters: $missing');
    var fixed = 0;
    for (final c in missing) {
      Map<String, dynamic>? data;
      for (var attempt = 0; attempt < 5 && data == null; attempt++) {
        data = await fetchChapter(book, c);
        if (data == null) await Future.delayed(const Duration(seconds: 1));
      }
      if (data != null) {
        chapters.addAll(data);
        fixed++;
      } else {
        stderr.writeln('  STILL FAILING: $book $c');
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    totalFixed += fixed;
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'book': book, 'chapters': chapters}));
    stdout.writeln('  -> $book now ${chapters.length}/$expected');
  }

  stdout.writeln('REPAIR DONE: $totalFixed/$totalMissing chapters fixed');
}