import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/subscription_service.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

class _TierCard extends StatelessWidget {
  final String name;
  final String price;
  final String period;
  final List<String> features;
  final Color color;

  const _TierCard({
    required this.name,
    required this.price,
    required this.period,
    required this.features,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: color, size: 20),
              const SizedBox(width: 8),
              Text(name, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Text(price, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
              Text(period, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: color, size: 14),
                const SizedBox(width: 8),
                Text(f, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class SubscriptionBadge extends ConsumerWidget {
  const SubscriptionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(userSubscriptionProvider);

    return subAsync.when(
      data: (sub) {
        if (sub == null) return const SizedBox.shrink();
        String label;
        Color color;
        if (sub.isTrialActive) {
          label = "Trial (${sub.trialDaysRemaining}d)";
          color = Theme.of(context).primaryColor;
        } else if (sub.isGold) {
          label = "Gold";
          color = Colors.amber;
        } else if (sub.tier == SubscriptionTier.silver) {
          label = "Silver";
          color = Colors.grey;
        } else {
          label = "Free";
          color = Colors.white38;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class SubscriptionManagementScreen extends ConsumerWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(userSubscriptionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("My Subscription")),
      body: subAsync.when(
        data: (sub) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    LucideIcons.crown,
                    color: sub?.isPremium == true
                        ? Colors.amber
                        : theme.primaryColor,
                  ),
                  title: Text(
                    "Current Plan: ${(sub?.tier ?? SubscriptionTier.free).name.toUpperCase()}",
                  ),
                  subtitle: Text(
                    "Memberships are free — churches pay, members enjoy.",
                  ),
                  trailing: sub == null ? null : const SubscriptionBadge(),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Member Tiers",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "Every member starts on Silver for free. Gold and Platinum are premium member tiers unlocked by your church.",
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              _TierCard(
                name: "Silver",
                price: "Free",
                period: "forever",
                features: [
                  "Bible, radio & live streams",
                  "Giving, events & marketplace",
                  "Bible Quiz, Church Coins & rewards",
                  "Carpso Rides & community",
                ],
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              _TierCard(
                name: "Gold",
                price: "—",
                period: "",
                features: [
                  "All Silver features",
                  "Priority support",
                  "Early access to new features",
                ],
                color: Colors.amber,
              ),
              const SizedBox(height: 12),
              _TierCard(
                name: "Platinum",
                price: "—",
                period: "",
                features: [
                  "All Gold features",
                  "Exclusive offers & partner rewards",
                ],
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 20),
              Card(
                color: theme.primaryColor.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(LucideIcons.coins, color: theme.primaryColor),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Quiz Engine leases are paid in Church Coins (CC), not cash. Buy CC from the Buy Coins screen when your wallet runs low.",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                SizedBox(width: double.infinity, height: 80, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))))),
                SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 180, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24))))),
                SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 180, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24))))),
              ],
            ),
          ),
        ),
error: (e, _) => Center(child: Text("Error: $e")),
      ),
    );
  }
}
