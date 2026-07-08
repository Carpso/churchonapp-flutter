import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../data/receipt_service.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final String reference;
  const ReceiptScreen({super.key, required this.reference});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  PaymentReceipt? _receipt;

  @override
  Widget build(BuildContext context) {
    final receiptAsync = ref.watch(receiptProvider(widget.reference));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: const Text("Payment Receipt"),
        centerTitle: true,
        actions: [
          if (_receipt != null)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.download),
              onSelected: (value) {
                if (value == 'pdf') _downloadPdf(_receipt!);
                if (value == 'share') _shareReceipt(_receipt!);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'pdf', child: Row(
                  children: [Icon(LucideIcons.fileText, size: 18), SizedBox(width: 8), Text("Save PDF")],
                )),
                const PopupMenuItem(value: 'share', child: Row(
                  children: [Icon(LucideIcons.share2, size: 18), SizedBox(width: 8), Text("Share Receipt")],
                )),
              ],
            ),
        ],
      ),
      body: receiptAsync.when(
        data: (receipt) {
          if (receipt == null) {
            return const Center(child: Text("Receipt not found"));
          }
          _receipt ??= receipt;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildReceiptHeader(context, receipt),
                const SizedBox(height: 20),
                _buildReceiptCard(context, receipt),
                const SizedBox(height: 20),
                _buildFeeBreakdown(context, receipt),
                const SizedBox(height: 20),
                _buildDetailsCard(context, receipt),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text("Error: $err")),
      ),
    );
  }

  Widget _buildReceiptHeader(BuildContext context, PaymentReceipt receipt) {
    final isCompleted = receipt.status == 'completed';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? LucideIcons.check : LucideIcons.clock,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isCompleted ? "Payment Successful" : "Payment Pending",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "K ${receipt.amount.toStringAsFixed(2)}",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: isCompleted ? Colors.green.shade800 : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, PaymentReceipt receipt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          if (receipt.tenantName != null) ...[
            Text(
              receipt.tenantName!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              receipt.recipientName ?? 'Church Organization',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: 12),
          ],
          _receiptRow("Reference", receipt.reference, mono: true),
          const SizedBox(height: 8),
          _receiptRow("Category", receipt.category.toUpperCase()),
          const SizedBox(height: 8),
          _receiptRow("Date", DateFormat.yMMMd().add_jm().format(receipt.createdAt)),
          if (receipt.provider != null) ...[
            const SizedBox(height: 8),
            _receiptRow("Payment Method", "Mobile Money (${receipt.provider})"),
          ],
        ],
      ),
    );
  }

  Widget _buildFeeBreakdown(BuildContext context, PaymentReceipt receipt) {
    if (receipt.platformFee == null || receipt.platformFee == 0) {
      return const SizedBox.shrink();
    }
    final netAmount = receipt.amount - receipt.platformFee!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.receipt, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                "Fee Breakdown",
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _feeRow("Transaction Amount", receipt.amount, Colors.black87),
          _feeRow("Platform Fee (${receipt.category == 'event' ? '10' : '5'}%)", -receipt.platformFee!, Colors.red),
          Divider(color: Colors.grey.shade200),
          _feeRow("Net to Recipient", netAmount, Colors.green.shade700),
          if (receipt.disbursementStatus != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  receipt.disbursementStatus == 'completed' ? LucideIcons.checkCircle : LucideIcons.clock,
                  size: 14,
                  color: receipt.disbursementStatus == 'completed' ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  "Settlement: ${receipt.disbursementStatus!.toUpperCase()}",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: receipt.disbursementStatus == 'completed' ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context, PaymentReceipt receipt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.shield, color: Colors.amber.shade400, size: 24),
          const SizedBox(height: 8),
          Text(
            "Secured & Verified",
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Powered by Church On App & Lipila",
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _badge("Bank of Zambia"),
              const SizedBox(width: 8),
              _badge("Lipila"),
              const SizedBox(width: 8),
              _badge("COA"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    );
  }

  Widget _receiptRow(String label, String value, {bool mono = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _feeRow(String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            "${amount >= 0 ? '+' : ''}K ${amount.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildPdf(PaymentReceipt receipt) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(30),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text("CHURCH ON APP", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.amber)),
                  pw.Text("Payment Receipt", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text("Reference: ${receipt.reference}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
                ],
              ),
            ),
            pw.Divider(),
            pw.SizedBox(height: 16),
            _pdfRow("Status", receipt.status.toUpperCase()),
            _pdfRow("Amount", "K ${receipt.amount.toStringAsFixed(2)}"),
            _pdfRow("Category", receipt.category.toUpperCase()),
            _pdfRow("Date", DateFormat.yMMMd().add_jm().format(receipt.createdAt)),
            if (receipt.tenantName != null) _pdfRow("Church", receipt.tenantName!),
            if (receipt.recipientName != null) _pdfRow("Recipient", receipt.recipientName!),
            if (receipt.provider != null) _pdfRow("Provider", receipt.provider!),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.SizedBox(height: 8),
            if (receipt.platformFee != null && receipt.platformFee! > 0) ...[
              _pdfRow("Platform Fee", "K ${receipt.platformFee!.toStringAsFixed(2)}"),
              _pdfRow("Net Payout", "K ${(receipt.amount - receipt.platformFee!).toStringAsFixed(2)}"),
              pw.SizedBox(height: 8),
            ],
            if (receipt.disbursementStatus != null)
              _pdfRow("Settlement", receipt.disbursementStatus!.toUpperCase()),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                "Regulated by Bank of Zambia via Lipila",
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(PaymentReceipt receipt) async {
    try {
      final pdfBytes = await _buildPdf(receipt);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/receipt_${receipt.reference.substring(0, 8)}.pdf');
      await file.writeAsBytes(pdfBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Receipt saved to ${file.path}"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save receipt: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareReceipt(PaymentReceipt receipt) async {
    try {
      final pdfBytes = await _buildPdf(receipt);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${receipt.reference.substring(0, 8)}.pdf');
      await file.writeAsBytes(pdfBytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: "Church On App Payment Receipt"));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to share receipt: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
}
