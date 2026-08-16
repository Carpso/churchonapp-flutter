import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import '../data/reward_service.dart';

class RewardManagementScreen extends ConsumerStatefulWidget {
  const RewardManagementScreen({super.key});

  @override
  ConsumerState<RewardManagementScreen> createState() => _RewardManagementScreenState();
}

class _RewardManagementScreenState extends ConsumerState<RewardManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final rewardsAsync = ref.watch(allRewardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rewards Management'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.coins),
            tooltip: 'Award Reward',
            onPressed: () => _showAwardDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildQuickActions(),
          const Divider(height: 1),
          Expanded(
            child: rewardsAsync.when(
              data: (rewards) => rewards.isEmpty
                  ? const Center(child: Text('No rewards awarded yet.'))
                  : ListView.builder(
                      itemCount: rewards.length,
                      itemBuilder: (context, index) {
                        final r = rewards[index];
                        return ListTile(
                          leading: _rewardIcon(r.rewardType, r.amount),
                          title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${r.rewardType} — ${r.description ?? ''}'),
                          trailing: Text(_formatDate(r.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        );
                      },
                    ),
              loading: () => const Center(child: ListSkeleton()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardIcon(String type, double amount) {
    IconData icon;
    Color color;
    switch (type) {
      case 'coins': icon = LucideIcons.coins; color = Colors.amber; break;
      case 'xp': icon = LucideIcons.zap; color = Theme.of(context).primaryColor; break;
      case 'badge': icon = LucideIcons.award; color = Theme.of(context).primaryColor.withValues(alpha: 0.7); break;
      case 'subscription_days': icon = LucideIcons.calendar; color = Colors.green; break;
      default: icon = LucideIcons.gift; color = Colors.grey;
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _actionChip(LucideIcons.coins, 'Award Coins', Colors.amber, () => _showAwardDialog(type: 'coins')),
          const SizedBox(width: 8),
          _actionChip(LucideIcons.zap, 'Award XP', Theme.of(context).primaryColor, () => _showAwardDialog(type: 'xp')),
          const SizedBox(width: 8),
          _actionChip(LucideIcons.award, 'Grant Badge', Theme.of(context).primaryColor.withValues(alpha: 0.7), () => _showBadgeDialog()),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  void _showAwardDialog({String? type}) async {
    final userIdC = TextEditingController();
    final amountC = TextEditingController();
    final titleC = TextEditingController(text: type == 'coins' ? 'Coins Reward' : type == 'xp' ? 'XP Reward' : 'Reward');
    final descC = TextEditingController();
    String rewardType = type ?? 'coins';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Award Reward'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: userIdC, decoration: const InputDecoration(labelText: 'User ID', hintText: 'Paste user UUID')),
              if (rewardType != 'badge') ...[
                TextField(controller: amountC, decoration: InputDecoration(labelText: rewardType == 'coins' ? 'Coin Amount' : 'XP Amount'), keyboardType: TextInputType.number),
              ],
              TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description (optional)'), maxLines: 2),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                setState(() => isSubmitting = true);
                try {
                  final svc = ref.read(rewardServiceProvider);
                  final userId = userIdC.text.trim();
                  if (rewardType == 'coins') {
                    await svc.awardCoins(userId, int.tryParse(amountC.text) ?? 0, titleC.text, descC.text);
                  } else if (rewardType == 'xp') {
                    await svc.awardXp(userId, int.tryParse(amountC.text) ?? 0, titleC.text, descC.text);
                  }
                  ref.invalidate(allRewardsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ctx.mounted) PremiumToast.showSuccess(ctx, 'Reward awarded!');
                } catch (e) {
                  if (ctx.mounted) PremiumToast.showError(ctx, 'Failed: $e');
                } finally {
                  setState(() => isSubmitting = false);
                }
              },
              child: const Text('Award'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDialog() async {
    final userIdC = TextEditingController();
    final titleC = TextEditingController();
    final descC = TextEditingController();
    final iconC = TextEditingController(text: 'award');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Grant Badge'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: userIdC, decoration: const InputDecoration(labelText: 'User ID')),
              TextField(controller: titleC, decoration: const InputDecoration(labelText: 'Badge Name')),
              TextField(controller: descC, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
              TextField(controller: iconC, decoration: const InputDecoration(labelText: 'Icon (lucide name)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSubmitting ? null : () async {
                setState(() => isSubmitting = true);
                try {
                  await ref.read(rewardServiceProvider).grantBadge(
                    userIdC.text.trim(), iconC.text.trim(), titleC.text, descC.text,
                  );
                  ref.invalidate(allRewardsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ctx.mounted) PremiumToast.showSuccess(ctx, 'Badge granted!');
                } catch (e) {
                  if (ctx.mounted) PremiumToast.showError(ctx, 'Failed: $e');
                } finally {
                  setState(() => isSubmitting = false);
                }
              },
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );
  }
}
