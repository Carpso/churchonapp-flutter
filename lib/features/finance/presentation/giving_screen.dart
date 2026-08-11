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
import 'widgets/giving_category_selector.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';

class GivingScreen extends ConsumerStatefulWidget {
  const GivingScreen({super.key});

  @override
  ConsumerState<GivingScreen> createState() => _GivingScreenState();
}

class _GivingScreenState extends ConsumerState<GivingScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = "Tithe";
  final TextEditingController _amountController = TextEditingController();

  final List<String> _categories = ["Tithe", "Offering", "Mission", "Building Fund", "Other"];

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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Giving", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TitheHistoryScreen())),
            icon: const Icon(LucideIcons.history, size: 16),
            label: const Text("HISTORY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildTotalGivenCard(profile),
            const SizedBox(height: 20),
            _buildFeatureTiles(context),
            const SizedBox(height: 30),
            GivingCategorySelector(
              categories: _categories,
              selectedCategory: _selectedCategory,
              onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
            ),
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
                          ? (tenant?.pastorPhone ??
                              tenant?.treasurerPhone ??
                              'CHURCH-OFFICIAL-AC')
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

  void _showSuccessSheet(String txId) {
    PremiumConfirmationSheet.show(
      context: context,
      title: 'Transaction Successful!',
      subtitle: 'Your giving has been received.',
      message:
          'God bless your faithfulness. Your giving of ${formatKwacha(double.tryParse(_amountController.text) ?? 0)} has been processed securely.',
      referenceId: txId,
      type: ConfirmationType.success,
      primaryLabel: 'AMEN',
    );
  }

  Widget _buildTotalGivenCard(UserProfile? profile) {
    final balanceZmw = profile?.balanceZmw ?? 0.0;
    final balanceCc = profile?.balanceCc ?? 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
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
          const Text("MY GIVING", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatKwacha(balanceZmw), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  const Text("ZMW BALANCE", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${balanceCc.toInt()} CC", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  const Text("REWARDS CC", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text("Material Rewards Active", style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildFeatureTiles(BuildContext context) {
    final features = [
      (LucideIcons.coins, "Fundraising", "Active campaigns", '/fundraising', Colors.orange),
      (LucideIcons.users, "Group Giving", "Give together", '/fundraising/groups', Colors.blue),
      (LucideIcons.scrollText, "My Pledges", "Track promises", '/my-pledges', Colors.purple),
      (LucideIcons.history, "Giving History", "All transactions", '/giving-history', Colors.teal),
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

}
