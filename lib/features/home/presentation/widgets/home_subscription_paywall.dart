import 'dart:async';

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
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';

class HomeSubscriptionPaywall extends ConsumerStatefulWidget {
  final Tenant tenant;
  const HomeSubscriptionPaywall({super.key, required this.tenant});

  @override
  ConsumerState<HomeSubscriptionPaywall> createState() => _HomeSubscriptionPaywallState();
}

class _HomeSubscriptionPaywallState extends ConsumerState<HomeSubscriptionPaywall> {
  /// K500 for churches/pastors, K1000 for bishops (remote-configurable).
  double get _onboardingFee {
    final profile = ref.read(profileProvider).value;
    final isBishop = profile?.role == 'bishop';
    return widgetRemoteConfig(ref).getDouble(
      isBishop ? 'onboarding_fee_bishop_kwacha' : 'onboarding_fee_church_kwacha',
      isBishop ? 1000 : 500,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final onboardingPaid = tenant.onboardingFeePaid;
    final isTrial = tenant.isInTrialPeriod;
    final effectivePlan = tenant.effectivePlan;
    final onboardingFee = _onboardingFee;

    final settings = ref.watch(platformSettingsProvider).value;
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
            _message(onboardingPaid, isTrial, effectivePlan, onboardingFee),
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
          if (!onboardingPaid && tenant.onboardingBalanceDue > 0) ...[
            const SizedBox(height: 10),
            Text(
              'You have an outstanding balance of ${formatKwacha(tenant.onboardingBalanceDue)} from your installment. Pay it now to activate.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ],
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

  String _message(bool onboardingPaid, bool isTrial, TenantPlan plan, double onboardingFee) {
    final settings = ref.read(platformSettingsProvider).value;
    final platinumMonthly = settings?.platinumMonthlyFee ??
        PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha;
    if (!onboardingPaid && isTrial) {
      return "Your 30-day Silver trial ends ${widget.tenant.subscriptionEndsAt != null ? 'on ${widget.tenant.subscriptionEndsAt!.toLocal().toString().split(' ')[0]}' : 'soon'}. After trial, pay ${formatKwacha(onboardingFee)} once (setup + onboarding) to unlock 30 days free Platinum — or continue on Silver for free. Installments available.";
    }
    if (!onboardingPaid) {
      return "Your trial has ended. Pay a one-time setup + onboarding fee of ${formatKwacha(onboardingFee)} to unlock 30 days of Platinum (worth ${formatKwacha(platinumMonthly)}/mo), or continue on the free Silver plan with basic features. Pay in installments if you prefer.";
    }
    if (plan == TenantPlan.platinum && !_isAfterPromotion()) {
      return "You're enjoying a free Platinum upgrade after onboarding! This runs until ${_promotionEndStr()}. After that, choose your monthly plan or switch to free Silver.";
    }
    return "Pick a monthly plan that fits your church. Stay on Silver for free, or upgrade for more features. Paid plans can be paid in installments.";
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
          _planRow("Platinum", "K${platinumMonthly.toStringAsFixed(0)}/mo", "Unlimited members • Host quizzes • Priority", Theme.of(context).primaryColor),
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
    final fee = _onboardingFee;
    final balanceDue = widget.tenant.onboardingBalanceDue;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LipilaSubscriptionSheet(
        title: "Onboarding Fee",
        amount: balanceDue > 0 ? balanceDue : fee,
        narration: "Church Onboarding Fee (setup)",
        allowInstallments: balanceDue <= 0,
        onPaid: (reference, balance) async {
          final client = Supabase.instance.client;
          await client.from('churches').update({
            'payment_reference': reference,
            'payment_submitted_at': DateTime.now().toIso8601String(),
            'onboarding_balance_due': balance,
          }).eq('id', widget.tenant.id);
          if (mounted) {
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

/// Lipila mobile-money payment sheet used for onboarding fees and paid plans.
/// Supports optional 2-installment splitting (50% now, 50% due later).
class _LipilaSubscriptionSheet extends ConsumerStatefulWidget {
  final String title;
  final double amount;
  final String narration;
  final bool allowInstallments;
  final Future<void> Function(String reference, double balanceDue) onPaid;

  const _LipilaSubscriptionSheet({
    required this.title,
    required this.amount,
    required this.narration,
    this.allowInstallments = false,
    required this.onPaid,
  });

  @override
  ConsumerState<_LipilaSubscriptionSheet> createState() => _LipilaSubscriptionSheetState();
}

class _LipilaSubscriptionSheetState extends ConsumerState<_LipilaSubscriptionSheet> {
  final _phoneCtrl = TextEditingController();
  bool _installments = false;
  bool _paying = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(profileProvider).value;
      if (profile?.phoneNumber != null && profile!.phoneNumber!.isNotEmpty) {
        _phoneCtrl.text = profile.phoneNumber!;
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneCtrl.dispose();
    super.dispose();
  }

  double get _payNow => _installments ? (widget.amount / 2).floorToDouble() : widget.amount;
  double get _balanceDue => _installments ? (widget.amount - _payNow) : 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Center(
                child: Icon(LucideIcons.wallet, size: 48, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(widget.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.onSurface)),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "Pay ${formatKwacha(_payNow)}${_installments ? ' now (50%)' : ''} via mobile money",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              if (widget.allowInstallments) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.calendarClock, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Pay in 2 installments",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              "Pay 50% now (${formatKwacha((widget.amount / 2).floorToDouble())}), the rest later.",
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _installments,
                        onChanged: (v) => setState(() => _installments = v),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "Mobile Money number (MTN / Airtel / Zamtel)",
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(LucideIcons.smartphone, size: 20),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _paying ? null : _pay,
                  icon: _paying
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.shieldCheck, size: 20),
                  label: Text(_paying ? "Paying..." : "PAY ${formatKwacha(_payNow)}"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "Secure payment via Lipila Gateway. A PIN prompt will be sent to your phone.",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pay() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = "Enter your mobile money number");
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final phone = MomoPhoneInputWidget.formatPhone(_phoneCtrl.text.trim());
      final reference = 'coa-fee-${DateTime.now().millisecondsSinceEpoch}';

      await client.functions.invoke('lipila-collect', body: {
        'action': 'initiate',
        'accountNumber': phone,
        'amount': _payNow,
        'narration': widget.narration,
        'reference': reference,
      });

      final success = await _pollPayment(client, reference);
      if (!success) {
        setState(() {
          _paying = false;
          _error = "Payment not confirmed yet. You can try again.";
        });
        return;
      }

      await widget.onPaid(reference, _balanceDue);
      if (mounted) {
        showAppSnackBar(
          context,
          _balanceDue > 0
              ? "Payment received! Balance of ${formatKwacha(_balanceDue)} is due later."
              : "Payment received! Your subscription is being activated.",
          status: AppStatus.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paying = false;
          _error = AppErrorView.friendlyMessage(e);
        });
      }
    }
  }

  Future<bool> _pollPayment(SupabaseClient client, String reference) async {
    const maxAttempts = 30;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(const Duration(seconds: 4));
      try {
        final localPayment = await client
            .from('coa_payments')
            .select('status')
            .eq('payment_ref', reference)
            .maybeSingle();
        if (localPayment != null) {
          final status = (localPayment['status'] ?? '').toString().toLowerCase();
          if (['approved', 'completed', 'confirmed', 'settled'].contains(status)) return true;
          if (['rejected', 'failed', 'cancelled'].contains(status)) return false;
        }
      } catch (e) {
        debugPrint('Paywall poll (db) failed: $e');
      }
      try {
        final res = await client.functions.invoke('lipila-collect', body: {
          'action': 'status',
          'reference': reference,
        });
        final data = res.data;
        var statusText = '';
        if (data is Map) {
          final inner = data['data'];
          if (inner is Map && inner['status'] != null) {
            statusText = inner['status'].toString();
          } else if (data['status'] != null) {
            statusText = data['status'].toString();
          }
        }
        final status = statusText.toLowerCase();
        if (['successful', 'paid', 'completed', 'settled', 'success', 'approved', 'accepted', 'confirmed'].contains(status)) {
          return true;
        }
        if (['failed', 'cancelled', 'rejected', 'declined', 'error', 'timeout'].contains(status)) {
          return false;
        }
      } catch (e) {
        debugPrint('Paywall poll (lipila) failed: $e');
      }
    }
    return false;
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
          Text("All plans include full features at different usage levels. SMS credits purchased separately. Paid plans can be paid in installments.",
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

    // For Silver (free), just update the plan immediately
    if (plan == TenantPlan.silver) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        await client.from('churches').update({'plan': 'silver'}).eq('id', tenantId);
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          showAppSnackBar(context, "Downgraded to Silver plan", status: AppStatus.info);
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
          showAppSnackBar(context, AppErrorView.friendlyMessage(e), status: AppStatus.error);
        }
      }
      return;
    }

    // For Gold/Platinum, pay via Lipila with optional installments
    final settings = ref.read(platformSettingsProvider).value;
    final price = plan == TenantPlan.gold
        ? (settings?.goldMonthlyFee ?? PlanLimits.forPlan(TenantPlan.gold).monthlyPriceKwacha)
        : (settings?.platinumMonthlyFee ?? PlanLimits.forPlan(TenantPlan.platinum).monthlyPriceKwacha);
    final planName = PlanLimits.forPlan(plan).label;
    final extendDays = widgetRemoteConfig(ref).getInt('subscription_manual_payment_days', 30);

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LipilaSubscriptionSheet(
        title: "Subscribe to $planName",
        amount: price,
        narration: "$planName Plan (1 month)",
        allowInstallments: true,
        onPaid: (reference, balance) async {
          await client.from('churches').update({
            'plan': planName.toLowerCase(),
            'payment_reference': reference,
            'payment_submitted_at': DateTime.now().toIso8601String(),
            'subscription_ends_at': DateTime.now().add(Duration(days: extendDays)).toIso8601String(),
            'onboarding_balance_due': balance,
          }).eq('id', tenantId);
        },
      ),
    );
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
            : Theme.of(context).primaryColor;
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
              decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.trophy, size: 12, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    "Quiz hosting included",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
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
