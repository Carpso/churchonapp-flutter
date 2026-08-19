import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/config/remote_config.dart';
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
      final earned = await svc.collectDailyCoins();
      ref.invalidate(profileProvider);
      if (mounted) PremiumToast.showSuccess(context, '+$earned Coins collected!', title: 'Daily Reward');
    } catch (e) {
      if (mounted) PremiumToast.showError(context, 'Already collected today. Come back tomorrow!');
    } finally {
      if (mounted) setState(() => _isCollecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(profileProvider);
    final achievementsAsync = ref.watch(achievementsProvider);
    final referralCountAsync = ref.watch(referralCountProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Rewards', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBalanceHeader(theme, profileAsync),
            const SizedBox(height: 25),
            _buildDailyCollect(theme),
            const SizedBox(height: 25),
            _buildStreakSection(theme, profileAsync),
            const SizedBox(height: 25),
            _buildReferralSection(theme, referralCountAsync),
            const SizedBox(height: 25),
            Text('Achievements', style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text('Complete tasks to earn badges and XP', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 12)),
            const SizedBox(height: 15),
            _buildAchievements(theme, achievementsAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceHeader(ThemeData theme, AsyncValue<UserProfile?> profileAsync) {
    final scheme = theme.colorScheme;
    final profile = profileAsync.value;
    final coins = (profile?.balanceCc ?? 0).toInt();
    final streak = profile?.streakCount ?? 0;
    final name = profile?.name ?? 'Beloved';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, $name', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Rewards', style: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(LucideIcons.gift, color: theme.primaryColor, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _balanceItem(theme, 'Coins', coins.toString(), LucideIcons.coins, theme.primaryColor),
              const SizedBox(width: 15),
              _balanceItem(theme, 'Day Streak', '$streak', LucideIcons.flame, Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceItem(ThemeData theme, String label, String value, IconData icon, Color color) {
    final scheme = theme.colorScheme;
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
                Text(label, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyCollect(ThemeData theme) {
    final scheme = theme.colorScheme;
    final dailyCoins = currentRemoteConfig(ref).getInt('coins_daily_open_reward', 25);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(LucideIcons.sun, color: theme.primaryColor, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily Reward', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Collect $dailyCoins Coins every day', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isCollecting ? null : _collectDaily,
            icon: _isCollecting
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                : Icon(LucideIcons.gift, size: 16, color: scheme.onPrimary),
            label: Text(_isCollecting ? '...' : 'Collect', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onPrimary, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakSection(ThemeData theme, AsyncValue<UserProfile?> profileAsync) {
    final scheme = theme.colorScheme;
    final streak = profileAsync.value?.streakCount ?? 0;
    final maxStreak = 7;
    final progress = (streak / maxStreak).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reading Streak', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Read the Bible daily to build your streak', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 11)),
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
              backgroundColor: scheme.onSurface.withValues(alpha: 0.05),
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
                  color: filled ? Colors.orange : scheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    filled ? LucideIcons.check : LucideIcons.x,
                    size: 14,
                    color: filled ? Colors.white : scheme.onSurface.withValues(alpha: 0.2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralSection(ThemeData theme, AsyncValue<int> referralCountAsync) {
    final scheme = theme.colorScheme;
    final count = referralCountAsync.value ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
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
                Text('Referral Rewards', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('$count friends joined • Earn 100 CC per referral', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
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

  Widget _buildAchievements(ThemeData theme, AsyncValue<List<Map<String, dynamic>>> achievementsAsync) {
    return achievementsAsync.when(
      data: (achievements) {
        final categories = achievements.map((a) => a['category']?.toString() ?? '').toSet().toList();
        return Column(
          children: categories.map((cat) => _buildCategory(theme, cat, achievements.where((a) => a['category']?.toString() == cat).toList())).toList(),
        );
      },
      loading: () => Shimmer.fromColors(
        baseColor: theme.colorScheme.surface,
        highlightColor: theme.colorScheme.surfaceContainerHighest,
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
      error: (e, _) => Center(child: Text('$e', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)))),
    );
  }

  Widget _buildCategory(ThemeData theme, String category, List<Map<String, dynamic>> items) {
    final scheme = theme.colorScheme;
    final unlockedCount = items.where((a) => a['unlocked'] == true).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(category, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              Text('$unlockedCount/${items.length}', style: TextStyle(color: theme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((a) => _buildAchievementCard(theme, a)),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(ThemeData theme, Map<String, dynamic> achievement) {
    final scheme = theme.colorScheme;
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
        color: unlocked ? theme.primaryColor.withValues(alpha: 0.05) : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked ? theme.primaryColor.withValues(alpha: 0.2) : scheme.onSurface.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: unlocked ? theme.primaryColor.withValues(alpha: 0.15) : scheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              iconData,
              color: unlocked ? theme.primaryColor : scheme.onSurface.withValues(alpha: 0.2),
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
                    color: unlocked ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  achievement['description']?.toString() ?? '',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 11),
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
                color: scheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${achievement['xp_reward'] ?? 0} XP',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.2), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
