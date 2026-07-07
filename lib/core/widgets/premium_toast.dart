import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum PremiumToastType { success, error, info, warning }

class PremiumToast {
  static final List<OverlayEntry> _activeToasts = [];
  static const double toastWidth = 380;
  static const double toastHeight = 64;
  static const double toastSpacing = 12;

  static void show({
    required BuildContext context,
    required String message,
    String? title,
    PremiumToastType type = PremiumToastType.success,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
  }) {
    final overlay = Overlay.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final index = _activeToasts.length;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (context) => _PremiumToastEntry(
        message: message,
        title: title,
        type: type,
        duration: duration,
        onTap: onTap,
        onDismissed: () {
          entry?.remove();
          _activeToasts.remove(entry);
        },
        isRtl: isRtl,
        index: index,
        toastHeight: toastHeight,
        spacing: toastSpacing,
      ),
    );

    _activeToasts.add(entry);
    overlay.insert(entry);
  }

  static void showSuccess(BuildContext context, String message, {String? title, Duration? duration, VoidCallback? onTap}) {
    show(context: context, message: message, title: title, type: PremiumToastType.success, duration: duration ?? const Duration(seconds: 4), onTap: onTap);
  }

  static void showError(BuildContext context, String message, {String? title, Duration? duration, VoidCallback? onTap}) {
    show(context: context, message: message, title: title, type: PremiumToastType.error, duration: duration ?? const Duration(seconds: 5), onTap: onTap);
  }

  static void showInfo(BuildContext context, String message, {String? title, Duration? duration, VoidCallback? onTap}) {
    show(context: context, message: message, title: title, type: PremiumToastType.info, duration: duration ?? const Duration(seconds: 3), onTap: onTap);
  }

  static void showWarning(BuildContext context, String message, {String? title, Duration? duration, VoidCallback? onTap}) {
    show(context: context, message: message, title: title, type: PremiumToastType.warning, duration: duration ?? const Duration(seconds: 4), onTap: onTap);
  }

  static void dismissAll() {
    for (final entry in _activeToasts) {
      entry.remove();
    }
    _activeToasts.clear();
  }
}

class _PremiumToastEntry extends StatefulWidget {
  final String message;
  final String? title;
  final PremiumToastType type;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;
  final bool isRtl;
  final int index;
  final double toastHeight;
  final double spacing;

  const _PremiumToastEntry({
    required this.message,
    this.title,
    required this.type,
    required this.duration,
    this.onTap,
    required this.onDismissed,
    required this.isRtl,
    required this.index,
    required this.toastHeight,
    required this.spacing,
  });

  @override
  State<_PremiumToastEntry> createState() => _PremiumToastEntryState();
}

class _PremiumToastEntryState extends State<_PremiumToastEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _opacityAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.3, curve: Curves.easeOut),
    ));

    _controller.forward();

    Future.delayed(widget.duration, () {
      if (mounted && !_isDismissing) _dismiss();
    });
  }

  void _dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _controller.reverse().then((_) {
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.type) {
      case PremiumToastType.success: return LucideIcons.checkCircle;
      case PremiumToastType.error: return LucideIcons.alertOctagon;
      case PremiumToastType.info: return LucideIcons.info;
      case PremiumToastType.warning: return LucideIcons.alertTriangle;
    }
  }

  Color _accentColor(BuildContext ctx) {
    switch (widget.type) {
      case PremiumToastType.success: return Theme.of(ctx).primaryColor;
      case PremiumToastType.error: return const Color(0xFFEF4444);
      case PremiumToastType.info: return const Color(0xFF3B82F6);
      case PremiumToastType.warning: return const Color(0xFFF59E0B);
    }
  }

  Color _bgColor(BuildContext ctx) {
    switch (widget.type) {
      case PremiumToastType.success: return const Color(0xFF1C1600);
      case PremiumToastType.error: return const Color(0xFF2D0A0A);
      case PremiumToastType.info: return const Color(0xFF0A1E3D);
      case PremiumToastType.warning: return const Color(0xFF2D1F00);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final verticalOffset = 16.0 + bottomInset + bottomPadding + (widget.index * (widget.toastHeight + widget.spacing));

    return Positioned(
      bottom: verticalOffset,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: _isDismissing,
        child: GestureDetector(
          onTap: () {
            widget.onTap?.call();
            _dismiss();
          },
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.down,
                onDismissed: (_) => widget.onDismissed(),
                child: Center(
                  child: Container(
                    width: PremiumToast.toastWidth,
                    height: PremiumToast.toastHeight,
                    margin: EdgeInsets.only(bottom: widget.index > 0 ? -(PremiumToast.toastHeight * 0.3) : 0),
                    decoration: BoxDecoration(
                      color: _bgColor(context),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _accentColor(context).withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _accentColor(context),
                                    _accentColor(context).withValues(alpha: 0.3),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const SizedBox(width: 20),
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _accentColor(context).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_icon, color: _accentColor(context), size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.title != null) ...[
                                      Text(
                                        widget.title!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                    Text(
                                      widget.message,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontWeight: widget.title != null ? FontWeight.w400 : FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: widget.title != null ? 1 : 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: _dismiss,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Icon(
                                    LucideIcons.x,
                                    color: Colors.white.withValues(alpha: 0.4),
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
