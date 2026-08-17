import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/widgets/app_empty_view.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';

final notificationsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value([]);
  return Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(50)
      .map((data) => data.cast<Map<String, dynamic>>());
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconForType(String? type) {
    switch (type) {
      case 'prayer': return LucideIcons.flame;
      case 'sermon': return LucideIcons.playCircle;
      case 'payment': return LucideIcons.checkCircle;
      case 'event': return LucideIcons.bell;
      case 'chat': return LucideIcons.messageCircle;
      default: return LucideIcons.bell;
    }
  }

  Color _colorForType(BuildContext context, String? type) {
    final brand = Theme.of(context).primaryColor;
    switch (type) {
      case 'prayer': return Colors.orange;
      case 'sermon': return brand;
      case 'payment': return Colors.green;
      case 'event': return brand.withValues(alpha: 0.75);
      case 'chat': return brand.withValues(alpha: 0.55);
      default: return Colors.grey;
    }
  }

  String _timeAgo(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }

  void _onNotificationTap(BuildContext context, Map<String, dynamic> n) {
    final id = n['id']?.toString();
    if (id != null && n['is_read'] == false) {
      Supabase.instance.client.from('notifications').update({'is_read': true}).eq('id', id);
    }
    _showAlertDetailSheet(context, n);
  }

  void _showAlertDetailSheet(BuildContext context, Map<String, dynamic> n) {
    final type = n['type'] as String? ?? 'general';
    final title = n['title'] as String? ?? 'Alert';
    final body = (n['body'] ?? n['message'] ?? n['content'] ?? 'You have a new notification.').toString();
    final time = _timeAgo(n['created_at'] as String?);
    final icon = _iconForType(type);
    final color = _colorForType(context, type);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      backgroundColor: theme.colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 25,
            right: 25,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 25,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          time,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
              const SizedBox(height: 12),
              Text(
                body,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateFromAlert(context, type, n['reference_id']?.toString());
                  },
                  icon: const Icon(LucideIcons.arrowRightCircle, size: 18),
                  label: const Text("Take Action", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateFromAlert(BuildContext context, String type, String? id) {
    try {
      switch (type) {
        case 'chat':
          if (id != null && id.isNotEmpty) { context.push('/chat/$id'); } else { context.go('/connect'); }
        case 'post':
          if (id != null && id.isNotEmpty) { context.push('/posts/$id'); } else { context.go('/connect'); }
        case 'payment':
          context.go('/wallet');
        case 'event':
          if (id != null && id.isNotEmpty) { context.push('/events/$id'); } else { context.go('/'); }
        case 'sermon':
          context.go('/sermons');
        case 'prayer':
          context.go('/connect');
        default:
          context.go('/');
      }
    } catch (_) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Alerts"),
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return const AppEmptyView(
              title: "No notifications yet",
              message: "You'll see alerts here when something happens",
              icon: LucideIcons.bellOff,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsStreamProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(25),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                final type = n['type'] as String?;
                final icon = _iconForType(type);
                final color = _colorForType(context, type);
                final title = n['title'] as String? ?? 'Notification';
                final body = n['body'] as String? ?? '';
                final time = _timeAgo(n['created_at'] as String?);
                return _buildNotificationItem(context, title, body, time, icon, color, onTap: () => _onNotificationTap(context, n));
              },
            ),
          );
        },
        loading: () => const ListSkeleton(count: 4),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertTriangle, size: 48, color: Colors.orange.shade400),
              const SizedBox(height: 16),
              Text("Couldn't load notifications", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(notificationsStreamProvider),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(BuildContext context, String title, String body, String time, IconData icon, Color color, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 5),
                  Text(body, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 10),
                  Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
