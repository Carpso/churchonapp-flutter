import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The progression a person moves through in a Pentecostal / charismatic
/// church, and the one most Zambian churches actually keep.
enum MemberClass {
  visitor('visitor', 'Visitor'),
  convert('convert', 'Convert'),
  righteousMember('righteous_member', 'Righteous Member'),
  worker('worker', 'Worker');

  const MemberClass(this.id, this.label);
  final String id;
  final String label;

  static MemberClass parse(String? v) => MemberClass.values
      .firstWhere((c) => c.id == v, orElse: () => MemberClass.convert);
}

/// Formal and pastoral steps. Ordered from lightest to heaviest.
enum CareCategory {
  counselling('counselling', 'Counselling', Icons.support_agent, Colors.teal),
  warning('warning', 'Warning', Icons.warning_amber, Colors.orange),
  suspension('suspension', 'Suspension', Icons.pause_circle, Colors.deepOrange),
  excommunication('excommunication', 'Excommunication', Icons.block, Colors.red),
  restoration('restoration', 'Restoration', Icons.favorite, Colors.green);

  const CareCategory(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  static CareCategory parse(String? v) => CareCategory.values
      .firstWhere((c) => c.id == v, orElse: () => CareCategory.counselling);
}

enum CareStatus {
  open('open', 'Open'),
  resolved('resolved', 'Resolved'),
  appealed('appealed', 'Appealed'),
  restored('restored', 'Restored');

  const CareStatus(this.id, this.label);
  final String id;
  final String label;

  static CareStatus parse(String? v) => CareStatus.values
      .firstWhere((s) => s.id == v, orElse: () => CareStatus.open);
}

@immutable
class MemberClassRecord {
  final String id;
  final String memberId;
  final String? memberName;
  final MemberClass memberClass;
  final int? convertStage;
  final DateTime classDate;
  final String? notes;

  const MemberClassRecord({
    required this.id,
    required this.memberId,
    this.memberName,
    required this.memberClass,
    this.convertStage,
    required this.classDate,
    this.notes,
  });

  factory MemberClassRecord.fromMap(Map<String, dynamic> m) => MemberClassRecord(
        id: m['id'].toString(),
        memberId: m['member_id']?.toString() ?? '',
        memberName: m['member_name']?.toString(),
        memberClass: MemberClass.parse(m['class']?.toString()),
        convertStage: (m['convert_stage'] as num?)?.toInt(),
        classDate:
            DateTime.tryParse(m['class_date']?.toString() ?? '') ?? DateTime.now(),
        notes: m['notes']?.toString(),
      );

  String get label {
    if (memberClass == MemberClass.convert && convertStage != null) {
      return '${memberClass.label} (${convertStage == 1 ? '1st' : '2nd'} class)';
    }
    return memberClass.label;
  }
}

@immutable
class CareRecord {
  final String id;
  final String memberId;
  final String? memberName;
  final CareCategory category;
  final String severity;
  final DateTime incidentDate;
  final String summary;
  final String? actionTaken;
  final CareStatus status;
  final String? notes;

  const CareRecord({
    required this.id,
    required this.memberId,
    this.memberName,
    required this.category,
    required this.severity,
    required this.incidentDate,
    required this.summary,
    this.actionTaken,
    required this.status,
    this.notes,
  });

  factory CareRecord.fromMap(Map<String, dynamic> m) => CareRecord(
        id: m['id'].toString(),
        memberId: m['member_id']?.toString() ?? '',
        memberName: m['member_name']?.toString(),
        category: CareCategory.parse(m['category']?.toString()),
        severity: m['severity']?.toString() ?? 'pastoral',
        incidentDate:
            DateTime.tryParse(m['incident_date']?.toString() ?? '') ?? DateTime.now(),
        summary: m['summary']?.toString() ?? '',
        actionTaken: m['action_taken']?.toString(),
        status: CareStatus.parse(m['status']?.toString()),
        notes: m['notes']?.toString(),
      );

  bool get isOpen => status == CareStatus.open;

  String get severityLabel => switch (severity) {
        'serious' => 'Serious',
        'formal' => 'Formal',
        _ => 'Pastoral',
      };
}

class RegisterException implements Exception {
  final String message;
  const RegisterException(this.message);
  @override
  String toString() => message;
}

/// Reads and writes the membership-class and pastoral-care registers.
///
/// Both are leadership-only in RLS. Writes go through RPCs so the actor is
/// always recorded and the rules live in one place - a client cannot bypass the
/// pastoral-care restriction on discipline.
class ChurchRegistersService {
  final SupabaseClient _client;
  ChurchRegistersService(this._client);

  // ---------------------------------------------------------------- classes

  /// Current class per member, newest first, with names resolved.
  Future<List<MemberClassRecord>> fetchClasses(String tenantId) async {
    final rows = await _client
        .from('member_classes')
        .select('id, member_id, class, convert_stage, class_date, notes')
        .eq('tenant_id', tenantId)
        .order('class_date', ascending: false)
        .limit(300);
    return _withNames(
      rows,
      (m) => MemberClassRecord.fromMap(m),
      (m) => m['member_id']?.toString() ?? '',
    );
  }

  /// Headcount per class - the number a church is actually measured on.
  Future<Map<MemberClass, int>> classCounts(String tenantId) async {
    final rows = await _client
        .from('member_classes')
        .select('class')
        .eq('tenant_id', tenantId)
        .limit(2000);
    final out = <MemberClass, int>{};
    for (final r in rows) {
      final c = MemberClass.parse(r['class']?.toString());
      out[c] = (out[c] ?? 0) + 1;
    }
    return out;
  }

  Future<MemberClassRecord> setClass({
    required String memberId,
    required MemberClass memberClass,
    int? convertStage,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('set_member_class', params: {
        'p_member_id': memberId,
        'p_class': memberClass.id,
        'p_convert_stage': convertStage,
        'p_notes': notes,
      });
      return MemberClassRecord.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw RegisterException(_readable(e));
    }
  }

  // ------------------------------------------------------------- pastoral care

  Future<List<CareRecord>> fetchCareRecords(String tenantId) async {
    final rows = await _client
        .from('discipline_records')
        .select(
          'id, member_id, category, severity, incident_date, summary, '
          'action_taken, status, notes',
        )
        .eq('tenant_id', tenantId)
        .order('incident_date', ascending: false)
        .limit(300);
    return _withNames(
      rows,
      (m) => CareRecord.fromMap(m),
      (m) => m['member_id']?.toString() ?? '',
    );
  }

  Future<CareRecord> recordCare({
    required String memberId,
    required CareCategory category,
    required String summary,
    String severity = 'pastoral',
    String? actionTaken,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('record_discipline', params: {
        'p_member_id': memberId,
        'p_category': category.id,
        'p_summary': summary,
        'p_severity': severity,
        'p_action_taken': actionTaken,
        'p_notes': notes,
      });
      return CareRecord.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw RegisterException(_readable(e));
    }
  }

  Future<CareRecord> resolveCare({
    required String recordId,
    required CareStatus status,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('resolve_discipline', params: {
        'p_record_id': recordId,
        'p_status': status.id,
        'p_notes': notes,
      });
      return CareRecord.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw RegisterException(_readable(e));
    }
  }

  /// Members of this church, for the picker.
  Future<List<Map<String, dynamic>>> fetchMembers(String tenantId) async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, phone_number')
        .eq('tenant_id', tenantId)
        .order('full_name')
        .limit(400);
    return rows;
  }

  /// Attaches member names to records that only carry member_id.
  Future<List<T>> _withNames<T>(
    List<dynamic> rows,
    T Function(Map<String, dynamic>) build,
    String Function(Map<String, dynamic>) memberIdOf,
  ) async {
    if (rows.isEmpty) return [];
    final ids = {for (final r in rows) memberIdOf(Map<String, dynamic>.from(r))}
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return [for (final r in rows) build(Map<String, dynamic>.from(r))];
    }
    final people = await _client
        .from('profiles')
        .select('id, full_name')
        .inFilter('id', ids);
    final names = {
      for (final p in people) p['id'].toString(): p['full_name']?.toString(),
    };

    return [
      for (final r in rows)
        () {
          final m = Map<String, dynamic>.from(r);
          m['member_name'] = names[memberIdOf(m)];
          return build(m);
        }(),
    ];
  }

  String _readable(Object e) {
    final s = e.toString();
    if (s.contains('pastoral leadership')) {
      return 'Only pastoral leadership (pastor, bishop or admin) can do this.';
    }
    if (s.contains('only church leadership')) {
      return 'Only church leadership can do this.';
    }
    if (s.contains('summary is required')) {
      return 'Please write a short summary of what happened.';
    }
    if (s.contains('unknown class') || s.contains('unknown category')) {
      return 'That option is not valid.';
    }
    if (s.contains('not authenticated')) {
      return 'Your session expired. Sign in and try again.';
    }
    return 'Could not save. Please try again.';
  }
}