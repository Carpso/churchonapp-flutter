import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/services/plan_service.dart';
import 'package:church_on_app/core/services/tenant_sms_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/give/presentation/lipila_payment_gateway.dart';

class BuySmsCreditsScreen extends ConsumerWidget {
  const BuySmsCreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final balanceAsync = tenant != null
        ? ref.watch(smsBalanceProvider(tenant.id))
        : const AsyncValue.data(0);

    return Scaffold(
      appBar: AppBar(title: const Text("Buy SMS Credits")),
      body: balanceAsync.when(
        data: (balance) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Theme.of(context).primaryColor, Theme.of(context).primaryColor.withValues(alpha: 0.7)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const Text("SMS CREDIT BALANCE", style: TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text("$balance", style: const TextStyle(color: Colors.black, fontSize: 42, fontWeight: FontWeight.w900)),
                  const Text("credits", style: TextStyle(color: Colors.black54, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text("BUY SMS BUNDLES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey)),
            const SizedBox(height: 16),
            ...PlanLimits.smsBundles.entries.map((entry) {
              final price = entry.key;
              final credits = entry.value;
              final costPerSms = (price / credits).toStringAsFixed(2);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BundleCard(
                  price: price,
                  credits: credits,
                  costPerSms: costPerSms,
                  onBuy: () => _buyCredits(context, ref, tenant, price, credits),
                ),
              );
            }),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: const Color(0xFF7A5C00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "1 SMS = 1 credit. Credits never expire. Unused credits from expired bundles remain available.",
                      style: TextStyle(fontSize: 11, color: const Color(0xFF7A5C00), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error loading balance: $e")),
      ),
    );
  }

  void _buyCredits(BuildContext context, WidgetRef ref, dynamic tenant, int price, int credits) {
    if (tenant == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LipilaPaymentGateway(
        amount: price.toDouble(),
        description: "SMS Credits - $credits credits",
        category: 'sms_credits',
        recipientName: "Church On App",
        recipientAccount: "0976847775",
        paymentReason: "SMS Credit Bundle - K$price",
        onComplete: (success, txId) async {
          if (ctx.mounted) Navigator.pop(ctx);
          if (success && txId != null) {
            try {
              final service = ref.read(tenantSmsServiceProvider);
              final ok = await service.buyCredits(
                tenantId: tenant.id,
                credits: credits,
                amountKwacha: price.toDouble(),
                paymentRef: txId,
              );
              if (ok && context.mounted) {
                ref.invalidate(smsBalanceProvider(tenant.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$credits SMS credits added! ✅"), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                );
              }
            }
          }
        },
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  final int price;
  final int credits;
  final String costPerSms;
  final VoidCallback onBuy;

  const _BundleCard({
    required this.price,
    required this.credits,
    required this.costPerSms,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(LucideIcons.messageCircle, color: Theme.of(context).primaryColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("K$price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                    const SizedBox(width: 8),
                    Text("($credits SMS)", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Text("K$costPerSms per SMS", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: onBuy,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Buy", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
