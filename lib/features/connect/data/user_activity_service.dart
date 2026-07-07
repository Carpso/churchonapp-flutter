import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

enum ActivityType {
  bibleRead,
  prayerPosted,
  fastStarted,
  fastCompleted,
  socialPosted,
  testimonyShared,
  quizPlayed,
  attendanceScanned,
  dailyStreak,
  coinCollected,
}

class UserActivity {
  final String id;
  final String userId;
  final ActivityType type;
  final String description;
  final int coinsEarned;
  final DateTime createdAt;

  UserActivity({
    required this.id,
    required this.userId,
    required this.type,
    required this.description,
    this.coinsEarned = 0,
    required this.createdAt,
  });

  factory UserActivity.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type']?.toString() ?? 'bibleRead';
    return UserActivity(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      type: ActivityType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => ActivityType.bibleRead,
      ),
      description: map['description']?.toString() ?? '',
      coinsEarned: int.tryParse(map['coins_earned']?.toString() ?? '0') ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }
}

class UserActivityService {
  final SupabaseClient _client;
  UserActivityService(this._client);

  Future<void> logActivity({
    required ActivityType type,
    required String description,
    int coinsEarned = 0,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('user_activities').insert({
      'user_id': user.id,
      'type': type.name,
      'description': description,
      'coins_earned': coinsEarned,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<UserActivity>> getActivities({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final data = await _client
        .from('user_activities')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List).map((m) => UserActivity.fromMap(m)).toList();
  }

  Future<int> getTotalCoinsEarned() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;

    final data = await _client
        .from('user_activities')
        .select('coins_earned')
        .eq('user_id', user.id);

    return (data as List).fold<int>(0, (sum, m) => sum + ((m['coins_earned'] as num?)?.toInt() ?? 0));
  }
}

final userActivityServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return UserActivityService(client);
});

final userActivitiesProvider = FutureProvider<List<UserActivity>>((ref) {
  return ref.watch(userActivityServiceProvider).getActivities();
});

final totalCoinsEarnedProvider = FutureProvider<int>((ref) {
  return ref.watch(userActivityServiceProvider).getTotalCoinsEarned();
});
