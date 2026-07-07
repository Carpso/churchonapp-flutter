import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

enum ConfirmationType { success, error, info, warning }

class PremiumConfirmationSheet {
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    String? referenceId,
    String? subtitle,
    ConfirmationType type = ConfirmationType.success,
    String primaryLabel = 'Continue',
    String? secondaryLabel,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PremiumConfirmationContent(
        title: title,
        message: message,
        referenceId: referenceId,
        subtitle: subtitle,
        type: type,
        primaryLabel: primaryLabel,
        secondaryLabel: secondaryLabel,
        onPrimary: onPrimary,
        onSecondary: onSecondary,
      ),
    );
  }
}

class _PremiumConfirmationContent extends StatefulWidget {
  final String title;
  final String message;
  final String? referenceId;
  final String? subtitle;
  final ConfirmationType type;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  const _PremiumConfirmationContent({
    required this.title,
    required this.message,
    this.referenceId,
    this.subtitle,
    required this.type,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
  });

  @override
  State<_PremiumConfirmationContent> createState() => _PremiumConfirmationContentState();
}

class _PremiumConfirmationContentState extends State<_PremiumConfirmationContent> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.5, curve: Curves.elasticOut),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext ctx) {
    switch (widget.type) {
      case ConfirmationType.success: return Theme.of(ctx).primaryColor;
      case ConfirmationType.error: return const Color(0xFFEF4444);
      case ConfirmationType.info: return const Color(0xFF3B82F6);
      case ConfirmationType.warning: return const Color(0xFFF59E0B);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ConfirmationType.success: return LucideIcons.checkCircle;
      case ConfirmationType.error: return LucideIcons.alertOctagon;
      case ConfirmationType.info: return LucideIcons.info;
      case ConfirmationType.warning: return LucideIcons.alertTriangle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: EdgeInsets.only(
        left: 28,
        right: 28,
        top: 40,
        bottom: MediaQuery.of(context).viewPadding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 32),
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accentColor(context).withValues(alpha: 0.3),
                    _accentColor(context).withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentColor(context).withValues(alpha: 0.15),
                    border: Border.all(
                      color: _accentColor(context).withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(_icon, color: _accentColor(context), size: 40),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _accentColor(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (widget.referenceId != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.receipt, color: Colors.white.withValues(alpha: 0.4), size: 14),
                        const SizedBox(width: 10),
                        Text(
                          'REF: ${widget.referenceId}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onPrimary?.call();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor(context),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      widget.primaryLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (widget.secondaryLabel != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () {
                        widget.onSecondary?.call();
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        widget.secondaryLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
