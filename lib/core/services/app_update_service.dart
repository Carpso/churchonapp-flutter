import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the server says about the newest published build.
class ReleaseInfo {
  const ReleaseInfo({
    required this.latestBuild,
    required this.latestVersion,
    required this.minSupportedBuild,
    this.updateMessage,
    this.releaseNotes,
    this.playUrl,
    this.apkUrl,
    this.aabUrl,
  });

  final int latestBuild;
  final String latestVersion;

  /// Installs below this build number are force-updated (non-dismissible).
  final int minSupportedBuild;
  final String? updateMessage;
  final String? releaseNotes;
  final String? playUrl;

  /// Direct APK. This matters more than `playUrl`: most installs today are
  /// sideloaded from R2, where there is no Play listing to open.
  final String? apkUrl;
  final String? aabUrl;

  factory ReleaseInfo.fromMap(Map<String, dynamic> m) => ReleaseInfo(
        // `.num?.toInt()` because PostgREST returns integers, but a bigint
        // column or an implicit cast can hand back a num.
        latestBuild: (m['latest_build'] as num?)?.toInt() ?? 0,
        latestVersion: m['latest_version']?.toString() ?? '',
        minSupportedBuild: (m['min_supported_build'] as num?)?.toInt() ?? 0,
        updateMessage: m['update_message']?.toString(),
        releaseNotes: m['release_notes']?.toString(),
        playUrl: m['play_url']?.toString(),
        apkUrl: m['apk_url']?.toString(),
        aabUrl: m['aab_url']?.toString(),
      );

  /// A hard block: this build cannot keep working against current servers.
  bool isBelowMinimum(int currentBuild) => currentBuild < minSupportedBuild;
}

/// Tells the user a new version exists and takes them to it.
///
/// WHY THIS USED TO DO NOTHING (and how it failed silently)
///   The previous implementation read `app_config` with `.maybeSingle()`. That
///   table holds THREE rows (coin_exchange_rate, trophy_config, version) and
///   `maybeSingle()` asserts at most one — so the query threw PGRST116 on
///   every launch and a bare `catch (_) { return; }` swallowed it. The update
///   prompt could never fire for anybody. Even if it had returned, the only
///   `latest_build` present was 1, which is `<= currentBuild` forever.
///
///   It also opened the store with `LaunchMode.inAppWebView`, which cannot open
///   a `market://` deep link at all — the same class of bug as the SOS `tel:`
///   launch. A user who sideloaded from R2 had no Play listing either, so
///   "Update Now" dead-ended either way.
///
/// BEHAVIOUR NOW
///   * Reads a purpose-built single-row `app_release_config`.
///   * Optional update  -> dismissible "Later".
///   * Below the supported floor -> non-dismissible, cannot be skipped.
///   * Offers BOTH the Play listing and the direct R2 APK, preferring whichever
///     is likely to work, and falls back automatically if one fails to launch.
///   * Throttled, so a resume loop cannot spam the user with dialogs.
///   * Re-checks after returning from the store, so dismissing the Play prompt
///     with "Not now" comes back as a *check*, not a stuck dialog.
class AppUpdateService {
  const AppUpdateService._();

  static const String _lastPromptKey = 'app_update_last_prompt_build';
  static const String _lastPromptAtKey = 'app_update_last_prompt_at';
  static const Duration _throttle = Duration(hours: 6);

  /// Guards against overlapping checks (launch + resume fire close together).
  static bool _inFlight = false;

  /// The release info from the most recent successful check, for diagnostics
  /// and for the "what's new" screen.
  static ReleaseInfo? lastKnown;

  /// Reads the current release config. Returns null when the server is
  /// unreachable — a user must never be blocked by a failed update check.
  static Future<ReleaseInfo?> fetchRelease() async {
    try {
      // `.limit(1)` + `.maybeSingle()`: safe for a singleton row without relying
      // on the table happening to contain exactly one record.
      final res = await Supabase.instance.client
          .from('app_release_config')
          .select(
            'latest_build, latest_version, min_supported_build, '
            'update_message, release_notes, play_url, apk_url, aab_url',
          )
          .limit(1)
          .maybeSingle();

      if (res == null) return null;
      final info = ReleaseInfo.fromMap(Map<String, dynamic>.from(res));
      lastKnown = info;
      return info;
    } catch (e) {
      // Deliberately non-fatal and quiet: no network, no crash, no nagging.
      debugPrint('[AppUpdate] release fetch failed: $e');
      return null;
    }
  }

  /// Checks for an update and prompts if warranted.
  ///
  /// [force] bypasses the throttle (used by the manual "Check for updates"
  /// action, where the user explicitly asked).
  static Future<void> checkForUpdate(
    BuildContext context, {
    bool force = false,
  }) async {
    // Web is updated by the service worker on load; a build-number prompt there
    // would be meaningless and confusing.
    if (kIsWeb) return;
    if (_inFlight) return;

    _inFlight = true;
    try {
      final info = await fetchRelease();
      if (info == null || !context.mounted) return;

      final pkg = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;

      if (info.latestBuild <= currentBuild) return; // up to date

      final blocking = info.isBelowMinimum(currentBuild);

      if (!force && !blocking && !await _shouldPromptAgain(info.latestBuild)) {
        return; // throttled
      }
      if (!context.mounted) return;

      await _prompt(context, info, currentBuild, blocking: blocking);
    } catch (e) {
      debugPrint('[AppUpdate] check failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  static Future<bool> _shouldPromptAgain(int build) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastPromptKey) ?? 0;
      final lastAt = DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_lastPromptAtKey) ?? 0,
      );
      if (last == build && DateTime.now().difference(lastAt) < _throttle) {
        return false;
      }
    } catch (_) {
      return true; // never suppress because of a prefs failure
    }
    return true;
  }

  static Future<void> _markPrompted(int build) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPromptKey, build);
      await prefs.setInt(
          _lastPromptAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {/* non-fatal */}
  }

  static Future<void> _prompt(
    BuildContext context,
    ReleaseInfo info,
    int currentBuild, {
    required bool blocking,
  }) async {
    await _markPrompted(info.latestBuild);
    // The screen can be torn down while the throttle write is in flight.
    if (!context.mounted) return;
    final brand = Theme.of(context).colorScheme.primary;

    final notes = (info.releaseNotes ?? '').trim();

    await showDialog<void>(
      context: context,
      // A blocked build cannot be dismissed: there is no way to "continue"
      // safely, and letting the user past this just produces a broken client.
      barrierDismissible: !blocking,
      builder: (ctx) => PopScope(
        canPop: !blocking,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(blocking ? Icons.error_outline : Icons.system_update,
                  color: blocking ? Colors.red : brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(blocking ? 'Update Required' : 'Update Available'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.updateMessage?.trim().isNotEmpty == true
                      ? info.updateMessage!.trim()
                      : 'A new version of Church On App is available.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Your version $currentBuild · latest ${info.latestVersion} '
                  '(${info.latestBuild})',
                  style: const TextStyle(fontSize: 12),
                ),
                if (blocking) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'This version is no longer supported and must be updated '
                    'to keep working.',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(notes,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ],
              ],
            ),
          ),
          actions: [
            if (!blocking)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Later'),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Update Now'),
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                navigator.pop();
                // Capture the caller's context and re-check `mounted` after the
                // launch await: using `ctx` after the dialog is popped would be
                // a use-across-async-gap on a defunct element.
                await openUpdate(info);
                if (!context.mounted) return;
                // Re-check on return: the user may have cancelled in the store
                // ("Not now"), and they need to be able to try again rather
                // than be met with silence. `force` bypasses the throttle.
                await checkForUpdate(context, force: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the best available update target, falling back automatically.
  ///
  /// Uses `LaunchMode.externalApplication`: an `market://` link (and any
  /// custom scheme) cannot be loaded inside an in-app WebView, so the previous
  /// inAppWebView mode silently did nothing on Android.
  static Future<void> openUpdate(ReleaseInfo info) async {
    final apk = info.apkUrl?.trim();
    final play = info.playUrl?.trim();

    // Direct APK first: sideloaded installs (the majority today) have no Play
    // listing, so a store-first order would dead-end for them.
    if (apk != null && apk.isNotEmpty) {
      final ok = await _launch(Uri.parse(apk));
      if (ok) return;
    }
    if (play != null && play.isNotEmpty) {
      final pkg = 'com.churchonapp.churchonapp';
      // Prefer the native scheme so it opens the installed store app, but fall
      // back to the https URL on devices without it.
      final marketOk = await _launch(Uri.parse('market://details?id=$pkg'));
      if (marketOk) return;
      await _launch(Uri.parse(play));
    }
  }

  static Future<bool> _launch(Uri uri) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AppUpdate] launch failed for $uri: $e');
      return false;
    }
  }

  /// Clears the throttle — used by "Check for updates" in settings so a manual
  /// check always surfaces an available update.
  static Future<void> resetThrottle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastPromptKey);
      await prefs.remove(_lastPromptAtKey);
    } catch (_) {}
  }
}
