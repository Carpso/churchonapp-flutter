import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class DailyBibleVerse {
  final String id;
  final String reference;
  final String text;
  final DateTime createdAt;

  DailyBibleVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.createdAt,
  });

  factory DailyBibleVerse.fromMap(Map<String, dynamic> map) {
    return DailyBibleVerse(
      id: map['id']?.toString() ?? '',
      reference: map['reference'] ?? map['media_url'] ?? 'Scripture',
      text: map['text'] ?? map['content'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }
}

class VerseNote {
  final String id;
  final int? chapter;
  final int? verse;
  final String note;
  final bool isBookmark;
  final bool isFavorite;
  final List<String> tags;
  final DateTime createdAt;

  VerseNote({
    required this.id,
    this.chapter,
    this.verse,
    required this.note,
    required this.isBookmark,
    required this.isFavorite,
    required this.tags,
    required this.createdAt,
  });

  factory VerseNote.fromMap(Map<String, dynamic> map) {
    return VerseNote(
      id: map['id']?.toString() ?? '',
      chapter: map['chapter'] as int?,
      verse: map['verse'] as int?,
      note: map['note'] ?? '',
      isBookmark: map['is_bookmark'] ?? false,
      isFavorite: map['is_favorite'] ?? false,
      tags: List<String>.from(map['tags'] ?? []),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }
}

class CrossReference {
  final String sourceRef;
  final String targetRef;
  final String type;

  CrossReference({
    required this.sourceRef,
    required this.targetRef,
    required this.type,
  });

  factory CrossReference.fromMap(Map<String, dynamic> map) {
    return CrossReference(
      sourceRef: map['source_ref'] ?? '',
      targetRef: map['target_ref'] ?? '',
      type: map['reference_type'] ?? 'parallel',
    );
  }
}

class ChapterSummary {
  final String summary;
  final List<String> keyVerses;
  final List<String> themes;

  ChapterSummary({
    required this.summary,
    required this.keyVerses,
    required this.themes,
  });

  factory ChapterSummary.fromMap(Map<String, dynamic> map) {
    return ChapterSummary(
      summary: map['summary'] ?? '',
      keyVerses: List<String>.from(map['key_verses'] ?? []),
      themes: List<String>.from(map['themes'] ?? []),
    );
  }
}

class BibleVerseService {
  final SupabaseClient _client;
  BibleVerseService(this._client);

  Future<DailyBibleVerse> fetchLatestVerse() async {
    try {
      final response = await _client
          .from('daily_bible_verses')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return DailyBibleVerse.fromMap(response);
      }
    } catch (e) {
      debugPrint('Querying daily_bible_verses failed, falling back: $e');
      debugPrint(e.toString());
    }

    try {
      final response = await _client
          .from('social_posts')
          .select()
          .eq('category', 'daily_verse')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return DailyBibleVerse.fromMap(response);
      }
    } catch (e, s) {
      debugPrint('Querying fallback social_posts failed: $e');
      debugPrint(s.toString());
    }

    try {
      final response = await _client
          .from('bible_verses')
          .select('id, reference, text')
          .limit(1)
          .maybeSingle();
      if (response != null) {
        return DailyBibleVerse(
          id: response['id']?.toString() ?? 'random',
          reference: response['reference'] ?? 'Scripture',
          text: response['text'] ?? '',
          createdAt: DateTime.now(),
        );
      }
    } catch (e, s) {
      debugPrint('Querying random bible_verses failed: $e');
      debugPrint(s.toString());
    }

    return DailyBibleVerse(
      id: 'default',
      reference: 'Jeremiah 29:11',
      text:
          'For I know the thoughts that I think toward you, saith the Lord, thoughts of peace, and not of evil, to give you an expected end.',
      createdAt: DateTime.now(),
    );
  }

  Future<void> postDailyVerse({
    required String reference,
    required String text,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('daily_bible_verses').insert({
        'reference': reference,
        'text': text,
        'posted_by': user.id,
      });
      debugPrint('Successfully posted to daily_bible_verses');
    } catch (e, s) {
      debugPrint('Posting to daily_bible_verses failed, falling back: $e');
      debugPrint(s.toString());
      await _client.from('social_posts').insert({
        'user_id': user.id,
        'content': text,
        'media_url': reference,
        'category': 'daily_verse',
      });
      debugPrint('Successfully posted to fallback social_posts');
    }
  }

  Future<List<Map<String, dynamic>>> searchVerses({
    required String query,
    String? translationCode,
    int limit = 20,
  }) async {
    try {
      final searchQuery = query.trim();
      if (searchQuery.isEmpty) return [];
      final escaped = searchQuery
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');

      dynamic queryBuilder = _client
          .from('bible_verses')
          .select(
            'id, reference, text, chapter, verse, '
            'book:bible_books(name), translation:bible_translations(code)',
          )
          .ilike('text', '%$escaped%')
          .order('verse', ascending: true)
          .limit(limit);

      if (translationCode != null) {
        final translation = await _client
            .from('bible_translations')
            .select('id')
            .eq('code', translationCode)
            .maybeSingle();
        if (translation != null) {
          queryBuilder = queryBuilder.eq('translation_id', translation['id']);
        }
      }

      final data = await queryBuilder;
      return (data as List<dynamic>).map((row) {
        final book = row['book'];
        final translation = row['translation'];
        return {
          'id': row['id'],
          'reference': row['reference'],
          'text': row['text'],
          'chapter': row['chapter'],
          'verse': row['verse'],
          'book_name':
              (book is Map ? book['name'] : null)?.toString() ?? '',
          'translation_code':
              (translation is Map ? translation['code'] : null)?.toString() ??
                  '',
        };
      }).toList();
    } catch (e, s) {
      debugPrint('Search verses error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  Future<List<VerseNote>> fetchVerseNotes({
    int? bookId,
    int? chapter,
    int? verse,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return [];

      var queryBuilder = _client
          .from('verse_notes')
          .select('id, note, is_bookmark, is_favorite, tags, created_at, chapter, verse')
          .eq('user_id', user.id);

      if (bookId != null) {
        queryBuilder = queryBuilder.eq('book_id', bookId);
      }
      if (chapter != null) {
        queryBuilder = queryBuilder.eq('chapter', chapter);
      }
      if (verse != null) {
        queryBuilder = queryBuilder.eq('verse', verse);
      }

      final data = await queryBuilder.order('created_at', ascending: false);
      return (data as List<dynamic>)
          .map((row) => VerseNote.fromMap(row))
          .toList();
    } catch (e, s) {
      debugPrint('Fetch verse notes error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Upsert semantics: one note row per user/book/chapter/verse. Re-saving
  /// updates the existing row instead of inserting a duplicate (the old
  /// always-INSERT behavior doubled every highlight/note on repeat taps).
  Future<VerseNote?> addVerseNote({
    required int bookId,
    required int chapter,
    required int verse,
    required String note,
    bool isBookmark = false,
    bool isFavorite = false,
    List<String> tags = const [],
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final book = await _client
          .from('bible_books')
          .select('id')
          .eq('book_order', bookId)
          .maybeSingle();

      if (book == null) return null;

      // Look up an existing note for this exact verse first.
      final existing = await _client
          .from('verse_notes')
          .select('id')
          .eq('user_id', user.id)
          .eq('book_id', book['id'])
          .eq('chapter', chapter)
          .eq('verse', verse)
          .maybeSingle();

      final payload = {
        'note': note,
        'is_bookmark': isBookmark,
        'is_favorite': isFavorite,
        'tags': tags,
      };

      final response = existing != null
          ? await _client
              .from('verse_notes')
              .update(payload)
              .eq('id', existing['id'])
              .select()
              .maybeSingle()
          : await _client
              .from('verse_notes')
              .insert({
                'user_id': user.id,
                'book_id': book['id'],
                'chapter': chapter,
                'verse': verse,
                ...payload,
              })
              .select()
              .maybeSingle();

      if (response != null) {
        return VerseNote.fromMap(response);
      }
    } catch (e, s) {
      debugPrint('Add verse note error: $e');
      debugPrint(s.toString());
    }
    return null;
  }

  /// Deletes a verse note/highlight entirely (toggle-off + explicit delete).
  Future<bool> deleteVerseNote(String noteId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client.from('verse_notes').delete().eq('id', noteId);
      return true;
    } catch (e) {
      debugPrint('Delete verse note error: $e');
      return false;
    }
  }

  Future<List<CrossReference>> fetchCrossReferences({
    required int bookId,
    required int chapter,
    required int verse,
  }) async {
    try {
      final book = await _client
          .from('bible_books')
          .select('id')
          .eq('book_order', bookId)
          .maybeSingle();

      if (book == null) return [];

      final data = await _client
          .from('cross_references')
          .select('''
            id,
            source_book_id,
            source_chapter,
            source_verse,
            target_book_id,
            target_chapter,
            target_verse,
            reference_type,
            target_book:bible_books(name, abbreviation)
          ''')
          .eq('source_book_id', book['id'])
          .eq('source_chapter', chapter)
          .eq('source_verse', verse);

      return (data as List<dynamic>)
          .map((row) {
            final targetBook = row['target_book'] as Map<String, dynamic>?;
            return CrossReference(
              sourceRef: '$bookId $chapter:$verse',
              targetRef:
                  '${targetBook?['abbreviation'] ?? targetBook?['name'] ?? 'Unknown'} ${row['target_chapter']}:${row['target_verse']}',
              type: row['reference_type'] ?? 'parallel',
            );
          })
          .toList();
    } catch (e, s) {
      debugPrint('Fetch cross-references error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  Future<ChapterSummary?> fetchChapterSummary({
    required int bookId,
    required int chapter,
    String? translationCode,
  }) async {
    try {
      final book = await _client
          .from('bible_books')
          .select('id')
          .eq('book_order', bookId)
          .maybeSingle();

      if (book == null) return null;

      dynamic translationId;
      if (translationCode != null) {
        final translation = await _client
            .from('bible_translations')
            .select('id')
            .eq('code', translationCode)
            .maybeSingle();
        translationId = translation?['id'];
      }

      var queryBuilder = _client
          .from('bible_chapter_summaries')
          .select('summary, key_verses, themes')
          .eq('book_id', book['id'])
          .eq('chapter_number', chapter);

      if (translationId != null) {
        queryBuilder = queryBuilder.eq('translation_id', translationId);
      }

      final response = await queryBuilder.maybeSingle();
      if (response != null) {
        return ChapterSummary.fromMap(response);
      }
    } catch (e, s) {
      debugPrint('Fetch chapter summary error: $e');
      debugPrint(s.toString());
    }
    return null;
  }

  Future<ChapterSummary?> generateChapterSummary({
    required int bookId,
    required int chapter,
    String? translationCode,
  }) async {
    try {
      final book = await _client
          .from('bible_books')
          .select('id, name')
          .eq('book_order', bookId)
          .maybeSingle();

      if (book == null) return null;

      final verses = await _client
          .from('bible_verses')
          .select('text')
          .eq('book_id', book['id'])
          .eq('chapter', chapter)
          .order('verse', ascending: true);

      if (verses.isEmpty) return null;

      final verseTexts = (verses as List<dynamic>)
          .map((v) => v['text'] ?? '')
          .join(' ');

      final user = _client.auth.currentUser;
      if (user == null) return null;

      final summary = await _client.functions.invoke('kael-ai', body: {
        'action': 'summary',
        'prompt':
            'Provide a concise chapter summary for ${book['name']} chapter $chapter. Include key themes, main message, and 3-5 key verses. Chapter text: $verseTexts',
      });

      final summaryText = summary.data?['response'] ?? 'No summary available.';

      dynamic tid;
      if (translationCode != null) {
        final translation = await _client
            .from('bible_translations')
            .select('id')
            .eq('code', translationCode)
            .maybeSingle();
        tid = translation?['id'];
      }

      await _client.from('bible_chapter_summaries').upsert({
        'book_id': book['id'],
        'translation_id': tid,
        'chapter_number': chapter,
        'summary': summaryText,
        'key_verses': [],
        'themes': [],
        'ai_model': 'kael',
        'generated_by': user.id,
      });

      return ChapterSummary(
        summary: summaryText,
        keyVerses: [],
        themes: [],
      );
    } catch (e, s) {
      debugPrint('Generate chapter summary error: $e');
      debugPrint(s.toString());
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchReadingPlans({
    bool activeOnly = true,
  }) async {
    try {
      var queryBuilder = _client
          .from('reading_plans')
          .select('id, name, description, plan_type, day_count, start_date, created_at');

      if (activeOnly) {
        queryBuilder = queryBuilder.eq('is_active', true);
      }

      final data = await queryBuilder.order('created_at', ascending: false);
      return (data as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e, s) {
      debugPrint('Fetch reading plans error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchReadingPlanEntries({
    required String planId,
  }) async {
    try {
      final data = await _client
          .from('reading_plan_entries')
          .select('''
            id,
            day_number,
            book_id,
            chapter,
            verse_start,
            verse_end,
            book:bible_books(name, abbreviation, book_order)
          ''')
          .eq('plan_id', planId)
          .order('day_number', ascending: true);

      return (data as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e, s) {
      debugPrint('Fetch reading plan entries error: $e');
      debugPrint(s.toString());
      return [];
    }
  }
}

final bibleVerseServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return BibleVerseService(client);
});

final dailyBibleVerseProvider = FutureProvider<DailyBibleVerse>((ref) async {
  return ref.watch(bibleVerseServiceProvider).fetchLatestVerse();
});

final bibleSearchProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, query) async {
    return ref.watch(bibleVerseServiceProvider).searchVerses(query: query);
  },
);

final verseNotesProvider = FutureProvider.family<List<VerseNote>, Map<String, dynamic>>(
  (ref, params) async {
    return ref.watch(bibleVerseServiceProvider).fetchVerseNotes(
      bookId: params['bookId'] as int?,
      chapter: params['chapter'] as int?,
      verse: params['verse'] as int?,
    );
  },
);

final chapterSummaryProvider = FutureProvider.family<ChapterSummary?, Map<String, dynamic>>(
  (ref, params) async {
    return ref.watch(bibleVerseServiceProvider).fetchChapterSummary(
      bookId: params['bookId'] as int,
      chapter: params['chapter'] as int,
      translationCode: params['translationCode'] as String?,
    );
  },
);