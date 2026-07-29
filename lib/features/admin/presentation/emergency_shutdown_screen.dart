import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/lockdown_service.dart';

class EmergencyShutdownScreen extends ConsumerStatefulWidget {
  const EmergencyShutdownScreen({super.key});

  @override
  ConsumerState<EmergencyShutdownScreen> createState() => _EmergencyShutdownScreenState();
}

class _EmergencyShutdownScreenState extends ConsumerState<EmergencyShutdownScreen> {
  bool _isToggling = false;
  late TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: 'System is under maintenance. Please check back later.',
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lockdownAsync = ref.watch(isSystemLockedProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Shutdown'),
      ),
      body: lockdownAsync.when(
        data: (isLocked) => _buildBody(context, isLocked, theme),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isLocked, ThemeData theme) {
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
                    controller: _messageController,
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
              onPressed: _isToggling ? null : () => _confirmToggle(context, !isLocked),
              icon: _isToggling
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Icon(isLocked ? Icons.lock_open : Icons.lock_outline),
              label: Text(
                _isToggling
                    ? 'Processing...'
                    : (isLocked ? 'DISABLE LOCKDOWN' : 'ACTIVATE LOCKDOWN'),
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

  void _confirmToggle(BuildContext context, bool lock) {
    final action = lock ? 'LOCK DOWN' : 'UNLOCK';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm $action'),
        content: Text(lock
            ? 'This will prevent ALL users from accessing the app. Are you sure?'
            : 'This will restore access for all users. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _toggleLockdown(lock);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: lock ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLockdown(bool lock) async {
    setState(() => _isToggling = true);
    try {
      await ref.read(lockdownServiceProvider).toggleLockdown(
        lock: lock,
        message: _messageController.text.trim(),
      );
      ref.invalidate(isSystemLockedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lock ? 'System locked down' : 'Lockdown disabled'),
            backgroundColor: lock ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }
}
