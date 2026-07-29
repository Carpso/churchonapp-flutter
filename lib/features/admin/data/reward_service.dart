import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserReward {
  final String id;
  final String userId;
  final String rewardType;
  final double amount;
  final String title;
  final String? description;
  final String? badgeIcon;
  final String? grantedBy;
  final DateTime createdAt;

  UserReward({
    required this.id,
    required this.userId,
    required this.rewardType,
    this.amount = 0,
    required this.title,
    this.description,
    this.badgeIcon,
    this.grantedBy,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserReward.fromMap(Map<String, dynamic> m) => UserReward(
    id: m['id']?.toString() ?? '',
    userId: m['user_id']?.toString() ?? '',
    rewardType: m['reward_type']?.toString() ?? 'coins',
    amount: (m['amount'] as num?)?.toDouble() ?? 0,
    title: m['title']?.toString() ?? 'Reward',
    description: m['description']?.toString(),
    badgeIcon: m['badge_icon']?.toString(),
    grantedBy: m['granted_by']?.toString(),
    createdAt: m['created_at'] != null
        ? DateTime.tryParse(m['created_at'].toString())
        : null,
  );
}

class RewardService {
  final SupabaseService _supabase;
  RewardService(this._supabase);

  Future<List<UserReward>> getRewardsForUser(String userId) async {
    final result = await _supabase.client
        .from('user_rewards')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (result as List).map((e) => UserReward.fromMap(e)).toList();
  }

  Future<List<UserReward>> getAllRewards() async {
    final result = await _supabase.client
        .from('user_rewards')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (result as List).map((e) => UserReward.fromMap(e)).toList();
  }

  Future<void> awardCoins(
    String userId,
    int amount,
    String title,
    String description,
  ) async {
    final granterId = _supabase.client.auth.currentUser?.id;
    await _supabase.client.rpc(
      'award_user_coins',
      params: {
        'target_user_id': userId,
        'coin_amount': amount,
        'reason_title': title,
        'reason_desc': description,
        'granter_id': granterId,
      },
    );
  }

  Future<void> awardXp(
    String userId,
    int amount,
    String title,
    String description,
  ) async {
    final granterId = _supabase.client.auth.currentUser?.id;
    await _supabase.client.rpc(
      'award_user_xp',
      params: {
        'target_user_id': userId,
        'xp_amount': amount,
        'reason_title': title,
        'reason_desc': description,
        'granter_id': granterId,
      },
    );
  }

  Future<void> awardSubscriptionDays(String userId, int days) async {
    final granterId = _supabase.client.auth.currentUser?.id;
    await _supabase.client.from('user_rewards').insert({
      'user_id': userId,
      'reward_type': 'subscription_days',
      'amount': days,
      'title': 'Subscription Extension',
      'description': '$days days added to subscription',
      'granted_by': granterId,
    });
  }

  Future<void> grantBadge(
    String userId,
    String badgeIcon,
    String title,
    String description,
  ) async {
    final granterId = _supabase.client.auth.currentUser?.id;
    await _supabase.client.from('user_rewards').insert({
      'user_id': userId,
      'reward_type': 'badge',
      'amount': 0,
      'title': title,
      'description': description,
      'badge_icon': badgeIcon,
      'granted_by': granterId,
    });
  }
}

final rewardServiceProvider = Provider<RewardService>((ref) {
  return RewardService(ref.read(supabaseServiceProvider));
});

final userRewardsProvider = FutureProvider.family<List<UserReward>, String>((
  ref,
  userId,
) async {
  return ref.read(rewardServiceProvider).getRewardsForUser(userId);
});

final allRewardsProvider = FutureProvider<List<UserReward>>((ref) async {
  return ref.read(rewardServiceProvider).getAllRewards();
});
