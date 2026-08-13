import 'package:flutter/widgets.dart';

/// Breakpoint + layout helpers for adaptive web/mobile layouts.
///
/// Mobile-first: phone (<600), tablet (600–1024), desktop (>=1024).
abstract final class Responsive {
  static const double compact = 600;
  static const double medium = 1024;

  /// Cap for page content so desktop screens don't stretch full-bleed.
  static const double maxContentWidth = 1200;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  /// Centres [child] and caps its width to [maxWidth] so wide screens keep
  /// readable line lengths instead of stretching full-bleed.
  static Widget wrap(
    Widget child, {
    double maxWidth = maxContentWidth,
    EdgeInsetsGeometry? padding,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding == null ? child : Padding(padding: padding, child: child),
      ),
    );
  }

  /// Horizontal page padding that grows with the viewport:
  /// 20 on phones, 28 on tablets, ~(w - maxWidth)/2 + 24 (clamped 24–96) on
  /// laptops so content visually centres within [maxWidth].
  static double hPadding(
    BuildContext context, {
    double maxWidth = maxContentWidth,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < compact) return 20;
    if (w < medium) return 28;
    final grown = (w - maxWidth) / 2 + 24;
    return grown.clamp(24.0, 96.0).toDouble();
  }

  /// Responsive display font size (used for hero/section headlines).
  static double displayFont(
    BuildContext context,
    double desktop, {
    double? tablet,
    double? phone,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < compact) return phone ?? desktop * 0.5;
    if (w < medium) return tablet ?? desktop * 0.75;
    return desktop;
  }
}