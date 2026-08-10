import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/plan_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/platform_settings_service.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/widgets/app_error_view.dart';
import 'package:church_on_app/core/utils/money.dart';

class HomeSubscriptionPaywall extends ConsumerStatefulWidget {
  final Tenant tenant;
  const HomeSubscriptionPaywall({super.key, required this.tenant});

  @override
  ConsumerState<HomeSubscriptionPaywall> createState() => _HomeSubscriptionPaywallState();
}

class _HomeSubscriptionPaywallState extends ConsumerState<HomeSubscriptionPaywall> {
  String get _momoNumber => widgetRemoteConfig(ref).getString('coa_payment_momo', '0976847775');

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final onboardingPaid = tenant.onboardingFeePaid;
    final isTrial = tenant.isInTrialPeriod;
    final effectivePlan = tenant.effectivePlan;

    // Plan prices are remote-configurable (platform_settings).
    final settings = ref.watch(platformSettingsProvider).value;
    final onboardingFee =
        settings?.onboardingFee ?? PlanLimits.onboardingFeeKwacha;
    final goldMonthly = settings?.goldMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha;
    final platinumMonthly = settings?.platinumMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Theme.of(context).colorScheme.error, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _title(onboardingPaid, isTrial),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _message(onboardingPaid, isTrial, effectivePlan),
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface, height: 1.5),
          ),
          if (!onboardingPaid) ...[
            const SizedBox(height: 12),
            _buildPlanComparison(onboardingFee, goldMonthly, platinumMonthly),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: !onboardingPaid ? _payOnboarding : _choosePlan,
              icon: const Icon(LucideIcons.creditCard),
              label: Text(
                !onboardingPaid
                    ? 'Pay Onboarding Fee (${formatKwacha(onboardingFee)})'
                    : 'Choose Your Plan',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => ref.read(currentTenantProvider.notifier).setTenant(null),
              child: const Text("SELECT ANOTHER CHURCH"),
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
    final settings = ref.read(platformSettingsProvider).value;
    final onboardingFee =
        settings?.onboardingFee ?? PlanLimits.onboardingFeeKwacha;
    final platinumMonthly = settings?.platinumMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;
    if (!onboardingPaid && isTrial) {
      return "Your 30-day Silver trial ends ${widget.tenant.subscriptionEndsAt != null ? 'on ${widget.tenant.subscriptionEndsAt!.toLocal().toString().split(' ')[0]}' : 'soon'}. After trial, pay K${onboardingFee.toStringAsFixed(0)} once to unlock 30 days free Platinum — or continue on Silver for free.";
    }
    if (!onboardingPaid) {
      return "Your trial has ended. Pay a one-time fee of K${onboardingFee.toStringAsFixed(0)} to unlock 30 days of Platinum (worth K${platinumMonthly.toStringAsFixed(0)}/mo), or continue on the free Silver plan with basic features.";
    }
    if (plan == TenantPlan.platinum && !_isAfterPromotion()) {
      return "You're enjoying a free Platinum upgrade after onboarding! This runs until ${_promotionEndStr()}. After that, choose your monthly plan or switch to free Silver.";
    }
    return "Pick a monthly plan that fits your church. Stay on Silver for free, or upgrade for more features.";
  }

  Widget _buildPlanComparison(double onboardingFee, double goldMonthly, double platinumMonthly) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _planRow("Silver", "K0/mo", "100 members • 10 events • 1GB", Colors.grey),
          const Divider(height: 16),
          _planRow("Gold", "K${goldMonthly.toStringAsFixed(0)}/mo", "500 members • 50 events • 10GB", Colors.amber),
          const Divider(height: 16),
          _planRow("Platinum", "K${platinumMonthly.toStringAsFixed(0)}/mo", "Unlimited members • Host quizzes • Priority", Colors.blueAccent),
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
        Text(
          desc,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  void _payOnboarding() {
    final settings = ref.read(platformSettingsProvider).value;
    final onboardingFee =
        settings?.onboardingFee ?? PlanLimits.onboardingFeeKwacha;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OnboardingPaymentSheet(
        tenant: widget.tenant,
        onboardingFee: onboardingFee,
        momoNumber: _momoNumber,
        onComplete: (success) {
          if (success && mounted) {
            ref.read(currentTenantProvider.notifier).loadTenant();
          }
        },
      ),
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
  final double onboardingFee;
  final String momoNumber;
  final ValueChanged<bool> onComplete;
  const _OnboardingPaymentSheet({
    required this.tenant,
    required this.onboardingFee,
    required this.momoNumber,
    required this.onComplete,
  });

  @override
  State<_OnboardingPaymentSheet> createState() => _OnboardingPaymentSheetState();
}

class _OnboardingPaymentSheetState extends State<_OnboardingPaymentSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final onboardingFee = widget.onboardingFee;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(LucideIcons.wallet, size: 48, color: Colors.blueAccent),
          const SizedBox(height: 12),
          Text("Onboarding Fee", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text("K${onboardingFee.toStringAsFixed(0)} — one-time payment\nUnlock 30 days of Platinum + full access", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), height: 1.5)),
          const SizedBox(height: 24),
          Text("Send K${onboardingFee.toStringAsFixed(0)} to:", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text("Superadmin MoMo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                  Text(widget.momoNumber, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                 Text("Zamtel / Airtel / MTN", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text("After sending, the Superadmin will verify and activate your account.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
               onPressed: _loading ? null : _submitPaymentRef,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                  : const Text("I'VE SENT THE PAYMENT"),
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
        showAppSnackBar(
          context,
          "Payment notification sent! Superadmin will verify shortly.",
          status: AppStatus.success,
        );
        Navigator.pop(context);
        widget.onComplete(true);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
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
    final settings = ref.watch(platformSettingsProvider).value;
    final goldMonthly = settings?.goldMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha;
    final platinumMonthly = settings?.platinumMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Your Plan")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Plans", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          const SizedBox(height: 8),
          Text("All plans include full features at different usage levels. SMS credits purchased separately.",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 24),
          _PlanCard(
            plan: TenantPlan.silver,
            isCurrent: tenant?.effectivePlan == TenantPlan.silver,
            onSelect: () => _selectPlan(context, ref, TenantPlan.silver),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            plan: TenantPlan.gold,
            priceOverride: goldMonthly,
            isCurrent: tenant?.effectivePlan == TenantPlan.gold,
            onSelect: () => _selectPlan(context, ref, TenantPlan.gold),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            plan: TenantPlan.platinum,
            priceOverride: platinumMonthly,
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
          showAppSnackBar(
            context,
            "Downgraded to Silver plan",
            status: AppStatus.info,
          );
        }
        return;
      }

      // For Gold/Platinum, show Lipila payment sheet
      if (context.mounted) Navigator.pop(context);
      final settings = ref.read(platformSettingsProvider).value;
      final price = plan == TenantPlan.gold
          ? (settings?.goldMonthlyFee ??
              PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha)
          : (settings?.platinumMonthlyFee ??
              PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha);
      final planName = PlanLimits.forPlan(plan).label;
      final momo = widgetRemoteConfig(ref).getString('coa_payment_momo', '0976847775');

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(ctx).dividerColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text("Subscribe to $planName", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(ctx).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text("Pay K$price/mo via mobile money", style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 16),
              Text("Send K$price to:", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                     Text("Superadmin MoMo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface)),
                     Text(momo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(ctx).colorScheme.primary)),
                    Text("Zamtel / Airtel / MTN", style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5))),
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
                      final extendDays = widgetRemoteConfig(ref)
                          .getInt('subscription_manual_payment_days', 30);
                      await client.from('churches').update({
                        'plan': planName.toLowerCase(),
                        'subscription_ends_at': DateTime.now()
                            .add(Duration(days: extendDays))
                            .toIso8601String(),
                      }).eq('id', tenantId);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) Navigator.pop(context);
                      if (context.mounted) {
                        showAppSnackBar(
                          context,
                          "Subscribed to $planName! 🎉",
                          status: AppStatus.success,
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        showAppSnackBar(
                          context,
                          AppErrorView.friendlyMessage(e),
                          status: AppStatus.error,
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                     backgroundColor: Theme.of(ctx).colorScheme.primary,
                     foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("CONFIRM & SUBSCRIBE"),
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
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }
}

class _PlanCard extends StatelessWidget {
  final TenantPlan plan;
  final bool isCurrent;
  final VoidCallback onSelect;
  final double? priceOverride;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onSelect,
    this.priceOverride,
  });

  @override
  Widget build(BuildContext context) {
    final limits = PlanLimits.forPlan(plan);
    final color = plan == TenantPlan.silver
        ? Colors.grey
        : plan == TenantPlan.gold
            ? Colors.amber
            : Colors.blueAccent;
    final priceDisplay = priceOverride != null
        ? 'K${priceOverride!.toStringAsFixed(0)}/mo'
        : limits.priceDisplay;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isCurrent ? color : Theme.of(context).dividerColor, width: isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(limits.label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
              const Spacer(),
              Text(priceDisplay, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
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
                  Text(
                     "Quiz hosting included",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _featureRow(context, "Members", limits.isUnlimited ? "Unlimited" : "${limits.maxMembers} max"),
          _featureRow(context, "Live Streaming", limits.isSilverSharedPool ? "Shared pool" : "${limits.liveStreamMinutesPerMonth ~/ 60} hrs/mo"),
          _featureRow(context, "Events/mo", limits.isUnlimited ? "Unlimited" : "${limits.eventsPerMonth}"),
          _featureRow(context, "Media Storage", "${limits.mediaStorageGb} GB"),
          _featureRow(context, "Kael AI Queries", limits.isUnlimited ? "Unlimited" : "${limits.kaelAiQueriesPerMonth}/mo"),
          _featureRow(context, "Marketplace Listings", limits.isUnlimited ? "Unlimited" : "${limits.marketplaceListingsPerMonth}/mo"),
          _featureRow(context, "Support", limits.supportLevel),
          _featureRow(context, "Platform Fee", "COA + Lipila fees apply"),
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
                 isCurrent ? "Current Plan" : plan == TenantPlan.silver ? "Stay Free" : "Subscribe ${priceOverride != null ? formatKwacha(priceOverride!) : limits.priceDisplay}/mo",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(LucideIcons.check, size: 12, color: Colors.green),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}
