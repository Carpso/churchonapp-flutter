import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class BibleService {
  /// Translations that bible-api.com serves remotely.
  static const _remoteCodes = {'kjv', 'web', 'asv', 'bbe', 'ylt', 'dra'};

  /// Translations that are seeded in the local Supabase bible_verses table.
  /// NOTE: KJV/WEB are fetched from bible-api.com (reliable remote source);
  /// only NKJV/NLT (not on bible-api.com) use the local table.
  static const _dbCodes = {'nkjv', 'nlt'};

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

      // KJV is self-hosted on Cloudflare R2 (media.churchonapp.com) — fetch
      // the whole book once, cache it, then pull the chapter locally.
      if (translation == 'kjv') {
        final r2Verses = await _fetchFromR2(book, chapter);
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
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List versesJson = data['verses'] ?? [];

          if (versesJson.isNotEmpty) {
            await prefs.setString(cacheKey, json.encode(versesJson));
          }

          return versesJson.map((v) => BibleVerse.fromJson(v)).toList();
        }
      }
      return [];
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
      } catch (e2) {
        debugPrint('Offline Bible fallback failed: $e2');
      }
      return [];
    }
  }

  static const _r2Base = 'https://media.churchonapp.com/bible-text/kjv';

  Future<List<Map<String, dynamic>>> _fetchFromR2(
    String book,
    int chapter,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final bookKey = 'bible_book_kjv_$book';
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
          .get(Uri.parse('$_r2Base/$fileName.json'))
          .timeout(const Duration(seconds: 15));
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
            params['translation'] ?? 'web',
            params['book'] ?? 'John',
            params['chapter'] ?? 1,
          );
    });
