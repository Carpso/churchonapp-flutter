import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:church_on_app/features/data_import/data/data_import_provider.dart';
import 'package:church_on_app/features/data_import/data/data_import_service.dart';

class DataImportScreen extends ConsumerStatefulWidget {
  const DataImportScreen({super.key});

  @override
  ConsumerState<DataImportScreen> createState() => _DataImportScreenState();
}

class _DataImportScreenState extends ConsumerState<DataImportScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _entity = 'profiles';
  final _csvController = TextEditingController();
  final _docController = TextEditingController();
  final _mappingController = TextEditingController();
  String? _conflictOn;
  List<Map<String, dynamic>> _rows = [];
  List<String> _columns = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _mappingController.text = 'full_name:full_name\nphone_number:phone_number';
  }

  @override
  void dispose() {
    _tab.dispose();
    _csvController.dispose();
    _docController.dispose();
    _mappingController.dispose();
    super.dispose();
  }

  void _setEntity(String? v) {
    if (v == null) return;
    setState(() {
      _entity = v;
      _rows = [];
      _columns = [];
      _mappingController.text = 'full_name:full_name\nphone_number:phone_number';
    });
  }

  void _parseCsv() {
    final text = _csvController.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paste CSV data first')));
      return;
    }
    final parsed = DataImportService.parseCsv(text);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No rows found')));
      return;
    }
    setState(() {
      _rows = parsed.cast<Map<String, dynamic>>();
      _columns = _rows.first.keys.toList();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Parsed ${_rows.length} rows')));
  }

  Map<String, String> _resolveMapping() {
    final map = <String, String>{};
    for (final line in _mappingController.text.trim().split(RegExp(r'\r?\n'))) {
      final parts = line.split(':');
      if (parts.length == 2) map[parts[0].trim()] = parts[1].trim();
    }
    return map;
  }

  void _import() {
    if (_rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parse CSV first')));
      return;
    }
    final entityCols = List<String>.from(DataImportService.columnsFor[_entity] ?? []);
    if (_conflictOn != null && !entityCols.contains(_conflictOn)) {
      entityCols.add(_conflictOn!);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importing…')));
    ref.read(dataImportControllerProvider.notifier).runImport(
          entityType: _entity,
          rows: _rows,
          columns: entityCols,
          tenantId: ref.read(importTenantIdProvider) ?? '',
          mapping: _mappingController.text.trim().isNotEmpty ? _resolveMapping() : null,
          conflictOn: _conflictOn,
          fileName: 'csv_import_$_entity',
          sourceSystem: 'csv_paste',
        );
  }

  void _extractDocument() {
    final text = _docController.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paste document text or provide a file URL')));
      return;
    }
    ref.read(dataImportControllerProvider.notifier).extractDocument(entityType: _entity, text: text);
  }

  void _importExtracted() {
    final flow = ref.read(dataImportControllerProvider);
    final rows = flow.extractedRows;
    if (rows == null || rows.isEmpty) return;
    final cols = rows.first.keys.toList();
    ref.read(dataImportControllerProvider.notifier).runImport(
          entityType: _entity,
          rows: rows,
          columns: cols,
          tenantId: ref.read(importTenantIdProvider) ?? '',
          conflictOn: _conflictOn,
        );
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref.watch(isImporterAllowedProvider);
    final tenantId = ref.watch(importTenantIdProvider);

    if (!allowed) {
      return Scaffold(appBar: AppBar(title: const Text('Data Import')), body: const Center(child: Text('Only church leadership can import data.')));
    }
    if (tenantId == null || tenantId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Data Import')),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No church/tenant selected. Select your church to enable data import.', textAlign: TextAlign.center))),
      );
    }

    final flow = ref.watch(dataImportControllerProvider);
    final entityColumns = DataImportService.columnsFor[_entity] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Import'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(LucideIcons.fileText), text: 'CSV / JSON'),
            Tab(icon: Icon(LucideIcons.fileSearch), text: 'Document'),
            Tab(icon: Icon(LucideIcons.list), text: 'Results'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _csvTab(entityColumns),
          _documentTab(),
          _resultTab(flow),
        ],
      ),
      floatingActionButton: Builder(
        builder: (context) {
          if (_tab.index == 0) return _fab('Import CSV', _import);
          if (_tab.index == 1) return _fab('Extract Document', _extractDocument);
          return _fab('Import Extracted Rows', _importExtracted);
        },
      ),
    );
  }

  Widget _fab(String label, VoidCallback onPressed) => FloatingActionButton.extended(
        onPressed: onPressed,
        icon: const Icon(LucideIcons.upload),
        label: Text(label),
      );

  Widget _csvTab(List<String> entityColumns) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _entity,
            items: DataImportService.entities.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: _setEntity,
            decoration: const InputDecoration(labelText: 'Entity'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _csvController, decoration: const InputDecoration(labelText: 'Paste CSV (first row = headers)', border: OutlineInputBorder()), maxLines: 6),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: _parseCsv, icon: const Icon(LucideIcons.fileInput), label: const Text('Parse CSV')),
          const SizedBox(height: 12),
          TextField(
            controller: _mappingController,
             decoration: const InputDecoration(labelText: 'Column mapping (target:source, one per line)', border: OutlineInputBorder(), helperText: 'e.g. full_name:First Name'),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          if (entityColumns.isNotEmpty)
            Wrap(
              spacing: 8,
              children: entityColumns.map((c) => Chip(label: Text(c))).toList(),
            ),
          if (entityColumns.isNotEmpty) const SizedBox(height: 12),
          if (_rows.isNotEmpty) Text('${_rows.length} rows parsed; ${_columns.length} columns', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _conflictOn, items: entityColumns.map((c) => DropdownMenuItem(value: c, child: Text('Conflict on: $c'))).toList(), onChanged: (v) => setState(() => _conflictOn = v), decoration: const InputDecoration(labelText: 'Upsert key (optional)')),
        ],
      );

  Widget _documentTab() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Entity: $_entity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _docController,
            decoration: const InputDecoration(labelText: 'Paste document text (PDF/Word extracted text)', border: OutlineInputBorder()),
            maxLines: 8,
          ),
          const SizedBox(height: 12),
          const Text('The kael-ai assistant extracts a JSON array of rows matching the entity columns.'),
          const SizedBox(height: 8),
          ElevatedButton.icon(onPressed: _extractDocument, icon: const Icon(LucideIcons.fileSearch), label: const Text('Extract with AI')),
        ],
      );

  Widget _resultTab(ImportFlowState flow) {
    if (flow.loading) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    final res = flow.result;
    if (res == null && flow.error == null && flow.extractedRows == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Import results will appear here.')));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (flow.error != null)
          Card(color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.2), child: ListTile(title: const Text('Error'), subtitle: Text(flow.error!))),
        if (res != null)
          Card(
            child: ListTile(
              leading: Icon(res.isSuccess ? LucideIcons.checkCircle : LucideIcons.alertCircle, color: res.isSuccess ? Colors.green : Colors.orange),
              title: Text('${res.entityType}: ${res.imported} imported / ${res.failed} failed of ${res.totalRows}'),
              subtitle: Text('Status: ${res.status} · ID: ${res.importId}'),
            ),
          ),
        if (flow.extractedRows != null && flow.extractedRows!.isNotEmpty)
          Card(child: ListTile(title: Text('Extracted ${flow.extractedRows!.length} rows'), trailing: IconButton(icon: const Icon(LucideIcons.upload), onPressed: _importExtracted))),
        ...?flow.extractedRows?.map((r) => ListTile(title: Text(r.toString()), dense: true)),
      ],
    );
  }
}
