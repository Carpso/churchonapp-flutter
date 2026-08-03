import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/admin/data/session_service.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';

class ActiveSessionsScreen extends ConsumerStatefulWidget {
  const ActiveSessionsScreen({super.key});

  @override
  ConsumerState<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends ConsumerState<ActiveSessionsScreen> {
  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Active Sessions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, color: Colors.white),
            onPressed: () => ref.invalidate(activeSessionsProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activeSessionsProvider),
        color: Colors.amber,
        backgroundColor: const Color(0xFF1E1E1E),
        child: sessionsAsync.when(
          data: (sessions) {
            if (sessions.isEmpty) {
              return _buildEmptyState(theme);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return _buildSessionCard(session, theme);
              },
            );
          },
          loading: () => _buildLoadingState(),
          error: (error, stack) => _buildErrorState(error, theme),
        ),
      ),
    );
  }

  Widget _buildSessionCard(UserSession session, ThemeData theme) {
    final isCurrent = session.isCurrentSession;
    final timeAgo = _formatTimeAgo(session.lastActiveAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent 
            ? Colors.amber.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent 
              ? Colors.amber.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with device name and badges
          Row(
            children: [
              // Device icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Colors.amber.withValues(alpha: 0.15)
                      : (session.isActive ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCurrent ? LucideIcons.monitor : (session.isActive ? LucideIcons.wifi : LucideIcons.wifiOff),
                  color: isCurrent ? Colors.amber : (session.isActive ? Colors.greenAccent : Colors.grey),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.deviceName ?? session.deviceInfo ?? 'Unknown Device',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        isCurrent
                            ? _buildBadge('Current Device', Colors.amber, LucideIcons.checkCircle)
                            : (session.isActive
                                ? _buildBadge('Active', Colors.greenAccent, LucideIcons.shieldCheck)
                                : _buildBadge('Inactive', Colors.grey, LucideIcons.xCircle)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.ipAddress ?? 'Unknown IP'}  •  $timeAgo',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Action buttons
          if (!isCurrent) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                // Logout button for other devices
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogoutSession(session),
                    icon: const Icon(LucideIcons.logOut, size: 16),
                    label: const Text('Log Out This Device'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                // Logout all other devices button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogoutOtherDevices(),
                    icon: const Icon(LucideIcons.users, size: 16),
                    label: const Text('Log Out All Other Devices'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Refresh current session
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _refreshCurrentSession(),
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Refresh Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber,
                      side: const BorderSide(color: Colors.amber),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: Icon(LucideIcons.monitor, size: 48, color: Colors.white38),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Active Sessions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your login sessions will appear here.\nSign in on another device to see it listed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(activeSessionsProvider),
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 11,
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error, ThemeData theme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: ErrorRetryWidget(
          message: 'Failed to load sessions',
          onRetry: () => ref.invalidate(activeSessionsProvider),
        ),
      ),
    );
  }

  Future<void> _confirmLogoutSession(UserSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out Device?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will log out "${session.deviceName ?? session.deviceInfo ?? 'this device'}". '
          'You will need to sign in again on that device.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(sessionServiceProvider).logoutSession(session.id);
        ref.invalidate(activeSessionsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device logged out successfully ✅'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to log out device: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmLogoutOtherDevices() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out All Other Devices?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will log you out from all other active sessions. '
          'Your current session will remain active.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out Others'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(sessionServiceProvider).logoutOtherSessions();
        ref.invalidate(activeSessionsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All other devices logged out ✅'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to log out devices: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _refreshCurrentSession() async {
    try {
      await ref.read(sessionServiceProvider).recordSession();
      ref.invalidate(activeSessionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session refreshed ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}