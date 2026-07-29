import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/coins_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:shimmer/shimmer.dart';

final achievementsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return [];

  final userAchievements = await client
      .from('user_achievements')
      .select('achievement_id, unlocked_at')
      .eq('user_id', user.id) as List;

  final unlockedIds = userAchievements.map((a) => a['achievement_id']?.toString() ?? '').toSet();
  final unlockedAt = {for (final a in userAchievements) a['achievement_id']?.toString() ?? '': a['unlocked_at']?.toString() ?? ''};

  final allAchievements = await client
      .from('achievements')
      .select('id, title, description, icon, category, xp_reward, sort_order')
      .order('sort_order', ascending: true) as List;

  return allAchievements.map((a) {
    final id = a['id']?.toString() ?? '';
    return {
      'id': id,
      'title': a['title']?.toString() ?? '',
      'description': a['description']?.toString() ?? '',
      'icon': a['icon']?.toString() ?? 'star',
      'category': a['category']?.toString() ?? '',
      'xp_reward': (a['xp_reward'] ?? 0) as int,
      'unlocked': unlockedIds.contains(id),
      'unlocked_at': unlockedAt[id] ?? '',
    };
  }).toList();
});

final referralCountProvider = FutureProvider<int>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return 0;
  final res = await client
      .from('referrals')
      .select('id')
      .eq('referrer_id', user.id)
      .eq('status', 'completed');
  return res.length;
});

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  bool _isCollecting = false;

  Future<void> _collectDaily() async {
    setState(() => _isCollecting = true);
    try {
      final svc = ref.read(coinsServiceProvider);
      final canCollect = await svc.canCollectDaily();
      if (!canCollect) {
        if (mounted) PremiumToast.showError(context, 'Come back later! You can collect again in ~20h.');
        return;
      }
      await svc.collectDailyCoins();
      ref.invalidate(profileProvider);
      if (mounted) PremiumToast.showSuccess(context, '+25 Coins collected!', title: 'Daily Reward');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Already collected today. Come back tomorrow!');
    } finally {
      if (mounted) setState(() => _isCollecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final achievementsAsync = ref.watch(achievementsProvider);
    final referralCountAsync = ref.watch(referralCountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Rewards', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceHeader(profileAsync),
            const SizedBox(height: 25),
            _buildDailyCollect(),
            const SizedBox(height: 25),
            _buildStreakSection(profileAsync),
            const SizedBox(height: 25),
            _buildReferralSection(referralCountAsync),
            const SizedBox(height: 25),
            const Text('Achievements', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('Complete tasks to earn badges and XP', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 15),
            _buildAchievements(achievementsAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceHeader(AsyncValue<UserProfile?> profileAsync) {
    final profile = profileAsync.value;
    final coins = (profile?.balanceCc ?? 0).toInt();
    final streak = profile?.streakCount ?? 0;
    final name = profile?.name ?? 'Beloved';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, $name', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('Rewards', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(LucideIcons.gift, color: Colors.amber, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _balanceItem('Coins', coins.toString(), LucideIcons.coins, Colors.amber),
              const SizedBox(width: 15),
              _balanceItem('Day Streak', '$streak', LucideIcons.flame, Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyCollect() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.withValues(alpha: 0.1), Colors.orange.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(LucideIcons.sun, color: Colors.amber, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Reward', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Collect 25 Coins every day', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isCollecting ? null : _collectDaily,
            icon: _isCollecting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(LucideIcons.gift, size: 16, color: Colors.black),
            label: Text(_isCollecting ? '...' : 'Collect', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakSection(AsyncValue<UserProfile?> profileAsync) {
    final streak = profileAsync.value?.streakCount ?? 0;
    final maxStreak = 7;
    final progress = (streak / maxStreak).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.flame, color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reading Streak', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Read the Bible daily to build your streak', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Text('$streak / $maxStreak', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(maxStreak, (i) {
              final filled = i < streak;
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: filled ? Colors.orange : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    filled ? LucideIcons.check : LucideIcons.x,
                    size: 14,
                    color: filled ? Colors.white : Colors.white24,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralSection(AsyncValue<int> referralCountAsync) {
    final count = referralCountAsync.value ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(LucideIcons.share2, color: Colors.greenAccent, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Referral Rewards', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('$count friends joined • Earn 100 CC per referral', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('+${count * 100}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements(AsyncValue<List<Map<String, dynamic>>> achievementsAsync) {
    return achievementsAsync.when(
      data: (achievements) {
        final categories = achievements.map((a) => a['category']?.toString() ?? '').toSet().toList();
        return Column(
          children: categories.map((cat) => _buildCategory(cat, achievements.where((a) => a['category']?.toString() == cat).toList())).toList(),
        );
      },
      loading: () => Shimmer.fromColors(
        baseColor: const Color(0xFF1E293B),
        highlightColor: const Color(0xFF334155),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(width: double.infinity, height: 100, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.all(Radius.circular(24))))),
              SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 100, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.all(Radius.circular(24))))),
              SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 100, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.all(Radius.circular(24))))),
            ],
          ),
        ),
      ),
      error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: Colors.white38))),
    );
  }

  Widget _buildCategory(String category, List<Map<String, dynamic>> items) {
    final unlockedCount = items.where((a) => a['unlocked'] == true).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(category, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              Text('$unlockedCount/${items.length}', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((a) => _buildAchievementCard(a)),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(Map<String, dynamic> achievement) {
    final unlocked = achievement['unlocked'] as bool;
    final iconName = (achievement['icon'] as String?)?.toLowerCase() ?? 'star';
    IconData iconData;
    switch (iconName) {
      case 'zap': iconData = LucideIcons.zap; break;
      case 'target': iconData = LucideIcons.target; break;
      case 'flame': iconData = LucideIcons.flame; break;
      case 'star': default: iconData = LucideIcons.star; break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked ? Colors.amber.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked ? Colors.amber.withValues(alpha: 0.2) : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: unlocked ? Colors.amber.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              iconData,
              color: unlocked ? Colors.amber : Colors.white24,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement['title']?.toString() ?? '',
                  style: TextStyle(
                    color: unlocked ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  achievement['description']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (unlocked)
            const Icon(LucideIcons.checkCircle, color: Colors.greenAccent, size: 20)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${achievement['xp_reward'] ?? 0} XP',
                style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
