import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class MinistryScheduleEntry {
  final String id;
  final String ministryName;
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay? endTime;
  final String location;
  final String leader;
  final String? notes;
  final String recurrence;

  MinistryScheduleEntry({
    required this.id,
    required this.ministryName,
    required this.date,
    required this.time,
    this.endTime,
    required this.location,
    required this.leader,
    this.notes,
    this.recurrence = 'none',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ministry_name': ministryName,
        'scheduled_for': date.toIso8601String().substring(0, 10),
        'start_time': _timeToString(time),
'end_time': endTime != null ? _timeToString(endTime!) : null,
        'location': location,
        'leader': leader,
        'notes': notes,
        'recurrence': recurrence,
      };

  factory MinistryScheduleEntry.fromJson(Map<String, dynamic> json) => MinistryScheduleEntry(
        id: (json['id'] ?? '').toString(),
        ministryName: (json['ministry_name'] ?? '') as String,
        date: DateTime.parse((json['scheduled_for'] ?? DateTime.now().toIso8601String().substring(0, 10)) as String),
        time: _parseTime(json['start_time']),
        endTime: json['end_time'] != null ? _parseTime(json['end_time']) : null,
        location: (json['location'] ?? '') as String? ?? '',
        leader: (json['leader'] ?? '') as String? ?? '',
        notes: json['notes'] as String?,
        recurrence: (json['recurrence'] ?? 'none') as String,
      );
}

String _timeToString(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

TimeOfDay _parseTime(dynamic value, [TimeOfDay fallback = const TimeOfDay(hour: 9, minute: 0)]) {
  if (value == null) return fallback;
  if (value is int) return TimeOfDay(hour: value ~/ 60, minute: value % 60);
  final parts = value.toString().split(':');
  if (parts.length < 2) return fallback;
  final hour = int.tryParse(parts[0]) ?? fallback.hour;
  final minute = int.tryParse(parts[1]) ?? fallback.minute;
  return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
}

class MinistryScheduleService {
  final SupabaseClient _client;
  MinistryScheduleService(this._client);

  String get _userId {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    return user.id;
  }

  /// Fetch all ministry schedules for the given tenant within [month] (bounded).
  Future<List<MinistryScheduleEntry>> fetchForMonth(String tenantId, DateTime month) async {
    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      final res = await _client
          .from('ministry_schedules')
          .select()
          .eq('tenant_id', tenantId)
          .gte('scheduled_for', start.toIso8601String().substring(0, 10))
          .lt('scheduled_for', end.toIso8601String().substring(0, 10))
          .order('scheduled_for', ascending: false);
      return (res as List).map((e) => MinistryScheduleEntry.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e, s) {
      debugPrint('fetchForMonth error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  Future<MinistryScheduleEntry?> create({
    required String tenantId,
    required String ministryName,
    required DateTime date,
    required TimeOfDay time,
    TimeOfDay? endTime,
    String location = '',
    String leader = '',
    String? notes,
    String recurrence = 'none',
  }) async {
    final id = const Uuid().v4();
    final payload = {
      'id': id,
      'tenant_id': tenantId,
      'ministry_name': ministryName,
      'scheduled_for': date.toIso8601String().substring(0, 10),
      'start_time': _timeToString(time),
      'end_time': endTime != null ? _timeToString(endTime) : null,
      'location': location,
      'leader': leader,
      'notes': notes,
      'recurrence': recurrence,
      'created_by': _userId,
    };
    final res = await _client.from('ministry_schedules').insert(payload).select().maybeSingle();
    return res != null ? MinistryScheduleEntry.fromJson(Map<String, dynamic>.from(res)) : null;
  }

  Future<void> update(String id, {
    String? ministryName,
    DateTime? date,
    TimeOfDay? time,
    TimeOfDay? endTime,
    String? location,
    String? leader,
    String? notes,
    String? recurrence,
  }) async {
    final payload = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (ministryName != null) payload['ministry_name'] = ministryName;
    if (date != null) payload['scheduled_for'] = date.toIso8601String().substring(0, 10);
    if (time != null) payload['start_time'] = _timeToString(time);
    if (endTime != null) payload['end_time'] = _timeToString(endTime);
    if (location != null) payload['location'] = location;
    if (leader != null) payload['leader'] = leader;
    if (notes != null) payload['notes'] = notes;
    if (recurrence != null) payload['recurrence'] = recurrence;
    await _client.from('ministry_schedules').update(payload).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('ministry_schedules').delete().eq('id', id);
  }
}

final ministryScheduleServiceProvider = Provider<MinistryScheduleService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return MinistryScheduleService(client);
});

/// Month-scoped, tenant-scoped provider. Bounded to one month for mega-church scale.
final ministryScheduleMonthProvider = FutureProvider.autoDispose.family<List<MinistryScheduleEntry>, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length != 3) return [];
  final tenantId = parts[0];
  final year = int.parse(parts[1]);
  final month = int.parse(parts[2]);
  final service = ref.watch(ministryScheduleServiceProvider);
  return service.fetchForMonth(tenantId, DateTime(year, month, 1));
});

/// Convenience key builder.
String ministryMonthKey(String tenantId, DateTime month) => '$tenantId|${month.year}|${month.month}';
