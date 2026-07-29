import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlannerEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime eventDate;
  final String color;
  final String category;
  final bool isRecurring;
  final String? recurringPattern;
  final DateTime? endDate;
  final List<int>? recurringDaysOfWeek;
  final int? recurringDayOfMonth;
  final int? recurringMonthOfYear;
  final int? reminderMinutes;
  final String? location;
  final String? linkUrl;
  final String? tenantId;
  final String? userId;

  PlannerEvent({
    required this.id,
    required this.title,
    this.description,
    required this.eventDate,
    this.color = '#FFD700',
    this.category = 'general',
    this.isRecurring = false,
    this.recurringPattern,
    this.endDate,
    this.recurringDaysOfWeek,
    this.recurringDayOfMonth,
    this.recurringMonthOfYear,
    this.reminderMinutes,
    this.location,
    this.linkUrl,
    this.tenantId,
    this.userId,
  });

  factory PlannerEvent.fromMap(Map<String, dynamic> map) {
    return PlannerEvent(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? '',
      description: map['description'],
      eventDate: DateTime.tryParse(map['event_date']?.toString() ?? '') ?? DateTime.now(),
      color: map['color'] ?? '#FFD700',
      category: map['category'] ?? 'general',
      isRecurring: map['is_recurring'] ?? false,
      recurringPattern: map['recurring_pattern'],
      endDate: map['end_date'] != null ? DateTime.tryParse(map['end_date']) : null,
      recurringDaysOfWeek: map['recurring_days_of_week'] != null
          ? (map['recurring_days_of_week'] as List).cast<int>()
          : null,
      recurringDayOfMonth: map['recurring_day_of_month'],
      recurringMonthOfYear: map['recurring_month_of_year'],
      reminderMinutes: map['reminder_minutes'],
      location: map['location'],
      linkUrl: map['link_url'],
      tenantId: map['tenant_id'],
      userId: map['user_id'],
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'event_date': eventDate.toIso8601String().split('T')[0],
    'color': color,
    'category': category,
    'is_recurring': isRecurring,
    'recurring_pattern': recurringPattern,
    'end_date': endDate?.toIso8601String().split('T')[0],
    'recurring_days_of_week': recurringDaysOfWeek,
    'recurring_day_of_month': recurringDayOfMonth,
    'recurring_month_of_year': recurringMonthOfYear,
    'reminder_minutes': reminderMinutes,
    'location': location,
    'link_url': linkUrl,
    'tenant_id': tenantId,
    'user_id': userId,
  };
}

class PlannerService {
  final SupabaseClient _client;
  PlannerService(this._client);

  Stream<List<PlannerEvent>> getPlannerStream({String? tenantId, required String userId}) {
    return _client
        .from('year_planner')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('event_date', ascending: true)
        .map((data) => data.map((m) => PlannerEvent.fromMap(m)).toList());
  }

  Future<List<PlannerEvent>> fetchByMonth({required int year, required int month, String? tenantId, required String userId}) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];

    final userEvents = await _client
        .from('year_planner')
        .select()
        .eq('user_id', userId)
        .gte('event_date', startStr)
        .lte('event_date', endStr)
        .order('event_date', ascending: true);

    final tenantEvents = tenantId != null
        ? await _client
            .from('year_planner')
            .select()
            .eq('tenant_id', tenantId)
            .gte('event_date', startStr)
            .lte('event_date', endStr)
            .order('event_date', ascending: true)
        : <dynamic>[];

    final all = [
      ...(userEvents as List).map((m) => PlannerEvent.fromMap(m)),
      ...tenantEvents.map((m) => PlannerEvent.fromMap(m)),
    ];

    all.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    return all;
  }

  Future<void> addEvent(PlannerEvent event) async {
    await _client.from('year_planner').insert(event.toMap());
  }

  Future<void> updateEvent(String id, Map<String, dynamic> updates) async {
    await _client.from('year_planner').update(updates).eq('id', id);
  }

  Future<void> deleteEvent(String id) async {
    await _client.from('year_planner').delete().eq('id', id);
  }

  Future<void> notifyEventReminder(String userId, String eventId, String title, String date) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': '📅 Event Reminder',
        'body': '$title is coming up on $date',
        'data': {
          'type': 'event',
          'reference_id': eventId,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[PlannerService] Event reminder push failed: $e');
    }
  }

  Future<void> notifyEventShared(String userId, String eventId, String title, String sharedBy) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': '📅 Event Shared With You',
        'body': '$sharedBy shared "$title" with you',
        'data': {
          'type': 'event',
          'reference_id': eventId,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[PlannerService] Event shared push failed: $e');
    }
  }
}

final plannerServiceProvider = Provider((ref) => PlannerService(Supabase.instance.client));

final plannerEventsProvider = FutureProvider.family<List<PlannerEvent>, Map<String, dynamic>>((ref, params) {
  return ref.watch(plannerServiceProvider).fetchByMonth(
    year: params['year'] as int,
    month: params['month'] as int,
    tenantId: params['tenantId'] as String?,
    userId: params['userId'] as String,
  );
});
