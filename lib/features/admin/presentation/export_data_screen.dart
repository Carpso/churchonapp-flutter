import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/export_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class ExportDataScreen extends ConsumerStatefulWidget {
  const ExportDataScreen({super.key});

  @override
  ConsumerState<ExportDataScreen> createState() => _ExportDataScreenState();
}

class _ExportDataScreenState extends ConsumerState<ExportDataScreen> {
  late final ExportService _exportService;
  bool _generating = false;
  String _lastExportPath = '';

  final List<_ExportType> _dataTypes = [
    _ExportType('Ledger (All Transactions)', LucideIcons.bookOpen, true),
    _ExportType('Members', LucideIcons.users, false),
    _ExportType('Giving & Tithes', LucideIcons.coins, false),
    _ExportType('Events', LucideIcons.calendarDays, false),
    _ExportType('Attendance', LucideIcons.clipboardCheck, false),
    _ExportType('Sermons', LucideIcons.bookOpen, false),
    _ExportType('Marketplace Orders', LucideIcons.shoppingCart, false),
    _ExportType('Bible Quiz Scores', LucideIcons.helpCircle, false),
    _ExportType('Ride & Delivery History', LucideIcons.car, false),
    _ExportType('Financial Reports', LucideIcons.barChart2, false),
  ];

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    if (tenant == null) {
      return const Scaffold(body: Center(child: Text('Select a Church')));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Export Data', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Church: ${tenant.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Export format: PDF (primary), then CSV, then JSON', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _dataTypes.length,
              itemBuilder: (context, index) {
                final type = _dataTypes[index];
                return Semantics(
                  label: 'Export ${type.label} as PDF document',
                  button: true,
                  hint: type.primary ? 'Primary export format' : 'Secondary export format',
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
                    child: ListTile(
                      leading: Icon(type.icon, color: Colors.amber, size: 24),
                      title: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: _generating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                          : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: _generating ? null : () => _exportData(type, tenant),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_lastExportPath.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('Export complete!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Semantics(
                    label: 'Share exported PDF file',
                    button: true,
                    hint: 'Shares the exported PDF via device share sheet',
                    child: TextButton(
                      onPressed: () => _exportService.shareFile(File(_lastExportPath), 'application/pdf'),
                      child: const Text('Share', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _exportData(_ExportType type, Tenant tenant) async {
    setState(() => _generating = true);
    try {
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final title = '${tenant.name.replaceAll(' ', '_')}_${type.label.replaceAll(' ', '_')}_$now';
      final dir = await getApplicationDocumentsDirectory();

      List<Map<String, dynamic>> data = [];
      switch (type.label) {
        case 'Ledger (All Transactions)':
          final ledger = await _exportService.client.from('ledger').select().order('created_at', ascending: false).limit(500);
          data = List<Map<String, dynamic>>.from(ledger);
          break;
        case 'Members':
          final members = await _exportService.client.from('profiles').select('full_name, email, phone_number, role, created_at').eq('tenant_id', tenant.id).order('created_at', ascending: false);
          data = List<Map<String, dynamic>>.from(members);
          break;
        case 'Giving & Tithes':
          final giving = await _exportService.client.from('giving').select('id, user_id, amount, category, currency, payment_method, payment_ref, status, created_at, tenant_id, church_id').order('created_at', ascending: false).limit(500);
          data = List<Map<String, dynamic>>.from(giving);
          break;
        case 'Events':
          final events = await _exportService.client.from('events').select('id, title, description, event_date, event_time, location, category, type, price, currency, max_attendees, is_public, status, created_at, tenant_id, church_id').order('event_date', ascending: false).limit(500);
          data = List<Map<String, dynamic>>.from(events);
          break;
        default:
          final generic = await _exportService.client.from(type.label.toLowerCase().replaceAll(' ', '_')).select().limit(100);
          data = List<Map<String, dynamic>>.from(generic);
      }

      final rows = data.map((d) => ExportRow(d)).toList();
      final List<String> columns = data.isNotEmpty ? data.first.keys.toList().cast<String>() : <String>[];

      if (columns.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data found')));
        setState(() => _generating = false);
        return;
      }

      final pdfFile = await _exportService.exportToPdf(
        title: title,
        tenantName: tenant.name,
        columns: columns,
        rows: rows,
      );

      setState(() {
        _lastExportPath = pdfFile.path;
        _generating = false;
      });

      final csvPath = '${dir.path}/$title.csv';
      await File(csvPath).writeAsString(await _exportService.exportToCsv(rows, columns));

      final jsonPath = '${dir.path}/$title.json';
      await File(jsonPath).writeAsString(await _exportService.exportToJson(rows));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      setState(() => _generating = false);
    }
  }
}

class _ExportType {
  final String label;
  final IconData icon;
  final bool primary;
  _ExportType(this.label, this.icon, this.primary);
}