import 'package:flutter/foundation.dart';
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
  final DateTime? endDate;
  final String speakers;
  final String organizerMomoPhone;
  final String organizerMomoName;

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
    this.endDate,
    required this.speakers,
    required this.organizerMomoPhone,
    required this.organizerMomoName,
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
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      speakers: map['speakers'] ?? '',
      organizerMomoPhone: map['organizer_momo_phone'] ?? '',
      organizerMomoName: map['organizer_momo_name'] ?? '',
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
        .map((data) {
          final events = data.map((map) => ChurchEvent.fromMap(map)).toList();
          if (events.isEmpty) {
            return _getMockEvents();
          }
          return events;
        });
  }

  List<ChurchEvent> _getMockEvents() {
    return [
      ChurchEvent(
        id: 'mock-1',
        title: 'National Prayer Day',
        description: 'Join the entire nation in prayer.',
        location: 'National Stadium, Lusaka',
        date: DateTime.now().add(const Duration(days: 10)),
        imageUrl: 'https://images.unsplash.com/photo-1444464666168-49d633b867ad?w=800',
        ticketPrice: 0,
        attendeeCount: 1540,
        category: 'Spiritual',
        speakers: 'Apostolic Council',
        organizerMomoPhone: '0976847775',
        organizerMomoName: 'National Committee',
        endDate: DateTime.now().add(const Duration(days: 10, hours: 4)),
      ),
      ChurchEvent(
        id: 'mock-2',
        title: 'Youth Impact Conference',
        description: 'Empowering the next generation.',
        location: 'Grace Cathedral, Harare',
        date: DateTime.now().add(const Duration(days: 5)),
        imageUrl: 'https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800',
        ticketPrice: 50,
        attendeeCount: 420,
        category: 'Youth',
        speakers: 'Dr. Myles & Team',
        organizerMomoPhone: '0976847775',
        organizerMomoName: 'Grace Youth Treasury',
        endDate: DateTime.now().add(const Duration(days: 5, hours: 3)),
      ),
    ];
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> eventData) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Please login first");

    String dateStr;
    if (eventData['date'] is DateTime) {
      dateStr = (eventData['date'] as DateTime).toIso8601String();
    } else if (eventData['date'] is String) {
      try {
        dateStr = DateTime.parse(eventData['date']).toIso8601String();
      } catch (_) {
        dateStr = eventData['date'];
      }
    } else {
      dateStr = DateTime.now().add(const Duration(days: 7)).toIso8601String();
    }

    final dbData = {
      'title': eventData['title'],
      'description': eventData['description'] ?? 'No description',
      'location': eventData['location'] ?? 'Main Hall',
      'date': dateStr,
      'image_url': eventData['cover'] ?? eventData['image_url'] ?? '',
      'ticket_price': (eventData['price'] ?? eventData['ticket_price'] ?? 0.0).toDouble(),
      'category': eventData['type'] ?? eventData['category'] ?? 'General',
      'created_by': user.id,
      'tenant_id': eventData['tenant_id'],
      'organizer_momo_phone': eventData['organizer_momo_phone'],
      'organizer_momo_name': eventData['organizer_momo_name'],
      'speakers': eventData['speakers'],
      'end_date': eventData['end_date'],
    };

    final result = await _client.from('events').insert(dbData).select().single();
    final eventId = result['id'];

    // Notify church members about new event
    final tenantId = eventData['tenant_id'];
    if (tenantId != null) {
      final members = await _client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId);
      final title = eventData['title'] ?? 'New Event';
      for (final member in members) {
        if (member['id'] != user.id) {
          await _client.from('notifications').insert({
            'user_id': member['id'],
            'tenant_id': tenantId,
            'title': 'New Event: $title',
            'body': 'A new event has been created in your church.',
            'type': 'event',
            'reference_id': eventId,
          });
        }
      }
    }

    _ref.invalidate(eventsStreamProvider);
    return result;
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
      final res = await _client.from('events').select('attendee_count, title, tenant_id').eq('id', eventId).single();
      final current = res['attendee_count'] ?? 0;
      await _client.from('events').update({'attendee_count': current + 1}).eq('id', eventId);

      // Notify user about registration
      final title = res['title'] ?? 'Event';
      await _client.from('notifications').insert({
        'user_id': user.id,
        'tenant_id': res['tenant_id'],
        'title': 'Registered: $title',
        'body': 'You have successfully registered for $title.',
        'type': 'event',
        'reference_id': eventId,
      });

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

  Future<Map<String, dynamic>?> getEventById(String eventId) async {
    try {
      final res = await _client.from('events').select().eq('id', eventId).maybeSingle();
      if (res != null) {
        return {
          ...res,
          'cover': res['image_url'] ?? 'https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800',
          'price': (res['ticket_price'] ?? 0).toDouble(),
        };
      }
    } catch (e) {
      debugPrint("Error fetching event by ID: $e");
    }
    return null;
  }
}

final eventServiceProvider = Provider((ref) => EventService(Supabase.instance.client, ref));

final eventsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getEventsStream();
});

final myTicketsStreamProvider = StreamProvider<List<ChurchEvent>>((ref) {
  return ref.watch(eventServiceProvider).getMyTicketsStream();
});

