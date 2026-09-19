import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/features/bible/data/curated_daily_verses.dart';

class DailyBibleVerse {
  final String id;
  final String reference;
  final String text;
  final DateTime createdAt;
  final String theme;

  DailyBibleVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.createdAt,
    this.theme = '',
  });

  factory DailyBibleVerse.fromMap(Map<String, dynamic> map) {
    return DailyBibleVerse(
      id: map['id']?.toString() ?? '',
      reference: map['reference'] ?? map['media_url'] ?? 'Scripture',
      text: map['text'] ?? map['content'] ?? '',
      theme: map['theme']?.toString() ?? '',
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
  final bool isLiked;
  final List<String> tags;
  final DateTime createdAt;

  VerseNote({
    required this.id,
    this.chapter,
    this.verse,
    required this.note,
    required this.isBookmark,
    required this.isFavorite,
    this.isLiked = false,
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
      isLiked: map['is_liked'] ?? false,
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

  /// Verse of the Day — curated, thematic rotation served server-side by the
  /// `get_verse_of_the_day(p_date)` RPC over the `daily_verse_pool` table.
  ///
  /// Deterministic per calendar day (same verse for everyone, stable across
  /// reinstalls/tenants), complete KJV sentences, no repeat within ~60 days
  /// (the pool is >= 120 verses and rotates as a full cycle). When the RPC is
  /// unreachable we fall back to a small built-in uplifting set — NEVER to
  /// random `bible_verses` rows (those produced contextless fragments).
  Future<DailyBibleVerse> fetchLatestVerse() async {
    final today = DateTime.now();
    final isoDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    try {
      final data = await _client.rpc(
        'get_verse_of_the_day',
        params: {'p_date': isoDate},
      );
      Map<String, dynamic>? row;
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map) row = Map<String, dynamic>.from(first);
      } else if (data is Map) {
        row = Map<String, dynamic>.from(data);
      }
      final text = row?['verse_text']?.toString() ?? '';
      final reference = row?['reference']?.toString() ?? '';
      if (text.trim().isNotEmpty && reference.trim().isNotEmpty) {
        debugPrint('[BibleVerseService] VOTD RPC $isoDate ref=$reference');
        return DailyBibleVerse(
          id: 'votd_$isoDate',
          reference: reference,
          text: text,
          theme: row?['theme']?.toString() ?? '',
          createdAt: DateTime(today.year, today.month, today.day),
        );
      }
    } catch (e) {
      debugPrint('[BibleVerseService] VOTD RPC failed, using curated set: $e');
    }

    final curated = curatedVerseForDate(today);
    return DailyBibleVerse(
      id: 'votd_curated_$isoDate',
      reference: curated.reference,
      text: curated.text,
      theme: curated.theme,
      createdAt: DateTime(today.year, today.month, today.day),
    );
  }

  /// Deprecated: the Verse of the Day is now a curated rotation served by the
  /// `get_verse_of_the_day(p_date)` RPC (with a built-in uplifting fallback).
  /// Kept for test compat; no longer called from UI.
  @Deprecated('VOTD is served by the curated daily_verse_pool rotation')
  Future<void> postDailyVerse({
    required String reference,
    required String text,
  }) async {
    debugPrint('[BibleVerseService] postDailyVerse deprecated — VOTD is the curated rotation, ignoring manual insert');
    return;
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

      // `verse_notes.book_id` is a UUID FK to `bible_books(id)`, but callers
      // pass the integer book ORDER. Resolve it first — filtering a uuid column
      // with an int raised 22P02, was swallowed, and made every verse read as
      // "not highlighted".
      String? bookUuid;
      if (bookId != null) {
        final book = await _client
            .from('bible_books')
            .select('id')
            .eq('book_order', bookId)
            .maybeSingle();
        if (book == null) return [];
        bookUuid = book['id'] as String;
      }

      var queryBuilder = _client
          .from('verse_notes')
          .select('id, note, is_bookmark, is_favorite, is_liked, tags, created_at, chapter, verse')
          .eq('user_id', user.id);

      if (bookUuid != null) {
        queryBuilder = queryBuilder.eq('book_id', bookUuid);
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
    bool isLiked = false,
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
        'is_liked': isLiked,
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

  /// Flips one or more boolean flags (highlight/bookmark/like) on a verse
  /// while PRESERVING any existing note text and the other flags. Upserts the
  /// row when nothing exists yet.
  Future<VerseNote?> setVerseFlag({
    required int bookId,
    required int chapter,
    required int verse,
    bool? isBookmark,
    bool? isFavorite,
    bool? isLiked,
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

      final existing = await _client
          .from('verse_notes')
          .select('id, note, is_bookmark, is_favorite, is_liked, tags')
          .eq('user_id', user.id)
          .eq('book_id', book['id'])
          .eq('chapter', chapter)
          .eq('verse', verse)
          .maybeSingle();

      final currentNote = existing?['note']?.toString() ?? '';
      final currentBookmark = existing?['is_bookmark'] ?? false;
      final currentFavorite = existing?['is_favorite'] ?? false;
      final currentLiked = existing?['is_liked'] ?? false;
      final currentTags =
          List<String>.from(existing?['tags'] ?? const []);

      final payload = {
        'note': currentNote,
        'is_bookmark': isBookmark ?? currentBookmark,
        'is_favorite': isFavorite ?? currentFavorite,
        'is_liked': isLiked ?? currentLiked,
        'tags': currentTags,
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
      debugPrint('Set verse flag error: $e');
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

  /// Fetches cross-references for a verse — BOTH directions (source→target
  /// and target→source) so any verse in a pair surfaces its counterpart.
  /// Fallback: when the local DB has nothing, asks kael (`cross_ref`) for
  /// scholarly cross-references and persists what parses cleanly.
  Future<List<CrossReference>> fetchCrossReferences({
    required int bookId,
    required int chapter,
    required int verse,
    String? verseText,
    bool allowAiFallback = true,
  }) async {
    try {
      final book = await _client
          .from('bible_books')
          .select('id, name')
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
            source_book:bible_books!(source_book_id)(name, abbreviation),
            target_book:bible_books!(target_book_id)(name, abbreviation)
          ''')
          .or(
            'and(source_book_id.eq.${book['id']},source_chapter.eq.$chapter,source_verse.eq.$verse),'
            'and(target_book_id.eq.${book['id']},target_chapter.eq.$chapter,target_verse.eq.$verse)',
          );

      final refs = (data as List<dynamic>)
          .map((row) {
            final targetBook = row['target_book'] as Map<String, dynamic>?;
            final sourceBook = row['source_book'] as Map<String, dynamic>?;
            // Reverse-direction row: THIS verse matched as the *target*, so
            // the counterpart is the source (book AND its chapter:verse).
            final isReverse =
                '${row['target_book_id']}' == '${book['id']}';
            final counterpart =
                isReverse ? sourceBook : targetBook;
            return CrossReference(
              sourceRef: '${book['name']} $chapter:$verse',
              targetRef:
                  '${counterpart?['abbreviation'] ?? counterpart?['name'] ?? 'Unknown'} '
                  '${isReverse ? row['source_chapter'] : row['target_chapter']}:'
                  '${isReverse ? row['source_verse'] : row['target_verse']}',
              type: row['reference_type'] ?? 'parallel',
            );
          })
          .toList();

      if (refs.isNotEmpty || !allowAiFallback) return refs;

      final aiRefs = await generateCrossReferences(
        bookId: bookId,
        chapter: chapter,
        verse: verse,
        verseText: verseText,
      );
      return aiRefs.isNotEmpty ? aiRefs : const [];
    } catch (e, s) {
      debugPrint('Fetch cross-references error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Asks kael for cross-references and best-effort persists parsed ones.
  Future<List<CrossReference>> generateCrossReferences({
    required int bookId,
    required int chapter,
    required int verse,
    String? verseText,
  }) async {
    try {
      final book = await _client
          .from('bible_books')
          .select('id, name')
          .eq('book_order', bookId)
          .maybeSingle();
      if (book == null) return [];

      final user = _client.auth.currentUser;
      if (user == null) return [];

      final response = await _client.functions.invoke('kael-ai', body: {
        'action': 'cross_ref',
        'prompt':
            'Find cross-references for ${book['name']} $chapter:$verse${verseText != null && verseText.trim().isNotEmpty ? ' — verse text: "$verseText"' : ''}. For each reference, give: the book chapter:verse, then a 1-sentence connection. Output plain text with each reference on its own line starting with "BibleRef: Book C:V".',
      });

      final text = response.data?['response']?.toString() ?? '';
      if (text.trim().isEmpty) return [];

      // Surface the AI explanation as the source text for display/parse.
      final parsed = _parseAiCrossReferences(text);

      // Persist clean parses (best-effort via the fresh authenticated INSERT
      // policy, idempotent through the unique pair index).
      final books = await _client
          .from('bible_books')
          .select('id, name');
      final byName = <String, dynamic>{};
      for (final b in books as List<dynamic>) {
        byName[(b as Map<String, dynamic>)['name']?.toString().toLowerCase() ??
            ''] = b;
      }

      for (final ref in parsed) {
        final target = byName[ref['book']!.toLowerCase()];
        if (target == null) continue;
        final targetChapter = ref['chapter'] as int;
        final targetVerse = ref['verse'] as int;
        if (targetChapter <= 0 || targetVerse <= 0) continue;
        try {
          await _client.from('cross_references').upsert({
            'source_book_id': book['id'],
            'source_chapter': chapter,
            'source_verse': verse,
            'target_book_id': target['id'],
            'target_chapter': targetChapter,
            'target_verse': targetVerse,
            'reference_type': 'thematic',
          }, onConflict:
              'source_book_id,source_chapter,source_verse,target_book_id,target_chapter,target_verse,reference_type');
        } catch (err) {
          debugPrint('Persist AI cross-ref failed: $err');
        }
      }

      return parsed.map((ref) {
        final target = byName[ref['book']!.toLowerCase()];
        return CrossReference(
          sourceRef: '${book['name']} $chapter:$verse',
          targetRef:
              '${target?['abbreviation'] ?? ref['book']} ${ref['chapter']}:${ref['verse']}',
          type: 'thematic',
        );
      }).toList();
    } catch (e, s) {
      debugPrint('Generate cross-references error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Parses AI cross-reference output lines of the form
  /// "BibleRef: Book C:V" or "Book C:V" into [{book, chapter, verse}].
  List<Map<String, dynamic>> _parseAiCrossReferences(String text) {
    final out = <Map<String, dynamic>>[];
    final re = RegExp(
      r'(?:BibleRef:\s*)?([A-Za-z]+(?:\s+[A-Za-z]+)*?)\s+(\d+):(\d+)',
    );
    for (final m in re.allMatches(text)) {
      final book = m.group(1)!.trim();
      final chapter = int.tryParse(m.group(2)!) ?? 0;
      final verse = int.tryParse(m.group(3)!) ?? 0;
      if (book.length < 3 || chapter <= 0 || verse <= 0) continue;
      out.add({'book': book, 'chapter': chapter, 'verse': verse});
    }
    return out;
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

  /// Toggles one reading-plan entry done/undone for the signed-in user via the
  /// `toggle_reading_plan_entry` RPC (server-authoritative progress). Returns
  /// the plan's new completed-entry count. Throws on failure so the caller can
  /// surface a snackbar.
  Future<int> toggleReadingPlanEntry({
    required String entryId,
    required bool done,
  }) async {
    if (_client.auth.currentUser == null) {
      throw Exception('Not authenticated');
    }
    final result = await _client.rpc(
      'toggle_reading_plan_entry',
      params: {'p_entry_id': entryId, 'p_done': done},
    );
    if (result is Map && result['ok'] == true) {
      return (result['completed'] as num?)?.toInt() ?? 0;
    }
    final reason = result is Map ? result['reason']?.toString() : null;
    throw Exception(reason ?? 'Could not update reading progress');
  }

  /// Completed entry ids for [planId] for the signed-in user, read from the
  /// `get_reading_plan_completed` RPC (persisted server-side, survives
  /// restarts). Returns an empty set on error/empty so the UI never crashes.
  Future<Set<String>> fetchCompletedPlanEntries(String planId) async {
    try {
      if (_client.auth.currentUser == null || planId.isEmpty) {
        return <String>{};
      }
      final data = await _client.rpc(
        'get_reading_plan_completed',
        params: {'p_plan_id': planId},
      );
      return (data as List<dynamic>)
          .map((row) => row is Map ? row['entry_id'] : row)
          .whereType<Object>()
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e, s) {
      debugPrint('Fetch completed plan entries error: $e');
      debugPrint(s.toString());
      return <String>{};
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

/// Value-equal family key for [verseNotesProvider] (a Map key has no value
/// equality → endless family churn; see the Riverpod rule in AGENTS.md).
typedef VerseNotesQuery = ({int? bookId, int? chapter, int? verse});

final verseNotesProvider =
    FutureProvider.family<List<VerseNote>, VerseNotesQuery>(
  (ref, q) async {
    return ref.watch(bibleVerseServiceProvider).fetchVerseNotes(
      bookId: q.bookId,
      chapter: q.chapter,
      verse: q.verse,
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