import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class StreakInfo {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final List<DateTime> activityLog;

  const StreakInfo({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActivityDate,
    this.activityLog = const [],
  });

  String get tier {
    if (currentStreak >= 365) return '💎 DIAMOND';
    if (currentStreak >= 100) return '👑 GOLD';
    if (currentStreak >= 30) return '🏆 SILVER';
    if (currentStreak >= 7) return '⭐ BRONZE';
    if (currentStreak >= 3) return '🔥 BEGINNER';
    return '🌱 STARTER';
  }

  String get motivationalMessage {
    if (currentStreak >= 365) return 'A full year of devotion! You are a biblical scholar! 🙌';
    if (currentStreak >= 100) return 'Century mark! Your commitment is inspiring! Keep going! 💪';
    if (currentStreak >= 30) return 'One month strong! Discipline is becoming a habit! 🔥';
    if (currentStreak >= 14) return 'Two weeks of consistent study! You\'re on fire! ⭐';
    if (currentStreak >= 7) return 'One week streak! Consistency is key! Keep it up! 🎯';
    if (currentStreak >= 3) return 'Three days in a row! Building momentum! 💪';
    if (currentStreak >= 1) return 'Great start! Come back tomorrow to keep your streak! 🌟';
    return 'Start your study journey today! 📖';
  }
}

class StreakService {
  final SupabaseClient _client;

  StreakService(this._client);

  static const _streakKey = 'study_streak_info';

  Future<void> logStudyActivity(String userId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await _saveToSupabase(userId, today);
    await _saveToLocal(userId, today);
  }

  Future<void> _saveToSupabase(String userId, DateTime today) async {
    try {
      final existing = await _client
          .from('user_study_streaks')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        final lastDate = existing['last_activity_date'] != null
            ? DateTime.parse(existing['last_activity_date'])
            : null;
        final currentStreak = (existing['current_streak'] as num?)?.toInt() ?? 0;
        final longestStreak = (existing['longest_streak'] as num?)?.toInt() ?? 0;
        final loggedDates = _parseDates(existing['activity_log']);

        if (!loggedDates.contains(today)) {
          loggedDates.add(today);
        }

        final yesterday = today.subtract(const Duration(days: 1));
        int newStreak;

        if (lastDate != null && lastDate == yesterday) {
          newStreak = currentStreak + 1;
        } else if (lastDate != null && lastDate == today) {
          newStreak = currentStreak;
        } else {
          newStreak = 1;
        }

        final newLongest = newStreak > longestStreak ? newStreak : longestStreak;

        await _client.from('user_study_streaks').update({
          'current_streak': newStreak,
          'longest_streak': newLongest,
          'last_activity_date': today.toIso8601String(),
          'activity_log': jsonEncode(loggedDates.map((d) => d.toIso8601String()).toList()),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('user_id', userId);
      } else {
        await _client.from('user_study_streaks').insert({
          'user_id': userId,
          'current_streak': 1,
          'longest_streak': 1,
          'last_activity_date': today.toIso8601String(),
          'activity_log': jsonEncode([today.toIso8601String()]),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error saving streak to Supabase: $e');
    }
  }

  Future<void> _saveToLocal(String userId, DateTime today) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final info = await _getStreakFromLocal(userId);

      final logged = List<DateTime>.from(info.activityLog);
      if (!logged.contains(today)) {
        logged.add(today);
      }

      final yesterday = today.subtract(const Duration(days: 1));
      int newStreak;

      if (info.lastActivityDate != null &&
          info.lastActivityDate! == yesterday) {
        newStreak = info.currentStreak + 1;
      } else if (info.lastActivityDate != null &&
          info.lastActivityDate! == today) {
        newStreak = info.currentStreak;
      } else {
        newStreak = 1;
      }

      final newLongest = newStreak > info.longestStreak ? newStreak : info.longestStreak;

      final streakData = {
        'userId': userId,
        'currentStreak': newStreak,
        'longestStreak': newLongest,
        'lastActivityDate': today.toIso8601String(),
        'activityLog': logged.map((d) => d.toIso8601String()).toList(),
      };

      await prefs.setString('$_streakKey-$userId', jsonEncode(streakData));
    } catch (e) {
      debugPrint('Error saving streak locally: $e');
    }
  }

  StreakInfo _sanitizeStreakInfo(StreakInfo info) {
    if (info.lastActivityDate == null) return info;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final lastAct = DateTime(
      info.lastActivityDate!.year,
      info.lastActivityDate!.month,
      info.lastActivityDate!.day,
    );

    if (lastAct.isBefore(yesterday)) {
      return StreakInfo(
        currentStreak: 0,
        longestStreak: info.longestStreak,
        lastActivityDate: info.lastActivityDate,
        activityLog: info.activityLog,
      );
    }
    return info;
  }

  Future<StreakInfo> getStreakInfo(String userId) async {
    try {
      final supabaseInfo = await _getStreakFromSupabase(userId);
      return _sanitizeStreakInfo(supabaseInfo);
    } catch (e) {
      debugPrint('Error loading streak from Supabase, using local: $e');
      final localInfo = await _getStreakFromLocal(userId);
      return _sanitizeStreakInfo(localInfo);
    }
  }

  Future<StreakInfo> _getStreakFromSupabase(String userId) async {
    final data = await _client
        .from('user_study_streaks')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return const StreakInfo();

    return StreakInfo(
      currentStreak: (data['current_streak'] as num?)?.toInt() ?? 0,
      longestStreak: (data['longest_streak'] as num?)?.toInt() ?? 0,
      lastActivityDate: data['last_activity_date'] != null
          ? DateTime.parse(data['last_activity_date'])
          : null,
      activityLog: _parseDates(data['activity_log']),
    );
  }

  Future<StreakInfo> _getStreakFromLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('$_streakKey-$userId');
      if (data == null) return const StreakInfo();

      final map = jsonDecode(data) as Map<String, dynamic>;
      final activityLog = (map['activityLog'] as List)
          .map((d) => DateTime.parse(d.toString()))
          .toList();

      return StreakInfo(
        currentStreak: map['currentStreak'] as int? ?? 0,
        longestStreak: map['longestStreak'] as int? ?? 0,
        lastActivityDate: map['lastActivityDate'] != null
            ? DateTime.parse(map['lastActivityDate'] as String)
            : null,
        activityLog: activityLog,
      );
    } catch (e) {
      return const StreakInfo();
    }
  }

  List<DateTime> _parseDates(dynamic log) {
    if (log == null) return [];
    try {
      final list = jsonDecode(log.toString()) as List;
      return list.map((d) => DateTime.parse(d.toString())).toList();
    } catch (_) {
      return [];
    }
  }

  List<bool> getLast30DaysStatus(StreakInfo info) {
    final today = DateTime.now();
    final localToday = DateTime(today.year, today.month, today.day);
    final results = <bool>[];

    for (int i = 29; i >= 0; i--) {
      final day = localToday.subtract(Duration(days: i));
      results.add(info.activityLog.any((d) =>
          d.year == day.year &&
          d.month == day.month &&
          d.day == day.day));
    }

    return results;
  }

  Future<void> updateSupabaseStreak(String userId, int currentStreak, int longestStreak, String lastActivityDate, String activityLog) async {
    try {
      final existing = await _client.from('user_study_streaks').select().eq('user_id', userId).maybeSingle();
      if (existing != null) {
        await _client.from('user_study_streaks').update({
          'current_streak': currentStreak,
          'longest_streak': longestStreak,
          'last_activity_date': lastActivityDate,
          'activity_log': activityLog,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('user_id', userId);
      } else {
        await _client.from('user_study_streaks').insert({
          'user_id': userId,
          'current_streak': currentStreak,
          'longest_streak': longestStreak,
          'last_activity_date': lastActivityDate,
          'activity_log': activityLog,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error updating Supabase streak: $e');
    }
  }
}

final streakServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return StreakService(client);
});

final streakInfoProvider = FutureProvider.family<StreakInfo, String>((ref, userId) {
  return ref.watch(streakServiceProvider).getStreakInfo(userId);
});
