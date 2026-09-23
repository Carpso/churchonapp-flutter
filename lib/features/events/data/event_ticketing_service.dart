import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// Event Ticketing v2 — client service.
///
/// All pricing/capacity/check-in logic is enforced SERVER-SIDE via the RPCs in
/// `20261229_event_ticketing_v2.sql`. This layer only shapes data and calls
/// those RPCs; it never computes a payable amount.
/// ---------------------------------------------------------------------------

class EventTicketTier {
  final String id;
  final String eventId;
  final String name;
  final String? description;
  final double price;
  final int? quantityTotal;
  final int quantitySold;
  final int? remaining;
  final int maxPerOrder;
  final DateTime? salesStart;
  final DateTime? salesEnd;
  final int sortOrder;
  final bool isActive;
  final bool salesOpen;

  const EventTicketTier({
    required this.id,
    required this.eventId,
    required this.name,
    this.description,
    required this.price,
    this.quantityTotal,
    required this.quantitySold,
    this.remaining,
    required this.maxPerOrder,
    this.salesStart,
    this.salesEnd,
    required this.sortOrder,
    required this.isActive,
    required this.salesOpen,
  });

  bool get isSoldOut => remaining != null && remaining! <= 0;

  factory EventTicketTier.fromMap(Map<String, dynamic> m) => EventTicketTier(
        id: m['id'].toString(),
        eventId: m['event_id']?.toString() ?? '',
        name: m['name'] ?? 'General',
        description: m['description'],
        price: (m['price_kwacha'] ?? m['price'] ?? 0).toDouble(),
        quantityTotal: (m['quantity_total'] as num?)?.toInt(),
        quantitySold: (m['quantity_sold'] as num?)?.toInt() ?? 0,
        remaining: (m['remaining'] as num?)?.toInt(),
        maxPerOrder: (m['max_per_order'] as num?)?.toInt() ?? 10,
        salesStart: m['sales_start'] != null ? DateTime.tryParse(m['sales_start'].toString()) : null,
        salesEnd: m['sales_end'] != null ? DateTime.tryParse(m['sales_end'].toString()) : null,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        isActive: m['is_active'] != false,
        salesOpen: m['sales_open'] != false,
      );
}

class TicketInventory {
  final List<EventTicketTier> tiers;
  final int capacity;
  final int sold;
  final int remaining;
  final bool soldOut;
  final int waitlistCount;

  const TicketInventory({
    required this.tiers,
    required this.capacity,
    required this.sold,
    required this.remaining,
    required this.soldOut,
    required this.waitlistCount,
  });

  static const empty = TicketInventory(
    tiers: [],
    capacity: 0,
    sold: 0,
    remaining: 0,
    soldOut: false,
    waitlistCount: 0,
  );

  factory TicketInventory.fromMap(Map<String, dynamic> m) => TicketInventory(
        tiers: ((m['tiers'] as List?) ?? const [])
            .map((t) => EventTicketTier.fromMap(Map<String, dynamic>.from(t as Map)))
            .toList(),
        capacity: (m['capacity'] as num?)?.toInt() ?? 0,
        sold: (m['sold'] as num?)?.toInt() ?? 0,
        remaining: (m['remaining'] as num?)?.toInt() ?? 0,
        soldOut: m['sold_out'] == true,
        waitlistCount: (m['waitlist_count'] as num?)?.toInt() ?? 0,
      );
}

class EventTicket {
  final String id;
  final String orderId;
  final String eventId;
  final String? tierId;
  final String ownerId;
  final String ticketCode;
  final String status; // pending|valid|used|refunded|transferred|cancelled
  final DateTime? checkedInAt;
  final DateTime createdAt;

  // Enriched (nullable — present only on the My Tickets query)
  final String? orderRef;
  final double? unitPrice;
  final String? tierName;
  final String? eventTitle;
  final DateTime? eventDate;
  final String? eventLocation;
  final String? eventImageUrl;

  const EventTicket({
    required this.id,
    required this.orderId,
    required this.eventId,
    this.tierId,
    required this.ownerId,
    required this.ticketCode,
    required this.status,
    this.checkedInAt,
    required this.createdAt,
    this.orderRef,
    this.unitPrice,
    this.tierName,
    this.eventTitle,
    this.eventDate,
    this.eventLocation,
    this.eventImageUrl,
  });

  bool get isValid => status == 'valid';
  bool get isUsed => status == 'used';

  String get qrPayload => '$ticketCode|https://churchonapp.com/ticket/$id';

  factory EventTicket.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic>? tier;
    Map<String, dynamic>? event;
    Map<String, dynamic>? order;
    if (m['event_ticket_tiers'] is Map) {
      tier = Map<String, dynamic>.from(m['event_ticket_tiers'] as Map);
    }
    if (m['events'] is Map) {
      event = Map<String, dynamic>.from(m['events'] as Map);
    }
    if (m['event_ticket_orders'] is Map) {
      order = Map<String, dynamic>.from(m['event_ticket_orders'] as Map);
    }
    return EventTicket(
      id: m['id'].toString(),
      orderId: m['order_id']?.toString() ?? '',
      eventId: m['event_id']?.toString() ?? '',
      tierId: m['tier_id']?.toString(),
      ownerId: m['owner_id']?.toString() ?? '',
      ticketCode: m['ticket_code']?.toString() ?? '',
      status: m['status']?.toString() ?? 'valid',
      checkedInAt: m['checked_in_at'] != null ? DateTime.tryParse(m['checked_in_at'].toString()) : null,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      orderRef: order?['order_ref']?.toString(),
      unitPrice: (order?['unit_price'] as num?)?.toDouble(),
      tierName: tier?['name']?.toString(),
      eventTitle: event?['title']?.toString(),
      eventDate: event?['date'] != null ? DateTime.tryParse(event!['date'].toString()) : null,
      eventLocation: event?['location']?.toString(),
      eventImageUrl: event?['image_url']?.toString(),
    );
  }
}

class TicketValidationResult {
  final String status; // valid | already_used | invalid
  final String message;
  final String? attendeeName;
  final String? ticketCode;

  const TicketValidationResult({
    required this.status,
    required this.message,
    this.attendeeName,
    this.ticketCode,
  });

  bool get isValid => status == 'valid';
  bool get isAlreadyUsed => status == 'already_used';

  factory TicketValidationResult.fromMap(Map<String, dynamic> m) => TicketValidationResult(
        status: m['status']?.toString() ?? 'invalid',
        message: m['message']?.toString() ?? 'Could not validate ticket.',
        attendeeName: m['attendee_name']?.toString(),
        ticketCode: m['ticket_code']?.toString(),
      );
}

class EventTicketingException implements Exception {
  final String code;
  const EventTicketingException(this.code);

  static const _messages = <String, String>{
    'sold_out': 'Sorry, this ticket tier is sold out.',
    'sales_not_started': 'Sales for this tier have not opened yet.',
    'sales_closed': 'Sales for this tier have closed.',
    'tier_inactive': 'This ticket tier is no longer available.',
    'max_per_order_exceeded': 'You selected more tickets than allowed per order.',
    'payment_required': 'A payment reference is required for a paid ticket.',
    'payment_not_found': 'We could not find your payment. Please try again.',
    'payment_failed': 'Your payment did not go through.',
    'not_event_host': 'Only the event host can do that.',
    'already_refunded': 'This ticket was already refunded.',
    'ticket_not_transferable': 'Only a valid ticket can be transferred.',
    'invalid_recipient': 'Choose someone else to receive the ticket.',
    'recipient_not_found': 'That user could not be found.',
  };

  String get message => _messages[code] ?? 'Something went wrong. Please try again.';

  @override
  String toString() => message;
}

class EventTicketingService {
  final SupabaseClient _client;
  EventTicketingService(this._client);

  String _mapError(Object e) {
    final raw = e is PostgrestException ? (e.message) : e.toString();
    for (final key in EventTicketingException._messages.keys) {
      if (raw.contains(key)) return key;
    }
    return 'unknown';
  }

  Future<TicketInventory> fetchInventory(String eventId) async {
    final res = await _client.rpc('get_event_ticket_inventory', params: {'p_event_id': eventId});
    if (res is Map) return TicketInventory.fromMap(Map<String, dynamic>.from(res));
    return TicketInventory.empty;
  }

  Stream<List<EventTicket>> myTicketsStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(const <EventTicket>[]);
    return _client
        .from('event_tickets')
        .stream(primaryKey: ['id'])
        .eq('owner_id', user.id)
        .asyncMap((rows) async {
      if (rows.isEmpty) return <EventTicket>[];
      try {
        final res = await _client
            .from('event_tickets')
            .select('*, event_ticket_tiers(name), events(title, date, location, image_url), event_ticket_orders(order_ref, unit_price)')
            .eq('owner_id', user.id)
            .order('created_at', ascending: false);
        return (res as List)
            .map((r) => EventTicket.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
      } catch (e) {
        debugPrint('myTicketsStream enrich failed: $e');
        return rows.map((r) => EventTicket.fromMap(Map<String, dynamic>.from(r))).toList();
      }
    }).handleError(
      // Realtime subscribe timeouts must stay non-fatal (no uncaught error).
      (e) => debugPrint('myTicketsStream realtime error (non-fatal): $e'),
    );
  }

  Future<List<EventTicketTier>> fetchTiers(String eventId) async {
    final res = await _client
        .from('event_ticket_tiers')
        .select()
        .eq('event_id', eventId)
        .order('sort_order', ascending: true);
    return (res as List).map((r) => EventTicketTier.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Reserves tickets atomically. For paid tiers pass the Lipila `payment_ref`.
  Future<Map<String, dynamic>> reserve({
    required String eventId,
    required String tierId,
    required int quantity,
    String? paymentRef,
  }) async {
    try {
      final res = await _client.rpc('reserve_event_tickets', params: {
        'p_event_id': eventId,
        'p_tier_id': tierId,
        'p_quantity': quantity,
        if (paymentRef != null) 'p_payment_ref': paymentRef,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  Future<TicketValidationResult> validate({required String eventId, required String ticketCode}) async {
    try {
      final res = await _client.rpc('validate_event_ticket', params: {
        'p_event_id': eventId,
        'p_ticket_code': ticketCode,
      });
      return TicketValidationResult.fromMap(res is Map ? Map<String, dynamic>.from(res) : const {});
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  Future<void> refund({required String ticketId, String? reason}) async {
    try {
      await _client.rpc('refund_event_ticket', params: {
        'p_ticket_id': ticketId,
        if (reason != null) 'p_reason': reason,
      });
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  Future<String?> transfer({required String ticketId, required String toUserId}) async {
    try {
      final res = await _client.rpc('transfer_event_ticket', params: {
        'p_ticket_id': ticketId,
        'p_to_user': toUserId,
      });
      if (res is Map) return res['new_ticket_code']?.toString();
      return null;
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  Future<void> joinWaitlist({required String eventId, String? tierId}) async {
    try {
      await _client.rpc('join_event_waitlist', params: {
        'p_event_id': eventId,
        if (tierId != null) 'p_tier_id': tierId,
      });
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  Future<void> cancelEvent({required String eventId, String? reason}) async {
    try {
      await _client.rpc('cancel_event_tickets', params: {
        'p_event_id': eventId,
        if (reason != null) 'p_reason': reason,
      });
    } catch (e) {
      throw EventTicketingException(_mapError(e));
    }
  }

  /// Whether the signed-in user may manage tickets for [eventId].
  Future<bool> isEventHost(String eventId) async {
    try {
      final res = await _client.rpc('is_event_host', params: {'p_event_id': eventId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches a single enriched ticket by id.
  Future<EventTicket?> fetchTicket(String ticketId) async {
    final res = await _client
        .from('event_tickets')
        .select('*, event_ticket_tiers(name), events(title, date, location, image_url), event_ticket_orders(order_ref, unit_price)')
        .eq('id', ticketId)
        .maybeSingle();
    if (res == null) return null;
    return EventTicket.fromMap(Map<String, dynamic>.from(res));
  }

  /// Fetches all tickets belonging to an order.
  Future<List<EventTicket>> fetchOrderTickets(String orderId) async {
    final res = await _client
        .from('event_tickets')
        .select('*, event_ticket_tiers(name), events(title, date, location, image_url), event_ticket_orders(order_ref, unit_price)')
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
    return (res as List)
        .map((r) => EventTicket.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ---- Host tier management -------------------------------------------------

  Future<void> upsertTier({
    String? id,
    required String eventId,
    required String name,
    String? description,
    required double price,
    int? quantityTotal,
    int maxPerOrder = 10,
    DateTime? salesStart,
    DateTime? salesEnd,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    final payload = <String, dynamic>{
      'event_id': eventId,
      'name': name,
      'description': description,
      'price_kwacha': price,
      'quantity_total': quantityTotal,
      'max_per_order': maxPerOrder,
      'sales_start': salesStart?.toIso8601String(),
      'sales_end': salesEnd?.toIso8601String(),
      'sort_order': sortOrder,
      'is_active': isActive,
    };
    if (id == null) {
      await _client.from('event_ticket_tiers').insert(payload);
    } else {
      await _client.from('event_ticket_tiers').update(payload).eq('id', id);
    }
  }

  Future<void> deleteTier(String id) async {
    await _client.from('event_ticket_tiers').delete().eq('id', id);
  }
}

final eventTicketingServiceProvider = Provider((ref) => EventTicketingService(Supabase.instance.client));

final myEventTicketsProvider = StreamProvider<List<EventTicket>>((ref) {
  return ref.watch(eventTicketingServiceProvider).myTicketsStream();
});

final eventTicketInventoryProvider = FutureProvider.family<TicketInventory, String>((ref, eventId) {
  return ref.watch(eventTicketingServiceProvider).fetchInventory(eventId);
});

final eventTicketTiersProvider = FutureProvider.family<List<EventTicketTier>, String>((ref, eventId) {
  return ref.watch(eventTicketingServiceProvider).fetchTiers(eventId);
});

final eventTicketHostProvider = FutureProvider.family<bool, String>((ref, eventId) {
  return ref.watch(eventTicketingServiceProvider).isEventHost(eventId);
});
