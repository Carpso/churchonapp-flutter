import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionGuardService {
  static const Duration defaultTimeout = Duration(minutes: 5);
  Timer? _inactivityTimer;
  bool _isLocked = false;
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

  void _onPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      registerActivity();
    }
  }

  /// Resets the inactivity countdown — call on any user activity
  /// (pointer taps, app resume, etc.).
  void registerActivity() {
    if (_isLocked) return;
    resetTimer();
  }

  void resetTimer() {
    if (_isLocked) return;
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
  }
}

final sessionGuardProvider = Provider<SessionGuardService>((ref) {
  final service = SessionGuardService();
  ref.onDispose(() => service.stop());
  return service;
});
