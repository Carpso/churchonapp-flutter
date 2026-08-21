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
  /// Real per-day engagement counts for the last 7 days (notes+quiz+attendance).
  /// Empty when no data — the growth chart renders an honest empty state.
  final List<double> weeklyEngagement;

  SpiritualPrediction({
    required this.spiritualScore,
    required this.growthVelocityPercent,
    required this.streakDaysForecast,
    required this.consistencyRating,
    required this.momentumLabel,
    required this.predictedMilestone,
    required this.recommendedAction,
    required this.scripturalEncouragement,
    this.weeklyEngagement = const [],
  });

  factory SpiritualPrediction.fromProfileData({
    required int streakDays,
    required int coins,
    required String role,
  }) {
    // Honest fallback — computed only when live data cannot be fetched.
    final baseScore = (streakDays * 8 + (coins > 100 ? 20 : 10)).clamp(5, 98);
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

  /// Real spiritual-momentum score computed from live engagement signals:
  /// bible-study streak, verse notes, quiz challenges and church attendance
  /// over the last 14 days.
  Future<SpiritualPrediction> calculatePrediction(String userId) async {
    final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);
      DateTime daysAgo(int days) => today.subtract(Duration(days: days));
      String isoDaysAgo(int days) => daysAgo(days).toIso8601String();

    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('profiles')
            .select('coins')
            .eq('id', userId)
            .maybeSingle(),
        _client
            .from('user_study_streaks')
            .select('current_streak, last_activity_date')
            .eq('user_id', userId)
            .maybeSingle(),
        _client
            .from('verse_notes')
            .select('created_at')
            .eq('user_id', userId)
            .gte('created_at', isoDaysAgo(14)),
        _client
            .from('daily_challenge_results')
            .select('completed_at')
            .eq('user_id', userId)
            .gte('completed_at', isoDaysAgo(14)),
        _client
            .from('attendance_logs')
            .select('check_in_time')
            .eq('user_id', userId)
            .gte('check_in_time', isoDaysAgo(14)),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final streakRow = results[1] as Map<String, dynamic>?;
      final verseNotes = (results[2] as List).cast<Map<String, dynamic>>();
      final challenges = (results[3] as List).cast<Map<String, dynamic>>();
      final attendance = (results[4] as List).cast<Map<String, dynamic>>();

      final coins = (profile?['coins'] as num?)?.toInt() ?? 0;
      final streak = (streakRow?['current_streak'] as num?)?.toInt() ?? 0;
      final lastActivity = streakRow?['last_activity_date']?.toString();

      // Distinct active days over the last 7 and previous 7 days.
      int dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
      final activeRecent = <int>{};
      final activePrior = <int>{};
      for (final row in verseNotes) {
        final dt = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (dt == null) continue;
        final d = dayKey(dt);
        if (dt.isAfter(daysAgo(7))) {
          activeRecent.add(d);
        } else if (dt.isAfter(daysAgo(14))) {
          activePrior.add(d);
        }
      }
      for (final row in challenges) {
        final dt = DateTime.tryParse(row['completed_at']?.toString() ?? '');
        if (dt == null) continue;
        final d = dayKey(dt);
        if (dt.isAfter(daysAgo(7))) {
          activeRecent.add(d);
        } else if (dt.isAfter(daysAgo(14))) {
          activePrior.add(d);
        }
      }
      for (final row in attendance) {
        final dt = DateTime.tryParse(row['check_in_time']?.toString() ?? '');
        if (dt == null) continue;
        final d = dayKey(dt);
        if (dt.isAfter(daysAgo(7))) {
          activeRecent.add(d);
        } else if (dt.isAfter(daysAgo(14))) {
          activePrior.add(d);
        }
      }

      final recentDays = activeRecent.length;
      final priorDays = activePrior.length;

      // Score: 40% streak, 40% weekly consistency, 20% coin engagement.
      final streakScore = (streak / 30.0).clamp(0.0, 1.0) * 40;
      final activityScore = (recentDays / 7.0).clamp(0.0, 1.0) * 40;
      final engagementScore = (coins / 1000.0).clamp(0.0, 1.0) * 20;
      final score = (streakScore + activityScore + engagementScore).round();

      // Velocity: engagement change week-over-week (real, not guessed).
      var velocity = 0;
      if (priorDays > 0) {
        velocity = (((recentDays - priorDays) / priorDays) * 100).round();
      } else if (recentDays > 0) {
        velocity = 100;
      }
      velocity = velocity.clamp(-100, 100);

      final consistency = (recentDays / 7.0).clamp(0.0, 1.0) * 5;
      final streakAlive = lastActivity == today.toIso8601String();
      final forecast = streakAlive ? streak + 7 : streak;

      String momentum;
      if (score >= 80) {
        momentum = '🔥 High Momentum';
      } else if (score >= 50) {
        momentum = 'Steady Growth';
      } else if (recentDays > 0 || streak > 0) {
        momentum = '🌱 Building Momentum';
      } else {
        momentum = 'Needs Revival';
      }

      String milestone;
      String action;
      if (streak >= 30) {
        milestone = '30-day study streak achieved — keep it alive!';
        action = 'Share today\'s verse with a friend to encourage them.';
      } else if (streak > 0) {
        final to30 = 30 - streak;
        milestone = '30-day study streak in $to30 day${to30 == 1 ? '' : 's'}';
        action = 'Complete today\'s devotional to protect your streak.';
      } else if (recentDays >= 5) {
        milestone = 'Active on $recentDays of the last 7 days';
        action = 'Aim for 7 straight days to ignite a study streak.';
      } else if (recentDays > 0) {
        milestone = 'Active on $recentDays of the last 7 days';
        action = 'Read one Bible chapter today and log a verse note.';
      } else {
        milestone = 'No recent activity recorded';
        action = 'Read a chapter and save your first verse note today.';
      }

      final scriptures = [
        '“Your word is a lamp for my feet, a light on my path.” — Psalm 119:105',
        '“He who began a good work in you will carry it on to completion.” — Philippians 1:6',
        '“Create in me a pure heart, O God, and renew a steadfast spirit within me.” — Psalm 51:10',
        '“Faith comes by hearing, and hearing by the word of God.” — Romans 10:17',
        '“Do not grow weary in doing good, for in due season you will reap.” — Galatians 6:9',
      ];
      final scripture = scriptures[score % scriptures.length];

      // Real 7-day engagement series for the growth chart: distinct
      // note/quiz/attendance events per day (oldest → today). Zero-fill days
      // with no activity so the line never fabricates shape.
      final perDay = List<double>.filled(7, 0);
      void bump(DateTime dt) {
        final diff = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;
        if (diff >= 0 && diff < 7) perDay[6 - diff] += 1;
      }
      for (final row in verseNotes) {
        final dt = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (dt != null && dt.isAfter(daysAgo(7))) bump(dt);
      }
      for (final row in challenges) {
        final dt = DateTime.tryParse(row['completed_at']?.toString() ?? '');
        if (dt != null && dt.isAfter(daysAgo(7))) bump(dt);
      }
      for (final row in attendance) {
        final dt = DateTime.tryParse(row['check_in_time']?.toString() ?? '');
        if (dt != null && dt.isAfter(daysAgo(7))) bump(dt);
      }

      return SpiritualPrediction(
        spiritualScore: score,
        growthVelocityPercent: velocity,
        streakDaysForecast: forecast,
        consistencyRating: double.parse(consistency.toStringAsFixed(1)),
        momentumLabel: momentum,
        predictedMilestone: milestone,
        recommendedAction: action,
        scripturalEncouragement: scripture,
        weeklyEngagement: perDay,
      );
    } catch (e) {
      debugPrint('PredictionService: live calculation failed ($e) — using fallback');
      return SpiritualPrediction.fromProfileData(
        streakDays: 0,
        coins: 0,
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.trendingUp,
                    color: Color(0xFFFDE047),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spiritual Momentum',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Growth Forecast',
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
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
