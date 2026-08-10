import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppErrorView extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final String? title;

  const AppErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.title,
  });

  static String friendlyMessage(dynamic error) {
    if (error is AuthException) {
      if (error.message.contains('Invalid login credentials')) {
        return "Incorrect email or password. Please try again.";
      }
      return error.message;
    }
    if (error.toString().contains('SocketException')) {
      return "No internet connection. Please check your network.";
    }
    if (error.toString().contains('PostgrestException')) {
      return "We encountered a database error. Please try again later.";
    }
    return "Something went wrong. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = friendlyMessage(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.alertCircle, color: scheme.error, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              title ?? "Oops!",
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text("TRY AGAIN"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size(180, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                "GO BACK",
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showAppSnackBar(BuildContext context, String message, {AppStatus status = AppStatus.info}) {
  final scheme = Theme.of(context).colorScheme;
  Color bgColor;
  IconData icon;

  switch (status) {
    case AppStatus.success:
      bgColor = const Color(0xFF059669);
      icon = LucideIcons.checkCircle2;
      break;
    case AppStatus.error:
      bgColor = scheme.error;
      icon = LucideIcons.alertCircle;
      break;
    case AppStatus.warning:
      bgColor = const Color(0xFFD97706);
      icon = LucideIcons.alertTriangle;
      break;
    case AppStatus.info:
      bgColor = scheme.onSurface;
      icon = LucideIcons.info;
      break;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}

enum AppStatus { success, error, warning, info }
