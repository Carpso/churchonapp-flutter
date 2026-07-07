import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/lockdown_service.dart';

class LockdownOverlay extends ConsumerWidget {
  final Widget child;

  const LockdownOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockdownAsync = ref.watch(isSystemLockedProvider);

    return Stack(
      children: [
        child,
        lockdownAsync.whenOrNull(
          data: (isLocked) => isLocked ? _buildLockdown(context, ref) : null,
        ) ?? const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildLockdown(BuildContext context, WidgetRef ref) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: FutureBuilder<String>(
          future: ref.read(lockdownServiceProvider).getLockdownMessage(),
          builder: (context, snapshot) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 80, color: Colors.white),
                    const SizedBox(height: 24),
                    const Text(
                      'System Lockdown',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      snapshot.data ?? 'System is under maintenance.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
