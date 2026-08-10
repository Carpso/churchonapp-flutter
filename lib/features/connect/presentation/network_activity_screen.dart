import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/network_service.dart';

class NetworkActivityScreen extends ConsumerWidget {
  const NetworkActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(networkActivityStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Network Activity"),
      ),
      body: activitiesAsync.when(
        data: (activities) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(networkActivityStreamProvider);
          },
          child: activities.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                    Center(
                      child: Column(
                        children: [
                          Icon(LucideIcons.rss, size: 60, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          const Text("No network activity yet", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          const Text("Connect with other churches to see their updates", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: activities.length,
                  itemBuilder: (context, index) => _buildActivityCard(context, activities[index]),
                ),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.wifiOff, size: 50, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text("Error loading activity: $err", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text("Retry"),
                onPressed: () => ref.invalidate(networkActivityStreamProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard(BuildContext context, NetworkActivity activity) {
    IconData icon;
    Color color;
    String typeLabel;

    switch (activity.type) {
      case 'sermon':
        icon = LucideIcons.bookOpen;
        color = Colors.blue;
        typeLabel = 'Sermon';
        break;
      case 'event':
        icon = LucideIcons.calendarDays;
        color = Colors.green;
        typeLabel = 'Event';
        break;
      case 'prayer':
        icon = LucideIcons.flame;
        color = Colors.orange;
        typeLabel = 'Prayer';
        break;
      default:
        icon = LucideIcons.radio;
        color = Colors.purple;
        typeLabel = 'Update';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: InkWell(
        onTap: () {
          if (activity.referenceId != null) {
            context.push('/${activity.type}s/${activity.referenceId}');
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(typeLabel, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        Text(_formatTime(activity.createdAt), style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(activity.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (activity.description != null && activity.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(activity.description!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.church, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(activity.churchName, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt);
  }
}
