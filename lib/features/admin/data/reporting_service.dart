import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServiceReport {
  final String id;
  final String tenantId;
  final String title;
  final String description;
  final int attendance;
  final double offering;
  final String testimony;
  final String? notes;
  final DateTime? serviceDate;
  final int visitors;
  final int salvations;
  final int onlineViewers;
  final int ministriesActive;
  final DateTime date;
  final String reporterId;
  final String type; // 'service', 'announcement', 'ledger_entry'

  ServiceReport({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.description,
    required this.attendance,
    required this.offering,
    required this.testimony,
    this.notes,
    this.serviceDate,
    this.visitors = 0,
    this.salvations = 0,
    this.onlineViewers = 0,
    this.ministriesActive = 0,
    required this.date,
    required this.reporterId,
    this.type = 'service',
  });

  factory ServiceReport.fromMap(Map<String, dynamic> map) {
    return ServiceReport(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      attendance: map['attendance'] ?? 0,
      offering: (map['offering'] ?? 0).toDouble(),
      testimony: map['testimony'] ?? '',
      notes: map['notes'],
      serviceDate: map['service_date'] != null ? DateTime.tryParse(map['service_date'].toString()) : null,
      visitors: (map['visitors'] as num?)?.toInt() ?? 0,
      salvations: (map['salvations'] as num?)?.toInt() ?? 0,
      onlineViewers: (map['online_viewers'] as num?)?.toInt() ?? 0,
      ministriesActive: (map['ministries_active'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      reporterId: map['reporter_id'] ?? '',
      type: map['type'] ?? 'service',
    );
  }
}

class ReportingService {
  final SupabaseClient _client;
  ReportingService(this._client);

  Stream<List<ServiceReport>> getReportsStream(String tenantId) {
    return _client
        .from('service_reports')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => ServiceReport.fromMap(map)).toList());
  }

  Future<void> submitReport(ServiceReport report) async {
    await _client.from('service_reports').insert({
      'tenant_id': report.tenantId,
      'title': report.title,
      'description': report.description,
      'attendance': report.attendance,
      'offering': report.offering,
      'testimony': report.testimony,
      'reporter_id': report.reporterId,
      'type': report.type,
      'service_date': report.serviceDate?.toIso8601String().substring(0, 10),
      'visitors': report.visitors,
      'salvations': report.salvations,
      'online_viewers': report.onlineViewers,
      'ministries_active': report.ministriesActive,
      'notes': report.notes,
    });
  }

  /// Per-church service summary (attendance, offering, visitors, salvations this month).
  Future<Map<String, dynamic>> getServiceSummary(String tenantId) async {
    final res = await _client.rpc('get_church_service_summary', params: {'p_tenant_id': tenantId});
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Organization-wide service aggregation (all churches under one org, current month).
  Future<Map<String, dynamic>> getOrganizationServiceSummary(String orgId) async {
    final res = await _client.rpc('get_organization_service_summary', params: {'p_org_id': orgId});
    return (res as Map<String, dynamic>?) ?? {};
  }
}

final reportingServiceProvider = Provider((ref) => ReportingService(Supabase.instance.client));

final reportsStreamProvider = StreamProvider.family<List<ServiceReport>, String>((ref, tenantId) {
  return ref.watch(reportingServiceProvider).getReportsStream(tenantId);
});

