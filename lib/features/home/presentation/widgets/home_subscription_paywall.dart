import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/plan_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class HomeSubscriptionPaywall extends ConsumerStatefulWidget {
  final Tenant tenant;
  const HomeSubscriptionPaywall({super.key, required this.tenant});

  @override
  ConsumerState<HomeSubscriptionPaywall> createState() => _HomeSubscriptionPaywallState();
}

class _HomeSubscriptionPaywallState extends ConsumerState<HomeSubscriptionPaywall> {
  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final onboardingPaid = tenant.onboardingFeePaid;
    final isTrial = tenant.isInTrialPeriod;
    final effectivePlan = tenant.effectivePlan;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _title(onboardingPaid, isTrial),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _message(onboardingPaid, isTrial, effectivePlan),
            style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5),
          ),
          if (!onboardingPaid) ...[
            const SizedBox(height: 12),
            _buildPlanComparison(),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: !onboardingPaid ? _payOnboarding : _choosePlan,
              icon: const Icon(LucideIcons.creditCard, color: Colors.white),
              label: Text(
                !onboardingPaid
                    ? "Pay Onboarding Fee (K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)})"
                    : "Choose Your Plan",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => ref.read(currentTenantProvider.notifier).setTenant(null),
              child: const Text("SELECT ANOTHER CHURCH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  String _title(bool onboardingPaid, bool isTrial) {
    if (!onboardingPaid && isTrial) return "Trial Active";
    if (!onboardingPaid) return "Onboarding Fee Required";
    return "Choose Your Plan";
  }

  String _message(bool onboardingPaid, bool isTrial, TenantPlan plan) {
    if (!onboardingPaid && isTrial) {
      return "Your 30-day Silver trial ends ${widget.tenant.subscriptionEndsAt != null ? 'on ${widget.tenant.subscriptionEndsAt!.toLocal().toString().split(' ')[0]}' : 'soon'}. After trial, pay K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)} once to unlock 30 days free Platinum — or continue on Silver for free.";
    }
    if (!onboardingPaid) {
      return "Your trial has ended. Pay a one-time fee of K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)} to unlock 30 days of Platinum (worth K500/mo), or continue on the free Silver plan with basic features.";
    }
    if (plan == TenantPlan.platinum && !_isAfterPromotion()) {
      return "You're enjoying a free Platinum upgrade after onboarding! This runs until ${_promotionEndStr()}. After that, choose your monthly plan or switch to free Silver.";
    }
    return "Pick a monthly plan that fits your church. Stay on Silver for free, or upgrade for more features.";
  }

  Widget _buildPlanComparison() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _planRow("Silver", "K0/mo", "100 members • 10 events • 1GB", Colors.grey),
          const Divider(height: 16),
          _planRow("Gold", "K100/mo", "500 members • 50 events • 10GB", Colors.amber),
          const Divider(height: 16),
          _planRow("Platinum", "K500/mo", "Unlimited members • Host quizzes • Priority", Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _planRow(String name, String price, String desc, Color color) {
    return Row(
      children: [
        Icon(LucideIcons.circle, size: 8, color: color),
        const SizedBox(width: 8),
        Text("$name ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        Text(price, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: color)),
        const Spacer(),
        Text(desc, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

  void _payOnboarding() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OnboardingPaymentSheet(tenant: widget.tenant, onComplete: (success) {
        if (success && mounted) {
          ref.read(currentTenantProvider.notifier).loadTenant();
        }
      }),
    );
  }

  void _choosePlan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _PlanSelectionScreen()),
    ).then((_) {
      if (mounted) ref.read(currentTenantProvider.notifier).loadTenant();
    });
  }

  bool _isAfterPromotion() => DateTime.now().isAfter(PlanLimits.promotionEndDate);
  String _promotionEndStr() => PlanLimits.promotionEndDate.toLocal().toString().split(' ')[0];
}

class _OnboardingPaymentSheet extends StatefulWidget {
  final Tenant tenant;
  final ValueChanged<bool> onComplete;
  const _OnboardingPaymentSheet({required this.tenant, required this.onComplete});

  @override
  State<_OnboardingPaymentSheet> createState() => _OnboardingPaymentSheetState();
}

class _OnboardingPaymentSheetState extends State<_OnboardingPaymentSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(LucideIcons.wallet, size: 48, color: Colors.blueAccent),
          const SizedBox(height: 12),
          const Text("Onboarding Fee", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 8),
          Text("K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)} — one-time payment\nUnlock 30 days of Platinum + full access", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.5)),
          const SizedBox(height: 24),
          Text("Send K${PlanLimits.onboardingFeeKwacha.toStringAsFixed(0)} to:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Column(
              children: [
                Text("Superadmin MoMo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text("0976847775", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)),
                Text("Zamtel / Airtel / MTN", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("After sending, the Superadmin will verify and activate your account.", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _loading ? null : _submitPaymentRef,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("I'VE SENT THE PAYMENT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _submitPaymentRef() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      await client.from('churches').update({
        'payment_reference': 'manual-onboarding-${DateTime.now().millisecondsSinceEpoch}',
        'payment_submitted_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.tenant.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment notification sent! Superadmin will verify shortly."), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
        widget.onComplete(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _PlanSelectionScreen extends ConsumerWidget {
  const _PlanSelectionScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Your Plan")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Plans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          const SizedBox(height: 8),
          Text("All plans include full features at different usage levels. SMS credits purchased separately.", style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          _PlanCard(
            plan: TenantPlan.silver,
            isCurrent: tenant?.effectivePlan == TenantPlan.silver,
            onSelect: () => _selectPlan(context, ref, TenantPlan.silver),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            plan: TenantPlan.gold,
            isCurrent: tenant?.effectivePlan == TenantPlan.gold,
            onSelect: () => _selectPlan(context, ref, TenantPlan.gold),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            plan: TenantPlan.platinum,
            isCurrent: tenant?.effectivePlan == TenantPlan.platinum,
            onSelect: () => _selectPlan(context, ref, TenantPlan.platinum),
          ),
        ],
      ),
    );
  }

  void _selectPlan(BuildContext context, WidgetRef ref, TenantPlan plan) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final tenantId = ref.read(currentTenantProvider)?.id;
    if (tenantId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // For Silver (free), just update the plan immediately
      if (plan == TenantPlan.silver) {
        await client.from('churches').update({'plan': 'silver'}).eq('id', tenantId);
        if (context.mounted) {
          Navigator.pop(context);
        }
        if (context.mounted) {
          Navigator.pop(context);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Downgraded to Silver plan"),
                backgroundColor: Colors.grey),
          );
        }
        return;
      }

      // For Gold/Platinum, show Lipila payment sheet
      if (context.mounted) Navigator.pop(context);
      final price = PlanLimits.forPlan(plan).monthlyPriceKwacha;
      final planName = PlanLimits.forPlan(plan).label;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text("Subscribe to $planName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text("Pay K$price/mo via mobile money", style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Text("Send K$price to:", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: const Column(
                  children: [
                    Text("Superadmin MoMo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("0976847775", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)),
                    Text("Zamtel / Airtel / MTN", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await client.from('churches').update({
                        'plan': planName.toLowerCase(),
                        'subscription_ends_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
                      }).eq('id', tenantId);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) Navigator.pop(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Subscribed to $planName! 🎉"), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: plan == TenantPlan.gold ? Colors.amber.shade700 : Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("CONFIRM & SUBSCRIBE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    }
  }
}

class _PlanCard extends StatelessWidget {
  final TenantPlan plan;
  final bool isCurrent;
  final VoidCallback onSelect;

  const _PlanCard({required this.plan, required this.isCurrent, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final limits = PlanLimits.forPlan(plan);
    final color = plan == TenantPlan.silver
        ? Colors.grey
        : plan == TenantPlan.gold
            ? Colors.amber
            : Colors.blueAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isCurrent ? color : Colors.grey.shade200, width: isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(limits.label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
              const Spacer(),
              Text(limits.priceDisplay, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
            ],
          ),
          if (plan == TenantPlan.platinum)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trophy, size: 12, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text("Quiz hosting included • K250 leasing available", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _featureRow("Members", limits.isUnlimited ? "Unlimited" : "${limits.maxMembers} max"),
          _featureRow("Live Streaming", limits.isSilverSharedPool ? "Shared pool" : "${limits.liveStreamMinutesPerMonth ~/ 60} hrs/mo"),
          _featureRow("Events/mo", limits.isUnlimited ? "Unlimited" : "${limits.eventsPerMonth}"),
          _featureRow("Media Storage", "${limits.mediaStorageGb} GB"),
          _featureRow("Kael AI Queries", limits.isUnlimited ? "Unlimited" : "${limits.kaelAiQueriesPerMonth}/mo"),
          _featureRow("Marketplace Listings", limits.isUnlimited ? "Unlimited" : "${limits.marketplaceListingsPerMonth}/mo"),
          _featureRow("Support", limits.supportLevel),
          _featureRow("Platform Fee", "1% (min K3)"),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                isCurrent ? "Current Plan" : plan == TenantPlan.silver ? "Stay Free" : "Subscribe K${limits.monthlyPriceKwacha}/mo",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(LucideIcons.check, size: 12, color: Colors.green),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
