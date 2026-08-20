import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionGuardService {
  static const Duration defaultTimeout = Duration(minutes: 30);
  Timer? _inactivityTimer;
  bool _isLocked = false;
  bool _isPaused = false;
  VoidCallback? _onTimeout;
  Duration _timeout = defaultTimeout;
  GestureBinding? _binding;

  bool get isLocked => _isLocked;

  /// Starts inactivity monitoring. Any pointer down anywhere in the app
  /// (including modal barriers/overlays) resets the countdown via the
  /// global pointer route.
  void startMonitoring({
    VoidCallback? onTimeout,
    Duration timeout = defaultTimeout,
  }) {
    _onTimeout = onTimeout;
    _timeout = timeout;
    _binding = GestureBinding.instance;
    _binding?.pointerRouter.addGlobalRoute(_onPointerEvent);
    resetTimer();
  }

  /// Pauses the countdown while the app is backgrounded — otherwise the
  /// timer fired on resume and signed users out after briefly leaving the
  /// app (e.g. checking WhatsApp for 5 minutes).
  void pauseMonitoring() {
    _isPaused = true;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  /// Restarts the countdown when the app returns to the foreground.
  void resumeMonitoring() {
    _isPaused = false;
    resetTimer();
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      registerActivity();
    }
  }

  /// Resets the inactivity countdown — call on any user activity
  /// (pointer taps, app resume, etc.).
  void registerActivity() {
    if (_isLocked || _isPaused) return;
    resetTimer();
  }

  void resetTimer() {
    if (_isLocked || _isPaused) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_timeout, () {
      _isLocked = true;
      debugPrint('[SessionGuardService] Inactivity timeout triggered.');
      _onTimeout?.call();
    });
  }

  void unlock() {
    _isLocked = false;
    resetTimer();
  }

  void stop() {
    _binding?.pointerRouter.removeGlobalRoute(_onPointerEvent);
    _binding = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _isLocked = false;
    _isPaused = false;
  }
}

final sessionGuardProvider = Provider<SessionGuardService>((ref) {
  final service = SessionGuardService();
  ref.onDispose(() => service.stop());
  return service;
});
