import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:church_on_app/core/services/supabase_service.dart';

/// Enterprise data-import service — talks to the `data-import` Edge Function.
/// Supports CSV/JSON paste, per-tenant column-mapping presets, and document
/// extraction (PDF/Word/Image via the kael-ai Edge Function).
class DataImportService {
  final SupabaseClient _client;
  DataImportService(this._client);

  static const entities = [
    'profiles',
    'transactions',
    'events',
    'ministries',
    'service_reports',
  ];

  /// Column sets per entity (used to pre-fill / validate mappings client-side).
  static const columnsFor = <String, List<String>>{
    'profiles': [
      'full_name', 'phone_number', 'avatar_url', 'is_verified',
      'kyc_status', 'referral_code', 'fcm_token', 'lat', 'lng',
    ],
    'transactions': [
      'amount', 'category', 'status', 'reference',
      'recipient_name', 'recipient_phone', 'type', 'user_id',
    ],
    'events': ['title', 'description', 'date', 'end_date', 'location', 'category', 'ticket_price'],
    'ministries': ['name', 'description', 'meeting_day', 'meeting_time', 'meeting_location'],
    'service_reports': ['title', 'description', 'attendance', 'offering', 'testimony'],
  };

  /// System presets (source column -> target column). Church admins can save
  /// custom presets which override these defaults.
  static const presetMappings = <String, Map<String, String>>{
    'breeze': {
      'First Name': 'full_name', 'Phone': 'phone_number', 'Email': 'email',
    },
    'planning_center': {
      'Name': 'full_name', 'Phone': 'phone_number', 'Created At': 'created_at',
    },
    'rockrms': {
      'FullName': 'full_name', 'MobilePhoneNumber': 'phone_number', 'Email': 'email',
    },
    'mtnbank': {
      'Narrative': 'reference', 'Amount': 'amount', 'Date': 'created_at',
    },
  };

  /// Run a batch import of already-parsed rows.
  Future<ImportResult> importRows({
    required String entityType,
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
    required String tenantId,
    Map<String, String>? mapping,
    String? conflictOn,
    String? fileName,
    String? sourceSystem,
  }) async {
    final res = await _client.functions.invoke('data-import', body: {
      'action': 'import',
      'entity_type': entityType,
      'rows': rows,
      'columns': columns,
      'tenant_id': tenantId,
      'mapping': mapping,
      'conflict_on': conflictOn,
      'file_name': fileName,
      'source_system': sourceSystem,
    });

    final data = res.data;
    if (data is Map<String, dynamic> && data['error'] != null) {
      throw Exception(data['error']);
    }
    return ImportResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Extract structured rows from a document (PDF/Word/Image text) via kael-ai.
  Future<List<Map<String, dynamic>>> extractDocument({
    required String entityType,
    required String text,
    String? fileUrl,
    String? prompt,
  }) async {
    final res = await _client.functions.invoke('data-import', body: {
      'action': 'extract_document',
      'entity_type': entityType,
      'text': text,
      'file_url': fileUrl,
      'prompt': prompt,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return (data['rows'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  Future<List<ImportTemplate>> listTemplates(String entityType, String tenantId) async {
    final res = await _client.functions.invoke('data-import', body: {
      'action': 'list_templates',
      'entity_type': entityType,
      'tenant_id': tenantId,
    });
    final data = res.data as Map<String, dynamic>? ?? {};
    if (data['error'] != null) throw Exception(data['error']);
    return (data['templates'] as List? ?? [])
        .map((e) => ImportTemplate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ImportTemplate> saveTemplate(ImportTemplate template, String tenantId) async {
    final res = await _client.functions.invoke('data-import', body: {
      'action': 'save_template',
      'tenant_id': tenantId,
      'name': template.name,
      'entity_type': template.entityType,
      'system_name': template.systemName,
      'mappings': template.mappings,
      'conflict_on': template.conflictOn,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return ImportTemplate.fromJson(Map<String, dynamic>.from(data['template']));
  }

  /// Minimal CSV parser (RFC 4180 subset): handles quoted fields, commas,
  /// newlines inside quotes. First row = headers.
  static List<Map<String, String>> parseCsv(String text) {
    final rows = _parseCsvRows(text);
    if (rows.isEmpty) return [];
    final headers = rows.first;
    return rows.skip(1).map((r) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < r.length; i++) {
        map[headers[i]] = r[i];
      }
      return map;
    }).toList();
  }

  static List<List<String>> _parseCsvRows(String text) {
    final out = <List<String>>[];
    final field = StringBuffer();
    final row = <String>[];
    bool inQuotes = false;
    void endRow() {
      row.add(field.toString());
      field.clear();
      out.add(List<String>.from(row));
      row.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          row.add(field.toString());
          field.clear();
        } else if (c == '\r') {
          // ignore CR
        } else if (c == '\n') {
          endRow();
        } else {
          field.write(c);
        }
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      out.add(row);
    }
    return out;
  }
}

class ImportResult {
  ImportResult({
    required this.importId,
    required this.entityType,
    required this.totalRows,
    required this.imported,
    required this.failed,
    required this.status,
  });

  final String importId;
  final String entityType;
  final int totalRows;
  final int imported;
  final int failed;
  final String status;

  ImportResult.fromJson(Map<String, dynamic> m)
      : importId = m['import_id'] ?? m['id'] ?? '',
        entityType = m['entity_type'] ?? '',
        totalRows = (m['total_rows'] ?? m['totalRows'] ?? 0).toInt(),
        imported = (m['imported'] ?? m['imported_rows'] ?? 0).toInt(),
        failed = (m['failed'] ?? m['failed_rows'] ?? 0).toInt(),
        status = m['status'] ?? 'unknown';

  bool get isSuccess => failed == 0 && imported > 0;
}

class ImportTemplate {
  ImportTemplate({
    this.id,
    required this.tenantId,
    required this.name,
    required this.entityType,
    this.systemName,
    required this.mappings,
    this.conflictOn,
  });

  final String? id;
  final String tenantId;
  final String name;
  final String entityType;
  final String? systemName;
  final Map<String, String> mappings;
  final String? conflictOn;

  ImportTemplate.fromJson(Map<String, dynamic> m)
      : id = m['id']?.toString(),
        tenantId = m['tenant_id']?.toString() ?? '',
        name = m['name'] ?? '',
        entityType = m['entity_type'] ?? '',
        systemName = m['system_name'],
        mappings = Map<String, String>.from(m['mappings'] ?? {}),
        conflictOn = m['conflict_on'];

  Map<String, dynamic> toMap() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'entity_type': entityType,
        'system_name': systemName,
        'mappings': mappings,
        'conflict_on': conflictOn,
      };
}

final dataImportServiceProvider = Provider<DataImportService>((ref) {
  return DataImportService(ref.watch(supabaseServiceProvider).client);
});
