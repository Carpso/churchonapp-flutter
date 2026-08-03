import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../data/discover_service.dart';
import '../data/sermon_service.dart';
import '../../../core/widgets/app_image.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(discoverContentProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Discover"),
      ),
      body: contentAsync.when(
        data: (content) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(discoverContentProvider);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(context, "Recommended Sermons", "See All", () => context.push('/sermons')),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: content.recommendedSermons.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) => _buildSermonCard(context, content.recommendedSermons[index]),
                  ),
                ),
                const SizedBox(height: 28),
                _buildSectionHeader(context, "Upcoming Events", "See All", () => {}),
                const SizedBox(height: 12),
                ...content.upcomingEvents.map((e) => _buildEventCard(context, e)),
                const SizedBox(height: 28),
                _buildSectionHeader(context, "Popular in Your Church", "See All", () => context.push('/sermons')),
                const SizedBox(height: 12),
                ...content.popularContent.map((s) => _buildContentRow(context, s)),
                const SizedBox(height: 28),
                _buildSectionHeader(context, "New This Week", "See All", () => context.push('/sermons')),
                const SizedBox(height: 12),
                ...content.newThisWeek.map((s) => _buildContentRow(context, s)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.wifiOff, size: 50, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text("Error loading recommendations: $err", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text("Retry"),
                onPressed: () => ref.invalidate(discoverContentProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String actionLabel, VoidCallback onAction) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        GestureDetector(
          onTap: onAction,
          child: Text(actionLabel, style: TextStyle(color: Colors.amber.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSermonCard(BuildContext context, Sermon sermon) {
    return GestureDetector(
      onTap: () => _showSermonDetail(context, sermon),
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AppImage(sermon.thumbnailUrl, height: 110, width: double.infinity, fit: BoxFit.cover),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.play, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sermon.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(sermon.preacher, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Map<String, dynamic> event) {
    final title = event['title'] ?? '';
    final location = event['location'] ?? '';
    final date = event['date'] != null ? DateTime.tryParse(event['date'].toString()) : null;
    final imageUrl = event['image_url'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/events/${event['id']}'),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              child: AppImage(imageUrl, width: 80, height: 80, fit: BoxFit.cover),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [Icon(LucideIcons.mapPin, size: 12, color: Colors.grey.shade400), const SizedBox(width: 4), Text(location.toString(), style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
                    if (date != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [Icon(LucideIcons.clock, size: 12, color: Colors.grey.shade400), const SizedBox(width: 4), Text(DateFormat.MMMd().add_jm().format(date), style: TextStyle(color: Colors.grey.shade500, fontSize: 11))]),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey.shade300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentRow(BuildContext context, Sermon sermon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showSermonDetail(context, sermon),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AppImage(sermon.thumbnailUrl, width: 56, height: 56, fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sermon.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(sermon.preacher, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(LucideIcons.play, size: 16, color: Colors.amber.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSermonDetail(BuildContext context, Sermon sermon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AppImage(sermon.thumbnailUrl, height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 20),
            Text(sermon.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6),
            Text(sermon.preacher, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(LucideIcons.play, size: 18),
                label: const Text("Play Sermon"),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
