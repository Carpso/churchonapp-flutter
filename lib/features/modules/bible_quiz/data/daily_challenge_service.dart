import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/notification_service.dart';

class DailyChallenge {
  final String id;
  final DateTime date;
  final String title;
  final int questionCount;
  final String? category;
  final String? difficulty;
  final int xpReward;
  final bool isActive;

  DailyChallenge({
    required this.id,
    required this.date,
    required this.title,
    this.questionCount = 5,
    this.category,
    this.difficulty,
    this.xpReward = 100,
    this.isActive = true,
  });

  factory DailyChallenge.fromMap(Map<String, dynamic> m) => DailyChallenge(
    id: m['id']?.toString() ?? '',
    date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
    title: m['title'] ?? '',
    questionCount: m['question_count'] ?? 5,
    category: m['category'],
    difficulty: m['difficulty'],
    xpReward: m['xp_reward'] ?? 100,
    isActive: m['is_active'] == true,
  );
}

class DailyChallengeResult {
  final String id;
  final String challengeId;
  final String userId;
  final int score;
  final int correctCount;
  final int totalQuestions;
  final int xpEarned;
  final DateTime completedAt;

  DailyChallengeResult({
    required this.id,
    required this.challengeId,
    required this.userId,
    this.score = 0,
    this.correctCount = 0,
    this.totalQuestions = 0,
    this.xpEarned = 0,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  factory DailyChallengeResult.fromMap(Map<String, dynamic> m) => DailyChallengeResult(
    id: m['id']?.toString() ?? '',
    challengeId: m['challenge_id']?.toString() ?? '',
    userId: m['user_id']?.toString() ?? '',
    score: m['score'] ?? 0,
    correctCount: m['correct_count'] ?? 0,
    totalQuestions: m['total_questions'] ?? 0,
    xpEarned: m['xp_earned'] ?? 0,
    completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'].toString()) : null,
  );

  bool get isPerfect => correctCount >= totalQuestions;
  double get accuracy => totalQuestions > 0 ? correctCount / totalQuestions : 0;
}

class DailyChallengeService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<DailyChallenge?> getTodaysChallenge() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    try {
      final res = await _client
          .from('daily_challenges')
          .select()
          .eq('date', today)
          .eq('is_active', true)
          .maybeSingle();
      if (res != null) return DailyChallenge.fromMap(res);
    } catch (e) {
      debugPrint('DailyChallengeService.getTodaysChallenge error: $e');
    }

    // Fallback: create synthetic daily challenge from seed questions
    return DailyChallenge(
      id: 'daily_$today',
      date: DateTime.now(),
      title: 'Daily Challenge — $today',
      questionCount: 5,
      category: 'General',
      difficulty: null,
      xpReward: 100,
      isActive: true,
    );
  }

  Future<DailyChallengeResult?> getTodaysResult() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final challenge = await getTodaysChallenge();
      if (challenge == null) return null;

      final res = await _client
          .from('daily_challenge_results')
          .select()
          .eq('challenge_id', challenge.id)
          .eq('user_id', uid)
          .maybeSingle();
      if (res == null) return null;
      return DailyChallengeResult.fromMap(res);
    } catch (e) {
      debugPrint('DailyChallengeService.getTodaysResult error: $e');
      return null;
    }
  }

  Future<void> saveResult({
    required String challengeId,
    required int score,
    required int correctCount,
    required int totalQuestions,
    required int xpEarned,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _client.from('daily_challenge_results').insert({
        'challenge_id': challengeId,
        'user_id': uid,
        'score': score,
        'correct_count': correctCount,
        'total_questions': totalQuestions,
        'xp_earned': xpEarned,
      });

      // Notify user of completion
      try {
        final notifService = NotificationService(_client);
        await notifService.sendNotification(
          userId: uid,
          title: 'Challenge Complete!',
          body: 'You scored $score ($correctCount/$totalQuestions correct). +$xpEarned XP earned!',
          type: 'daily_challenge',
          channelId: 'coa_events',
        );
      } catch (e) {
        debugPrint('Daily challenge notification failed: $e');
      }
    } catch (e) {
      debugPrint('DailyChallengeService.saveResult error: $e');
    }
  }
}

final dailyChallengeServiceProvider = Provider((ref) => DailyChallengeService());

final todaysChallengeProvider = FutureProvider.autoDispose<DailyChallenge?>((ref) {
  return ref.read(dailyChallengeServiceProvider).getTodaysChallenge();
});

final todaysChallengeResultProvider = FutureProvider.autoDispose<DailyChallengeResult?>((ref) {
  return ref.read(dailyChallengeServiceProvider).getTodaysResult();
});
