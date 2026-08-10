import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/core/utils/money.dart';

enum PaymentStatus { idle, initiating, awaitingPin, succeeded, failed, cancelled, cardRedirect }

class PaymentStatusOverlay extends StatefulWidget {
  final PaymentStatus status;
  final String statusMessage;
  final String? errorMessage;
  final double amount;
  final String? referenceId;
  final String? recipientName;
  final VoidCallback? onCancel;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;

  const PaymentStatusOverlay({
    super.key,
    required this.status,
    required this.statusMessage,
    this.errorMessage,
    required this.amount,
    this.referenceId,
    this.recipientName,
    this.onCancel,
    this.onContinue,
    this.onRetry,
  });

  @override
  State<PaymentStatusOverlay> createState() => _PaymentStatusOverlayState();
}

class _PaymentStatusOverlayState extends State<PaymentStatusOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.status == PaymentStatus.initiating ||
        widget.status == PaymentStatus.awaitingPin ||
        widget.status == PaymentStatus.cardRedirect) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PaymentStatusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == PaymentStatus.initiating ||
        widget.status == PaymentStatus.awaitingPin ||
        widget.status == PaymentStatus.cardRedirect) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (widget.status) {
      case PaymentStatus.initiating:
      case PaymentStatus.awaitingPin:
      case PaymentStatus.cardRedirect:
        return _buildProcessingState(theme);
      case PaymentStatus.succeeded:
        return _buildSuccessState(theme);
      case PaymentStatus.failed:
        return _buildErrorState(theme);
      case PaymentStatus.cancelled:
      case PaymentStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProcessingState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          Text(
            widget.statusMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            widget.status == PaymentStatus.awaitingPin
                ? 'Please check your phone for the PIN request pop-up.'
                : widget.status == PaymentStatus.cardRedirect
                    ? 'You will be redirected to complete card payment. After payment, return here.'
                    : 'Initializing secure payment channel...',
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12),
            textAlign: TextAlign.center,
          ),
          if (widget.status == PaymentStatus.awaitingPin) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shieldCheck,
                      size: 16, color: theme.colorScheme.warning),
                  const SizedBox(width: 8),
                  Text(
                    'Do NOT share your PIN with anyone',
                    style: TextStyle(
                      color: theme.colorScheme.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 30),
          if (widget.onCancel != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('CANCEL'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.check,
                  color: theme.colorScheme.success, size: 48),
            ),
          ),
          const SizedBox(height: 20),
          Text('Payment Successful!',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            'Your payment of ${formatKwacha(widget.amount)} was processed securely.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                _buildInfoRow(theme, 'Recipient:',
                    widget.recipientName ?? 'Church On App'),
                const SizedBox(height: 8),
                _buildInfoRow(
                  theme,
                  'Reference:',
                  widget.referenceId ?? '',
                  isMonospace: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          if (widget.onContinue != null)
            FilledButton(
              onPressed: widget.onContinue,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              child: const Text('CONTINUE'),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.x,
                color: theme.colorScheme.error, size: 48),
          ),
          const SizedBox(height: 20),
          Text('Payment Failed',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            widget.errorMessage ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13),
          ),
          const SizedBox(height: 30),
          if (widget.onRetry != null)
            FilledButton(
              onPressed: widget.onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: theme.colorScheme.error,
              ),
              child: const Text('TRY AGAIN'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value,
      {bool isMonospace = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12)),
        const SizedBox(width: 15),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isMonospace ? 11 : 12,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
