import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  static Future<void> checkForUpdate(BuildContext context, {bool isInForeground = false}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      int latestBuild = 0;
      bool forceUpdate = false;
      String message = 'A new version is available. Please update to continue.';

      try {
        final response = await Supabase.instance.client
            .from('app_config')
            .select('latest_build, update_message, force_update')
            .maybeSingle();
        if (response != null) {
          latestBuild = response['latest_build'] as int? ?? currentBuild;
          message = response['update_message'] as String? ?? message;
          forceUpdate = response['force_update'] as bool? ?? false;
        }
      } catch (_) {
        return;
      }

      if (latestBuild <= currentBuild) return;
      if (!context.mounted) return;

      final pkg = info.packageName;
      if (forceUpdate) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Update Required'),
            content: Text(message),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openPlayStore(pkg);
                  checkForUpdate(context, isInForeground: true);
                },
                child: const Text('Update Now'),
              ),
            ],
          ),
        );
      } else {
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Update Available'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openPlayStore(pkg);
                },
                child: const Text('Update Now'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdate] check failed: $e');
    }
  }

  static Future<void> _openPlayStore(String packageName) async {
    final uri = Uri.parse('market://details?id=$packageName');
    final fallbackUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    } else if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.inAppWebView);
    }
  }
}
