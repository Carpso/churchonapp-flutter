import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/profile_provider.dart';

class SpiritualPrediction {
  final int spiritualScore; // 0 - 100
  final int growthVelocityPercent; // e.g. +14
  final int streakDaysForecast; // e.g. 30
  final double consistencyRating; // 0.0 - 5.0
  final String momentumLabel; // "High Momentum", "Steady Growth", "Needs Revival"
  final String predictedMilestone; // "30-Day Bible Streak in 4 days"
  final String recommendedAction; // "Read Psalm 119 today to maintain streak"
  final String scripturalEncouragement;

  SpiritualPrediction({
    required this.spiritualScore,
    required this.growthVelocityPercent,
    required this.streakDaysForecast,
    required this.consistencyRating,
    required this.momentumLabel,
    required this.predictedMilestone,
    required this.recommendedAction,
    required this.scripturalEncouragement,
  });

  factory SpiritualPrediction.fromProfileData({
    required int streakDays,
    required int coins,
    required String role,
  }) {
    // Prediction logic based on user engagement signals
    final baseScore = (streakDays * 8 + (coins > 100 ? 20 : 10)).clamp(35, 98);
    final velocity = streakDays > 5 ? 18 : (streakDays > 2 ? 10 : 5);
    final forecast = (streakDays + 7).clamp(7, 90);
    final rating = (baseScore / 20.0).clamp(1.0, 5.0);

    String momentum = 'Steady Growth';
    String milestone = '14-Day Streak Target';
    String action = 'Complete today\'s devotional to boost your score!';
    String scripture = '“He who began a good work in you will carry it on to completion.” — Philippians 1:6';

    if (baseScore >= 80) {
      momentum = '🔥 High Momentum';
      milestone = '30-Day Bible Mastery Milestone in ${30 - (streakDays % 30)} days';
      action = 'Join today\'s Bible Quiz PVP or pray for 3 members on the wall.';
      scripture = '“Your word is a lamp for my feet, a light on my path.” — Psalm 119:105';
    } else if (baseScore < 50) {
      momentum = '🌱 Renewal Phase';
      milestone = '7-Day Habit Benchmark in ${7 - (streakDays % 7)} days';
      action = 'Read 1 Bible chapter today to reactivate your spiritual streak.';
      scripture = '“Create in me a pure heart, O God, and renew a steadfast spirit within me.” — Psalm 51:10';
    }

    return SpiritualPrediction(
      spiritualScore: baseScore,
      growthVelocityPercent: velocity,
      streakDaysForecast: forecast,
      consistencyRating: rating,
      momentumLabel: momentum,
      predictedMilestone: milestone,
      recommendedAction: action,
      scripturalEncouragement: scripture,
    );
  }
}

class PredictionService {
  final SupabaseClient _client;
  PredictionService(this._client);

  Future<SpiritualPrediction> calculatePrediction(String userId) async {
    try {
      final res = await _client
          .from('profiles')
          .select('coins, role, created_at')
          .eq('id', userId)
          .maybeSingle();

      final coins = (res?['coins'] as num?)?.toInt() ?? 0;
      final role = res?['role']?.toString() ?? 'member';

      // Fetch streak if available
      int streak = 3;
      try {
        final streakRes = await _client
            .from('user_streaks')
            .select('current_streak')
            .eq('user_id', userId)
            .maybeSingle();
        if (streakRes != null) {
          streak = (streakRes['current_streak'] as num?)?.toInt() ?? 3;
        }
      } catch (_) {}

      return SpiritualPrediction.fromProfileData(
        streakDays: streak,
        coins: coins,
        role: role,
      );
    } catch (_) {
      return SpiritualPrediction.fromProfileData(
        streakDays: 4,
        coins: 50,
        role: 'member',
      );
    }
  }
}

final predictionServiceProvider = Provider<PredictionService>((ref) {
  return PredictionService(Supabase.instance.client);
});

final spiritualPredictionProvider = FutureProvider.autoDispose<SpiritualPrediction>((ref) async {
  final profileAsync = ref.watch(profileProvider);
  final user = profileAsync.value;
  final userId = user?.id ?? Supabase.instance.client.auth.currentUser?.id ?? '';
  final service = ref.watch(predictionServiceProvider);
  return service.calculatePrediction(userId);
});

class SpiritualPredictorCard extends ConsumerWidget {
  const SpiritualPredictorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictionAsync = ref.watch(spiritualPredictionProvider);

    return predictionAsync.when(
      data: (pred) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4338CA).withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.sparkles,
                        color: Color(0xFFFDE047),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Spiritual Momentum',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'Personalized Growth Forecast',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE047).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE047).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    pred.momentumLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFDE047),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${pred.spiritualScore}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '+${pred.growthVelocityPercent}% velocity',
                            style: const TextStyle(
                              color: Color(0xFF4ADE80),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pred.predictedMilestone,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.compass, color: Color(0xFF93C5FD), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pred.recommendedAction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
      loading: () => Container(
        height: 140,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.indigo.shade900.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
