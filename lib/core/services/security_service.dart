import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:universal_io/io.dart' show Platform;

class SecurityService {
  final SupabaseClient _client;

  SecurityService(this._client);

  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);
  static const String _failedAttemptsKey = 'failed_login_attempts';
  static const String _lockoutUntilKey = 'lockout_until';

  Future<bool> isLockedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getString(_lockoutUntilKey);
    if (lockoutUntil == null) return false;
    final lockoutTime = DateTime.tryParse(lockoutUntil);
    if (lockoutTime == null) return false;
    if (DateTime.now().isAfter(lockoutTime)) {
      await prefs.remove(_lockoutUntilKey);
      await prefs.remove(_failedAttemptsKey);
      return false;
    }
    return true;
  }

  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failedAttemptsKey) ?? 0;
  }

  Future<void> recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_failedAttemptsKey) ?? 0;
    final newCount = current + 1;
    await prefs.setInt(_failedAttemptsKey, newCount);

    if (newCount >= maxFailedAttempts) {
      final lockoutUntil = DateTime.now().add(lockoutDuration).toIso8601String();
      await prefs.setString(_lockoutUntilKey, lockoutUntil);
      debugPrint('SecurityService: Account locked for $lockoutDuration after $newCount failed attempts');
    }
  }

  Future<void> clearFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockoutUntilKey);
  }

  Future<void> recordLoginEvent({
    required String status,
    String? failureReason,
    String? ipAddress,
  }) async {
    try {
      final user = _client.auth.currentUser;
      await _client.from('login_history').insert({
        'user_id': user?.id ?? 'unknown',
        'status': status,
        'failure_reason': failureReason,
        'ip_address': ipAddress,
        'device_info': _getDeviceInfo(),
        'user_agent': 'ChurchOnApp/Flutter',
      });
    } catch (e) {
      debugPrint('SecurityService: Failed to record login event: $e');
    }
  }

  Future<void> logSecurityEvent({
    required String eventType,
    required String severity,
    String? userId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _client.from('security_events').insert({
        'event_type': eventType,
        'severity': severity,
        'user_id': userId ?? _client.auth.currentUser?.id,
        'details': details,
        'ip_address': await _getClientIp(),
      });
    } catch (e) {
      debugPrint('SecurityService: Failed to log security event: $e');
    }
  }

  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return 'Android ${android.version.release} (${android.model})';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return 'iOS ${ios.systemVersion} (${ios.model})';
      }
    } catch (e) {
      debugPrint('SecurityService: Failed to get device info: $e');
    }
    return 'Unknown Device';
  }

  Future<String?> _getClientIp() async {
    try {
      final response = await _client.rpc('get_client_ip');
      return response?.toString();
    } catch (e) {
      debugPrint('SecurityService: Failed to get client IP: $e');
      return null;
    }
  }
}

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService(Supabase.instance.client);
});
