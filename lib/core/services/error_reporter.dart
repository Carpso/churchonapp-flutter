import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-app error reporting to the `app_error_reports` table so the COA team
/// can triage and respond without relying on external crash dashboards.
/// Complements (not replaces) Firebase Crashlytics.
class ErrorReporter {
  ErrorReporter._();

  static final ErrorReporter instance = ErrorReporter._();

  bool _hooked = false;

  /// Dedupe: same message + screen is reported at most once per 10 minutes.
  static const Duration _throttleWindow = Duration(minutes: 10);
  final Map<String, DateTime> _throttle = {};

  String _appVersion = 'unknown';
  String _deviceInfo = 'unknown';

  /// Populates app version + device info. Call once at startup (non-blocking).
  Future<void> init() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (kIsWeb) {
        _deviceInfo = 'web';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final d = info as AndroidDeviceInfo;
        _deviceInfo = '${d.brand} ${d.model} · Android ${d.version.release}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final d = info as IosDeviceInfo;
        _deviceInfo = 'iOS · ${d.systemVersion}';
      } else {
        _deviceInfo = defaultTargetPlatform.name;
      }
    } catch (_) {
      _deviceInfo = defaultTargetPlatform.name;
    }
  }

  /// Installs global Flutter + platform error handlers. Safe to call once.
  void attachGlobal() {
    if (_hooked) return;
    _hooked = true;

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousFlutter?.call(details);
      unawaited(report(
        error: details.exception,
        stack: details.stack,
        screen: 'framework',
      ));
    };

    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = previousPlatform == null
          ? false
          : previousPlatform(error, stack);
      unawaited(report(error: error, stack: stack, screen: 'platform'));
      return handled;
    };
  }

  /// Reports an error to Supabase. Fire-and-forget; never throws.
  Future<void> report({
    required Object error,
    StackTrace? stack,
    String? screen,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    final message = error.toString();
    final key = '${screen ?? ''}|$message';
    final last = _throttle[key];
    if (last != null && DateTime.now().difference(last) < _throttleWindow) {
      return;
    }
    _throttle[key] = DateTime.now();

    try {
      await client.from('app_error_reports').insert({
        'user_id': user?.id,
        'screen': screen,
        'error_message': message.length > 4000 ? message.substring(0, 4000) : message,
        'stack_trace': _truncate(stack?.toString(), 8000),
        'app_version': _appVersion,
        'device_info': _deviceInfo,
      });
    } catch (e) {
      debugPrint('ErrorReporter: failed to persist report: $e');
    }
  }

  String? _truncate(String? value, int max) {
    if (value == null) return null;
    return value.length > max ? value.substring(0, max) : value;
  }
}

final errorReporterProvider = Provider((ref) => ErrorReporter.instance);
