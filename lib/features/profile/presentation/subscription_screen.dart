import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/subscription_service.dart';
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
          color = Colors.blueAccent;
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
          child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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

    return Scaffold(
      appBar: AppBar(title: const Text("My Subscription")),
      body: subAsync.when(
        data: (sub) {
          if (sub == null) return const Center(child: Text("No subscription found"));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  title: Text("Current Plan: ${sub.tier.name.toUpperCase()}"),
                  subtitle: sub.isTrialActive
                      ? Text("Trial ends in ${sub.trialDaysRemaining} days")
                      : sub.isSubscriptionActive
                          ? Text("Active until ${sub.subscriptionEndsAt?.toLocal().toString().split(' ')[0]}")
                          : const Text("Inactive"),
                ),
              ),
              const SizedBox(height: 20),
              if (!sub.isPremium) ...[
                const Text("Upgrade to unlock premium features:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _TierCard(
                  name: "Silver",
                  price: "K150",
                  period: "/month",
                  features: ["HD Video", "Priority Support"],
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                _TierCard(
                  name: "Gold",
                  price: "K1,500",
                  period: "/year",
                  features: ["4K Video", "Unlimited Support", "Custom Branding"],
                  color: Colors.amber,
                ),
              ],
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
