import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/core/utils/money.dart';
import 'tithe_history_screen.dart';
import 'lipila_payment_gateway.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/i18n/l10n.dart';
import 'package:church_on_app/features/finance/data/offline_giving_queue.dart';
import 'widgets/giving_category_selector.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/core/widgets/entity_selector.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_providers.dart';

class GivingScreen extends ConsumerStatefulWidget {
  const GivingScreen({super.key});

  @override
  ConsumerState<GivingScreen> createState() => _GivingScreenState();
}

class _GivingScreenState extends ConsumerState<GivingScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = "Offering";
  String _selectedTitheRecipient = "Pastor";
  final TextEditingController _amountController = TextEditingController();

  final List<String> _categories = ["Offering", "Tithe", "Mission", "Building Fund", "Other"];
  final List<String> _titheRecipients = ["Pastor", "Bishop", "Treasurer"];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      data: (profile) => _buildScreen(context, profile),
      loading: () => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ShimmerLoader.rectangular(width: 200, height: 120),
              const SizedBox(height: 20),
              const ShimmerLoader.rectangular(width: 160, height: 14),
              const SizedBox(height: 10),
              const ShimmerLoader.rectangular(width: 120, height: 14),
            ],
          ),
        ),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: ErrorRetryWidget(
          message: "Failed to load profile",
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, UserProfile? profile) {
    final txAsync = ref.watch(transactionsStreamProvider);
    final churchAsync = ref.watch(churchGivingOverviewProvider);
    final config = widgetRemoteConfig(ref);
    final personalGoal = config.getInt('giving_monthly_goal_kwacha', 500);
    final churchGoal = config.getInt('church_monthly_goal_kwacha', 10000);

    double monthlyGiven = 0;
    txAsync.whenData((txs) {
      final now = DateTime.now();
      monthlyGiven = txs
          .where((t) =>
              t.status == 'completed' &&
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month)
          .fold(0.0, (sum, t) => sum + t.amount);
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.tr('Give'), style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'QR Payment',
            icon: const Icon(LucideIcons.qrCode, size: 18),
            onPressed: _showQrPaymentDialog,
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TitheHistoryScreen())),
            icon: const Icon(LucideIcons.history, size: 16),
            label: const Text("HISTORY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(25, 25, 25, 25 + MediaQuery.of(context).padding.bottom + 90),
        child: Column(
          children: [
            _buildOfflineQueueBanner(),
            _buildTotalGivenCard(profile, monthlyGiven, personalGoal),
            const SizedBox(height: 16),
            _buildChurchGoalCard(churchAsync, churchGoal),
            const SizedBox(height: 20),
             _buildFeatureTiles(context),
            const SizedBox(height: 16),
            _buildGroupGivingShortcut(),
            const SizedBox(height: 30),
             GivingCategorySelector(
              categories: _categories,
              selectedCategory: _selectedCategory,
              onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
            ),
            if (_selectedCategory == "Tithe") ...[
              const SizedBox(height: 16),
              _buildTitheRecipientSelector(),
            ],
            const SizedBox(height: 30),
            Form(
              key: _formKey,
              child: _buildAmountInput(),
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState == null ||
                    !_formKey.currentState!.validate()) {
                  return;
                }
                final amount = double.tryParse(_amountController.text) ?? 0.0;

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (sheetCtx) {
                    final tenant = ref.read(currentTenantProvider);
                    return LipilaPaymentGateway(
                      amount: amount,
                      description: 'Giving: $_selectedCategory',
                      category: _selectedCategory.toLowerCase(),
                     recipientName: tenant?.name ?? 'Local Church',
                     recipientAccount: _selectedCategory.toLowerCase() == 'tithe'
                         ? _titheRecipientPhone(tenant)
                         : (tenant?.treasurerPhone ??
                             tenant?.contactPhone ??
                             'CHURCH-OFFICIAL-AC'),
                      paymentReason: '$_selectedCategory Support',
                      onComplete: (success, txId) async {
                        Navigator.pop(sheetCtx);
                        if (success && txId != null) {
                          await ref
                              .read(financeServiceProvider)
                              .logTransaction(
                                amount,
                                _selectedCategory.toLowerCase(),
                                txId,
                                tenantId: tenant?.id,
                                recipientPhone: tenant?.treasurerPhone,
                                recipientName: tenant?.name,
                                recipientRole:
                                    _selectedCategory.toLowerCase() == 'tithe'
                                        ? _selectedTitheRecipient
                                        : null,
                              );
                          ref.invalidate(transactionsStreamProvider);
                          ref.invalidate(profileProvider);
                          if (mounted) _showSuccessSheet(txId);
                        }
                      },
                    );
                  },
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Text('PROCEED TO SECURE PAYMENT'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSheet(String txId, {bool groupLinked = false, String groupLabel = ''}) {
    final message = groupLinked
        ? 'Your giving of ${formatKwacha(double.tryParse(_amountController.text) ?? 0)} has been processed securely and linked to the $groupLabel group.'
        : 'Your giving of ${formatKwacha(double.tryParse(_amountController.text) ?? 0)} has been processed securely.';
    PremiumConfirmationSheet.show(
      context: context,
      title: 'Transaction Successful!',
      subtitle: 'Your giving has been received.',
      message: message,
      referenceId: txId,
      type: ConfirmationType.success,
      primaryLabel: 'AMEN',
    );
  }

  Future<void> _linkGroupGiving(String type, double amount, Tenant? tenant) async {
    final profile = ref.read(profileProvider).value;
    if (tenant == null || profile == null) return;
    final service = ref.read(groupContributionServiceProvider);
    final group = await service.findOrCreateTypeGroup(
      tenantId: tenant.id,
      title: '$type Giving',
      description: 'Give together as a $type',
      createdBy: profile.id,
    );
    final memberId = await service.ensureMembership(
      groupId: group.id,
      userId: profile.id,
      userName: profile.name,
      pledgedAmount: amount,
    );
    await service.contribute(
      groupId: group.id,
      memberId: memberId,
      userName: profile.name,
      amount: amount,
    );
    ref.invalidate(groupDetailProvider(group.id));
    ref.invalidate(groupMembersProvider(group.id));
    ref.invalidate(groupPaymentsProvider(group.id));
    ref.invalidate(groupContributionsProvider(tenant.id));
  }

  Widget _buildOfflineQueueBanner() {
    final pendingAsync = ref.watch(offlineGivingPendingProvider);
    return pendingAsync.when(
      data: (pending) {
        if (pending.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.wifiOff, color: Colors.amber, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${pending.length} offline gift${pending.length == 1 ? '' : 's'} queued",
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Your giving is saved and will sync automatically when you're back online.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(offlineGivingQueueProvider).syncNow();
                  if (mounted) ref.invalidate(offlineGivingPendingProvider);
                },
                child: const Text("SYNC NOW", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Widget _buildTotalGivenCard(UserProfile? profile, double monthlyGiven, int goal) {
    final balanceZmw = profile?.balanceZmw ?? 0.0;
    final balanceCc = profile?.balanceCc ?? 0.0;
    final progress = goal <= 0 ? 0.0 : (monthlyGiven / goal).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('My Giving').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatKwacha(monthlyGiven),
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    const Text("THIS MONTH", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ],
                ),
              ),
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress.toDouble(),
                      strokeWidth: 7,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFFFDA03)),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(progress.toDouble() * 100).round()}%',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                          ),
                          const Text("GOAL", style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFDA03)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "K${monthlyGiven.toStringAsFixed(0)} of K$goal monthly goal",
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatKwacha(balanceZmw), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const Text("ZMW BALANCE", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${balanceCc.toInt()} CC", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const Text("REWARDS CC", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text("Material Rewards Active", style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildChurchGoalCard(
    AsyncValue<ChurchGivingOverview> churchAsync,
    int goal,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: churchAsync.when(
        data: (overview) {
          final raised = overview.monthlyTotal;
          final progress = goal <= 0 ? 0.0 : (raised / goal).clamp(0.0, 1.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.church, size: 18, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    "CHURCH GIVING GOAL",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatKwacha(raised),
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 6),
                      child: Text(
                        "of K$goal raised this month",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress.toDouble() * 100).round()}%',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.toDouble(),
                  minHeight: 8,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).primaryColor),
                ),
              ),
              if (overview.givers.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  "TOP GIVERS THIS MONTH",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                ...overview.givers.take(3).map((g) {
                  final initial = g.name.trim().isEmpty
                      ? '?'
                      : g.name.trim()[0].toUpperCase();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.12),
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          formatKwacha(g.amount),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
        error: (e, _) => Row(
          children: [
            Icon(LucideIcons.info, size: 16, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Church giving goal unavailable",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTiles(BuildContext context) {
    final brand = Theme.of(context).primaryColor;
    final features = [
      (LucideIcons.coins, "Fundraising", "Active campaigns", '/fundraising', brand),
      (LucideIcons.scrollText, "My Pledges", "Track promises", '/my-pledges', brand.withValues(alpha: 0.6)),
      (LucideIcons.creditCard, "Tithe Card", "Physical giving card", '/tithe-card', Colors.amber),
      (LucideIcons.bellRing, "Transaction Alerts", "Monitor giving activity", '/alerts', Colors.deepOrange),
      (LucideIcons.wallet, "Wallet", "Manage funds", '/wallet', Colors.green),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("More Ways to Give", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(features.length, (index) {
                final (icon, title, subtitle, route, color) = features[index];
                return GestureDetector(
                  onTap: () => context.push(route),
                  child: Container(
                    width: tileWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 22),
                        ),
                        const SizedBox(height: 8),
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 10), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  void _showQrPaymentDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR Payment'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter amount (K)',
            prefixIcon: Icon(LucideIcons.qrCode),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(controller.text.trim()) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx);
              final tenant = ref.read(currentTenantProvider);
              context.push('/qr-payment', extra: {
                'amount': amount,
                'description': 'Giving: $_selectedCategory',
                'recipient': tenant?.name ?? 'Local Church',
              });
            },
            child: const Text('Generate QR'),
          ),
        ],
      ),
    );
  }

  double _calculateFee(double amount) {
    final fees = ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
    return fees.platformFee(amount);
  }

  Widget _buildAmountInput() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Enter Amount (K)", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() {}),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final amount = double.tryParse(v.trim());
              if (amount == null || amount <= 0) return 'Enter a valid positive amount';
              return null;
            },
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary),
            decoration: const InputDecoration(
              hintText: "0.00",
              prefixText: "K ",
              border: InputBorder.none,
            ),
          ),
          if (_amountController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.info, size: 12, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    "+ Platform Fee (K${(() { final amt = double.tryParse(_amountController.text); if (amt == null) return '3.00'; return _calculateFee(amt).toStringAsFixed(2); })()})",
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          ]
        ],
      ),
     );
  }

  Widget _buildTitheRecipientSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Tithe Recipient",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => showEntitySelector(
            context: context,
            title: 'Tithe Recipient',
            options: _titheRecipients
                .map((r) => EntityOption(
                      id: r,
                      name: r,
                      subtitle: 'Send tithe to the $r',
                      icon: r == 'Pastor'
                          ? LucideIcons.mic2
                          : r == 'Bishop'
                              ? LucideIcons.crown
                              : LucideIcons.wallet,
                    ))
                .toList(),
            onSelected: (selected) =>
                setState(() => _selectedTitheRecipient = selected.id),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTitheRecipient,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(LucideIcons.chevronDown,
                    size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _groupTypes = ["Couple", "Friend", "Family"];

  Widget _buildGroupGivingShortcut() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users, size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text("Group Giving",
                  style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text("Gifts are linked into a shared Couple / Friend / Family giving group",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _groupTypes.map((type) {
              return ChoiceChip(
                label: Text(type, style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor)),
                selected: false,
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                showCheckmark: false,
                onSelected: (_) => _openGroupGivingSheet(type),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _openGroupGivingSheet(String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final tenant = ref.read(currentTenantProvider);
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(sheetCtx).viewPadding.bottom + 30),
            color: Theme.of(sheetCtx).colorScheme.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$type Giving",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(sheetCtx).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text("Enter amount to give as a $type",
                    style: TextStyle(color: Theme.of(sheetCtx).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _groupAmountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "0.00",
                    prefixText: "K ",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _groupAmountController.text.isNotEmpty
                        ? () {
                            final amount = double.tryParse(_groupAmountController.text) ?? 0.0;
                            if (amount <= 0) return;
                            Navigator.pop(sheetCtx);
                            _proceedGroupPayment(sheetCtx, type, amount, tenant);
                          }
                        : null,
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                    child: const Text("PROCEED TO SECURE PAYMENT"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  final TextEditingController _groupAmountController = TextEditingController();

  void _proceedGroupPayment(BuildContext ctx, String type, double amount, Tenant? tenant) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return LipilaPaymentGateway(
          amount: amount,
          description: '$type Giving',
          category: 'offering',
          recipientName: tenant?.name ?? 'Local Church',
          recipientAccount: tenant?.treasurerPhone ?? tenant?.contactPhone ?? 'CHURCH-OFFICIAL-AC',
          paymentReason: '$type Giving',
          onComplete: (success, txId) async {
            Navigator.pop(sheetCtx);
            if (success && txId != null) {
              await ref.read(financeServiceProvider).logTransaction(
                    amount,
                    'offering',
                    txId,
                    tenantId: tenant?.id,
                    recipientPhone: tenant?.treasurerPhone,
                    recipientName: tenant?.name,
                  );
              ref.invalidate(transactionsStreamProvider);
              ref.invalidate(profileProvider);
              var linked = false;
              try {
                await _linkGroupGiving(type, amount, tenant);
                linked = true;
              } catch (e) {
                debugPrint('[Give] Group giving link failed: $e');
              }
              _groupAmountController.clear();
              if (mounted) _showSuccessSheet(txId, groupLinked: linked, groupLabel: '$type Giving');
            }
          },
        );
      },
    );
  }

  String _titheRecipientPhone(Tenant? tenant) {
    switch (_selectedTitheRecipient) {
      case "Pastor":
        return tenant?.pastorPhone ?? tenant?.treasurerPhone ?? 'CHURCH-OFFICIAL-AC';
      case "Bishop":
        return tenant?.contactPhone ?? tenant?.pastorPhone ?? 'CHURCH-OFFICIAL-AC';
      case "Treasurer":
        return tenant?.treasurerPhone ?? tenant?.contactPhone ?? 'CHURCH-OFFICIAL-AC';
      default:
        return tenant?.pastorPhone ?? tenant?.treasurerPhone ?? 'CHURCH-OFFICIAL-AC';
    }
  }
}
