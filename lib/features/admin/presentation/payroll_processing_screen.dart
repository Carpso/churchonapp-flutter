import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../data/payroll_service.dart';
import 'payslip_detail_screen.dart';

final _payrollRunsProvider = FutureProvider.autoDispose<List<PayrollRun>>((ref) async {
  final tenantId = ref.watch(currentTenantProvider)?.id;
  if (tenantId == null) return [];
  return ref.read(payrollServiceProvider).getPayrollRuns(tenantId);
});

final _employeesProvider = FutureProvider.autoDispose<List<Employee>>((ref) async {
  final tenantId = ref.watch(currentTenantProvider)?.id;
  if (tenantId == null) return [];
  return ref.read(payrollServiceProvider).getEmployees(tenantId);
});

class PayrollProcessingScreen extends ConsumerStatefulWidget {
  const PayrollProcessingScreen({super.key});

  @override
  ConsumerState<PayrollProcessingScreen> createState() => _PayrollProcessingScreenState();
}

class _PayrollProcessingScreenState extends ConsumerState<PayrollProcessingScreen> {
  bool _isProcessing = false;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runsAsync = ref.watch(_payrollRunsProvider);
    final employeesAsync = ref.watch(_employeesProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Payroll Processing", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.calendar),
            onPressed: _pickMonth,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodSelector(theme),
            const SizedBox(height: 16),
            _buildProcessButton(theme, employeesAsync),
            const SizedBox(height: 24),
            const Text("Payroll History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            runsAsync.when(
              data: (runs) {
                if (runs.isEmpty) {
                  return _buildEmptyState(theme);
                }
                return Column(
                  children: runs.map((run) => _buildRunCard(run, theme)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme) {
    final months = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Payroll Period", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text("${months[_selectedMonth]} $_selectedYear", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
            ],
          ),
          IconButton(
            icon: const Icon(LucideIcons.chevronDown),
            onPressed: _pickMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessButton(ThemeData theme, AsyncValue<List<Employee>> employeesAsync) {
    return employeesAsync.when(
      data: (employees) {
        final activeEmps = employees.where((e) => e.isActive).toList();
        final totalGross = activeEmps.fold(0.0, (sum, e) => sum + e.totalEarnings);
        final totalPaye = activeEmps.fold(0.0, (sum, e) => sum + (PayrollService.calculateEmployeePayroll(e)['paye'] as double));
        final totalNapsa = activeEmps.fold(0.0, (sum, e) => sum + PayrollService.calculateNapsa(e.totalEarnings));
        final totalNhima = activeEmps.fold(0.0, (sum, e) => sum + PayrollService.calculateNhima(e.totalEarnings));
        final totalNet = totalGross - totalPaye - totalNapsa - totalNhima;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.teal.shade500],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.teal.withValues(alpha: 0.3), blurRadius: 12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${activeEmps.length} Active Employees", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Text("K${totalGross.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryPill("PAYE", totalPaye),
                  _summaryPill("NAPSA", totalNapsa),
                  _summaryPill("NHIMA", totalNhima),
                  _summaryPill("Net Pay", totalNet, isHighlight: true),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isProcessing || activeEmps.isEmpty ? null : () => _processPayroll(activeEmps.length),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.teal.shade700,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isProcessing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal))
                      : Text(
                          activeEmps.isEmpty ? "No Active Employees" : "PROCESS PAYROLL",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
    );
  }

  Widget _summaryPill(String label, double amount, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(
          "K${amount.toStringAsFixed(0)}",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isHighlight ? 16 : 13,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildRunCard(PayrollRun run, ThemeData theme) {
    final statusColor = switch (run.status) {
      'processed' => Colors.green,
      'paid' => Colors.blue,
      'draft' => Colors.orange,
      _ => Colors.grey,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(run.periodLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(run.status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("${run.employeeCount} employees • Gross: K${run.totalGross.toStringAsFixed(2)}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _runStat("PAYE", run.totalPaye, Colors.red),
              _runStat("NAPSA", run.totalNapsaEmployee + run.totalNapsaEmployer, Colors.orange),
              _runStat("NHIMA", run.totalNhimaEmployee + run.totalNhimaEmployer, Colors.purple),
              _runStat("Net", run.totalNetPay, Colors.green),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _viewPayslips(run),
              child: const Text("VIEW PAYSLIPS"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _runStat(String label, double amount, Color color) {
    return Column(
      children: [
        Text("K${amount.toStringAsFixed(0)}", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(LucideIcons.fileSpreadsheet, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text("No payroll runs yet", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text("Process your first payroll above", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_selectedYear, _selectedMonth),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = picked.month;
        _selectedYear = picked.year;
      });
    }
  }

  Future<void> _processPayroll(int employeeCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Process Payroll?"),
        content: Text("This will generate payslips for $employeeCount employees for ${_monthName(_selectedMonth)} $_selectedYear. Continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("PROCESS"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      final tenantId = ref.read(currentTenantProvider)?.id;
      final userId = ref.read(profileProvider).value?.id;
      if (tenantId == null || userId == null) throw Exception("Missing tenant or user");

      final run = await ref.read(payrollServiceProvider).processPayroll(
        tenantId, _selectedMonth, _selectedYear, userId,
      );

      ref.invalidate(_payrollRunsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Payroll processed! ${run.employeeCount} payslips generated."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _viewPayslips(PayrollRun run) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PayslipDetailScreen(payrollRun: run)),
    );
  }

  String _monthName(int month) {
    const names = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month];
  }
}
