import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/app_error_view.dart';
import '../data/care_service.dart';

/// Items 1 + 4 — the pastoral care queue ("People to see today").
///
/// One list fed by `get_people_to_see_today`, which unions four signals:
///   • follow-ups that are due now
///   • visitors in their 2nd week (the Breeze "nobody slips through" window)
///   • people absent 4+ weeks
///   • long-unbaptised contacts
///
/// Actions: mark someone a visitor (which auto-creates their first-visit
/// follow-up server-side) and complete a due follow-up.
class PeopleCareScreen extends ConsumerWidget {
  const PeopleCareScreen({super.key, required this.tenantId});

  final String tenantId;

  static IconData _iconFor(int priority) {
    switch (priority) {
      case 0:
        return LucideIcons.clipboardList;
      case 2:
        return LucideIcons.userPlus;
      case 3:
        return LucideIcons.userX;
      case 4:
        return LucideIcons.droplet;
      default:
        return LucideIcons.user;
    }
  }

  static Color _colorFor(int priority) {
    switch (priority) {
      case 0:
        return Colors.orange;
      case 2:
        return Colors.teal;
      case 3:
        return Colors.red;
      case 4:
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _labelFor(int priority) {
    switch (priority) {
      case 0:
        return 'FOLLOW-UP DUE';
      case 2:
        return 'NEW VISITOR';
      case 3:
        return 'GONE QUIET';
      case 4:
        return 'NOT BAPTISED';
      default:
        return 'PASTORAL CARE';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queueAsync = ref.watch(careQueueProvider(tenantId));
    final service = ref.read(careServiceProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('People to See Today',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.invalidate(
                careQueueProvider(tenantId)),
          ),
        ],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorView(
          error: e,
          onRetry: () => ref.invalidate(
              careQueueProvider(tenantId)),
        ),
        data: (queue) {
          if (queue.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.checkCircle,
                        size: 64, color: Colors.green.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text('Nobody needs a follow-up',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Your members are all up to date. New visitors will appear here the moment they are checked in.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(
                careQueueProvider(tenantId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: queue.people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final person = queue.people[idx];
                final color = _colorFor(person.priority);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
                        child: (person.avatarUrl != null &&
                                person.avatarUrl!.isNotEmpty)
                            ? AppImage(person.avatarUrl!, width: 42, height: 42)
                            : Container(
                                width: 42,
                                height: 42,
                                color: color.withValues(alpha: 0.15),
                                child: Icon(_iconFor(person.priority),
                                    color: color, size: 20),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              person.reason.isEmpty
                                  ? _labelFor(person.priority)
                                  : person.reason,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _tag(_labelFor(person.priority), color),
                                if (person.services > 0)
                                  _tag(
                                      '${person.services} svc', Colors.grey),
                                if (person.baptized)
                                  _tag('Baptised', Colors.green),
                              ],
                            ),
                            if (person.followupId != null) ...[
                              const SizedBox(height: 10),
                              // Mark the pastoral follow-up done.
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await service.completeFollowup(
                                      person.followupId!);
                                  ref.invalidate(careQueueProvider(tenantId));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Marked ${person.name} as followed up.'),
                                    ));
                                  }
                                },
                                icon: const Icon(LucideIcons.check,
                                    size: 16, color: Colors.green),
                                label: const Text('Mark done',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Mark as visitor (item 1) — server auto-creates the
                      // first-visit follow-up.
                      IconButton(
                        tooltip: 'Mark as visitor',
                        onPressed: () async {
                          final created = await service.setVisitorStatus(
                              person.id, 'visitor');
                          ref.invalidate(careQueueProvider(tenantId));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(created
                                    ? '${person.name} marked as visitor — a welcome follow-up was created.'
                                    : '${person.name} updated.'),
                              ),
                            );
                          }
                        },
                        icon: Icon(LucideIcons.userPlus,
                            color: theme.primaryColor, size: 20),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
