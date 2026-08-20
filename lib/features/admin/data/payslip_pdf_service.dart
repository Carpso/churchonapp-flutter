import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'payroll_service.dart';

class PayslipPdfService {
  static final _fmt = NumberFormat.decimalPattern();

  static PdfColor _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return PdfColor.fromInt(int.parse('FF$h', radix: 16));
  }

  static Future<Uint8List> generatePayslip({
    required Payslip payslip,
    required String employeeName,
    required String employeeRole,
    required String department,
    required String periodLabel,
    String? companyName,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(periodLabel, companyName),
        footer: (context) => _buildFooter(),
        build: (context) => [
          _buildEmployeeInfo(employeeName, employeeRole, department),
          pw.SizedBox(height: 20),
          _buildEarningsSection(payslip),
          pw.SizedBox(height: 16),
          _buildDeductionsSection(payslip),
          pw.SizedBox(height: 16),
          _buildNetPaySection(payslip),
          pw.SizedBox(height: 20),
          _buildEmployerContributions(payslip),
          pw.SizedBox(height: 20),
          if (payslip.taxBreakdown.isNotEmpty) ...[
            _buildTaxBreakdown(payslip),
            pw.SizedBox(height: 16),
          ],
          _buildDisclaimer(),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(String periodLabel, String? companyName) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName ?? 'Church On App',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _hex('#0F172A')),
              ),
              pw.SizedBox(height: 4),
              pw.Text('PAYSLIP', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600, letterSpacing: 2)),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _hex('#10B981'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(periodLabel, style: pw.TextStyle(fontSize: 11, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildEmployeeInfo(String name, String role, String dept) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _hex('#F8FAFC'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('$role • $dept', style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Employee ID', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
              pw.Text(name.hashCode.toRadixString(16).toUpperCase(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildEarningsSection(Payslip p) {
    return _section(
      'EARNINGS',
      [
        _row('Basic Salary', p.basicSalary),
        if (p.allowances > 0) _row('Allowances', p.allowances),
        if (p.benefitsInKind > 0) _row('Benefits-in-Kind', p.benefitsInKind),
        _divider(),
        _row('GROSS SALARY', p.grossSalary, bold: true),
      ],
    );
  }

  static pw.Widget _buildDeductionsSection(Payslip p) {
    return _section(
      'STATUTORY DEDUCTIONS',
      [
        _row('PAYE (Income Tax)', p.paye, isDeduction: true),
        _row('NAPSA (Employee 5%)', p.napsaEmployee, isDeduction: true),
        _row('NHIMA (Employee 1%)', p.nhimaEmployee, isDeduction: true),
        _divider(),
        _row('Total Deductions', p.totalDeductions, bold: true, isDeduction: true),
      ],
    );
  }

  static pw.Widget _buildNetPaySection(Payslip p) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _hex('#ECFDF5'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _hex('#10B981'), width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('NET PAY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _hex('#059669'))),
          pw.Text('K ${_fmt.format(p.netPay)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _hex('#059669'))),
        ],
      ),
    );
  }

  static pw.Widget _buildEmployerContributions(Payslip p) {
    return _section(
      'EMPLOYER CONTRIBUTIONS (not deducted from employee)',
      [
        _row('NAPSA (Employer 5%)', p.napsaEmployer),
        _row('NHIMA (Employer 1%)', p.nhimaEmployer),
        if (p.sdl > 0) _row('SDL (0.5%)', p.sdl),
        _divider(),
        _row('Total Employer Cost', p.napsaEmployer + p.nhimaEmployer + p.sdl, bold: true),
      ],
    );
  }

  static pw.Widget _buildTaxBreakdown(Payslip p) {
    final bands = p.taxBreakdown['bands'];
    if (bands == null || bands is! List || bands.isEmpty) return pw.SizedBox();

    return _section(
      'TAX BAND BREAKDOWN (ZRA Progressive)',
      bands.map<pw.Widget>((band) {
        final label = band['band']?.toString() ?? '';
        final amount = (band['amount'] as num?)?.toDouble() ?? 0;
        final rate = (band['rate'] as num?)?.toDouble() ?? 0;
        final tax = (band['tax'] as num?)?.toDouble() ?? 0;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 10))),
              pw.SizedBox(width: 60, child: pw.Text('K ${_fmt.format(amount)}', style: pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: 40, child: pw.Text('${rate.toStringAsFixed(0)}%', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600), textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: 60, child: pw.Text('K ${_fmt.format(tax)}', style: pw.TextStyle(fontSize: 10, color: PdfColors.red700), textAlign: pw.TextAlign.right)),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _buildDisclaimer() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _hex('#FFF7ED'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('DISCLAIMER', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _hex('#C2410C'))),
          pw.SizedBox(height: 4),
          pw.Text(
            'This payslip is computer-generated and does not require a signature. '
            'NAPSA contributions are subject to a monthly cap of K1,861.80. '
            'PAYE is calculated using ZRA progressive tax bands (Tax-Free Threshold: K4,500/month). '
            'For queries, contact your payroll administrator.',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by Church On App Payroll', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          pw.Text('churchonapp.com', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  static pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _row(String label, double amount, {bool bold = false, bool isDeduction = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            '${isDeduction ? '-' : ''}K ${_fmt.format(amount)}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isDeduction ? PdfColors.red700 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _divider() => pw.Divider(color: PdfColors.grey300, height: 8);

  static Future<String> saveToFile(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> downloadPayslip({
    required Payslip payslip,
    required String employeeName,
    required String employeeRole,
    required String department,
    required String periodLabel,
    String? companyName,
  }) async {
    final bytes = await generatePayslip(
      payslip: payslip,
      employeeName: employeeName,
      employeeRole: employeeRole,
      department: department,
      periodLabel: periodLabel,
      companyName: companyName,
    );
    final safeName = employeeName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    await Printing.sharePdf(bytes: bytes, filename: 'payslip_${safeName}_$periodLabel.pdf');
  }

  static Future<void> sharePayslip({
    required Payslip payslip,
    required String employeeName,
    required String employeeRole,
    required String department,
    required String periodLabel,
    String? companyName,
  }) async {
    final bytes = await generatePayslip(
      payslip: payslip,
      employeeName: employeeName,
      employeeRole: employeeRole,
      department: department,
      periodLabel: periodLabel,
      companyName: companyName,
    );
    final safeName = employeeName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final path = await saveToFile(bytes, 'payslip_${safeName}_$periodLabel.pdf');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path)],
      text: 'Payslip for $employeeName — $periodLabel',
    ));
  }

  static Future<Uint8List> generateBulkPayslips({
    required List<Map<String, dynamic>> payslipsWithNames,
    required String periodLabel,
    String? companyName,
  }) async {
    final pdf = pw.Document();

    for (final data in payslipsWithNames) {
      final payslip = Payslip.fromMap(data);
      final empData = data['employees'] as Map<String, dynamic>?;
      final empName = empData?['full_name'] ?? 'Unknown';
      final empRole = empData?['role_title'] ?? '';
      final dept = empData?['department'] ?? '';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => _buildHeader(periodLabel, companyName),
          footer: (context) => _buildFooter(),
          build: (context) => [
            _buildEmployeeInfo(empName, empRole, dept),
            pw.SizedBox(height: 20),
            _buildEarningsSection(payslip),
            pw.SizedBox(height: 16),
            _buildDeductionsSection(payslip),
            pw.SizedBox(height: 16),
            _buildNetPaySection(payslip),
            pw.SizedBox(height: 20),
            _buildEmployerContributions(payslip),
            pw.SizedBox(height: 20),
            if (payslip.taxBreakdown.isNotEmpty) ...[
              _buildTaxBreakdown(payslip),
              pw.SizedBox(height: 16),
            ],
            _buildDisclaimer(),
          ],
        ),
      );
    }

    return pdf.save();
  }

  static Future<void> downloadBulkPayslips({
    required List<Map<String, dynamic>> payslipsWithNames,
    required String periodLabel,
    String? companyName,
  }) async {
    final bytes = await generateBulkPayslips(
      payslipsWithNames: payslipsWithNames,
      periodLabel: periodLabel,
      companyName: companyName,
    );
    await Printing.sharePdf(bytes: bytes, filename: 'payslips_$periodLabel.pdf');
  }

  static Future<void> downloadAnnualReport({
    required Map<String, dynamic> summary,
    required int year,
    String? companyName,
  }) async {
    final pdf = pw.Document();
    final s = summary;
    final months = (s['monthsProcessed'] as num?)?.toInt() ?? 0;
    final gross = (s['annualGross'] as num?)?.toDouble() ?? 0;
    final paye = (s['annualPaye'] as num?)?.toDouble() ?? 0;
    final napsaEe = (s['annualNapsaEmployee'] as num?)?.toDouble() ?? 0;
    final napsaEr = (s['annualNapsaEmployer'] as num?)?.toDouble() ?? 0;
    final nhimaEe = (s['annualNhimaEmployee'] as num?)?.toDouble() ?? 0;
    final nhimaEr = (s['annualNhimaEmployer'] as num?)?.toDouble() ?? 0;
    final sdl = (s['annualSdl'] as num?)?.toDouble() ?? 0;
    final net = (s['annualNetPay'] as num?)?.toDouble() ?? 0;
    final remittances = (s['totalRemittances'] as num?)?.toDouble() ?? 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader('ANNUAL REPORT $year', companyName),
        footer: (context) => _buildFooter(),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _hex('#F8FAFC'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Payroll Summary — $year', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('$months month(s) processed', style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _section(
            'ANNUAL TOTALS',
            [
              _row('Gross Salary', gross),
              _row('PAYE (Income Tax)', paye, isDeduction: true),
              _row('NAPSA (Employee 5%)', napsaEe, isDeduction: true),
              _row('NAPSA (Employer 5%)', napsaEr),
              _row('NHIMA (Employee 1%)', nhimaEe, isDeduction: true),
              _row('NHIMA (Employer 1%)', nhimaEr),
              if (sdl > 0) _row('SDL (0.5%)', sdl),
              _divider(),
              _row('Net Pay', net, bold: true),
            ],
          ),
          pw.SizedBox(height: 16),
          _section(
            'REMITTANCES TO ZRA / NAPSA / NHIMA',
            [_row('Total Statutory Remittances', remittances, bold: true)],
          ),
          pw.SizedBox(height: 20),
          _buildDisclaimer(),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'payroll_annual_$year.pdf');
  }
}
