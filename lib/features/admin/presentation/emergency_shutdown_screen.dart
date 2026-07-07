import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/lockdown_service.dart';

class EmergencyShutdownScreen extends ConsumerWidget {
  const EmergencyShutdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockdownAsync = ref.watch(isSystemLockedProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Shutdown'),
      ),
      body: lockdownAsync.when(
        data: (isLocked) => _buildBody(context, ref, isLocked, theme),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, bool isLocked, ThemeData theme) {
    final messageController = TextEditingController(
      text: 'System is under maintenance. Please check back later.',
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            isLocked ? Icons.lock_outline : Icons.lock_open,
            size: 80,
            color: isLocked ? Colors.red : Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            isLocked ? 'System is LOCKED DOWN' : 'System is Operational',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isLocked ? Colors.red : Colors.green,
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lockdown Message', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter message shown to users...',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _toggleLockdown(context, ref, !isLocked, messageController.text),
              icon: Icon(isLocked ? Icons.lock_open : Icons.lock_outline),
              label: Text(
                isLocked ? 'DISABLE LOCKDOWN' : 'ACTIVATE LOCKDOWN',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLocked ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (isLocked) ...[
            const SizedBox(height: 16),
            Text(
              'Warning: Locking the system will prevent ALL users from accessing the app.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleLockdown(BuildContext context, WidgetRef ref, bool lock, String message) async {
    try {
      await ref.read(lockdownServiceProvider).toggleLockdown(lock: lock, message: message);
      ref.invalidate(isSystemLockedProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lock ? 'System locked down' : 'Lockdown disabled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
