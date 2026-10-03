import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One custom field in a conference's report template.
@immutable
class ReportFieldDef {
  final String key;
  final String label;
  final String type; // text | number | textarea | date | boolean | select
  final bool required;
  final List<String> options;

  const ReportFieldDef({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.options = const [],
  });

  factory ReportFieldDef.fromJson(Map<String, dynamic> j) => ReportFieldDef(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        type: j['type']?.toString() ?? 'text',
        required: j['required'] == true,
        options: [
          for (final o in (j['options'] as List? ?? const [])) o.toString(),
        ],
      );

  bool get isNumeric => type == 'number';
  bool get isLong => type == 'textarea';
}

/// A conference's form definition. Lives in `report_templates.field_schema` so a
/// conference can add questions without an app release.
@immutable
class ReportTemplate {
  final String id;
  final String reportType; // monthly | quarterly
  final String name;
  final String? description;
  final List<ReportFieldDef> fields;
  final double remittanceRate;
  final bool includeFinancials;

  const ReportTemplate({
    required this.id,
    required this.reportType,
    required this.name,
    this.description,
    this.fields = const [],
    this.remittanceRate = 0.10,
    this.includeFinancials = true,
  });

  factory ReportTemplate.fromMap(Map<String, dynamic> m) {
    final schema = m['field_schema'];
    final list = schema is List
        ? schema
            .whereType<Map>()
            .map((e) => ReportFieldDef.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ReportFieldDef>[];
    return ReportTemplate(
      id: m['id'].toString(),
      reportType: m['report_type']?.toString() ?? 'monthly',
      name: m['name']?.toString() ?? 'Return',
      description: m['description']?.toString(),
      fields: list,
      remittanceRate:
          double.tryParse(m['remittance_rate']?.toString() ?? '') ?? 0.10,
      includeFinancials: m['include_financials'] != false,
    );
  }
}

enum ReportStatus {
  draft('draft', 'Draft', Icons.edit_note, Colors.grey),
  submitted('submitted', 'With pastor', Icons.send, Colors.orange),
  returned('returned', 'Needs correction', Icons.replay, Colors.red),
  approved('approved', 'Approved', Icons.verified, Colors.green),
  submittedHq('submitted_hq', 'At HQ', Icons.cloud_upload, Colors.blue),
  acknowledged('acknowledged', 'Acknowledged', Icons.verified_user, Colors.teal);

  const ReportStatus(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  static ReportStatus parse(String? v) => ReportStatus.values
      .firstWhere((s) => s.id == v, orElse: () => ReportStatus.draft);
}

@immutable
class ReportSubmission {
  final String id;
  final String tenantId;
  final String? tenantName;
  final String? organizationId;
  final String reportType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodLabel;
  final ReportStatus status;
  final Map<String, dynamic> data;
  final double titheTotal;
  final double offeringTotal;
  final double otherIncomeTotal;
  final int attendanceTotal;
  final int newMembers;
  final int baptisms;
  final int salvations;
  final String? narrative;
  final String? reviewNote;

  const ReportSubmission({
    required this.id,
    required this.tenantId,
    this.tenantName,
    this.organizationId,
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    required this.status,
    this.data = const {},
    this.titheTotal = 0,
    this.offeringTotal = 0,
    this.otherIncomeTotal = 0,
    this.attendanceTotal = 0,
    this.newMembers = 0,
    this.baptisms = 0,
    this.salvations = 0,
    this.narrative,
    this.reviewNote,
  });

  factory ReportSubmission.fromMap(Map<String, dynamic> m) {
    final raw = m['data'];
    return ReportSubmission(
      id: m['id'].toString(),
      tenantId: m['tenant_id']?.toString() ?? '',
      tenantName: m['tenant_name']?.toString(),
      organizationId: m['organization_id']?.toString(),
      reportType: m['report_type']?.toString() ?? 'monthly',
      periodStart:
          DateTime.tryParse(m['period_start']?.toString() ?? '') ?? DateTime.now(),
      periodEnd:
          DateTime.tryParse(m['period_end']?.toString() ?? '') ?? DateTime.now(),
      periodLabel: m['period_label']?.toString() ?? '',
      status: ReportStatus.parse(m['status']?.toString()),
      data: raw is Map ? Map<String, dynamic>.from(raw) : const {},
      titheTotal: double.tryParse(m['tithe_total']?.toString() ?? '') ?? 0,
      offeringTotal: double.tryParse(m['offering_total']?.toString() ?? '') ?? 0,
      otherIncomeTotal:
          double.tryParse(m['other_income_total']?.toString() ?? '') ?? 0,
      attendanceTotal: (m['attendance_total'] as num?)?.toInt() ?? 0,
      newMembers: (m['new_members'] as num?)?.toInt() ?? 0,
      baptisms: (m['baptisms'] as num?)?.toInt() ?? 0,
      salvations: (m['salvations'] as num?)?.toInt() ?? 0,
      narrative: m['narrative']?.toString(),
      reviewNote: m['review_note']?.toString(),
    );
  }

  double get totalIncome => titheTotal + offeringTotal + otherIncomeTotal;
}

@immutable
class RemittanceRecord {
  final String id;
  final String reference;
  final String? fromChurchName;
  final String? toChurchName;
  final double basisAmount;
  final double rate;
  final double amount;
  final String status;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final String? note;

  const RemittanceRecord({
    required this.id,
    required this.reference,
    this.fromChurchName,
    this.toChurchName,
    this.basisAmount = 0,
    this.rate = 0.10,
    this.amount = 0,
    this.status = 'pending',
    this.sentAt,
    this.receivedAt,
    this.note,
  });

  factory RemittanceRecord.fromMap(Map<String, dynamic> m) => RemittanceRecord(
        id: m['id'].toString(),
        reference: m['reference']?.toString() ?? '',
        fromChurchName: m['from_church_name']?.toString(),
        toChurchName: m['to_church_name']?.toString(),
        basisAmount: double.tryParse(m['basis_amount']?.toString() ?? '') ?? 0,
        rate: double.tryParse(m['rate']?.toString() ?? '') ?? 0.10,
        amount: double.tryParse(m['amount']?.toString() ?? '') ?? 0,
        status: m['status']?.toString() ?? 'pending',
        sentAt: DateTime.tryParse(m['sent_at']?.toString() ?? ''),
        receivedAt: DateTime.tryParse(m['received_at']?.toString() ?? ''),
        note: m['note']?.toString(),
      );
}

class ReportException implements Exception {
  final String message;
  const ReportException(this.message);
  @override
  String toString() => message;
}

/// The reporting chain: local church -> secretary -> pastor -> HQ.
///
/// Every write goes through a workflow RPC. The client deliberately cannot
/// approve a return, send to HQ, or mark money received - those are the steps
/// that make the chain worth anything.
///
/// NOTE: deliberately a separate file from `reporting_service.dart`, which is
/// the older Sunday-service `ServiceReport` / `reportsStreamProvider` used by
/// the announcement ticker and livestream screens.
class ReportingChainService {
  final SupabaseClient _client;
  ReportingChainService(this._client);

  // ------------------------------------------------------------- templates

  /// The template this conference should use: its own if configured, else the
  /// platform default.
  Future<ReportTemplate?> loadTemplate({
    String? organizationId,
    required String reportType,
  }) async {
    final base = _client
        .from('report_templates')
        .select(
          'id, report_type, name, description, field_schema, '
          'remittance_rate, include_financials',
        )
        .eq('report_type', reportType)
        .eq('is_active', true);

    // postgrest has no `.is()`; a NULL test is a filter.
    final rows = organizationId == null
        ? await base.filter('organization_id', 'is', null)
        : await base.eq('organization_id', organizationId);
    if (rows.isEmpty) return null;

    // Prefer a conference-specific template over the platform default.
    final specific = organizationId == null
        ? <dynamic>[]
        : rows.where((r) => r['organization_id'] == organizationId).toList();
    final chosen = (specific.isNotEmpty ? specific : rows).first;
    return ReportTemplate.fromMap(Map<String, dynamic>.from(chosen));
  }

  // ------------------------------------------------------------ submissions

  Future<List<ReportSubmission>> fetchForTenant(String tenantId) async {
    final rows = await _client
        .from('report_submissions')
        .select('*')
        .eq('tenant_id', tenantId)
        .order('period_start', ascending: false)
        .limit(60);
    return [
      for (final r in rows) ReportSubmission.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  /// Every return for a conference, with church names attached.
  Future<List<ReportSubmission>> fetchForOrganization(
    String organizationId, {
    DateTime? periodStart,
  }) async {
    final base = _client
        .from('report_submissions')
        .select('*')
        .eq('organization_id', organizationId);
    final rows = periodStart == null
        ? await base.order('period_start', ascending: false).limit(300)
        : await base
            .eq('period_start', _date(periodStart))
            .limit(300);

    final names = await _churchNames([for (final r in rows) r['tenant_id']]);
    return [
      for (final r in rows)
        ReportSubmission.fromMap({
          ...Map<String, dynamic>.from(r),
          'tenant_name': names[r['tenant_id']],
        }),
    ];
  }

  /// Returns waiting on a pastor: their own church plus any branch in the same
  /// conference.
  Future<List<ReportSubmission>> fetchReviewQueue(String tenantId) async {
    final rows = await _client
        .from('report_submissions')
        .select('*')
        .inFilter('status', ['submitted', 'returned'])
        .order('period_start', ascending: false)
        .limit(200);

    final mine = rows
        .where((r) => r['tenant_id'] == tenantId)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();

    final orgIds = {
      for (final r in mine)
        if (r['organization_id'] != null) r['organization_id'].toString(),
    };
    for (final orgId in orgIds) {
      final branch = await _client
          .from('report_submissions')
          .select('*')
          .eq('organization_id', orgId)
          .neq('tenant_id', tenantId)
          .inFilter('status', ['submitted', 'returned'])
          .limit(200);
      for (final r in branch) {
        if (!mine.any((m) => m['id'] == r['id'])) {
          mine.add(Map<String, dynamic>.from(r));
        }
      }
    }

    final names = await _churchNames([for (final r in mine) r['tenant_id']]);
    return [
      for (final m in mine)
        ReportSubmission.fromMap({
          ...m,
          'tenant_name': names[m['tenant_id']],
        }),
    ];
  }

  Future<ReportSubmission> saveDraft({
    required String tenantId,
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String periodLabel,
    Map<String, dynamic> data = const {},
    double titheTotal = 0,
    double offeringTotal = 0,
    double otherIncomeTotal = 0,
    int attendanceTotal = 0,
    int newMembers = 0,
    int baptisms = 0,
    int salvations = 0,
    String? narrative,
    required bool submit,
  }) async {
    try {
      final row = await _client.rpc('save_report_draft', params: {
        'p_tenant_id': tenantId,
        'p_report_type': reportType,
        'p_period_start': _date(periodStart),
        'p_period_end': _date(periodEnd),
        'p_period_label': periodLabel,
        'p_data': data,
        'p_tithe_total': titheTotal,
        'p_offering_total': offeringTotal,
        'p_other_income_total': otherIncomeTotal,
        'p_attendance_total': attendanceTotal,
        'p_new_members': newMembers,
        'p_baptisms': baptisms,
        'p_salvations': salvations,
        'p_narrative': narrative,
        'p_submit': submit,
      });
      return ReportSubmission.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw ReportException(_readable(e));
    }
  }

  Future<ReportSubmission> review({
    required String reportId,
    required bool approve,
    String? note,
  }) async {
    try {
      final row = await _client.rpc('review_report', params: {
        'p_report_id': reportId,
        'p_approve': approve,
        'p_note': note,
      });
      return ReportSubmission.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw ReportException(_readable(e));
    }
  }

  Future<int> sendToHq({
    required String organizationId,
    required DateTime periodStart,
    required DateTime periodEnd,
    String? note,
  }) async =>
      _count(
        await _call('send_reports_to_hq', {
          'p_organization_id': organizationId,
          'p_period_start': _date(periodStart),
          'p_period_end': _date(periodEnd),
          'p_note': note,
        }),
        'sent_count',
      );

  Future<int> acknowledge({
    required String organizationId,
    required DateTime periodStart,
    required DateTime periodEnd,
    String? note,
  }) async =>
      _count(
        await _call('acknowledge_reports', {
          'p_organization_id': organizationId,
          'p_period_start': _date(periodStart),
          'p_period_end': _date(periodEnd),
          'p_note': note,
        }),
        'ack_count',
      );

  // ------------------------------------------------------------ remittances

  Future<RemittanceRecord> raiseRemittance({
    required String reportId,
    String? note,
  }) async {
    try {
      final row = await _client.rpc('raise_remittance', params: {
        'p_report_id': reportId,
        'p_note': note,
      });
      return RemittanceRecord.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw ReportException(_readable(e));
    }
  }

  Future<RemittanceRecord> settleRemittance({
    required String remittanceId,
    required bool receive,
    String? note,
  }) async {
    try {
      final row = await _client.rpc('settle_remittance', params: {
        'p_remittance_id': remittanceId,
        'p_receive': receive,
        'p_note': note,
      });
      return RemittanceRecord.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw ReportException(_readable(e));
    }
  }

  Future<List<RemittanceRecord>> fetchRemittances({
    String? organizationId,
    String? tenantId,
    int limit = 100,
  }) async {
    final base = _client.from('remittances').select('*');
    final rows = organizationId != null
        ? await base.eq('organization_id', organizationId).limit(limit)
        : tenantId != null
            ? await base.eq('from_tenant_id', tenantId).limit(limit)
            : await base.limit(limit);

    final names = await _churchNames([
      for (final r in rows) r['from_tenant_id'],
      for (final r in rows) r['to_tenant_id'],
    ]);
    return [
      for (final r in rows)
        RemittanceRecord.fromMap({
          ...Map<String, dynamic>.from(r),
          'from_church_name': names[r['from_tenant_id']],
          'to_church_name': names[r['to_tenant_id']],
        }),
    ];
  }

  /// Aggregate picture across a set of returns - what a bishop reads at a
  /// glance.
  Map<String, double> totals(List<ReportSubmission> rows) {
    var tithe = 0.0, offering = 0.0, other = 0.0;
    var attendance = 0, members = 0, baptisms = 0, salvations = 0;
    for (final r in rows) {
      tithe += r.titheTotal;
      offering += r.offeringTotal;
      other += r.otherIncomeTotal;
      attendance += r.attendanceTotal;
      members += r.newMembers;
      baptisms += r.baptisms;
      salvations += r.salvations;
    }
    return {
      'tithe': tithe,
      'offering': offering,
      'other': other,
      'total_income': tithe + offering + other,
      'attendance': attendance.toDouble(),
      'new_members': members.toDouble(),
      'baptisms': baptisms.toDouble(),
      'salvations': salvations.toDouble(),
    };
  }

  Future<dynamic> _call(String fn, Map<String, dynamic> params) async {
    try {
      return await _client.rpc(fn, params: params);
    } catch (e) {
      throw ReportException(_readable(e));
    }
  }

  int _count(dynamic rows, String key) {
    final list = rows as List;
    if (list.isEmpty) return 0;
    final first = list.first;
    return (first is Map && first[key] != null)
        ? (first[key] as num).toInt()
        : 0;
  }

  Future<Map<String, String?>> _churchNames(List<dynamic> ids) async {
    final clean = ids
        .whereType<Object>()
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (clean.isEmpty) return {};
    final rows =
        await _client.from('tenants').select('id, name').inFilter('id', clean);
    return {for (final r in rows) r['id'].toString(): r['name']?.toString()};
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _readable(Object e) {
    final s = e.toString();
    if (s.contains('cannot be reviewed')) {
      return 'This return is not ready for review yet.';
    }
    if (s.contains('already')) return 'That step has already been done.';
    if (s.contains('only an approved return')) {
      return 'Only an approved return can generate a remittance.';
    }
    if (s.contains('prepared it')) {
      return 'A return cannot be reviewed by the person who prepared it.';
    }
    if (s.contains('may submit to HQ') || s.contains('may acknowledge')) {
      return 'Only the bishop or conference secretary can do this.';
    }
    if (s.contains('only leadership of this church')) {
      return 'Only leadership of this church can file its return.';
    }
    if (s.contains('period end date')) {
      return 'The period end date must be after the start date.';
    }
    if (s.contains('not authenticated')) {
      return 'Your session expired. Sign in and try again.';
    }
    return 'Could not complete that. Please try again.';
  }
}