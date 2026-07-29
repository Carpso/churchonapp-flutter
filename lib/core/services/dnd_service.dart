import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DndService {
  static const _channel = MethodChannel('com.churchonapp.churchonapp/dnd_helper');

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod('isDndAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod('hasDndPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openDndSettings');
    } catch (e) {
      debugPrint('Error opening DND settings: $e');
    }
  }

  static Future<bool> enable() async {
    try {
      return await _channel.invokeMethod('enableDnd') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> disable() async {
    try {
      return await _channel.invokeMethod('disableDnd') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod('isDndEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens DND settings with a rationale dialog explaining why.
  /// Call from a UI context.
  static Future<bool> requestPermissionWithRationale(BuildContext context) async {
    if (!await isAvailable()) return false;
    if (await hasPermission()) {
      return await enable();
    }

    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do Not Disturb Access'),
        content: const Text(
          'Church On App needs Do Not Disturb (DND) permission to ensure '
          'you receive important notifications — such as incoming prayer '
          'calls and emergency alerts — even when your phone is in DND mode.\n\n'
          'You will be taken to system settings. Please find "Church On App" '
          'in the list and grant permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (proceed != true) return false;

    await openSettings();
    return false; // Permission must be granted manually in settings
  }

  static Future<bool> requestPermissionAndEnable() async {
    if (!await isAvailable()) return false;
    if (!await hasPermission()) {
      await openSettings();
      return false;
    }
    return await enable();
  }

  // ── Usage Access & Automatic App Pull-Back ─────────────────────────────────
  static Future<bool> hasUsagePermission() async {
    try {
      return await _channel.invokeMethod('hasUsagePermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageSettings');
    } catch (e) {
      debugPrint('Error opening usage settings: $e');
    }
  }

  static Future<bool> requestUsagePermissionWithRationale(BuildContext context) async {
    if (await hasUsagePermission()) return true;

    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Usage Access Permission'),
        content: const Text(
          'To detect and redirect you away from blocked apps (such as Instagram, TikTok, or YouTube) '
          'during a Tech Fast, Church On App needs Usage Access permission.\n\n'
          'You will be taken to system settings. Please find "Church On App" and toggle "Allow usage tracking".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await openUsageSettings();
    }
    return false;
  }

  static Future<void> startAppMonitor({List<String>? blockedPackages}) async {
    try {
      await _channel.invokeMethod('startAppMonitor', {
        'blockedPackages': blockedPackages ?? [
          'com.instagram.android',
          'com.zhiliaoapp.musically',
          'com.facebook.katana',
          'com.facebook.orca',
          'com.twitter.android',
          'com.snapchat.android',
          'com.google.android.youtube',
          'com.netflix.mediaclient',
          'com.pinterest',
          'com.linkedin.android'
        ]
      });
    } catch (e) {
      debugPrint('Error starting app monitor: $e');
    }
  }

  static Future<void> stopAppMonitor() async {
    try {
      await _channel.invokeMethod('stopAppMonitor');
    } catch (e) {
      debugPrint('Error stopping app monitor: $e');
    }
  }
}
