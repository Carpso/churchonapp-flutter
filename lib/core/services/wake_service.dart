import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Calls native Android wake mechanism so the screen turns on and
/// shows over the lock screen when a notification arrives.
class WakeService {
  static const _channel = MethodChannel('com.churchonapp.churchonapp/wake_service');

  static Future<void> wakeScreen() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('wakeScreen');
    } catch (e) {
      debugPrint('[WakeService] wakeScreen failed: $e');
    }
  }
}
