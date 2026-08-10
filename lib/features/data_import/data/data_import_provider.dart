import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:church_on_app/core/providers/profile_provider.dart';
import 'package:church_on_app/features/data_import/data/data_import_service.dart';

/// Loads import templates for a (tenant, entity).
final importTemplatesProvider =
    FutureProvider.family<List<ImportTemplate>, TemplateKey>((ref, key) async {
  final svc = ref.watch(dataImportServiceProvider);
  return svc.listTemplates(key.entityType, key.tenantId);
});

class TemplateKey {
  final String tenantId;
  final String entityType;
  const TemplateKey(this.tenantId, this.entityType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateKey && tenantId == other.tenantId && entityType == other.entityType;
  @override
  int get hashCode => Object.hash(tenantId, entityType);
}

final importTenantIdProvider = Provider<String?>((ref) {
  final profile = ref.watch(profileProvider).value;
  return profile?.tenantId;
});

final isImporterAllowedProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return false;
  return profile.isAdminOrHigher || profile.isPastorOrHigher || profile.isBishopOrHigher;
});

class ImportFlowState {
  final bool loading;
  final ImportResult? result;
  final String? error;
  final List<Map<String, dynamic>>? extractedRows;

  const ImportFlowState({this.loading = false, this.result, this.error, this.extractedRows});

  ImportFlowState copyWith({
    bool? loading,
    ImportResult? result,
    bool clearError = false,
    String? error,
    List<Map<String, dynamic>>? extractedRows,
  }) {
    return ImportFlowState(
      loading: loading ?? this.loading,
      result: result ?? this.result,
      error: clearError ? null : (error ?? this.error),
      extractedRows: extractedRows ?? this.extractedRows,
    );
  }
}

class DataImportNotifier extends Notifier<ImportFlowState> {
  @override
  ImportFlowState build() => const ImportFlowState();

  Future<void> runImport({
    required String entityType,
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
    required String tenantId,
    Map<String, String>? mapping,
    String? conflictOn,
    String? fileName,
    String? sourceSystem,
  }) async {
    state = state.copyWith(loading: true, clearError: true, result: null);
    try {
      final svc = ref.read(dataImportServiceProvider);
      final res = await svc.importRows(
        entityType: entityType,
        rows: rows,
        columns: columns,
        tenantId: tenantId,
        mapping: mapping,
        conflictOn: conflictOn,
        fileName: fileName,
        sourceSystem: sourceSystem,
      );
      state = state.copyWith(loading: false, result: res);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> extractDocument({
    required String entityType,
    required String text,
    String? fileUrl,
    String? prompt,
  }) async {
    state = state.copyWith(loading: true, clearError: true, extractedRows: null);
    try {
      final svc = ref.read(dataImportServiceProvider);
      final rows = await svc.extractDocument(entityType: entityType, text: text, fileUrl: fileUrl, prompt: prompt);
      state = state.copyWith(loading: false, extractedRows: rows);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void reset() => state = const ImportFlowState();
}

final dataImportControllerProvider = NotifierProvider<DataImportNotifier, ImportFlowState>(DataImportNotifier.new);
