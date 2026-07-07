import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:church_on_app/core/widgets/premium_confirmation_sheet.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'package:church_on_app/features/finance/presentation/lipila_payment_gateway.dart';

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
    "Tithe",
    "Offering",
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
  double get _fee => _amount * 0.05 > 3.00 ? _amount * 0.05 : 3.00;

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
          widget.churchName ?? tenant?.name ?? "Kingdom Giving",
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
            const SizedBox(height: 15),
            _buildQrOption(tenant),
            const SizedBox(height: 10),
            _buildOfflineKeyOption(secondary),
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
            "STEWARDSHIP REWARDS",
            style: TextStyle(
              color: _readableOn(primary),
              fontSize: 10,
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
                      fontSize: 9,
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
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "Sovereign Material Rewards Active",
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
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == _categories[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = _categories[index]),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? secondary : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: Text(
                  _categories[index],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
                const Icon(LucideIcons.info, size: 12, color: Colors.blue),
                const SizedBox(width: 5),
                Text(
                  "+ MoMo Transaction Fee (K${_fee.toStringAsFixed(2)})",
                  style: const TextStyle(color: Colors.blue, fontSize: 10),
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
        ),
        const SizedBox(height: 10),
        _PaymentOption(
          icon: LucideIcons.wallet,
          title: "Church Wallet",
          isSelected: false,
          primary: primary,
        ),
        const SizedBox(height: 10),
        _PaymentOption(
          icon: LucideIcons.creditCard,
          title: "Credit/Debit Card",
          isSelected: false,
          primary: primary,
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

  Widget _buildQrOption(Tenant? tenant) {
    return TextButton(
      onPressed: _amount <= 0
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _QrPaymentScreen(
                    amount: _amount,
                    description: "Giving: $_selectedCategory",
                    recipient:
                        tenant?.name ?? (widget.churchName ?? "Kingdom Local Church"),
                  ),
                ),
              );
            },
      child: const Text(
        "Pay via Kingdom QR Code",
        style: TextStyle(
          color: Colors.amber,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildOfflineKeyOption(Color secondary) {
    return TextButton(
      onPressed: _amount <= 0
          ? null
          : () => _showGivingKey(secondary),
      child: const Text(
        "Generate Offline Giving Key",
        style: TextStyle(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 12,
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
          amount: _amount + _fee,
          description: "Kingdom Giving: $_selectedCategory",
          category: _selectedCategory.toLowerCase(),
          recipientName: tenant?.name ?? (widget.churchName ?? "Local Church"),
          recipientAccount: tenant?.treasurerPhone ?? "CHURCH-OFFICIAL-AC",
          paymentReason: "$_selectedCategory Support",
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
      subtitle: "Your seed has been received.",
      message: "God bless your faithfulness. Your giving of K${_amountController.text} has been processed securely.",
      referenceId: txId,
      type: ConfirmationType.success,
      primaryLabel: "AMEN",
    );
  }

  void _showGivingKey(Color secondary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          "OFFICIAL GIVING KEY",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Present this at any verified COA hub or use in USSD checkout.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                "COA-GIVE-8822-XP",
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 25),
            const Icon(LucideIcons.qrCode, color: Colors.white, size: 100),
            const SizedBox(height: 20),
            Text(
              "Amount: K${_amountController.text}",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                "DONE",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Color _readableOn(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final Color primary;

  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}

class _QrPaymentScreen extends StatelessWidget {
  final double amount;
  final String description;
  final String recipient;

  const _QrPaymentScreen({
    required this.amount,
    required this.description,
    required this.recipient,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QR Payment")),
      body: Center(
        child: Text(
          "QR Payment of K$amount for $description to $recipient",
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}