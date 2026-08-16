import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/core/widgets/shimmer_loader.dart';
import 'package:church_on_app/core/widgets/error_retry_widget.dart';
import 'package:church_on_app/features/modules/events/presentation/event_details_screen.dart';

class DiscoverTab extends ConsumerWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsStreamProvider);

    return eventsAsync.when(
      data: (events) => events.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.calendarOff, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text("No upcoming events found.", style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(eventsStreamProvider);
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: events.length,
                itemBuilder: (context, index) => _buildPremiumEventCard(context, ref, events[index]),
              ),
            ),
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: 3,
        itemBuilder: (context, index) => _buildEventSkeleton(context),
      ),
      error: (err, stack) => ErrorRetryWidget(
        message: "Failed to load events",
        onRetry: () => ref.invalidate(eventsStreamProvider),
      ),
    );
  }

  Widget _buildPremiumEventCard(BuildContext context, WidgetRef ref, ChurchEvent event) {
    final isFree = event.ticketPrice == 0;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailsScreen(event: {
        'id': event.id,
        'title': event.title,
        'description': event.description,
        'date': DateFormat.yMMMd().format(event.date),
        'location': event.location,
        'cover': event.imageUrl,
        'price': event.ticketPrice.toInt(),
        'isLiveStream': false,
        'interchurch': true,
        'speakers': event.speakers,
        'end_date': event.endDate != null ? DateFormat.yMMMd().format(event.endDate!) : '',
        'organizer_momo_phone': event.organizerMomoPhone,
        'organizer_momo_name': event.organizerMomoName,
      }))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                  child: CachedNetworkImage(
                    imageUrl: event.imageUrl,
                    height: 180,
                    width: double.infinity,
                    memCacheHeight: 360,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey.shade200, height: 180),
                    errorWidget: (context, url, error) => Container(
                      height: 180,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.event, color: Colors.grey, size: 48),
                    ),
                  ),
                ),
                Positioned(
                  top: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 5)]),
                    child: Text(isFree ? "FREE" : "K${event.ticketPrice}", style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat.yMMMd().format(event.date), style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      Row(
                        children: [
                          Icon(LucideIcons.globe, size: 12, color: Theme.of(context).primaryColor),
                          SizedBox(width: 4),
                          Text("Interchurch", style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(event.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(event.location, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (isFree) {
                              ref.read(eventServiceProvider).registerForEvent(event.id);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registration Successful!")));
                            } else {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailsScreen(event: {
                                'id': event.id,
                                'title': event.title,
                                'description': event.description,
                                'date': DateFormat.yMMMd().format(event.date),
                                'location': event.location,
                                'cover': event.imageUrl,
                                'price': event.ticketPrice.toInt(),
                                'isLiveStream': false,
                                'interchurch': true,
                              })));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.secondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: Text(isFree ? "RSVP NOW" : "BUY TICKET", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
                        child: IconButton(
                          icon: const Icon(LucideIcons.share2, color: Colors.black87),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: "https://churchonapp.com/events/${event.id}"));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Event link copied to clipboard!"), backgroundColor: Colors.green)
                            );
                          },
                        ),
                      )
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEventSkeleton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerLoader.rectangular(height: 180),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShimmerLoader.rectangular(width: MediaQuery.of(context).size.width * 0.25, height: 12),
                    ShimmerLoader.rectangular(width: MediaQuery.of(context).size.width * 0.2, height: 12),
                  ],
                ),
                const SizedBox(height: 10),
                ShimmerLoader.rectangular(width: MediaQuery.of(context).size.width * 0.6, height: 18),
                const SizedBox(height: 10),
                ShimmerLoader.rectangular(width: MediaQuery.of(context).size.width * 0.4, height: 12),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: ShimmerLoader.rectangular(height: 48)),
                    const SizedBox(width: 10),
                    ShimmerLoader.rectangular(width: 48, height: 48),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
