import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BibleStudy {
  final String id;
  final String tenantId;
  final String title;
  final String description;
  final DateTime date;
  final String time;
  final String leader;
  final String location;
  final String? materialsUrl;
  final int maxAttendees;
  final int currentAttendees;
  final String status;
  final DateTime createdAt;

  BibleStudy({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.leader,
    required this.location,
    this.materialsUrl,
    this.maxAttendees = 0,
    this.currentAttendees = 0,
    this.status = 'scheduled',
    required this.createdAt,
  });

  factory BibleStudy.fromMap(Map<String, dynamic> map) {
    return BibleStudy(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      time: map['time']?.toString() ?? '',
      leader: map['leader']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      materialsUrl: map['materials_url']?.toString(),
      maxAttendees: int.tryParse(map['max_attendees']?.toString() ?? '0') ?? 0,
      currentAttendees: int.tryParse(map['current_attendees']?.toString() ?? '0') ?? 0,
      status: map['status']?.toString() ?? 'scheduled',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'time': time,
      'leader': leader,
      'location': location,
      'materials_url': materialsUrl,
      'max_attendees': maxAttendees,
      'current_attendees': currentAttendees,
      'status': status,
    };
  }

  BibleStudy copyWith({
    String? id,
    String? tenantId,
    String? title,
    String? description,
    DateTime? date,
    String? time,
    String? leader,
    String? location,
    String? materialsUrl,
    int? maxAttendees,
    int? currentAttendees,
    String? status,
    DateTime? createdAt,
  }) {
    return BibleStudy(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      leader: leader ?? this.leader,
      location: location ?? this.location,
      materialsUrl: materialsUrl ?? this.materialsUrl,
      maxAttendees: maxAttendees ?? this.maxAttendees,
      currentAttendees: currentAttendees ?? this.currentAttendees,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class BibleStudyAttendance {
  final String id;
  final String studyId;
  final String userId;
  final String userName;
  final bool attended;
  final String? notes;
  final DateTime createdAt;

  BibleStudyAttendance({
    required this.id,
    required this.studyId,
    required this.userId,
    required this.userName,
    this.attended = false,
    this.notes,
    required this.createdAt,
  });

  factory BibleStudyAttendance.fromMap(Map<String, dynamic> map) {
    return BibleStudyAttendance(
      id: map['id']?.toString() ?? '',
      studyId: map['study_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? '',
      attended: map['attended'] == true,
      notes: map['notes']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class BibleStudyService {
  final SupabaseClient _client;

  BibleStudyService(this._client);

  Future<List<BibleStudy>> getStudies(String tenantId) async {
    try {
      final res = await _client
          .from('bible_studies')
          .select()
          .eq('tenant_id', tenantId)
          .order('date', ascending: false);
      return (res as List).map((map) => BibleStudy.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error fetching Bible studies: $e');
      return [];
    }
  }

  Future<List<BibleStudy>> getUpcomingStudies(String tenantId) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final res = await _client
          .from('bible_studies')
          .select()
          .eq('tenant_id', tenantId)
          .gte('date', today)
          .neq('status', 'cancelled')
          .order('date', ascending: true);
      return (res as List).map((map) => BibleStudy.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error fetching upcoming Bible studies: $e');
      return [];
    }
  }

  Future<BibleStudy> createStudy({
    required String tenantId,
    required String title,
    required String description,
    required DateTime date,
    required String time,
    required String leader,
    required String location,
    String? materialsUrl,
    int maxAttendees = 0,
  }) async {
    final data = {
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'time': time,
      'leader': leader,
      'location': location,
      'materials_url': materialsUrl,
      'max_attendees': maxAttendees,
      'current_attendees': 0,
      'status': 'scheduled',
    };

    final res = await _client
        .from('bible_studies')
        .insert(data)
        .select()
        .single();
    final study = BibleStudy.fromMap(res);
    unawaited(notifyStudyCreated(
      study.id, study.tenantId, study.title,
      study.date.toIso8601String().split('T').first, study.time,
    ));
    return study;
  }

  Future<BibleStudy> updateStudy({
    required String id,
    String? title,
    String? description,
    DateTime? date,
    String? time,
    String? leader,
    String? location,
    String? materialsUrl,
    int? maxAttendees,
    String? status,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (date != null) data['date'] = date.toIso8601String();
    if (time != null) data['time'] = time;
    if (leader != null) data['leader'] = leader;
    if (location != null) data['location'] = location;
    if (materialsUrl != null) data['materials_url'] = materialsUrl;
    if (maxAttendees != null) data['max_attendees'] = maxAttendees;
    if (status != null) data['status'] = status;

    final res = await _client
        .from('bible_studies')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return BibleStudy.fromMap(res);
  }

  Future<void> deleteStudy(String id) async {
    await _client.from('bible_studies').delete().eq('id', id);
  }

  Future<void> attendStudy(String studyId, String userId, String userName) async {
    final existing = await _client
        .from('bible_study_attendance')
        .select('id')
        .eq('study_id', studyId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('bible_study_attendance')
          .update({'attended': true})
          .eq('id', existing['id']);
      return;
    }

    await _client.from('bible_study_attendance').insert({
      'study_id': studyId,
      'user_id': userId,
      'user_name': userName,
      'attended': true,
    });

    await _client.rpc('increment_study_attendees', params: {'study_id': studyId});
  }

  Future<List<BibleStudyAttendance>> getAttendance(String studyId) async {
    try {
      final res = await _client
          .from('bible_study_attendance')
          .select()
          .eq('study_id', studyId)
          .order('created_at', ascending: false);
      return (res as List).map((map) => BibleStudyAttendance.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      return [];
    }
  }

  Future<void> notifyStudyCreated(String studyId, String tenantId, String title, String studyDate, String studyTime) async {
    try {
      final members = await _client
          .from('profiles')
          .select('id')
          .eq('tenant_id', tenantId);

      if ((members as List).isNotEmpty) {
        final userIds = (members).map((m) => m['id'] as String).toList();
        await _client.functions.invoke('push-notifications', body: {
          'userIds': userIds,
          'title': '📖 New Bible Study',
          'body': '$title - $studyDate at $studyTime',
          'data': {
            'type': 'bible_study',
            'reference_id': studyId,
            'channel_id': 'coa_announcements',
          },
        });
      }
    } catch (e) {
      debugPrint('[BibleStudy] Push notification failed: $e');
    }
  }

  Future<void> notifyStudyReminder(String userId, String studyId, String title, String studyDate, String studyTime) async {
    try {
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': '⏰ Bible Study Reminder',
        'body': '$title starts $studyDate at $studyTime',
        'data': {
          'type': 'bible_study',
          'reference_id': studyId,
          'channel_id': 'coa_events',
        },
      });
    } catch (e) {
      debugPrint('[BibleStudy] Reminder push failed: $e');
    }
  }

  Future<void> updateAttendance(String id, {bool? attended, String? notes}) async {
    final data = <String, dynamic>{};
    if (attended != null) data['attended'] = attended;
    if (notes != null) data['notes'] = notes;

    await _client.from('bible_study_attendance').update(data).eq('id', id);
  }

  Stream<List<BibleStudy>> streamStudies(String tenantId) {
    return _client
        .from('bible_studies')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('date', ascending: false)
        .map((maps) => maps.map((map) => BibleStudy.fromMap(map)).toList());
  }
}
