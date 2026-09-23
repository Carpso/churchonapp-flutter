import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:church_on_app/core/widgets/app_image.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/events/data/event_ticketing_service.dart';
import 'package:church_on_app/features/modules/events/presentation/event_eticket_screen.dart';

class MyTicketsTab extends ConsumerWidget {
  final VoidCallback onBrowseEvents;
  const MyTicketsTab({super.key, required this.onBrowseEvents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myTicketsAsync = ref.watch(myEventTicketsProvider);

    return myTicketsAsync.when(
      data: (tickets) => tickets.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.ticket, size: 80, color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(height: 20),
                  const Text("No tickets yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
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
              onRefresh: () async => ref.invalidate(myEventTicketsProvider),
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: tickets.length,
                itemBuilder: (context, index) => _buildTicketCard(context, tickets[index]),
              ),
            ),
      loading: () => const _TicketSkeleton(),
      error: (err, stack) => ErrorRetryWidget(
        message: "Failed to load your tickets",
        onRetry: () => ref.invalidate(myEventTicketsProvider),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'valid':
        return Colors.green;
      case 'used':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'refunded':
      case 'cancelled':
        return Colors.red;
      case 'transferred':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTicketCard(BuildContext context, EventTicket ticket) {
    final color = _statusColor(ticket.status);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EventEticketScreen(ticketId: ticket.id)),
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
              child: AppImage(
                ticket.eventImageUrl ?? '',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                placeholder: Container(width: 60, height: 60, color: Colors.grey.shade200),
                errorWidget: (context, url) => Container(
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
                  Text(ticket.eventTitle ?? 'Event', style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (ticket.eventDate != null) DateFormat.yMMMd().format(ticket.eventDate!),
                      ticket.tierName ?? 'General',
                    ].join('  •  '),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(ticket.status.toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
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
