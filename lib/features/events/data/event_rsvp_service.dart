import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/code_generator_service.dart';

/// Centralized Event RSVP service using the `event_rsvps` table.
/// Handles RSVP lifecycle: confirm, decline, check-in, QR ticket generation.
class EventRsvpService {
  final SupabaseClient _client;
  final Ref _ref;

  EventRsvpService(this._client, this._ref);

  /// RSVP to an event with optional guest count.
  Future<Map<String, dynamic>> rsvpToEvent({
    required String eventId,
    required String status, // 'confirmed', 'declined'
    int guests = 0,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please login to RSVP');

    // Check capacity
    if (status == 'confirmed') {
      final event = await _client
          .from('events')
          .select('max_attendees, rsvp_enabled')
          .eq('id', eventId)
          .maybeSingle();
      if (event != null) {
        final maxAttendees = event['max_attendees'] as int?;
        if (maxAttendees != null && maxAttendees > 0) {
          final currentCount = await _client
              .from('event_rsvps')
              .select('id')
              .eq('event_id', eventId)
              .inFilter('status', ['confirmed', 'attended'])
              .count(CountOption.exact);
          final count = currentCount.count;
          if (count >= maxAttendees) {
            throw Exception('This event has reached maximum capacity');
          }
        }
      }
    }

    // Upsert RSVP (unique on event_id + user_id)
    final data = await _client
        .from('event_rsvps')
        .upsert(
          {
            'event_id': eventId,
            'user_id': user.id,
            'status': status,
            'guests': guests,
            'notes': notes,
          },
          onConflict: 'event_id,user_id',
        )
        .select()
        .single();

    // Update attendee count on the event
    if (status == 'confirmed') {
      await _refreshAttendeeCount(eventId);
    }

    // Notify user
    final eventData = await _client
        .from('events')
        .select('title, tenant_id')
        .eq('id', eventId)
        .maybeSingle();
    if (eventData != null) {
      await _client.from('notifications').insert({
        'user_id': user.id,
        'tenant_id': eventData['tenant_id'],
        'title':
            status == 'confirmed' ? 'RSVP Confirmed!' : 'RSVP Updated',
        'body': status == 'confirmed'
            ? 'You\'re confirmed for ${eventData['title']}${guests > 0 ? ' (+$guests guests)' : ''}.'
            : 'Your RSVP for ${eventData['title']} has been updated to $status.',
        'type': 'event',
        'reference_id': eventId,
      });
    }

    return data;
  }

  /// Cancel / decline an RSVP.
  Future<void> cancelRsvp(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await _client
        .from('event_rsvps')
        .update({'status': 'declined'})
        .eq('event_id', eventId)
        .eq('user_id', user.id);

    await _refreshAttendeeCount(eventId);
  }

  /// Get current user's RSVP status for an event.
  Future<Map<String, dynamic>?> getMyRsvp(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    return await _client
        .from('event_rsvps')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', user.id)
        .maybeSingle();
  }

  /// Stream all RSVPs for an event (for event hosts).
  Stream<List<Map<String, dynamic>>> getEventAttendeesStream(String eventId) {
    return _client
        .from('event_rsvps')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .order('created_at', ascending: false)
        .asyncMap((rsvps) async {
          if (rsvps.isEmpty) return <Map<String, dynamic>>[];
          final userIds = rsvps.map((r) => r['user_id']).toSet().toList();
          final profiles = await _client
              .from('profiles')
              .select('id, full_name, avatar_url, phone_number')
              .inFilter('id', userIds);

          final profileMap = {
            for (var p in profiles) p['id'] as String: p,
          };

          return rsvps.map((r) {
            final profile = profileMap[r['user_id']];
            return {
              ...r,
              'full_name': profile?['full_name'] ?? 'Unknown',
              'avatar_url': profile?['avatar_url'],
              'phone_number': profile?['phone_number'],
            };
          }).toList();
        });
  }

  /// Get RSVP summary counts for an event.
  Future<Map<String, int>> getRsvpSummary(String eventId) async {
    final rsvps = await _client
        .from('event_rsvps')
        .select('status')
        .eq('event_id', eventId);

    int confirmed = 0;
    int declined = 0;
    int attended = 0;
    int totalGuests = 0;

    for (final r in rsvps) {
      switch (r['status']) {
        case 'confirmed':
          confirmed++;
          break;
        case 'declined':
          declined++;
          break;
        case 'attended':
          attended++;
          break;
      }
    }

    return {
      'confirmed': confirmed,
      'declined': declined,
      'attended': attended,
      'total_guests': totalGuests,
      'total': rsvps.length,
    };
  }

  /// Check in an attendee at the door (scanner or manual).
  Future<void> checkInAttendee({
    required String eventId,
    required String userId,
  }) async {
    await _client
        .from('event_rsvps')
        .update({
          'status': 'attended',
          'checked_in_at': DateTime.now().toIso8601String(),
        })
        .eq('event_id', eventId)
        .eq('user_id', userId);
  }

  /// Generate a QR ticket payload containing both ticket reference string and deep link URL.
  Future<String> generateTicketQr({
    required String eventId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final codeGen = _ref.read(codeGeneratorProvider);
    final ticketRef = await codeGen.generateTicketId();

    // Check if already registered
    final existing = await _client
        .from('event_registrations')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', user.id)
        .maybeSingle();

    final regId = existing != null ? existing['id'] : ticketRef;
    final deepLink = 'https://churchonapp.com/ticket/$regId';
    
    // Combined payload: TicketRef | DeepLink
    return '$ticketRef|$deepLink';
  }

  /// Refresh the `attendee_count` on the events table.
  Future<void> _refreshAttendeeCount(String eventId) async {
    try {
      final countResult = await _client
          .from('event_rsvps')
          .select('id')
          .eq('event_id', eventId)
          .inFilter('status', ['confirmed', 'attended'])
          .count(CountOption.exact);
      await _client
          .from('events')
          .update({'attendee_count': countResult.count})
          .eq('id', eventId);
    } catch (e) {
      debugPrint('Error refreshing attendee count: $e');
    }
  }
}

// ── Providers ──────────────────────────────────────────────────

final eventRsvpServiceProvider = Provider(
  (ref) => EventRsvpService(Supabase.instance.client, ref),
);

final eventAttendeesProvider = StreamProvider.family<
    List<Map<String, dynamic>>, String>(
  (ref, eventId) =>
      ref.watch(eventRsvpServiceProvider).getEventAttendeesStream(eventId),
);

final rsvpSummaryProvider =
    FutureProvider.family<Map<String, int>, String>(
  (ref, eventId) =>
      ref.watch(eventRsvpServiceProvider).getRsvpSummary(eventId),
);
