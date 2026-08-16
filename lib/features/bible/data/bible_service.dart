import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'study_settings_provider.dart';
import 'bible_verse_service.dart';

class BibleVerse {
  final int chapter;
  final int verse;
  final String text;

  BibleVerse({required this.chapter, required this.verse, required this.text});

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    return BibleVerse(
      chapter: json['chapter'],
      verse: json['verse'],
      text: json['text'],
    );
  }
}

class ParsedReference {
  final String book; // canonical book name used for fetching
  final int chapter;
  final int? verseStart;
  final int? verseEnd;
  final String raw;

  const ParsedReference({
    required this.book,
    required this.chapter,
    this.verseStart,
    this.verseEnd,
    required this.raw,
  });

  bool get hasVerses => verseStart != null;
}

/// Parses "John 3:16", "Psalm 23:1-6", "1 Corinthians 13:4-5",
/// "Exodus 20" (whole chapter) and normalizes book aliases
/// (Psalm -> Psalms, Song of Songs -> Song of Solomon).
ParsedReference? parseScriptureReference(String reference) {
  final trimmed = reference.trim();
  final colonIdx = trimmed.indexOf(':');
  final left = colonIdx == -1 ? trimmed : trimmed.substring(0, colonIdx);
  final right = colonIdx == -1 ? '' : trimmed.substring(colonIdx + 1);

  final leftParts = left.trim().split(RegExp(r'\s+'));
  if (leftParts.isEmpty) return null;
  final chapterStr = leftParts.last.split('-').first.trim(); // "7-12" -> 7
  final chapterNum = int.tryParse(chapterStr);
  if (chapterNum == null) return null;
  final rawBook = leftParts.sublist(0, leftParts.length - 1).join(' ');
  if (rawBook.isEmpty) return null;

  const aliases = {
    'psalm': 'Psalms',
    'song of songs': 'Song of Solomon',
    'revelations': 'Revelation',
    'canticle of canticles': 'Song of Solomon',
  };
  final book = aliases[rawBook.toLowerCase()] ?? rawBook;

  int? verseStart;
  int? verseEnd;
  if (right.isNotEmpty) {
    final range = right.split('-');
    verseStart = int.tryParse(range[0].trim());
    verseEnd = range.length > 1 ? int.tryParse(range[1].trim()) : verseStart;
    if (verseEnd != null && verseEnd < (verseStart ?? 0)) verseEnd = verseStart;
  }

  return ParsedReference(
    book: book,
    chapter: chapterNum,
    verseStart: verseStart,
    verseEnd: verseEnd,
    raw: trimmed,
  );
}

class BibleSearchHit {
  final String reference;
  final String text;
  final String book;
  final String translation;

  const BibleSearchHit({
    required this.reference,
    required this.text,
    required this.book,
    required this.translation,
  });
}

class BibleService {
  /// Translations that bible-api.com serves remotely (fallback layer).
  static const _remoteCodes = {'kjv', 'web', 'asv', 'bbe', 'ylt', 'dra'};

  /// Translations that are seeded in the local Supabase bible_verses table.
  /// KJV is fully seeded (13 batch migrations); NKJV/NLT (not free to
  /// self-host) also live here. Reading from the local table is instant and
  /// never depends on external APIs — this is the primary KJV source.
  static const _dbCodes = {'kjv', 'nkjv', 'nlt'};

  /// Translations self-hosted on Cloudflare R2 (media.churchonapp.com) —
  /// whole books fetched once, then chapters read from the local cache.
  static const _r2Codes = {
    'kjv', 'web', 'dra', 'asv', 'bbe', 'ylt', 'geneva1599', 'acv', 'cpdv',
    'darby', 'jubilee2000', 'mkjv', 'nheb', 'noyes', 'rlt', 'rnkjv',
    'rotherham', 'ukjv', 'webster', 'tyndale', 'oeb',
  };

  Future<List<BibleVerse>> getChapter(
    String translation,
    String book,
    int chapter,
  ) async {
    final cacheKey = 'bible_${translation}_${book}_$chapter';

    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        final List versesJson = json.decode(cachedData);
        return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
      }

      // NKJV/NLT (and KJV/WEB) live in the local Supabase table — use it when
      // bible-api.com doesn't support the requested translation.
      if (_dbCodes.contains(translation)) {
        final dbVerses = await _fetchFromDb(translation, book, chapter);
        if (dbVerses.isNotEmpty) {
          await prefs.setString(
            cacheKey,
            json.encode(
              dbVerses
                  .map(
                    (v) => {
                      'chapter': v.chapter,
                      'verse': v.verse,
                      'text': v.text,
                    },
                  )
                  .toList(),
            ),
          );
          return dbVerses;
        }
      }

      // Self-hosted translations live on Cloudflare R2 — fetch the whole
      // book once, cache it, then pull the chapter locally.
      if (_r2Codes.contains(translation)) {
        final r2Verses = await _fetchFromR2(translation, book, chapter);
        if (r2Verses.isNotEmpty) {
          await prefs.setString(cacheKey, json.encode(r2Verses));
          return r2Verses.map((v) => BibleVerse.fromJson(v)).toList();
        }
      }

      if (_remoteCodes.contains(translation)) {
        final encodedBook = Uri.encodeComponent(book);
        final response = await http
            .get(
              Uri.parse(
                'https://bible-api.com/$encodedBook+$chapter?translation=$translation',
              ),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List versesJson = data['verses'] ?? [];

          if (versesJson.isNotEmpty) {
            await prefs.setString(cacheKey, json.encode(versesJson));
          }

          return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
        }
      }
      
      // All online sources returned empty — try offline asset as final fallback
      debugPrint('BibleService: All online sources empty for $translation $book $chapter, trying offline asset');
      return await _fetchFromOfflineAsset(translation, book, chapter);
    } catch (e) {
      debugPrint('Bible Error: $e — trying cache then offline asset');
      try {
        final prefs2 = await SharedPreferences.getInstance();
        final cachedData = prefs2.getString(cacheKey);
        if (cachedData != null) {
          final List versesJson = json.decode(cachedData);
          return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
        }
      } catch (e) {
        debugPrint('BibleService: Cache fallback failed: $e');
      }
      return _fetchFromOfflineAsset(translation, book, chapter);
    }
  }

  Future<List<BibleVerse>> _fetchFromOfflineAsset(
    String translation,
    String book,
    int chapter,
  ) async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/offline_bible_data.json',
      );
      final Map<String, dynamic> allData = json.decode(jsonString);
      final Map<String, dynamic>? translationData =
          allData[translation] as Map<String, dynamic>?;
      final Map<String, dynamic>? bookData =
          translationData?[book] as Map<String, dynamic>?;
      final List<dynamic>? chapterData =
          bookData?[chapter.toString()] as List<dynamic>?;
      if (chapterData != null) {
        return chapterData
            .map((v) => BibleVerse.fromJson(v as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('BibleService: Offline asset fallback failed: $e');
    }
    return [];
  }

  static const _r2Base = 'https://media.churchonapp.com/bible-text';

  Future<List<Map<String, dynamic>>> _fetchFromR2(
    String translation,
    String book,
    int chapter,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final bookKey = 'bible_book_${translation}_$book';
    try {
      final cached = prefs.getString(bookKey);
      if (cached != null) {
        final bookData = json.decode(cached) as Map<String, dynamic>;
        final verses = bookData[chapter.toString()] as List<dynamic>?;
        if (verses != null) {
          return verses.cast<Map<String, dynamic>>();
        }
      }
      final fileName = book.replaceAll(' ', '_');
      final response = await http
          .get(Uri.parse('$_r2Base/$translation/$fileName.json'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as Map<String, dynamic>;
      final chapters = data['chapters'] as Map<String, dynamic>? ?? {};
      await prefs.setString(bookKey, json.encode(chapters));
      final verses = chapters[chapter.toString()] as List<dynamic>?;
      return verses?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      debugPrint('Bible R2 fetch failed for $book $chapter: $e');
      return [];
    }
  }

  Future<List<BibleVerse>> _fetchFromDb(
    String translation,
    String book,
    int chapter,
  ) async {
    try {
      final client = Supabase.instance.client;
      final transRow = await client
          .from('bible_translations')
          .select('id')
          .eq('code', translation)
          .maybeSingle();
      if (transRow == null) return [];

      final bookRow = await client
          .from('bible_books')
          .select('id')
          .eq('name', book)
          .maybeSingle();
      if (bookRow == null) return [];

      final data = await client
          .from('bible_verses')
          .select('chapter, verse, text')
          .eq('translation_id', transRow['id'])
          .eq('book_id', bookRow['id'])
          .eq('chapter', chapter)
          .order('verse', ascending: true);

      return (data as List)
          .map(
            (v) => BibleVerse(
              chapter: (v['chapter'] as num?)?.toInt() ?? chapter,
              verse: (v['verse'] as num?)?.toInt() ?? 0,
              text: v['text']?.toString() ?? '',
            ),
          )
          .toList();
    } catch (e) {
      debugPrint(
        'BibleService DB fetch failed for $translation $book $chapter: $e',
      );
      return [];
    }
  }

  /// Fetches the text for a scripture reference ("John 3:16", "Psalm 23:1-6",
  /// "Exodus 20") in the given translation. Returns '' when unavailable.
  Future<String> getReferenceText(
    String translation,
    String reference,
  ) async {
    final parsed = parseScriptureReference(reference);
    if (parsed == null) return '';
    final verses = await getChapter(translation, parsed.book, parsed.chapter);
    if (verses.isEmpty) return '';
    if (!parsed.hasVerses) {
      return verses.map((v) => v.text).join(' ');
    }
    final start = (parsed.verseStart ?? 1) - 1;
    final end = (parsed.verseEnd ?? parsed.verseStart ?? 1) - 1;
    final selected = <BibleVerse>[];
    for (var i = start; i <= end && i < verses.length; i++) {
      if (i >= 0) selected.add(verses[i]);
    }
    if (selected.isEmpty) return '';
    return selected.map((v) => v.text).join(' ');
  }

  /// Searches locally cached R2 books (all translations the user has opened)
  /// for [query]. Returns up to [limit] matches with references.
  Future<List<BibleSearchHit>> searchCachedBooks(
    String query, {
    int limit = 30,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final hits = <BibleSearchHit>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('bible_book_'));
      for (final key in keys) {
        if (hits.length >= limit) break;
        final parts = key.split('_');
        // bible_book_<translation>_<book>
        final translation = parts.length > 2 ? parts[2] : '';
        final book = parts.sublist(3).join('_');
        if (translation.isEmpty || book.isEmpty) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final chapters = json.decode(raw) as Map<String, dynamic>;
          for (final entry in chapters.entries) {
            if (hits.length >= limit) break;
            final verses = entry.value as List<dynamic>?;
            if (verses == null) continue;
            for (final v in verses) {
              final text = (v['text'] ?? '').toString();
              if (text.toLowerCase().contains(q)) {
                hits.add(
                  BibleSearchHit(
                    reference: '$book ${entry.key}:${v['verse']}',
                    text: text,
                    book: book,
                    translation: translation,
                  ),
                );
                if (hits.length >= limit) break;
              }
            }
          }
        } catch (_) {
          // skip malformed cache entry
        }
      }
    } catch (e) {
      debugPrint('BibleService cached search failed: $e');
    }
    return hits;
  }
}

final bibleServiceProvider = Provider((ref) => BibleService());

final bibleChapterProvider =
    FutureProvider.family<List<BibleVerse>, Map<String, dynamic>>((
      ref,
      params,
    ) async {
      return ref
          .watch(bibleServiceProvider)
          .getChapter(
            params['translation'] ?? 'kjv',
            params['book'] ?? 'John',
            params['chapter'] ?? 1,
          );
    });

/// Fetches the text of a scripture reference in the user's preferred
/// translation (falls back to '' when unavailable).
final bibleReferenceTextProvider =
    FutureProvider.family<String, String>((ref, reference) async {
      final translation = ref
          .watch(studySettingsProvider)
          .preferredTranslation;
      return ref
          .watch(bibleServiceProvider)
          .getReferenceText(translation, reference);
    });

/// Full-text search: live Supabase DB (all translations) + locally cached
/// R2 books, merged and deduplicated by reference.
final scriptureSearchProvider =
    FutureProvider.family<List<BibleSearchHit>, String>((ref, query) async {
      final q = query.trim();
      if (q.isEmpty) return const [];
      final hits = <BibleSearchHit>[];
      final seen = <String>{};

      final dbResults = await ref
          .read(bibleVerseServiceProvider)
          .searchVerses(query: q, limit: 40);
      for (final row in dbResults) {
        final refText = row['reference']?.toString() ?? '';
        final text = row['text']?.toString() ?? '';
        if (refText.isEmpty || text.isEmpty) continue;
        final key = '$refText|$text';
        if (seen.contains(key)) continue;
        seen.add(key);
        hits.add(
          BibleSearchHit(
            reference: refText,
            text: text,
            book: row['book_name']?.toString() ?? '',
            translation: row['translation_code']?.toString() ?? '',
          ),
        );
      }

      final cached = await ref
          .read(bibleServiceProvider)
          .searchCachedBooks(q, limit: 30);
      for (final hit in cached) {
        if (seen.contains('${hit.reference}|${hit.text}')) continue;
        seen.add('${hit.reference}|${hit.text}');
        hits.add(hit);
      }

      return hits;
    });

/// Single-verse text in a parallel translation (used by the verse detail
/// view for translation comparison).
final parallelVerseTextProvider =
    FutureProvider.family<String, Map<String, dynamic>>((ref, params) async {
      final verses = await ref.read(bibleServiceProvider).getChapter(
            params['translation'] as String,
            params['book'] as String,
            params['chapter'] as int,
          );
      final target = params['verse'] as int;
      for (final v in verses) {
        if (v.verse == target) return v.text;
      }
      return '';
    });

/// Cross-references for a single verse (tappable in the verse detail view).
final verseCrossReferencesProvider =
    FutureProvider.family<List<CrossReference>, Map<String, dynamic>>((
      ref,
      params,
    ) async {
      return ref.watch(bibleVerseServiceProvider).fetchCrossReferences(
            bookId: params['bookId'] as int,
            chapter: params['chapter'] as int,
            verse: params['verse'] as int,
          );
    });
