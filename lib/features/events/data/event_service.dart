import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChurchEvent {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime date;
  final String imageUrl;
  final double ticketPrice;
  final int attendeeCount;
  final String category;

  ChurchEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    required this.imageUrl,
    required this.ticketPrice,
    required this.attendeeCount,
    required this.category,
  });

  factory ChurchEvent.fromMap(Map<String, dynamic> map) {
    return ChurchEvent(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      location: map['location'] ?? '',
      date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
      imageUrl: map['image_url'] ?? '',
      ticketPrice: (map['ticket_price'] ?? 0).toDouble(),
      attendeeCount: map['attendee_count'] ?? 0,
      category: map['category'] ?? 'General',
    );
  }
}

class EventService {
  final SupabaseClient _client;
  EventService(this._client);

  Stream<List<ChurchEvent>> getEventsStream() {
    return _client
        .from('events')
        .stream(primaryKey: ['id'])
        .order('date', ascending: true)
        .map((data) => data.map((map) => ChurchEvent.fromMap(map)).toList());
  }

  Future<void> createEvent(Map<String, dynamic> eventData) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('events').insert({
      ...eventData,
      'created_by': user.id,
      'attendee_count': 0,
    });
  }

  Future<void> registerForEvent(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // Insert into event_registrations junction table
    await _client.from('event_registrations').upsert({
      'event_id': eventId,
      'user_id': user.id,
    });

    // Increment count on event (or better: use a trigger in DB)
    final currentCount = await _getAttendeeCount(eventId);
    await _client.from('events').update({
      'attendee_count': currentCount + 1
    }).eq('id', eventId);
  }

  Stream<List<ChurchEvent>> getMyTicketsStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value([]);

    // This requires a join or complex query. For now, assuming event_registrations has event details or 
    // we use rpc. Let's simplify and just fetch events where the user is in event_registrations.
    // Simplifying for mock/real hybrid:
    return _client
        .from('event_registrations')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .asyncMap((data) async {
           if (data.isEmpty) return [];
           final eventIds = data.map((e) => e['event_id']).toList();
           final res = await _client.from('events').select().inFilter('id', eventIds);
           return (res as List).map((e) => ChurchEvent.fromMap(e)).toList();
        });
  }

  Future<int> _getAttendeeCount(String eventId) async {
     final res = await _client.from('events').select('attendee_count').eq('id', eventId).single();
     return res['attendee_count'] ?? 0;
  }
}

final eventServiceProvider = Provider((ref) => EventService(Supabase.instance.client));

final eventsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getEventsStream();
});

final myTicketsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getMyTicketsStream();
});
