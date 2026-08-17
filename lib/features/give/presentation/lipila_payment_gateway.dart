import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/analytics_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/finance/data/payment_state.dart';
import 'package:church_on_app/features/give/presentation/widgets/momo_phone_input_widget.dart';
import 'package:church_on_app/features/give/presentation/widgets/payment_status_overlay.dart';
import 'package:church_on_app/core/config/fee_config.dart';
import 'package:church_on_app/core/services/currency_service.dart';
import 'package:church_on_app/core/utils/money.dart';

enum _PayMethod { mobileMoney, card }

class LipilaPaymentGateway extends ConsumerStatefulWidget {
  final double amount;
  final String description;
  final String category;
  final String? recipientName;
  final String? recipientAccount;
  final String? paymentReason;
  final Function(bool success, String? transactionId) onComplete;

  const LipilaPaymentGateway({
    super.key,
    required this.amount,
    required this.description,
    this.category = 'giving',
    this.recipientName,
    this.recipientAccount,
    this.paymentReason,
    required this.onComplete,
  });

  @override
  ConsumerState<LipilaPaymentGateway> createState() =>
      _LipilaPaymentGatewayState();
}

class _LipilaPaymentGatewayState extends ConsumerState<LipilaPaymentGateway> {
  String _selectedNetwork = 'MTN';
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _errorMessage;
  _PayMethod _method = _PayMethod.mobileMoney;

  FeeConfig get _fees =>
      ref.read(feeConfigProvider).value ?? FeeConfig.defaults;
  bool get _isCard => _method == _PayMethod.card;
  double get _platformFee => _fees.platformFee(widget.amount, isCard: _isCard);
  double get _totalCharged => widget.amount + _platformFee;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileValue = ref.read(profileProvider).value;
      if (profileValue != null) {
        final phone = profileValue.phoneNumber;
        if (phone != null && phone.isNotEmpty) {
          _phoneCtrl.text = phone;
        }
        _firstNameCtrl.text = profileValue.name.split(' ').first;
        _lastNameCtrl.text = profileValue.name.split(' ').skip(1).join(' ');
        final user = Supabase.instance.client.auth.currentUser;
        _emailCtrl.text = user?.email ?? '';
      }
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _initiatePayment() {
    if (_method == _PayMethod.mobileMoney) {
      _initiateMomoPayment();
    } else {
      _initiateCardPayment();
    }
  }

  void _initiateMomoPayment() {
    final phoneError = MomoPhoneInputWidget.validateZambianPhone(
      _phoneCtrl.text,
    );
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }
    setState(() => _errorMessage = null);
    ref.read(analyticsServiceProvider).logEvent(
          'payment_initiated',
          properties: {
            'method': 'momo',
            'amount': widget.amount,
            'reason': widget.paymentReason,
          },
          tenantId: ref.read(currentTenantProvider)?.id,
        );
    ref
        .read(lipilaPaymentProvider.notifier)
        .initiatePayment(
          phone: _phoneCtrl.text,
          amount: _totalCharged,
          description: widget.description,
          narration: widget.paymentReason,
        );
  }

  Future<void> _initiateCardPayment() async {
    if (_firstNameCtrl.text.isEmpty || _lastNameCtrl.text.isEmpty) {
      setState(() => _errorMessage = 'First and last name are required');
      return;
    }
    setState(() => _errorMessage = null);
    ref.read(analyticsServiceProvider).logEvent(
          'payment_initiated',
          properties: {
            'method': 'card',
            'amount': widget.amount,
            'reason': widget.paymentReason,
          },
          tenantId: ref.read(currentTenantProvider)?.id,
        );
    ref
        .read(lipilaPaymentProvider.notifier)
        .initiateCardPayment(
          amount: _totalCharged,
          description: widget.description,
          narration: widget.paymentReason,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.isNotEmpty ? _phoneCtrl.text : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenant = ref.watch(currentTenantProvider);
    final paymentAsync = ref.watch(lipilaPaymentProvider);
    final paymentState = paymentAsync.value ?? const LipilaPaymentState();
    final displayRecipient =
        widget.recipientName ?? tenant?.name ?? 'Church On App';
    final displayAccount =
        widget.recipientAccount ??
        tenant?.treasurerPhone ??
        'Merchant ID: 68907';
    final isProcessing =
        paymentState.status == PaymentStatus.initiating ||
        paymentState.status == PaymentStatus.awaitingPin ||
        paymentState.status == PaymentStatus.cardRedirect;

    ref.listen<AsyncValue<LipilaPaymentState>>(lipilaPaymentProvider, (
      prev,
      next,
    ) {
      final data = next.value;
      if (data == null) return;
      if (data.status == PaymentStatus.succeeded) {
        ref.read(analyticsServiceProvider).logEvent(
              'payment_succeeded',
              properties: {
                'amount': widget.amount,
                'reference': data.referenceId,
                'reason': widget.paymentReason,
              },
              tenantId: ref.read(currentTenantProvider)?.id,
            );
        widget.onComplete(true, data.referenceId);
      } else if (data.status == PaymentStatus.cancelled) {
        widget.onComplete(false, null);
      } else if (data.status == PaymentStatus.cardRedirect &&
          data.cardUrl != null) {
        _launchCardUrl(data.cardUrl!);
      }
    });

    return PopScope(
      canPop: !isProcessing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showCancelConfirmationDialog(theme);
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 25,
            right: 25,
            top: 30,
            bottom: MediaQuery.of(context).viewInsets.bottom + 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Secure Settlement', style: theme.textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () {
                      if (isProcessing) {
                        _showCancelConfirmationDialog(theme);
                      } else {
                        ref.read(lipilaPaymentProvider.notifier).reset();
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (paymentState.status == PaymentStatus.succeeded)
                PaymentStatusOverlay(
                  status: paymentState.status,
                  statusMessage: paymentState.statusMessage,
                  amount: widget.amount,
                  referenceId: paymentState.referenceId,
                  recipientName: displayRecipient,
                  onContinue: () {
                    ref.read(lipilaPaymentProvider.notifier).reset();
                    widget.onComplete(true, paymentState.referenceId);
                  },
                )
              else if (paymentState.status == PaymentStatus.failed)
                PaymentStatusOverlay(
                  status: paymentState.status,
                  statusMessage: paymentState.statusMessage,
                  errorMessage: paymentState.errorMessage,
                  amount: widget.amount,
                  onRetry: () {
                    ref.read(lipilaPaymentProvider.notifier).reset();
                    _initiatePayment();
                  },
                )
              else if (paymentState.status == PaymentStatus.cancelled)
                PaymentStatusOverlay(
                  status: paymentState.status,
                  statusMessage: paymentState.statusMessage,
                  amount: widget.amount,
                  onRetry: () {
                    ref.read(lipilaPaymentProvider.notifier).reset();
                  },
                )
              else if (isProcessing)
                PaymentStatusOverlay(
                  status: paymentState.status,
                  statusMessage: paymentState.statusMessage,
                  amount: widget.amount,
                  onCancel: () =>
                      ref.read(lipilaPaymentProvider.notifier).cancel(),
                )
              else ...[
                _buildRecipientCard(theme, displayRecipient, displayAccount),
                const SizedBox(height: 20),
                _buildMethodToggle(theme),
                const SizedBox(height: 20),
                if (_method == _PayMethod.mobileMoney)
                  MomoPhoneInputWidget(
                    controller: _phoneCtrl,
                    selectedNetwork: _selectedNetwork,
                    onNetworkChanged: (n) =>
                        setState(() => _selectedNetwork = n),
                    error: _errorMessage,
                  ),
                if (_method == _PayMethod.card) _buildCardFields(theme),
                const SizedBox(height: 20),
                _buildFeePreview(theme),
                const SizedBox(height: 25),
                FilledButton(
                  onPressed: isProcessing ? null : _initiatePayment,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: Text(
                    _isCard ? 'Pay with Card' : 'Proceed to PIN Prompt',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Regulated by Bank of Zambia via Lipila',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodToggle(ThemeData theme) {
    return SegmentedButton<_PayMethod>(
      segments: const [
        ButtonSegment(
          value: _PayMethod.mobileMoney,
          icon: Icon(LucideIcons.smartphone, size: 18),
          label: Text('Mobile Money'),
        ),
        ButtonSegment(
          value: _PayMethod.card,
          icon: Icon(LucideIcons.creditCard, size: 18),
          label: Text('Card'),
        ),
      ],
      selected: {_method},
      onSelectionChanged: (s) => setState(() => _method = s.first),
    );
  }

  Widget _buildFeePreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                formatKwacha(widget.amount),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '≈ USD',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              ref
                  .watch(zmwPerUsdProvider)
                  .when(
                    data: (rate) => Text(
                      '\$${(widget.amount / rate).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    loading: () => const Text(
                      '…',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    error: (_, __) => const Text(
                      'USD n/a',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
            ],
          ),
          if (widget.category == 'giving' ||
              widget.category == 'donation' ||
              widget.category == 'tithe' ||
              widget.category == 'offering' ||
              widget.category == 'event' ||
              widget.category == 'top_up') ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fees.platformFeeLabel(isCard: _method == _PayMethod.card),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                Text(
                  '+${formatKwacha(_platformFee)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                formatKwacha(_totalCharged),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardFields(ThemeData theme) {
    return Column(
      children: [
        TextField(
          controller: _firstNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First Name',
            prefixIcon: Icon(LucideIcons.user, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastNameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Last Name',
            prefixIcon: Icon(LucideIcons.user, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            prefixIcon: Icon(LucideIcons.mail, size: 20),
          ),
        ),
        if (_errorMessage != null && _errorMessage!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  color: theme.colorScheme.error,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecipientCard(
    ThemeData theme,
    String displayRecipient,
    String displayAccount,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow(theme, 'Paying To:', displayRecipient, isTitle: true),
          const SizedBox(height: 8),
          _buildInfoRow(theme, 'Settlement A/C:', displayAccount),
          const SizedBox(height: 8),
          _buildInfoRow(
            theme,
            'Reference:',
            widget.paymentReason ?? widget.description,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value, {
    bool isTitle = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: isTitle ? FontWeight.w900 : FontWeight.bold,
              fontSize: isTitle ? 14 : 12,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchCardUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  void _showCancelConfirmationDialog(ThemeData theme) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.orange),
            SizedBox(width: 10),
            Text('Transaction Active'),
          ],
        ),
        content: const Text(
          'Your payment is currently active. '
          'Leaving or closing now may disrupt settlement verification.\n\n'
          'Are you sure you want to cancel this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CONTINUE TRANSACTION'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(lipilaPaymentProvider.notifier).cancel();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('ABORT TRANSACTION'),
          ),
        ],
      ),
    );
  }
}
