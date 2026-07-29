import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionGuardService {
  static const Duration defaultTimeout = Duration(minutes: 5);
  Timer? _inactivityTimer;
  bool _isLocked = false;
  VoidCallback? _onTimeout;

  bool get isLocked => _isLocked;

  void startMonitoring({VoidCallback? onTimeout, Duration timeout = defaultTimeout}) {
    _onTimeout = onTimeout;
    resetTimer(timeout: timeout);
  }

  void resetTimer({Duration timeout = defaultTimeout}) {
    if (_isLocked) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeout, () {
      _isLocked = true;
      debugPrint('[SessionGuardService] Inactivity timeout triggered after 5 minutes.');
      _onTimeout?.call();
    });
  }

  void unlock() {
    _isLocked = false;
    resetTimer();
  }

  void stop() {
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
