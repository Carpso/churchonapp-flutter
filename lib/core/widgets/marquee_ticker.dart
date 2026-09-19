import 'package:flutter/material.dart';

/// A continuous, seamless horizontal marquee. Reusable for the live-stream
/// news ticker (viewer + projector/big-screen mode).
class MarqueeTicker extends StatefulWidget {
  final List<String> items;
  final double pixelsPerSecond;
  final TextStyle style;
  final double height;
  final Color background;
  final EdgeInsetsGeometry padding;

  const MarqueeTicker({
    super.key,
    required this.items,
    this.pixelsPerSecond = 40,
    this.style = const TextStyle(color: Colors.white, fontSize: 12),
    this.height = 28,
    this.background = const Color(0xFF0E0E0E),
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  @override
  State<MarqueeTicker> createState() => _MarqueeTickerState();
}

class _MarqueeTickerState extends State<MarqueeTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _measuredWidth = 0;

  String get _text =>
      widget.items.map((e) => e.trim()).where((e) => e.isNotEmpty).join('     •     ');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureAnimating(double width) {
    if (width <= 0 || (width - _measuredWidth).abs() < 1) return;
    _measuredWidth = width;
    final ms = (width / widget.pixelsPerSecond.clamp(5, 400) * 1000).round();
    _controller.duration = Duration(milliseconds: ms.clamp(1500, 180000));
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    if (_text.isEmpty) return const SizedBox.shrink();
    final full = '$_text     •     ';

    return Container(
      height: widget.height,
      color: widget.background,
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: full, style: widget.style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ensureAnimating(painter.width);
          });

          return ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(-_controller.value * painter.width, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(full, style: widget.style, maxLines: 1),
                    Text(full, style: widget.style, maxLines: 1),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
