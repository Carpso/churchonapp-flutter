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
  final Ref _ref;
  EventService(this._client, this._ref);

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

    final dbData = {
      'title': eventData['title'],
      'description': eventData['description'] ?? 'No description',
      'location': eventData['location'] ?? 'Main Hall',
      'date': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      'image_url': eventData['cover'] ?? eventData['image_url'],
      'ticket_price': (eventData['price'] ?? eventData['ticket_price'] ?? 0.0).toDouble(),
      'category': eventData['type'] ?? eventData['category'] ?? 'General',
      'created_by': user.id,
      'tenant_id': eventData['tenant_id'],
    };

    await _client.from('events').insert(dbData);
    _ref.invalidate(eventsStreamProvider);
  }

  Future<void> registerForEvent(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Please login to register");

    try {
      await _client.from('event_registrations').upsert({
        'event_id': eventId,
        'user_id': user.id,
      });

      // Update attendee count
      final res = await _client.from('events').select('attendee_count').eq('id', eventId).single();
      final current = res['attendee_count'] ?? 0;
      await _client.from('events').update({'attendee_count': current + 1}).eq('id', eventId);
      
      _ref.invalidate(myTicketsStreamProvider);
    } catch (e) {
      if (e.toString().contains('22023')) {
        throw Exception("Registration failed: Invalid user session or profile role missing.");
      }
      rethrow;
    }
  }

  Stream<List<ChurchEvent>> getMyTicketsStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value([]);

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
}

final eventServiceProvider = Provider((ref) => EventService(Supabase.instance.client, ref));

final eventsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getEventsStream();
});

final myTicketsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getMyTicketsStream();
});

