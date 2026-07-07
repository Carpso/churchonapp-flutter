import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/admin/data/job_notification_service.dart';

class JobNotificationsScreen extends ConsumerWidget {
  const JobNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(_jobNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ref.read(jobNotificationServiceProvider).markAllAsRead();
              ref.invalidate(_jobNotificationsProvider);
            },
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) => notifications.isEmpty
            ? const Center(child: Text('No job notifications'))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(_jobNotificationsProvider);
                },
                child: ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                  final notif = notifications[index];
                  return ListTile(
                    leading: Icon(
                      notif.type == 'new_application' ? Icons.person_add : Icons.update,
                      color: notif.isRead ? Colors.grey : Colors.blue,
                    ),
                    title: Text(notif.message),
                    subtitle: Text(
                      _timeAgo(notif.createdAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: notif.isRead ? null : Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                    onTap: () async {
                      if (!notif.isRead) {
                        await ref.read(jobNotificationServiceProvider).markAsRead(notif.id);
                        ref.invalidate(_jobNotificationsProvider);
                      }
                    },
                  );
                },
              ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

final _jobNotificationsProvider = FutureProvider<List<JobNotification>>((ref) async {
  return ref.read(jobNotificationServiceProvider).getNotifications();
});
