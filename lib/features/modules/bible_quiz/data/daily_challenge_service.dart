import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      final res = await _client
          .from('daily_challenge_results')
          .select()
          .eq('user_id', uid)
          .gte('completed_at', todayStart.toUtc().toIso8601String())
          .order('completed_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return DailyChallengeResult.fromMap(res);
    } catch (e) {
      debugPrint('DailyChallengeService.getTodaysResult error: $e');
      return null;
    }
  }

  /// Submits today's challenge answers for server-side scoring.
  /// The RPC derives score/correct from the question bank (never trusts the
  /// client), enforces one completion per day, and feeds the leaderboard.
  Future<Map<String, dynamic>?> submitVerifiedResult({
    required List<String> questionIds,
    required List<int> answers,
    required List<int> responseTimesMs,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final res = await _client.rpc('submit_daily_challenge_result', params: {
        'p_question_ids': questionIds,
        'p_answers': answers,
        'p_response_times_ms': responseTimesMs,
        'p_xp_earned': 100,
      });
      if (res is Map<String, dynamic>) return res;
    } catch (e) {
      debugPrint('DailyChallengeService.submitVerifiedResult error: $e');
    }
    return null;
  }
}

final dailyChallengeServiceProvider = Provider((ref) => DailyChallengeService());

final todaysChallengeProvider = FutureProvider.autoDispose<DailyChallenge?>((ref) {
  return ref.read(dailyChallengeServiceProvider).getTodaysChallenge();
});

final todaysChallengeResultProvider = FutureProvider.autoDispose<DailyChallengeResult?>((ref) {
  return ref.read(dailyChallengeServiceProvider).getTodaysResult();
});
