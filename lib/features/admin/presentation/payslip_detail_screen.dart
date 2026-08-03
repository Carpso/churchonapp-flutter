import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/payroll_service.dart';
import '../data/payslip_pdf_service.dart';

class PayslipDetailScreen extends ConsumerStatefulWidget {
  final PayrollRun payrollRun;
  const PayslipDetailScreen({super.key, required this.payrollRun});

  @override
  ConsumerState<PayslipDetailScreen> createState() => _PayslipDetailScreenState();
}

class _PayslipDetailScreenState extends ConsumerState<PayslipDetailScreen> {
  List<Map<String, dynamic>> _payslipsWithNames = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPayslips();
  }

  Future<void> _loadPayslips() async {
    try {
      final res = await Supabase.instance.client
          .from('payslips')
          .select('*, employees(full_name, role_title, department)')
          .eq('payroll_run_id', widget.payrollRun.id)
          .order('created_at');

      setState(() {
        _payslipsWithNames = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadAllPayslips() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Generating PDF...")),
    );
    try {
      await PayslipPdfService.downloadBulkPayslips(
        payslipsWithNames: _payslipsWithNames,
        periodLabel: widget.payrollRun.periodLabel,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payslips downloaded"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadSinglePayslip(Map<String, dynamic> data) async {
    if (!mounted) return;
    final payslip = Payslip.fromMap(data);
    final emp = data['employees'] as Map<String, dynamic>?;
    try {
      await PayslipPdfService.downloadPayslip(
        payslip: payslip,
        employeeName: emp?['full_name'] ?? 'Unknown',
        employeeRole: emp?['role_title'] ?? '',
        department: emp?['department'] ?? '',
        periodLabel: widget.payrollRun.periodLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareSinglePayslip(Map<String, dynamic> data) async {
    if (!mounted) return;
    final payslip = Payslip.fromMap(data);
    final emp = data['employees'] as Map<String, dynamic>?;
    try {
      await PayslipPdfService.sharePayslip(
        payslip: payslip,
        employeeName: emp?['full_name'] ?? 'Unknown',
        employeeRole: emp?['role_title'] ?? '',
        department: emp?['department'] ?? '',
        periodLabel: widget.payrollRun.periodLabel,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = widget.payrollRun;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Payslips — ${run.periodLabel}", style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_payslipsWithNames.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.download),
              tooltip: "Download All Payslips (PDF)",
              onPressed: _downloadAllPayslips,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRunSummary(theme),
                  const SizedBox(height: 20),
                  const Text("Individual Payslips", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  if (_payslipsWithNames.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text("No payslips generated", style: TextStyle(color: Colors.grey)),
                    ))
                  else
                    ..._payslipsWithNames.map((p) => _buildPayslipCard(p, theme)),
                ],
              ),
            ),
    );
  }

  Widget _buildRunSummary(ThemeData theme) {
    final run = widget.payrollRun;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade500]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${run.periodLabel} Payroll Summary", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text("${run.employeeCount} employees processed", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _summaryStat("Gross", run.totalGross),
              _summaryStat("PAYE", run.totalPaye),
              _summaryStat("Net Pay", run.totalNetPay),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          Text("Statutory Remittances", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _remStat("ZRA (PAYE)", run.totalPaye),
              _remStat("NAPSA (EE+ER)", run.totalNapsaEmployee + run.totalNapsaEmployer),
              _remStat("NHIMA (EE+ER)", run.totalNhimaEmployee + run.totalNhimaEmployer),
            ],
          ),
          if (run.totalSdl > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _remStat("SDL (0.5%)", run.totalSdl),
                _remStat("Total Remit", run.totalPaye + run.totalNapsaEmployee + run.totalNapsaEmployer + run.totalNhimaEmployee + run.totalNhimaEmployer + run.totalSdl),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryStat(String label, double amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("K ${NumberFormat.decimalPattern().format(amount)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }

  Widget _remStat(String label, double amount) {
    return Column(
      children: [
        Text("K ${amount.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9)),
      ],
    );
  }

  Widget _buildPayslipCard(Map<String, dynamic> payslipData, ThemeData theme) {
    final payslip = Payslip.fromMap(payslipData);
    final empData = payslipData['employees'] as Map<String, dynamic>?;
    final empName = empData?['full_name'] ?? 'Unknown';
    final empRole = empData?['role_title'] ?? '';
    final empDept = empData?['department'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(empName.isNotEmpty ? empName[0].toUpperCase() : '?',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          title: Text(empName, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          subtitle: Text("$empRole • $empDept", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("K ${payslip.netPay.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade600, fontSize: 14)),
              const Text("NET PAY", style: TextStyle(fontSize: 8, color: Colors.grey)),
            ],
          ),
          children: [
            _buildPayslipBreakdown(payslip, payslipData, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPayslipBreakdown(Payslip payslip, Map<String, dynamic> payslipData, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("EARNINGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 6),
          _payslipRow("Basic Salary", payslip.basicSalary),
          if (payslip.allowances > 0) _payslipRow("Allowances", payslip.allowances),
          if (payslip.benefitsInKind > 0) _payslipRow("Benefits-in-Kind", payslip.benefitsInKind),
          _payslipRow("Gross Salary", payslip.grossSalary, bold: true),
          const SizedBox(height: 12),
          const Text("DEDUCTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 6),
          _payslipRow("PAYE (Income Tax)", payslip.paye, isDeduction: true),
          _payslipRow("NAPSA (Employee 5%)", payslip.napsaEmployee, isDeduction: true),
          _payslipRow("NHIMA (Employee 1%)", payslip.nhimaEmployee, isDeduction: true),
          _payslipRow("Total Deductions", payslip.totalDeductions, bold: true, isDeduction: true),
          const SizedBox(height: 12),
          const Divider(),
          _payslipRow("NET PAY", payslip.netPay, bold: true, isHighlight: true),
          const SizedBox(height: 12),
          const Text("EMPLOYER CONTRIBUTIONS (not deducted from employee)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1, color: Colors.grey)),
          const SizedBox(height: 6),
          _payslipRow("NAPSA (Employer 5%)", payslip.napsaEmployer, isGrey: true),
          _payslipRow("NHIMA (Employer 1%)", payslip.nhimaEmployer, isGrey: true),
          if (payslip.sdl > 0) _payslipRow("SDL (0.5%)", payslip.sdl, isGrey: true),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _downloadSinglePayslip(payslipData),
                  icon: const Icon(LucideIcons.download, size: 14),
                  label: const Text("Download PDF", style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareSinglePayslip(payslipData),
                  icon: const Icon(LucideIcons.share2, size: 14),
                  label: const Text("Share", style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payslipRow(String label, double amount, {bool bold = false, bool isDeduction = false, bool isHighlight = false, bool isGrey = false}) {
    final color = isHighlight
        ? Colors.green
        : isDeduction
            ? Colors.red
            : isGrey
                ? Colors.grey
                : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: isGrey ? Colors.grey.shade500 : null,
          )),
          Text(
            "${isDeduction ? '-' : ''}K ${amount.toStringAsFixed(2)}",
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
              fontSize: isHighlight ? 15 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
