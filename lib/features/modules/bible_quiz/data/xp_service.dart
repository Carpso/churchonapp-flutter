import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class XpService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, dynamic>> getUserXp() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {'xp': 0, 'level': 1};

    try {
      final res = await _client
          .from('profiles')
          .select('xp, level')
          .eq('id', uid)
          .maybeSingle();
      if (res == null) return {'xp': 0, 'level': 1};
      return {
        'xp': res['xp'] ?? 0,
        'level': res['level'] ?? 1,
      };
    } catch (e) {
      debugPrint('XpService.getUserXp error: $e');
      return {'xp': 0, 'level': 1};
    }
  }

  static int xpForLevel(int level) {
    final value = pow((level - 1) / 0.6, 1.0 / 0.6) * 100;
    return value.isFinite ? value.round() : 2147483647;
  }

  static int xpToNextLevel(int currentXp, int currentLevel) {
    final nextLevelXp = xpForLevel(currentLevel + 1);
    return nextLevelXp - currentXp;
  }

  static double levelProgress(int currentXp, int currentLevel) {
    final currentLevelXp = xpForLevel(currentLevel);
    final nextLevelXp = xpForLevel(currentLevel + 1);
    if (nextLevelXp <= currentLevelXp) return 1.0;
    return (currentXp - currentLevelXp) / (nextLevelXp - currentLevelXp);
  }

  static String levelTitle(int level) {
    if (level >= 100) return 'Divine Sage';
    if (level >= 75) return 'Prophet';
    if (level >= 50) return 'Apostle';
    if (level >= 35) return 'Bible Scholar';
    if (level >= 25) return 'Teacher';
    if (level >= 15) return 'Disciple';
    if (level >= 10) return 'Follower';
    if (level >= 5) return 'Seeker';
    return 'Beginner';
  }

  static int xpForCorrectAnswer(String difficulty, {bool streak = false, int streakCount = 0}) {
    int base;
    switch (difficulty) {
      case 'Easy': base = 10;
      case 'Medium': base = 20;
      case 'Hard': base = 35;
      default: base = 10;
    }
    if (streak && streakCount >= 3) base += streakCount * 2;
    return base;
  }

  static int xpForAccuracyPct(double accuracy) {
    if (accuracy >= 1.0) return 50;
    if (accuracy >= 0.8) return 30;
    if (accuracy >= 0.6) return 15;
    return 5;
  }
}

final xpServiceProvider = Provider((ref) => XpService());

final userXpProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(xpServiceProvider).getUserXp();
});
