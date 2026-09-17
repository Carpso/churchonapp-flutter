import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'bible_verse_service.dart';

class ReadingPlan {
  final String id;
  final String title;
  final int totalDays;
  final String description;
  final List<String> dailyVerses;
  int completedDays;

  ReadingPlan({
    required this.id,
    required this.title,
    required this.totalDays,
    required this.description,
    required this.dailyVerses,
    this.completedDays = 0,
  });
}

class ReadingPlanService {
  final SupabaseClient _client;

  ReadingPlanService(this._client);

  List<ReadingPlan> _defaultPlans() => [
    ReadingPlan(id: 'faith_wisdom', title: "Faith & Wisdom", totalDays: 7, description: "A 7-day scripture journey through James and Proverbs.", dailyVerses: ["James 1:5-6", "James 2:14-17", "Proverbs 3:5-6", "Proverbs 4:7-9", "Proverbs 16:9", "James 3:17-18", "James 4:7-8"]),
    ReadingPlan(id: 'walking_in_love', title: "Walking in Love", totalDays: 5, description: "Explore Christ-centered love in Romans and Corinthians.", dailyVerses: ["1 Corinthians 13:1-3", "1 Corinthians 13:4-7", "1 Corinthians 13:8-13", "Romans 12:9-10", "Romans 13:8-10"]),
    ReadingPlan(id: 'prayer_power', title: "Power of Prayer", totalDays: 7, description: "Learn from the prayer lives of biblical heroes.", dailyVerses: ["Matthew 6:9-13", "Luke 11:9-10", "Philippians 4:6-7", "1 Thessalonians 5:16-18", "James 5:16-18", "Luke 18:1-8", "Ephesians 6:18"]),
    ReadingPlan(id: 'psalms_peace', title: "Psalms of Peace", totalDays: 10, description: "Find rest in the Psalms during life's storms.", dailyVerses: ["Psalm 23:1-6", "Psalm 46:1-3", "Psalm 91:1-4", "Psalm 121:1-8", "Psalm 27:1-4", "Psalm 34:4-8", "Psalm 42:1-5", "Psalm 62:5-8", "Psalm 139:1-6", "Psalm 150:1-6"]),
  ];

  Future<List<ReadingPlan>> getPlans() async {
    try {
      final data = await _client.from('reading_plans').select().order('created_at');
      final plans = (data as List).map((map) => ReadingPlan(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Plan',
        totalDays: int.tryParse(map['total_days']?.toString() ?? '7') ?? 7,
        description: map['description']?.toString() ?? '',
        dailyVerses: (map['daily_verses'] as List?)?.map((v) => v.toString()).toList() ?? [],
      )).toList();

      if (plans.isNotEmpty) {
        final user = _client.auth.currentUser;
        if (user != null) {
          try {
            final progress = await _client.from('user_reading_progress').select().eq('user_id', user.id);
            final progressMap = <String, int>{};
            for (final p in progress as List) {
              progressMap[p['plan_id']?.toString() ?? ''] = int.tryParse(p['completed_days']?.toString() ?? '0') ?? 0;
            }
            for (final plan in plans) {
              plan.completedDays = progressMap[plan.id] ?? 0;
            }
          } catch (e) {
            debugPrint('Failed to load reading progress: $e');
          }
        }
        return plans;
      }
    } catch (e) {
      debugPrint('Failed to load reading plans from server, using defaults: $e');
    }

    return _defaultPlans();
  }

  /// Marks one day of [planId] complete and returns the new completed-day
  /// count (clamped to the plan length so it can't be farmed past the end).
  Future<int> completeDay(String planId, {int totalDays = 1}) async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;

    try {
      final existing = await _client.from('user_reading_progress').select().eq('user_id', user.id).eq('plan_id', planId).maybeSingle();
      final currentDays = existing != null ? (existing['completed_days'] as num?)?.toInt() ?? 0 : 0;
      if (currentDays >= totalDays) return currentDays;
      final newDays = (currentDays + 1).clamp(0, totalDays);
      if (existing != null) {
        await _client.from('user_reading_progress').update({'completed_days': newDays, 'updated_at': DateTime.now().toIso8601String()}).eq('user_id', user.id).eq('plan_id', planId);
      } else {
        await _client.from('user_reading_progress').insert({'user_id': user.id, 'plan_id': planId, 'completed_days': newDays});
      }
      return newDays;
    } catch (e) {
      debugPrint('Failed to save reading progress: $e');
      return 0;
    }
  }
}

final readingPlanServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ReadingPlanService(client);
});

final readingPlansProvider = FutureProvider<List<ReadingPlan>>((ref) {
  return ref.watch(readingPlanServiceProvider).getPlans();
});

/// A single tickable reading-plan entry (backed by `reading_plan_entries`).
class ReadingPlanEntry {
  final String id;
  final int dayNumber;
  final String bookName;
  final int chapter;
  final int? verseStart;
  final int? verseEnd;

  ReadingPlanEntry({
    required this.id,
    required this.dayNumber,
    required this.bookName,
    required this.chapter,
    this.verseStart,
    this.verseEnd,
  });

  /// Human reference, e.g. `John 3:16` or `Psalms 23:1-6`.
  String get reference {
    final base = '$bookName $chapter';
    if (verseStart == null) return base;
    if (verseEnd != null && verseEnd != verseStart) {
      return '$base:$verseStart-$verseEnd';
    }
    return '$base:$verseStart';
  }

  factory ReadingPlanEntry.fromMap(Map<String, dynamic> map) {
    dynamic book = map['book'];
    if (book is List) book = book.isNotEmpty ? book.first : null;
    final bookName =
        book is Map ? (book['name']?.toString() ?? 'Scripture') : 'Scripture';
    return ReadingPlanEntry(
      id: map['id']?.toString() ?? '',
      dayNumber: (map['day_number'] as num?)?.toInt() ?? 0,
      bookName: bookName,
      chapter: (map['chapter'] as num?)?.toInt() ?? 1,
      verseStart: (map['verse_start'] as num?)?.toInt(),
      verseEnd: (map['verse_end'] as num?)?.toInt(),
    );
  }
}

/// True only for a canonical UUID string (RPCs take `uuid` args; default/seed
/// plan ids like `faith_wisdom` would just error).
bool isUuidString(String value) => RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);

/// Entries for a plan, read from `reading_plan_entries`.
final readingPlanEntriesProvider =
    FutureProvider.family<List<ReadingPlanEntry>, String>((ref, planId) async {
  if (!isUuidString(planId)) return <ReadingPlanEntry>[];
  final rows = await ref
      .watch(bibleVerseServiceProvider)
      .fetchReadingPlanEntries(planId: planId);
  return rows.map(ReadingPlanEntry.fromMap).toList();
});

/// Completed entry ids for a plan (RPC-backed, persists across restarts).
final readingPlanCompletedProvider =
    FutureProvider.family<Set<String>, String>((ref, planId) async {
  if (!isUuidString(planId)) return <String>{};
  return ref.watch(bibleVerseServiceProvider).fetchCompletedPlanEntries(planId);
});
