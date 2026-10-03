import 'package:supabase_flutter/supabase_flutter.dart';

/// One recorded change.
class ChurchAuditEntry {
  final String id;
  final String action;
  final String entityType;
  final DateTime createdAt;
  final String? actorRole;

  /// Only the fields that actually changed, as `{column: {from, to}}`.
  final Map<String, Map<String, String?>> changed;

  const ChurchAuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.actorRole,
    this.changed = const {},
  });

  factory ChurchAuditEntry.fromMap(Map<String, dynamic> m) {
    final raw = m['changed'];
    final parsed = <String, Map<String, String?>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          parsed[k.toString()] = {
            'from': v['from']?.toString(),
            'to': v['to']?.toString(),
          };
        }
      });
    }
    return ChurchAuditEntry(
      id: m['id'].toString(),
      action: m['action']?.toString() ?? 'change',
      entityType: m['entity_type']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
      actorRole: m['actor_role']?.toString(),
      changed: parsed,
    );
  }

  /// e.g. "profiles" -> "Member record"
  String get entityLabel => switch (entityType) {
        'profiles' => 'Member record',
        'member_attendance' => 'Attendance',
        'transactions' => 'Money record',
        'payout_tasks' => 'Payout',
        _ => entityType,
      };

  String get actionLabel => switch (action) {
        'insert_profiles' => 'Member added',
        'update_profiles' => 'Member updated',
        'insert_member_attendance' => 'Attendance marked',
        'update_member_attendance' => 'Attendance corrected',
        'insert_transactions' => 'Money recorded',
        'update_transactions' => 'Money corrected',
        'update_payout_tasks' => 'Payout updated',
        _ => action.replaceAll('_', ' '),
      };
}

/// Reads the tenant-scoped audit trail.
///
/// RLS on `church_audit_log` restricts this to leadership of the owning church,
/// so a pastor sees their own church only and a member sees nothing. Rows are
/// written by database triggers, not by the app, so this screen cannot be
/// spoofed or bypassed by another client.
class ChurchAuditService {
  final SupabaseClient _client;
  ChurchAuditService(this._client);

  Future<List<ChurchAuditEntry>> fetchRecent({
    String? entityType,
    int limit = 100,
  }) async {
    // Filters must be applied before the order/limit transforms, otherwise
    // `.eq` is not available on the transform builder.
    final base = _client.from('church_audit_log').select(
      'id, action, entity_type, actor_role, changed, created_at',
    );
    final filtered =
        entityType == null ? base : base.eq('entity_type', entityType);
    final rows = await filtered
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map((r) => ChurchAuditEntry.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Distinct entity types present, for the filter chips.
  Future<List<String>> fetchEntityTypes() async {
    final rows = await _client.from('church_audit_log').select('entity_type');
    return {for (final r in rows) r['entity_type'].toString()}.toList()..sort();
  }
}