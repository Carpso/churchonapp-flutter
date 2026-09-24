import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/events/data/event_service.dart';
import 'package:church_on_app/features/events/data/event_ticketing_service.dart';
import 'buy_ticket_screen.dart';
import 'event_eticket_screen.dart';
import 'ticket_tier_manager_screen.dart';

/// Thin "by id" wrappers for the ticketing deep links:
///
///  * `/ticket/:id`                 → [TicketByIdScreen]
///  * `/events/:id/tickets`         → [BuyTicketByIdScreen]
///  * `/events/:id/manage-tickets`  → [ManageTicketsByIdScreen]
///
/// The existing screens required a fully-loaded object passed via `extra`
/// (e.g. `/ticket` demanded a `ChurchEvent`), which a QR code, a push
/// notification or a shared link can never supply. Each wrapper resolves the
/// entity from the id first, then renders the real screen.

final _ticketByIdProvider = FutureProvider.family<EventTicket?, String>(
  (ref, ticketId) => ref.watch(eventTicketingServiceProvider).fetchTicket(ticketId),
);

final _eventByIdProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, eventId) => ref.watch(eventServiceProvider).getEventById(eventId),
);

class TicketByIdScreen extends ConsumerWidget {
  final String ticketId;
  const TicketByIdScreen({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_ticketByIdProvider(ticketId)).when(
          loading: () => const _ByIdLoading(title: 'Ticket'),
          error: (e, _) => _ByIdNotFound(title: 'Ticket', error: e),
          data: (ticket) {
            if (ticket == null) return const _ByIdNotFound(title: 'Ticket');
            return EventEticketScreen(
              ticketId: ticket.id,
              eventTitle: ticket.eventTitle ?? 'Event',
            );
          },
        );
  }
}

class BuyTicketByIdScreen extends ConsumerWidget {
  final String eventId;
  const BuyTicketByIdScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_eventByIdProvider(eventId)).when(
          loading: () => const _ByIdLoading(title: 'Event'),
          error: (e, _) => _ByIdNotFound(title: 'Event', error: e),
          data: (event) {
            if (event == null) return const _ByIdNotFound(title: 'Event');
            return BuyTicketScreen(
              eventId: eventId,
              eventTitle: event['title']?.toString() ?? 'Event',
              organizerMomoPhone: event['organizer_momo_phone']?.toString(),
              organizerMomoName: event['organizer_momo_name']?.toString(),
            );
          },
        );
  }
}

class ManageTicketsByIdScreen extends ConsumerWidget {
  final String eventId;
  const ManageTicketsByIdScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(_eventByIdProvider(eventId)).when(
          loading: () => const _ByIdLoading(title: 'Event'),
          error: (e, _) => _ByIdNotFound(title: 'Event', error: e),
          data: (event) {
            if (event == null) return const _ByIdNotFound(title: 'Event');
            return TicketTierManagerScreen(
              eventId: eventId,
              eventTitle: event['title']?.toString() ?? 'Event',
            );
          },
        );
  }
}

class _ByIdLoading extends StatelessWidget {
  final String title;
  const _ByIdLoading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ByIdNotFound extends StatelessWidget {
  final String title;
  final Object? error;
  const _ByIdNotFound({required this.title, this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('$title not found',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'This link may have expired or the item was removed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('GO BACK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
