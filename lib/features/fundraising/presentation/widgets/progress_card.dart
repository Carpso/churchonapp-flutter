import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FundraisingProgressCard extends StatefulWidget {
  final double raisedAmount;
  final double targetAmount;
  final String currency;
  final int? daysLeft;

  const FundraisingProgressCard({
    super.key,
    required this.raisedAmount,
    required this.targetAmount,
    required this.currency,
    this.daysLeft,
  });

  @override
  State<FundraisingProgressCard> createState() => _FundraisingProgressCardState();
}

class _FundraisingProgressCardState extends State<FundraisingProgressCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  double get _percentage => widget.targetAmount > 0 ? (widget.raisedAmount / widget.targetAmount).clamp(0.0, 1.0) : 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _progressAnimation = Tween<double>(begin: 0, end: _percentage).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        final progress = _progressAnimation.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 10,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Container(
                        width: constraints.maxWidth * progress,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${widget.currency} ${_formatAmount(widget.raisedAmount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'raised of ${widget.currency} ${_formatAmount(widget.targetAmount)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: const Color(0xFFFFB300),
                  ),
                ),
              ],
            ),
            if (widget.daysLeft != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 13, color: widget.daysLeft! <= 3 ? Colors.red.shade400 : Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    widget.daysLeft! <= 0
                        ? 'Ended'
                        : '${widget.daysLeft} ${widget.daysLeft == 1 ? 'day' : 'days'} left',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.daysLeft! <= 3 ? Colors.red.shade400 : Colors.grey.shade500,
                      fontWeight: widget.daysLeft! <= 3 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
