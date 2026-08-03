import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_models.dart';
import 'package:church_on_app/features/fundraising/data/fundraising_providers.dart';
import 'package:church_on_app/core/providers/auth_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/widgets/premium_toast.dart';
import 'widgets/progress_card.dart';

class ContributeScreen extends ConsumerStatefulWidget {
  final String ventureId;

  const ContributeScreen({super.key, required this.ventureId});

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> with SingleTickerProviderStateMixin {
  final _customAmountController = TextEditingController();
  final _messageController = TextEditingController();

  double? _selectedAmount;
  bool _isCustomAmount = false;
  bool _isAnonymous = false;
  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _loadError = false;
  String? _paymentMethod;

  late AnimationController _successController;
  late Animation<double> _successAnimation;
  FundraisingVenture? _venture;

  final List<double> _presetAmounts = [50, 100, 200, 500, 1000];
  final List<String> _paymentMethods = ['Mobile Money', 'Church Wallet'];

  @override
  void initState() {
    super.initState();
    _loadVenture();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _successAnimation = CurvedAnimation(parent: _successController, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    _messageController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _loadVenture() async {
    try {
      final v = await ref.read(fundraisingServiceProvider).getVenture(widget.ventureId);
      if (mounted) setState(() => _venture = v);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venture = _venture;
    if (_loadError) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Contribute')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Failed to load venture', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _loadError = false);
                  _loadVenture();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (venture == null) {
      return Scaffold(body: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: const Center(child: CircularProgressIndicator()),
      ));
    }

    if (_isSuccess) return _buildSuccessScreen(theme);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Contribute'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVentureSummary(venture, theme),
            const SizedBox(height: 24),
            _buildSectionTitle('Select Amount'),
            const SizedBox(height: 12),
            _buildAmountChips(theme),
            if (_isCustomAmount) ...[
              const SizedBox(height: 12),
              _buildCustomAmountInput(theme),
            ],
            const SizedBox(height: 24),
            _buildSectionTitle('Contribution Options'),
            const SizedBox(height: 12),
            _buildOptions(theme),
            const SizedBox(height: 20),
            _buildSectionTitle('Message (Optional)'),
            const SizedBox(height: 8),
            _buildMessageField(theme),
            const SizedBox(height: 24),
            _buildSectionTitle('Payment Method'),
            const SizedBox(height: 8),
            _buildPaymentMethodSelector(theme),
            const SizedBox(height: 32),
            _buildContributeButton(theme),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildVentureSummary(FundraisingVenture venture, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(venture.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.secondary)),
          const SizedBox(height: 12),
          FundraisingProgressCard(
            raisedAmount: venture.raisedAmount,
            targetAmount: venture.targetAmount,
            currency: venture.currency,
            daysLeft: venture.daysLeft,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
    );
  }

  Widget _buildAmountChips(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ..._presetAmounts.map((amount) => _buildAmountChip(amount, theme)),
        _buildAmountChip(null, theme, isCustom: true),
      ],
    );
  }

  Widget _buildAmountChip(double? amount, ThemeData theme, {bool isCustom = false}) {
    final isSelected = isCustom ? _isCustomAmount : _selectedAmount == amount;
    final label = isCustom ? 'Custom' : '${_venture!.currency} ${amount!.toInt()}';

    return GestureDetector(
      onTap: () {
        setState(() {
          _isCustomAmount = isCustom;
          if (!isCustom) {
            _selectedAmount = amount;
            _customAmountController.clear();
          } else {
            _selectedAmount = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFB300) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFB300) : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isSelected ? Colors.white : theme.colorScheme.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAmountInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.3)),
      ),
      child: TextFormField(
        controller: _customAmountController,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          prefixText: '${_venture!.currency} ',
          prefixStyle: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
          hintText: '0.00',
          hintStyle: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.normal),
          border: InputBorder.none,
        ),
        onChanged: (v) {
          final amount = double.tryParse(v);
          if (amount != null && amount > 0) {
            setState(() => _selectedAmount = amount);
          } else {
            setState(() => _selectedAmount = null);
          }
        },
      ),
    );
  }

  Widget _buildOptions(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _isAnonymous,
            onChanged: (v) => setState(() => _isAnonymous = v),
            title: Row(
              children: [
                Icon(_isAnonymous ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: const Color(0xFFFFB300)),
                const SizedBox(width: 10),
                Text(_isAnonymous ? 'Contribute Anonymously' : 'Show my name',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
            activeThumbColor: const Color(0xFFFFB300),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField(ThemeData theme) {
    return TextFormField(
      controller: _messageController,
      maxLines: 3,
      maxLength: 200,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Add a prayer or blessing...',
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildPaymentMethodSelector(ThemeData theme) {
    return Column(
      children: _paymentMethods.map((method) {
        final isSelected = _paymentMethod == method;
        return GestureDetector(
          onTap: () => setState(() => _paymentMethod = method),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFFFFB300) : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  method == 'Mobile Money' ? LucideIcons.smartphone : LucideIcons.wallet,
                  color: const Color(0xFFFFB300),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Text(method, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                if (isSelected)
                  const Icon(LucideIcons.checkCircle, color: Color(0xFFFFB300), size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContributeButton(ThemeData theme) {
    final amount = _isCustomAmount
        ? double.tryParse(_customAmountController.text) ?? _selectedAmount
        : _selectedAmount;
    final isValid = amount != null && amount > 0 && _paymentMethod != null;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isValid && !_isProcessing ? () => _processContribution(amount) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFB300),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                isValid
                    ? 'Contribute ${_venture!.currency} ${amount.toStringAsFixed(0)}'
                    : 'Enter an amount',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      ),
    );
  }

  Widget _buildSuccessScreen(ThemeData theme) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Contribution Sent'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => _smartBack(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _successAnimation,
                builder: (context, child) => Transform.scale(
                  scale: _successAnimation.value,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.checkCircle, color: Color(0xFF10B981), size: 50),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Thank You!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Your contribution has been received.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Text(
                '${_venture!.currency} ${(_selectedAmount ?? 0).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)),
              ),
              const SizedBox(height: 8),
              Text(
                'to ${_venture!.title}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    SharePlus.instance.share(ShareParams(
                      text: 'I just contributed ${_venture!.currency} ${(_selectedAmount ?? 0).toStringAsFixed(0)} to ${_venture!.title}! Support this cause too: https://churchonapp.com/fundraising/${_venture!.id}',
                      subject: 'Support ${_venture!.title}',
                    ));
                  },
                  icon: const Icon(LucideIcons.share2),
                  label: const Text('Share with Friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _smartBack(),
                child: const Text('Back to Fundraising', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processContribution(double amount) async {
    setState(() => _isProcessing = true);
    try {
      final authState = ref.read(authProvider);
      final tenant = ref.read(currentTenantProvider);
      await ref.read(fundraisingServiceProvider).contribute(
        ventureId: _venture!.id,
        tenantId: tenant?.id ?? '',
        contributorId: authState.user?.id ?? '',
        contributorName: authState.user?.email,
        tenantName: tenant?.name,
        amount: amount,
        isAnonymous: _isAnonymous,
        message: _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
      );
      if (mounted) {
        ref.invalidate(contributionsProvider(widget.ventureId));
        ref.invalidate(ventureDetailProvider(widget.ventureId));
        setState(() => _isProcessing = false);
        _successController.forward();
        setState(() => _isSuccess = true);
        PremiumToast.showSuccess(context, 'Contribution successful!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        PremiumToast.showError(context, 'Contribution failed: ${e.toString()}');
      }
    }
  }

  void _smartBack() {
    if (context.canPop()) {
      Navigator.pop(context);
    } else {
      context.go('/');
    }
  }
}
