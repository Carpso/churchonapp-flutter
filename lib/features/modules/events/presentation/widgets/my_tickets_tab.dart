import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/modules/events/presentation/ticket_detail_screen.dart';

class MyTicketsTab extends ConsumerWidget {
  final VoidCallback onBrowseEvents;
  const MyTicketsTab({super.key, required this.onBrowseEvents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTicketsAsync = ref.watch(myTicketsStreamProvider);

    return myTicketsAsync.when(
      data: (tickets) => tickets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.ticket, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(height: 20),
                  const Text("No active tickets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: onBrowseEvents,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text("Browse Events", style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myTicketsStreamProvider);
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: tickets.length,
                itemBuilder: (context, index) => _buildSimpleTicketCard(context, tickets[index]),
              ),
            ),
      loading: () => const _TicketSkeleton(),
      error: (err, stack) => ErrorRetryWidget(
        message: "Failed to load your tickets",
        onRetry: () => ref.invalidate(myTicketsStreamProvider),
      ),
    );
  }

  Widget _buildSimpleTicketCard(BuildContext context, ChurchEvent event) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TicketDetailScreen(event: event)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: event.imageUrl,
                width: 60,
                height: 60,
                memCacheWidth: 120,
                memCacheHeight: 120,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(width: 60, height: 60, color: Colors.grey.shade200),
                errorWidget: (context, url, error) => Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.event, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateFormat.yMMMd().format(event.date), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _TicketSkeleton extends StatelessWidget {
  const _TicketSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const ShimmerLoader.rectangular(width: 60, height: 60),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerLoader.rectangular(width: MediaQuery.of(context).size.width * 0.4, height: 16),
                      const SizedBox(height: 8),
                      const ShimmerLoader.rectangular(width: 80, height: 12),
                    ],
                  ),
                ),
                const ShimmerLoader.rectangular(width: 24, height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
