import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/services/session_guard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SessionGuardService Inactivity Timer', () {
    test('starts with un-locked state', () {
      final guard = SessionGuardService();
      expect(guard.isLocked, false);
    });

    test('triggers lock state upon inactivity timeout', () async {
      final guard = SessionGuardService();
      bool timeoutTriggered = false;

      guard.startMonitoring(
        timeout: const Duration(milliseconds: 100),
        onTimeout: () {
          timeoutTriggered = true;
        },
      );

      expect(guard.isLocked, false);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(guard.isLocked, true);
      expect(timeoutTriggered, true);
    });

    test('unlock resets lock state', () async {
      final guard = SessionGuardService();
      guard.startMonitoring(timeout: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 80));

      expect(guard.isLocked, true);

      guard.unlock();
      expect(guard.isLocked, false);
    });

    test('stop cancels timer and unlocks', () async {
      final guard = SessionGuardService();
      guard.startMonitoring(timeout: const Duration(milliseconds: 50));
      guard.stop();

      await Future.delayed(const Duration(milliseconds: 80));
      expect(guard.isLocked, false);
    });
  });
}
