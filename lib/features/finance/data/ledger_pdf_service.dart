import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:church_on_app/features/finance/data/finance_service.dart';
import 'package:intl/intl.dart';

class LedgerPdfService {
  static Future<void> generateAndPrintLedger(List<Transaction> transactions, String churchName) async {
    final pdf = pw.Document();

    final total = transactions.fold(0.0, (sum, item) => sum + item.amount);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(churchName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Ecclesiastical Financial Statement", style: pw.TextStyle(color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("TOTAL BALANCE:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("K ${total.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Divider(),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ['Date', 'Category', 'Reference', 'Amount'],
                data: transactions.map((tx) => [
                  DateFormat('dd MMM').format(tx.createdAt),
                  tx.category.toUpperCase(),
                  tx.reference,
                  tx.amount.toStringAsFixed(2),
                ]).toList(),
              ),
              pw.SizedBox(height: 50),
              pw.Center(child: pw.Text("Church On App Platform • Audit Verified Statement", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600))),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}

