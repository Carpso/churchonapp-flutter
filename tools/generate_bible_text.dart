// Generates per-book Bible JSON files (chapter -> verses) for any translation.
// Sources:
//   - bible-api:  chapter-by-chapter fetches (codes: kjv, web, asv, bbe, ylt, dra)
//   - scrollmapper: single CSV download per translation (ASV, BBE, YLT, Darby,
//     Geneva1599, Webster, Tyndale, UKJV, MKJV, NHEB, OEB, CPDV, RNKJV, ACV,
//     Jubilee2000, Noyes, Rotherham, RLT, DRC, ...)
// Output: build/bible-text/<code>/<Book>.json  (uploaded to R2 as bible-text/<code>/<Book>.json)
// Usage:
//   dart run tools/generate_bible_text.dart --translation darby --source scrollmapper
//   dart run tools/generate_bible_text.dart --translation web --source bible-api
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

/// Book names in scrollmapper CSVs that differ from the app's canonical names.
const bookRenames = {
  'Revelation of John': 'Revelation',
  'I Samuel': '1 Samuel',
  'II Samuel': '2 Samuel',
  'I Kings': '1 Kings',
  'II Kings': '2 Kings',
  'I Chronicles': '1 Chronicles',
  'II Chronicles': '2 Chronicles',
  'I Corinthians': '1 Corinthians',
  'II Corinthians': '2 Corinthians',
  'I Thessalonians': '1 Thessalonians',
  'II Thessalonians': '2 Thessalonians',
  'I Timothy': '1 Timothy',
  'II Timothy': '2 Timothy',
  'I Peter': '1 Peter',
  'II Peter': '2 Peter',
  'I John': '1 John',
  'II John': '2 John',
  'III John': '3 John',
};

const scrollmapperBase =
    'https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/csv';

Future<Map<String, dynamic>?> fetchChapter(String code, String book, int chapter) async {
  // bible-api treats "<book> <n>" on single-chapter books as "verse n",
  // so fetch the whole book without a chapter suffix for those.
  final isSingleChapterBook = (chapterCounts[book] ?? 1) == 1;
  final reference = isSingleChapterBook
      ? Uri.encodeComponent(book)
      : '${Uri.encodeComponent(book)}+$chapter';
  final url = 'https://bible-api.com/$reference?translation=$code';
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'churchonapp-bible-tool');
    final res = await req.close();
    if (res.statusCode == 429) {
      stderr.writeln('RATE LIMIT $book $chapter — waiting 8s');
      await Future.delayed(const Duration(seconds: 8));
      return const <String, dynamic>{'_ratelimited': true};
    }
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final data = json.decode(body);
    final verses = (data['verses'] as List).map((v) => {
      'chapter': v['chapter'],
      'verse': v['verse'],
      'text': v['text'],
    }).toList();
    final byChapter = <String, List<Map<String, dynamic>>>{};
    for (final v in verses) {
      final ch = v['chapter'].toString();
      byChapter.putIfAbsent(ch, () => []).add(v);
    }
    return byChapter;
  } catch (e) {
    stderr.writeln('FAIL $book $chapter: $e');
    return null;
  } finally {
    client.close();
  }
}

/// Minimal RFC-4180 CSV row parser (handles quoted fields with commas and "" escapes).
List<List<String>> parseCsv(String content) {
  final rows = <List<String>>[];
  var row = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < content.length; i++) {
    final c = content[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < content.length && content[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(buf.toString());
      buf.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < content.length && content[i + 1] == '\n') i++;
      if (row.isNotEmpty || buf.isNotEmpty) {
        row.add(buf.toString());
        row = row.map((f) => f.trim()).toList();
        if (row.isNotEmpty && row[0].isNotEmpty) rows.add(row);
        row = <String>[];
        buf.clear();
      }
    } else {
      buf.write(c);
    }
  }
  if (row.isNotEmpty || buf.isNotEmpty) {
    row.add(buf.toString());
    if (row.isNotEmpty && row[0].isNotEmpty) rows.add(row);
  }
  return rows;
}

Future<void> generateFromScrollmapper(String code, String? csvPath) async {
  final outDir = Directory('build/bible-text/$code');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  String csv;
  if (csvPath != null) {
    csv = File(csvPath).readAsStringSync();
  } else {
    final cached = File('build/bible-text/_csv/$code.csv');
    if (cached.existsSync()) {
      stdout.writeln('$code: using cached CSV');
      csv = cached.readAsStringSync();
    } else {
      stdout.writeln('$code: downloading CSV from scrollmapper...');
      final url = '$scrollmapperBase/$code.csv';
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('User-Agent', 'churchonapp-bible-tool');
        final res = await req.close();
        if (res.statusCode != 200) {
          stderr.writeln('CSV download failed: HTTP ${res.statusCode}');
          return;
        }
        csv = await res.transform(utf8.decoder).join();
      } finally {
        client.close();
      }
      cached.parent.createSync(recursive: true);
      cached.writeAsStringSync(csv);
    }
  }

  final rows = parseCsv(csv);
  // Group by canonical book name -> chapter -> verses (skip header row).
  final byBook = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final r in rows) {
    if (r.length < 4) continue;
    final rawBook = r[0];
    final book = bookRenames[rawBook] ?? rawBook;
    if (!books.contains(book)) {
      if (rawBook == 'Book') continue; // header
      stderr.writeln('UNKNOWN BOOK: $rawBook');
      continue;
    }
    final chapter = int.tryParse(r[1]);
    final verse = int.tryParse(r[2]);
    if (chapter == null || verse == null) continue;
    final text = r[3].trim();
    byBook.putIfAbsent(book, () => {});
    byBook[book]!.putIfAbsent(chapter.toString(), () => []);
    byBook[book]![chapter.toString()]!.add({
      'chapter': chapter,
      'verse': verse,
      'text': text,
    });
  }

  var totalChapters = 0;
  var totalVerses = 0;
  final missingBooks = <String>[];
  var totalBytes = 0;
  for (final book in books) {
    final chapters = byBook[book];
    final outPath = '${outDir.path}/${book.replaceAll(' ', '_')}.json';
    if (File(outPath).existsSync() && File(outPath).lengthSync() > 1000) {
      stdout.writeln('$book: skipped (already generated)');
      continue;
    }
    if (chapters == null || chapters.isEmpty) {
      missingBooks.add(book);
      continue;
    }
    final jsonStr = const JsonEncoder.withIndent(' ').convert({'book': book, 'chapters': chapters});
    File(outPath).writeAsStringSync(jsonStr);
    final verses = chapters.values.fold<int>(0, (sum, list) => sum + list.length);
    totalChapters += chapters.length;
    totalVerses += verses;
    totalBytes += jsonStr.length;
    stdout.writeln('$book: ${chapters.length}/${chapterCounts[book] ?? 1} chapters, $verses verses');
  }
  stdout.writeln('TOTAL: $totalChapters chapters, $totalVerses verses, ${(totalBytes / 1048576).toStringAsFixed(2)} MB -> ${outDir.path}');
  if (missingBooks.isNotEmpty) {
    stdout.writeln('MISSING BOOKS (not in source): ${missingBooks.join(', ')}');
  }
}

Future<void> generateFromBibleApi(String code) async {
  final outDir = Directory('build/bible-text/$code');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  var totalChapters = 0;
  var totalVerses = 0;
  var totalBytes = 0;
  for (final book in books) {
    final count = chapterCounts[book] ?? 1;
    final outPath = '${outDir.path}/${book.replaceAll(' ', '_')}.json';
    if (File(outPath).existsSync()) {
      final existing = File(outPath).readAsStringSync();
      if (existing.length > 1000) {
        try {
          final prev = json.decode(existing) as Map<String, dynamic>;
          final prevChapters = (prev['chapters'] as Map<String, dynamic>).length;
          if (prevChapters >= count) {
            stdout.writeln('$book: skipped (already generated)');
            continue;
          }
          stdout.writeln('$book: partial ($prevChapters/$count) — regenerating');
        } catch (_) {
          stdout.writeln('$book: corrupt file — regenerating');
        }
      }
    }
    final merged = <String, dynamic>{};
    for (var chapter = 1; chapter <= count; chapter++) {
      Map<String, dynamic>? data;
      for (var attempt = 0; attempt < 6 && data == null; attempt++) {
        data = await fetchChapter(code, book, chapter);
        if (data == null) {
          await Future.delayed(const Duration(seconds: 2));
        } else if (data.containsKey('_ratelimited')) {
          data = null;
        }
      }
      if (data != null) merged.addAll(data);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final jsonStr = const JsonEncoder.withIndent(' ').convert({'book': book, 'chapters': merged});
    File(outPath).writeAsStringSync(jsonStr);
    final verses = merged.values.fold<int>(0, (sum, list) => sum + (list as List).length);
    totalChapters += merged.length;
    totalVerses += verses;
    totalBytes += jsonStr.length;
    stdout.writeln('$book: ${merged.length}/$count chapters, $verses verses');
  }
  stdout.writeln('TOTAL: $totalChapters chapters, $totalVerses verses, ${(totalBytes / 1048576).toStringAsFixed(2)} MB -> ${outDir.path}');
}

Future<void> main(List<String> args) async {
  String code = 'kjv';
  String source = 'bible-api';
  String? csvPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--translation' && i + 1 < args.length) {
      code = args[i + 1];
    } else if (args[i] == '--source' && i + 1 < args.length) {
      source = args[i + 1];
    } else if (args[i] == '--csv' && i + 1 < args.length) {
      csvPath = args[i + 1];
    }
  }
  stdout.writeln('Generating "$code" from source: $source');
  if (source == 'scrollmapper') {
    await generateFromScrollmapper(code, csvPath);
  } else {
    await generateFromBibleApi(code);
  }
}