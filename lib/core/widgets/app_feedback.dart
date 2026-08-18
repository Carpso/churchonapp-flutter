import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Centralized UI feedback widgets: status badges, friendly error views and
/// themed snackbars. Replaces per-screen `Colors.red/green/amber` literals,
/// raw `"Error: $e"` strings and bespoke `SnackBar` styling.

/// Semantic statuses — resolved to `AppColorScheme` colors.
enum AppStatus { success, error, warning, info, neutral }

extension AppStatusColor on AppStatus {
  Color resolve(ColorScheme scheme) => switch (this) {
    AppStatus.success => scheme.success,
    AppStatus.error => scheme.error,
    AppStatus.warning => scheme.warning,
    AppStatus.info => scheme.info,
    AppStatus.neutral => scheme.neutral,
  };
}

/// Small status badge used for order/ride/tithe/quiz statuses.
/// Font size is clamped at [kMinUIFontSize] for accessibility.
class StatusBadge extends StatelessWidget {
  final String label;
  final AppStatus status;
  final IconData? icon;
  final bool filled;

  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = status.resolve(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: kMinUIFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly error view — used in `.when(error:)` branches and catch blocks.
/// Shows a human message, optional retry and a collapsed technical detail.
class AppErrorView extends StatelessWidget {
  final String message;
  final String? technicalDetail;
  final VoidCallback? onRetry;
  final VoidCallback? onContactSupport;
  final IconData icon;

  const AppErrorView({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.technicalDetail,
    this.onRetry,
    this.onContactSupport,
    this.icon = LucideIcons.alertTriangle,
  });

  /// Friendly builder for async `.when(error: ...)` blocks.
  static Widget fromError(
    Object error,
    StackTrace? stack, {
    VoidCallback? onRetry,
    String fallback = 'Something went wrong. Please try again.',
  }) {
    // Log the raw error for crash reporting even when we show friendly copy.
    debugPrint('✗ AppError: $error');
    return AppErrorView(
      message: friendlyMessage(error, fallback),
      technicalDetail: error.toString(),
      onRetry: onRetry,
    );
  }

  /// Maps common exceptions to friendly, user-facing copy.
  static String friendlyMessage(
    Object error, [
    String fallback = 'Something went wrong. Please try again.',
  ]) {
    final s = error.toString().toLowerCase();
    if (s.contains('invalid login credentials') || s.contains('invalid_credentials')) {
      return 'Wrong email or password. Please check and try again.';
    }
    if (s.contains('email not confirmed')) {
      return 'Please confirm your email address first, then sign in.';
    }
    if (s.contains('socketexception') || s.contains('network')) {
      return 'You appear to be offline. Check your connection and try again.';
    }
    if (s.contains('timeout')) {
      return 'The request took too long. Please try again.';
    }
    if (s.contains('not authenticated') || s.contains('no access token')) {
      return 'Please sign in again to continue.';
    }
    if (s.contains('permission')) {
      return 'You do not have permission to do that.';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.error),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            if (technicalDetail != null) ...[
              const SizedBox(height: 6),
              // Show technical detail collapsed & subdued — never as headline.
              Text(
                technicalDetail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.neutral,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (onRetry != null || onContactSupport != null) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Try Again'),
                    ),
                  if (onContactSupport != null)
                    OutlinedButton.icon(
                      onPressed: onContactSupport,
                      icon: const Icon(LucideIcons.lifeBuoy, size: 16),
                      label: const Text('Contact Support'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Themed snackbar helper — replaces `SnackBar(backgroundColor: Colors.red)`
/// and `SnackBar(content: Text('Error: $e'))` call sites.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppStatus status = AppStatus.neutral,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onAction,
  String? actionLabel,
}) {
  final scheme = Theme.of(context).colorScheme;
  final color = status.resolve(scheme);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              switch (status) {
                AppStatus.success => LucideIcons.checkCircle,
                AppStatus.error => LucideIcons.alertCircle,
                AppStatus.warning => LucideIcons.alertTriangle,
                AppStatus.info => LucideIcons.info,
                AppStatus.neutral => LucideIcons.info,
              },
              size: 18,
              color: status == AppStatus.neutral ? Colors.white : color,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: status == AppStatus.neutral
            ? scheme.secondary
            : color.withValues(alpha: 0.95),
        duration: duration,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
}
