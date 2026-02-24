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
      date: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
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
    });
  }
}

final reportingServiceProvider = Provider((ref) => ReportingService(Supabase.instance.client));

final reportsStreamProvider = StreamProvider.family<List<ServiceReport>, String>((ref, tenantId) {
  return ref.watch(reportingServiceProvider).getReportsStream(tenantId);
});
