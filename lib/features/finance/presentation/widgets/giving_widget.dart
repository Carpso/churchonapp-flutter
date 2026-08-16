import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/coa_payment_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'giving_category_selector.dart';

class GivingWidget extends ConsumerStatefulWidget {
  final String? churchName;
  final double? initialAmount;
  final List<String>? categories;
  final bool showStewardshipCard;
  final Widget? header;
  final void Function(String txRef)? onSuccess;
  final VoidCallback? onCancel;

  const GivingWidget({
    super.key,
    this.churchName,
    this.initialAmount,
    this.categories,
    this.showStewardshipCard = true,
    this.header,
    this.onSuccess,
    this.onCancel,
  });

  @override
  ConsumerState<GivingWidget> createState() => _GivingWidgetState();
}

class _GivingWidgetState extends ConsumerState<GivingWidget> {
  late final List<String> _categories;
  late String _selectedCategory;
  late final TextEditingController _amountController;
  bool _isProcessing = false;

  static const _defaultCategories = [
    "Offering",
    "Tithe",
    "Mission",
    "Building Fund",
    "Other",
  ];

  @override
  void initState() {
    super.initState();
    _categories = widget.categories ?? _defaultCategories;
    _selectedCategory = _categories.first;
    _amountController = TextEditingController(
      text: widget.initialAmount?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text) ?? 0.0;
  double get _fee {
    final fees = ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
    return fees.platformFee(_amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final secondary = theme.colorScheme.secondary;
    final profileAsync = ref.watch(profileProvider);
    final tenant = ref.watch(currentTenantProvider);

    return profileAsync.when(
      data: (profile) => _buildScreen(context, theme, primary, secondary, profile, tenant),
      loading: () => Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildScreen(BuildContext context, ThemeData theme, Color primary, Color secondary, UserProfile? profile, Tenant? tenant) {
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.churchName ?? tenant?.name ?? "Giving",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: secondary,
          ),
        ),
        actions: [
          if (widget.onCancel != null)
            IconButton(
              icon: Icon(LucideIcons.x, color: secondary),
              onPressed: widget.onCancel,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            if (widget.header != null) ...[
              widget.header!,
              const SizedBox(height: 30),
            ],
            if (widget.showStewardshipCard)
              _buildStewardshipCard(profile, primary),
            if (widget.showStewardshipCard) const SizedBox(height: 30),
            _buildCategorySelector(primary, secondary),
            const SizedBox(height: 30),
            _buildAmountInput(secondary),
            const SizedBox(height: 40),
            _buildPaymentMethods(primary),
            const SizedBox(height: 40),
            _buildProceedButton(secondary, tenant),
          ],
        ),
      ),
    );
  }

  Widget _buildStewardshipCard(UserProfile? profile, Color primary) {
    final balanceZmw = profile?.balanceZmw ?? 0.0;
    final balanceCc = profile?.balanceCc ?? 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "MY GIVING",
            style: TextStyle(
              color: _readableOn(primary),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "K ${balanceZmw.toInt()}",
                    style: TextStyle(
                      color: _readableOn(primary),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    "ZMW BALANCE",
                    style: TextStyle(
                      color: _readableOn(primary).withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${balanceCc.toInt()} CC",
                    style: TextStyle(
                      color: _readableOn(primary),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    "REWARDS CC",
                    style: TextStyle(
                      color: _readableOn(primary).withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "Material Rewards Active",
            style: TextStyle(
              color: _readableOn(primary).withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector(Color primary, Color secondary) {
    return GivingCategorySelector(
      categories: _categories,
      selectedCategory: _selectedCategory,
      onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
      activeColor: secondary,
    );
  }

  Widget _buildAmountInput(Color secondary) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Enter Amount (K)",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() {}),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: secondary,
            ),
            decoration: const InputDecoration(
              hintText: "0.00",
              prefixText: "K ",
              border: InputBorder.none,
            ),
          ),
          if (_amount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.info, size: 12, color: Theme.of(context).primaryColor),
                const SizedBox(width: 5),
                Text(
                  "+ MoMo Transaction Fee (K${_fee.toStringAsFixed(2)})",
                  style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethods(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Method",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        _PaymentOption(
          icon: LucideIcons.smartphone,
          title: "Mobile Money",
          isSelected: true,
          primary: primary,
          onTap: null,
        ),
        const SizedBox(height: 10),
        _PaymentOption(
          icon: LucideIcons.creditCard,
          title: "Credit/Debit Card",
          isSelected: false,
          primary: primary,
          onTap: _startCardPayment,
        ),
      ],
    );
  }

  Widget _buildProceedButton(Color secondary, Tenant? tenant) {
    return ElevatedButton(
      onPressed: _isProcessing ? null : () => _startPayment(tenant),
      style: ElevatedButton.styleFrom(
        backgroundColor: secondary,
        disabledBackgroundColor: secondary.withValues(alpha: 0.5),
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: _isProcessing
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : const Text(
              "PROCEED TO SECURE PAYMENT",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
    );
  }

  Future<void> _startPayment(Tenant? tenant) async {
    if (_amount <= 0) {
      PremiumToast.showWarning(context, "Please enter a valid amount.");
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => LipilaPaymentGateway(
          amount: _amount,
          description: "Giving: $_selectedCategory",
          category: _selectedCategory.toLowerCase(),
          recipientName: tenant?.name ?? (widget.churchName ?? "Local Church"),
          recipientAccount: _selectedCategory == 'Tithe'
              ? (tenant?.pastorPhone ?? tenant?.treasurerPhone ?? "CHURCH-OFFICIAL-AC")
              : (tenant?.treasurerPhone ?? tenant?.contactPhone ?? "CHURCH-OFFICIAL-AC"),
          paymentReason: _selectedCategory == 'Tithe'
              ? "$_selectedCategory — sent to Pastor"
              : "$_selectedCategory Support",
          onComplete: (success, txId) async {
            Navigator.pop(ctx);
            if (success && txId != null) {
              await ref.read(financeServiceProvider).logTransaction(
                    _amount,
                    _selectedCategory.toLowerCase(),
                    txId,
                    tenantId: tenant?.id,
                    recipientPhone: tenant?.treasurerPhone,
                    recipientName: tenant?.name,
                  );
              if (mounted) {
                _showSuccessSheet(txId);
                widget.onSuccess?.call(txId);
              }
            }
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessSheet(String txId) {
    PremiumConfirmationSheet.show(
      context: context,
      title: "Transaction Successful!",
      subtitle: "Your giving has been received.",
      message: "God bless your faithfulness. Your giving of K${_amountController.text} has been processed securely.",
      referenceId: txId,
      type: ConfirmationType.success,
      primaryLabel: "AMEN",
    );
  }

  Color _readableOn(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  Future<void> _startCardPayment() async {
    if (_amount <= 0) {
      PremiumToast.showWarning(context, "Please enter a valid amount.");
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final res = await Supabase.instance.client.functions.invoke('lipila-card-collect', body: {
        'amount': _amount,
        'narration': 'Giving: $_selectedCategory via Church On App',
        'firstName': 'User',
        'lastName': 'COA',
        'phone': user?.phone ?? '',
        'email': user?.email ?? '',
      });
      final data = res.data as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url != null) {
        final paymentRef = data!['reference'] as String? ?? '';
        await ref.read(coaPaymentServiceProvider).submitPayment(serviceType: _selectedCategory, amount: _amount, paymentRef: paymentRef);
        if (mounted) {
          PremiumToast.showSuccess(context, "Card payment link ready. Complete on Lipila's page.");
        }
      } else {
        throw Exception(data?['error'] ?? 'Card payment failed');
      }
    } catch (e) {
      if (mounted) PremiumToast.showError(context, "Card error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final Color primary;
  final VoidCallback? onTap;

  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.primary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 24),
          const SizedBox(width: 15),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (isSelected)
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 20),
        ],
      ),
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: child);
    return child;
  }
}
