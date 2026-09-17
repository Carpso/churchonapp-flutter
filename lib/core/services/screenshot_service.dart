import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';

/// Detects screenshots on Android (it does NOT block them) so the app can offer
/// a "share instead" sheet. No-op on every other platform.
class ScreenshotService {
  static const _channel =
      MethodChannel('com.churchonapp.churchonapp/screenshot');

  final _controller = StreamController<void>.broadcast();
  Stream<void> get onScreenshot => _controller.stream;

  bool _watching = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (!isSupported || _watching) return;
    _watching = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenshot') _controller.add(null);
    });
    try {
      await _channel.invokeMethod('startWatching');
      debugPrint('[Screenshot] watching for screenshots');
    } catch (e) {
      debugPrint('[Screenshot] start failed: $e');
    }
  }

  Future<void> stop() async {
    if (!isSupported || !_watching) return;
    _watching = false;
    try {
      await _channel.invokeMethod('stopWatching');
    } catch (_) {}
    _channel.setMethodCallHandler(null);
  }

  void dispose() {
    _controller.close();
  }
}
