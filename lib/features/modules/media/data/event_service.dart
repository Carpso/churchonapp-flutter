import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class KingdomEvent {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime eventDate;
  final String? churchId;
  final double price;
  final int? capacity;
  final String category;

  KingdomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.eventDate,
    this.churchId,
    required this.price,
    this.capacity,
    required this.category,
  });

  factory KingdomEvent.fromMap(Map<String, dynamic> map) {
    return KingdomEvent(
      id: map['id'],
      title: map['title'],
      description: map['description'] ?? '',
      location: map['location'] ?? 'Online / Main Sanctuary',
      eventDate: DateTime.parse(map['event_date']),
      churchId: map['church_id'],
      price: (map['price'] as num).toDouble(),
      capacity: map['capacity'],
      category: map['category'] ?? 'General',
    );
  }
}

class EventService {
  final SupabaseClient _client;
  EventService(this._client);

  Future<List<KingdomEvent>> fetchUpcomingEvents() async {
    try {
      final response = await _client
          .from('events')
          .select()
          .gte('event_date', DateTime.now().toIso8601String())
          .order('event_date', ascending: true);
      
      return (response as List).map((e) => KingdomEvent.fromMap(e)).toList();
    } catch (e) {
      // Mock data for demo
      return [
        KingdomEvent(
          id: 'e1',
          title: 'Zambian Apostolic Conference 2026',
          description: 'A gathering of visionary leaders to shape the future of the Kingdom economy.',
          location: 'Mulungushi Conference Centre',
          eventDate: DateTime.now().add(const Duration(days: 15)),
          price: 150.0,
          category: 'Conference',
        ),
        KingdomEvent(
          id: 'e2',
          title: 'Night of Unlimited Grace',
          description: 'Join thousands in a unified night of worship and prophetic manifestations.',
          location: 'National Heroes Stadium',
          eventDate: DateTime.now().add(const Duration(days: 30)),
          price: 0.0,
          category: 'Worship',
        ),
      ];
    }
  }

  Future<void> purchaseTicket(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('tickets').insert({
      'event_id': eventId,
      'user_id': user.id,
      'status': 'valid',
    });
  }
}

final kingdomEventServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return EventService(client);
});

final kingdomUpcomingEventsProvider = FutureProvider<List<KingdomEvent>>((ref) {
  return ref.watch(kingdomEventServiceProvider).fetchUpcomingEvents();
});

