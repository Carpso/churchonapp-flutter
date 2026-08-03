import 'package:universal_io/io.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExportRow {
  final Map<String, dynamic> data;
  ExportRow(this.data);
}

class ExportService {
  final SupabaseClient _client;
  ExportService(this._client);

  SupabaseClient get client => _client;

  Future<String> exportToCsv(List<ExportRow> rows, List<String> columns) async {
    final buffer = StringBuffer();
    buffer.writeln(columns.map((c) => '"$c"').join(','));
    for (final row in rows) {
      buffer.writeln(columns.map((c) {
        final val = row.data[c]?.toString() ?? '';
        return '"${val.replaceAll('"', '""')}"';
      }).join(','));
    }
    return buffer.toString();
  }

  Future<String> exportToJson(List<ExportRow> rows) async {
    return jsonEncode(rows.map((r) => r.data).toList());
  }

  Future<File> exportToPdf({
    required String title,
    required String tenantName,
    required List<String> columns,
    required List<ExportRow> rows,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Church: $tenantName', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: columns,
                data: rows.map((r) => columns.map((c) => '${r.data[c] ?? ''}').toList()).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: PdfColors.amber100),
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$title.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<void> shareFile(File file, String mimeType) async {
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)], text: 'Exported data file');
  }
}

final exportServiceProvider = Provider<ExportService>((ref) => ExportService(Supabase.instance.client));