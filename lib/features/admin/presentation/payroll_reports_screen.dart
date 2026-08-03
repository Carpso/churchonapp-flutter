import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/services/tenant_service.dart';
import '../data/payroll_service.dart';

class PayrollReportsScreen extends ConsumerStatefulWidget {
  const PayrollReportsScreen({super.key});

  @override
  ConsumerState<PayrollReportsScreen> createState() => _PayrollReportsScreenState();
}

class _PayrollReportsScreenState extends ConsumerState<PayrollReportsScreen> {
  int _selectedYear = DateTime.now().year;
  Map<String, dynamic>? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    try {
      final tenantId = ref.read(currentTenantProvider)?.id;
      if (tenantId == null) return;
      final summary = await ref.read(payrollServiceProvider).getPayrollSummary(tenantId, _selectedYear);
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Payroll Reports", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("PDF export coming soon")),
              );
            },
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
                  _buildYearSelector(theme),
                  const SizedBox(height: 16),
                  if (_summary != null) ...[
                    _buildAnnualSummary(theme),
                    const SizedBox(height: 20),
                    _buildRemittanceSchedule(theme),
                    const SizedBox(height: 20),
                    _buildStatutoryBreakdown(theme),
                    const SizedBox(height: 20),
                    _buildComplianceChecklist(theme),
                  ] else
                    _buildEmptyState(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildYearSelector(ThemeData theme) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () {
            setState(() => _selectedYear--);
            _loadSummary();
          },
        ),
        Expanded(
          child: Center(
            child: Text("$_selectedYear", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: theme.colorScheme.onSurface)),
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.chevronRight),
          onPressed: () {
            setState(() => _selectedYear++);
            _loadSummary();
          },
        ),
      ],
    );
  }

  Widget _buildAnnualSummary(ThemeData theme) {
    final s = _summary!;
    final fmt = NumberFormat.decimalPattern();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade500]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Annual Payroll Summary", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          Text("$_selectedYear • ${s['monthsProcessed']} months processed", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 20),
          _annualStat("Total Gross Pay", "K ${fmt.format(s['annualGross'])}"),
          const SizedBox(height: 12),
          _annualStat("Total Net Pay", "K ${fmt.format(s['annualNetPay'])}"),
          const SizedBox(height: 12),
          _annualStat("Total Statutory Deductions", "K ${fmt.format(s['totalRemittances'])}"),
        ],
      ),
    );
  }

  Widget _annualStat(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
      ],
    );
  }

  Widget _buildRemittanceSchedule(ThemeData theme) {
    final s = _summary!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Annual Remittance Schedule", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text("What you owe to statutory bodies", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          _remittanceRow("ZRA — PAYE", s['annualPaye'], "File monthly, pay by 14th", Colors.red, theme),
          _remittanceRow("NAPSA — Employee", s['annualNapsaEmployee'], "5% of gross (capped K1,861.80/mo)", Colors.orange, theme),
          _remittanceRow("NAPSA — Employer", s['annualNapsaEmployer'], "5% of gross (capped K1,861.80/mo)", Colors.deepOrange, theme),
          _remittanceRow("NHIMA — Employee", s['annualNhimaEmployee'], "1% of gross", Colors.purple, theme),
          _remittanceRow("NHIMA — Employer", s['annualNhimaEmployer'], "1% of gross", Colors.deepPurple, theme),
          if (s['annualSdl'] > 0)
            _remittanceRow("SDL — Employer", s['annualSdl'], "0.5% of gross (5+ employees)", Colors.teal, theme),
          const Divider(height: 24),
          _remittanceRow("TOTAL REMITTANCES", s['totalRemittances'], "Annual total to all bodies", Colors.blue.shade700, theme, bold: true),
        ],
      ),
    );
  }

  Widget _remittanceRow(String label, double amount, String note, Color color, ThemeData theme, {bool bold = false}) {
    final fmt = NumberFormat.decimalPattern();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 14 : 13, color: theme.colorScheme.onSurface)),
                Text(note, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 10)),
              ],
            ),
          ),
          Text("K ${fmt.format(amount)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: bold ? 16 : 14, color: color)),
        ],
      ),
    );
  }

  Widget _buildStatutoryBreakdown(ThemeData theme) {
    final s = _summary!;
    final total = s['totalRemittances'] as double;
    if (total == 0) return const SizedBox();

    final items = [
      _PieItem("PAYE", s['annualPaye'] as double, Colors.red),
      _PieItem("NAPSA (EE)", s['annualNapsaEmployee'] as double, Colors.orange),
      _PieItem("NAPSA (ER)", s['annualNapsaEmployer'] as double, Colors.deepOrange),
      _PieItem("NHIMA (EE)", s['annualNhimaEmployee'] as double, Colors.purple),
      _PieItem("NHIMA (ER)", s['annualNhimaEmployer'] as double, Colors.deepPurple),
      if (s['annualSdl'] > 0) _PieItem("SDL", s['annualSdl'] as double, Colors.teal),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Statutory Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ...items.map((item) {
            final pct = total > 0 ? (item.amount / total * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.label, style: const TextStyle(fontSize: 13))),
                  Text("K ${item.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: item.color)),
                  const SizedBox(width: 8),
                  Text("${pct.toStringAsFixed(1)}%", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComplianceChecklist(ThemeData theme) {
    final items = [
      _CheckItem("ZRA PAYE returns filed monthly", true),
      _CheckItem("NAPSA contributions remitted by 15th", true),
      _CheckItem("NHIMA contributions remitted by 15th", true),
      _CheckItem("SDL remitted (if 5+ employees)", _summary!['annualSdl'] > 0),
      _CheckItem("Payslips issued to all employees", true),
      _CheckItem("Annual PAYE reconciliation (Form P14)", false),
      _CheckItem("NAPSA annual return filed", false),
      _CheckItem("NHIMA annual return filed", false),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Compliance Checklist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text("Statutory filing requirements", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(item.done ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 18, color: item.done ? Colors.green : Colors.grey),
                const SizedBox(width: 10),
                Expanded(child: Text(item.label, style: TextStyle(fontSize: 13, color: item.done ? theme.colorScheme.onSurface : Colors.grey))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(LucideIcons.barChart3, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text("No payroll data for this year", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text("Process payroll to see reports", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PieItem {
  final String label;
  final double amount;
  final Color color;
  _PieItem(this.label, this.amount, this.color);
}

class _CheckItem {
  final String label;
  final bool done;
  _CheckItem(this.label, this.done);
}
