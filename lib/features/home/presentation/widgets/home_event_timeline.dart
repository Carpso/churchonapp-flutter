import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'home_section_title.dart';


class HomeEventTimeline extends ConsumerWidget {
  const HomeEventTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionTitle(
          title: "Upcoming Events",
          trailing: "VIEW ALL",
          onTrailingTap: () => context.push('/events'),
        ),
        eventsAsync.when(
          skipLoadingOnRefresh: true,
          data: (events) {
            if (events.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendar, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), size: 20),
                    const SizedBox(width: 12),
                    Text("No upcoming events", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13)),
                  ],
                ),
              );
            }
            final upcoming = events.where((e) => e.date.isAfter(DateTime.now())).toList()..sort((a, b) => a.date.compareTo(b.date));
            final display = upcoming.take(3).toList();
            return Column(
              children: display.map((e) => _buildEventItem(context, e.title, _formatEventTime(e.date), _getEventIcon(e.category))).toList(),
            );
          },
          loading: () => Column(
            children: List.generate(2, (_) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12))),
                  const SizedBox(width: 15),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 14, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(width: 80, height: 10, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
                    ],
                  )),
                ],
              ),
            )),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(LucideIcons.calendarX, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 8),
                Text("Could not load events", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatEventTime(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);
    if (diff.inDays > 7) return "${(diff.inDays / 7).floor()}w away";
    if (diff.inDays > 0) return "${diff.inDays}d away";
    if (diff.inHours > 0) return "${diff.inHours}h away";
    return "Today";
  }

  IconData _getEventIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'worship': return LucideIcons.music;
      case 'study': return LucideIcons.book;
      case 'youth': return LucideIcons.users;
      case 'prayer': return LucideIcons.hand;
      default: return LucideIcons.calendar;
    }
  }

  Widget _buildEventItem(BuildContext context, String title, String time, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Theme.of(context).shadowColor.withValues(alpha: 0.02), blurRadius: 5)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                Text(time, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
