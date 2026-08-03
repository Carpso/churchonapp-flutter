import 'package:universal_io/io.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';

class UserSession {
  final String id;
  final String userId;
  final String? deviceName;
  final String? deviceInfo;
  final String? ipAddress;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool isActive;
  final bool isCurrentSession;

  UserSession({
    required this.id,
    required this.userId,
    this.deviceName,
    this.deviceInfo,
    this.ipAddress,
    required this.lastActiveAt,
    required this.createdAt,
    required this.isActive,
    this.isCurrentSession = false,
  });

  factory UserSession.fromMap(Map<String, dynamic> map, {String? currentSessionId}) => UserSession(
    id: map['id']?.toString() ?? '',
    userId: map['user_id']?.toString() ?? '',
    deviceName: map['device_name']?.toString(),
    deviceInfo: map['device_info']?.toString(),
    ipAddress: map['ip_address']?.toString(),
    lastActiveAt: DateTime.tryParse(map['last_active_at']?.toString() ?? '') ?? DateTime.now(),
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    isActive: map['is_active'] == true,
    isCurrentSession: currentSessionId != null && map['id']?.toString() == currentSessionId,
  );
}

class SessionService {
  final SupabaseClient _client;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  String? _currentSessionId;

  SessionService(this._client);

  /// Gets a human-readable device name (e.g., "Samsung Galaxy A14", "MacBook Pro Chrome")
  Future<String> _getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return '${info.name} (${info.model})';
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return '${info.model} (macOS ${info.majorVersion}.${info.minorVersion})';
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return 'Windows ${info.buildNumber}';
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return '${info.name} (${info.version})';
      } else if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return '${info.browserName.name} on ${info.userAgent ?? "Web"}';
      }
    } catch (e) {
      log('Error getting device name: $e');
    }
    return 'Unknown Device';
  }

  /// Gets detailed device info for the device_info column
  Future<String> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return 'Android ${info.version.release} | ${info.brand} ${info.model} | SDK ${info.version.sdkInt}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return 'iOS ${info.systemVersion} | ${info.name} ${info.model}';
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return 'macOS ${info.majorVersion}.${info.minorVersion}.${info.patchVersion} | ${info.model}';
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return 'Windows ${info.buildNumber} | ${info.productName}';
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return '${info.name} ${info.version}';
      } else if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return '${info.browserName.name} ${info.appVersion ?? ""} on ${info.userAgent ?? "Web"}';
      }
    } catch (e) {
      log('Error getting device info: $e');
    }
    return Platform.operatingSystem;
  }

  /// Records or updates the current session in Supabase
  /// Call this on app start and after successful login
  Future<void> recordSession({String? ipAddress}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final deviceName = await _getDeviceName();
    final deviceInfo = await _getDeviceInfo();

    try {
      // Upsert: update existing session for this device or create new
      final existingSession = await _client
          .from('user_sessions')
          .select('id')
          .eq('user_id', user.id)
          .eq('device_name', deviceName)
          .maybeSingle();

      if (existingSession != null) {
        // Update existing session - mark as current
        await _client
            .from('user_sessions')
            .update({
              'device_info': deviceInfo,
              'ip_address': ipAddress,
              'last_active_at': DateTime.now().toIso8601String(),
              'is_active': true,
            })
            .eq('id', existingSession['id']);
        _currentSessionId = existingSession['id']?.toString();
      } else {
        // Create new session
        final res = await _client
            .from('user_sessions')
            .insert({
              'user_id': user.id,
              'device_name': deviceName,
              'device_info': deviceInfo,
              'ip_address': ipAddress,
              'is_active': true,
            })
            .select('id')
            .single();
        _currentSessionId = res['id']?.toString();
      }
    } catch (e) {
      log('Error recording session: $e');
    }
  }

  /// Updates last_active_at for the current session (call periodically or on resume)
  Future<void> pingSession() async {
    if (_currentSessionId == null) return;
    await _client
        .from('user_sessions')
        .update({'last_active_at': DateTime.now().toIso8601String()})
        .eq('id', _currentSessionId!);
  }

  /// Logs out a specific session by ID (other devices)
  Future<void> logoutSession(String sessionId) async {
    await _client.from('user_sessions').update({
      'is_active': false,
      'last_active_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  /// Logs out all other sessions except current
  Future<void> logoutOtherSessions() async {
    final user = _client.auth.currentUser;
    if (user == null || _currentSessionId == null) return;
    await _client.from('user_sessions')
        .update({'is_active': false, 'last_active_at': DateTime.now().toIso8601String()})
        .eq('user_id', user.id)
        .neq('id', _currentSessionId!);
  }

  /// Logs out all sessions including current
  Future<void> logoutAllSessions() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('user_sessions')
        .update({'is_active': false, 'last_active_at': DateTime.now().toIso8601String()})
        .eq('user_id', user.id)
        .eq('is_active', true);
    _currentSessionId = null;
  }

  /// Gets all sessions for the current user (active + inactive)
  Stream<List<UserSession>> getActiveSessions() {
    final user = _client.auth.currentUser;
    if (user == null) return const Stream.empty();
    return _client
        .from('user_sessions')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('last_active_at', ascending: false)
        .map((data) => data
            .map((map) => UserSession.fromMap(map, currentSessionId: _currentSessionId))
            .toList());
  }

  /// One-time fetch of all sessions
  Future<List<UserSession>> getAllSessions({String? userId}) async {
    final targetUserId = userId ?? _client.auth.currentUser?.id;
    if (targetUserId == null) return [];
    
    final data = await _client
        .from('user_sessions')
        .select()
        .eq('user_id', targetUserId)
        .order('last_active_at', ascending: false);
    
    return data.map((map) => UserSession.fromMap(map, currentSessionId: _currentSessionId)).toList();
  }

  String? get currentSessionId => _currentSessionId;
}

final sessionServiceProvider = Provider((ref) => SessionService(Supabase.instance.client));

final activeSessionsProvider = StreamProvider<List<UserSession>>((ref) {
  return ref.watch(sessionServiceProvider).getActiveSessions();
});
