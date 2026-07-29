import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String category;
  final int xpReward;
  final int sortOrder;
  final DateTime? unlockedAt;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.category = 'general',
    this.xpReward = 0,
    this.sortOrder = 0,
    this.unlockedAt,
  });

  factory Achievement.fromMap(Map<String, dynamic> m, {DateTime? unlockedAt}) => Achievement(
    id: m['id']?.toString() ?? '',
    title: m['title'] ?? '',
    description: m['description'] ?? '',
    icon: m['icon'] ?? 'star',
    category: m['category'] ?? 'general',
    xpReward: m['xp_reward'] ?? 0,
    sortOrder: m['sort_order'] ?? 0,
    unlockedAt: unlockedAt,
  );

  bool get isUnlocked => unlockedAt != null;
}

class AchievementService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Achievement>> getAllAchievements() async {
    try {
      final uid = _client.auth.currentUser?.id;
      final res = await _client
          .from('achievements')
          .select('*, user_achievements!left(user_id, unlocked_at)')
          .order('sort_order');

      return (res as List).map((m) {
        final ua = m['user_achievements'] as List? ?? [];
        final userAchievement = ua.cast<Map<String, dynamic>>().where(
          (ua) => uid != null && ua['user_id']?.toString() == uid,
        ).toList();
        final unlockedAt = userAchievement.isNotEmpty
            ? DateTime.tryParse(userAchievement.first['unlocked_at']?.toString() ?? '')
            : null;
        return Achievement.fromMap(m, unlockedAt: unlockedAt);
      }).toList();
    } catch (e) {
      debugPrint('AchievementService.getAllAchievements error: $e');
      return [];
    }
  }

  Future<List<Achievement>> getUnlockedAchievements() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final res = await _client
          .from('user_achievements')
          .select('*, achievements(*)')
          .eq('user_id', uid);

      return (res as List).map((m) {
        final a = m['achievements'] as Map<String, dynamic>? ?? {};
        return Achievement.fromMap(a, unlockedAt: DateTime.tryParse(m['unlocked_at']?.toString() ?? ''));
      }).toList();
    } catch (e) {
      debugPrint('AchievementService.getUnlockedAchievements error: $e');
      return [];
    }
  }

  Future<bool> unlockAchievement(String achievementId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;

    try {
      await _client.from('user_achievements').insert({
        'user_id': uid,
        'achievement_id': achievementId,
      });
      return true;
    } catch (e) {
      debugPrint('AchievementService.unlockAchievement error: $e');
      return false;
    }
  }

  Future<List<String>> checkAndUnlock({
    required int correctCount,
    required int totalQuestions,
    required int bestStreak,
    required double accuracy,
    required double avgResponseTimeSec,
    required bool usedAllPowerUps,
    required bool isPvP,
    required bool isPvPWin,
    required int totalCorrectAllTime,
    required int dailyChallengeCount,
    required List<String> categoriesAnswered,
  }) async {
    final unlocked = <String>[];

    // first_quiz
    if (totalQuestions > 0) {
      final ok = await unlockAchievement('first_quiz');
      if (ok) unlocked.add('First Steps');
    }

    // perfect_score
    if (accuracy >= 1.0 && totalQuestions >= 5) {
      final ok = await unlockAchievement('perfect_score');
      if (ok) unlocked.add('Perfect Score');
    }

    // streak_3
    if (bestStreak >= 3) {
      final ok = await unlockAchievement('streak_3');
      if (ok) unlocked.add('On Fire');
    }

    // streak_5
    if (bestStreak >= 5) {
      final ok = await unlockAchievement('streak_5');
      if (ok) unlocked.add('Unstoppable');
    }

    // speed_demon
    if (avgResponseTimeSec <= 3 && correctCount >= 5) {
      final ok = await unlockAchievement('speed_demon');
      if (ok) unlocked.add('Lightning Fast');
    }

    // pvp_first
    if (isPvP) {
      final ok = await unlockAchievement('pvp_first');
      if (ok) unlocked.add('First Duel');
    }

    // pvp_winner
    if (isPvPWin) {
      final ok = await unlockAchievement('pvp_winner');
      if (ok) unlocked.add('Victor');
    }

    // scholar_10
    if (totalCorrectAllTime >= 100) {
      final ok = await unlockAchievement('scholar_10');
      if (ok) unlocked.add('Scholar');
    }

    // scholar_50
    if (totalCorrectAllTime >= 500) {
      final ok = await unlockAchievement('scholar_50');
      if (ok) unlocked.add('Theologian');
    }

    // diverse
    if (categoriesAnswered.length >= 5) {
      final ok = await unlockAchievement('diverse');
      if (ok) unlocked.add('Well-Rounded');
    }

    // daily_7
    if (dailyChallengeCount >= 7) {
      final ok = await unlockAchievement('daily_7');
      if (ok) unlocked.add('Devoted');
    }

    // quick_draw
    if (avgResponseTimeSec <= 2 && correctCount > 0) {
      final ok = await unlockAchievement('quick_draw');
      if (ok) unlocked.add('Quick Draw');
    }

    // power_up_master
    if (usedAllPowerUps) {
      final ok = await unlockAchievement('power_up_master');
      if (ok) unlocked.add('Power-Up Master');
    }

    return unlocked;
  }
}

final achievementServiceProvider = Provider((ref) => AchievementService());

final allAchievementsProvider = FutureProvider.autoDispose<List<Achievement>>((ref) {
  return ref.read(achievementServiceProvider).getAllAchievements();
});

final unlockedAchievementsProvider = FutureProvider.autoDispose<List<Achievement>>((ref) {
  return ref.read(achievementServiceProvider).getUnlockedAchievements();
});
