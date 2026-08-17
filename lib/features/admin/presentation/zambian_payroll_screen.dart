import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import '../data/payroll_service.dart';

class ZambianPayrollScreen extends ConsumerStatefulWidget {
  const ZambianPayrollScreen({super.key});

  @override
  ConsumerState<ZambianPayrollScreen> createState() => _ZambianPayrollScreenState();
}

class _ZambianPayrollScreenState extends ConsumerState<ZambianPayrollScreen> {
  bool _isLoading = true;
  String? _error;
  List<Employee> _employees = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final tenant = ref.read(currentTenantProvider);
      if (tenant == null) {
        if (mounted) setState(() { _isLoading = false; _error = 'No church selected'; });
        return;
      }
      final emps = await ref.read(payrollServiceProvider).getEmployees(tenant.id);
      if (mounted) setState(() { _employees = emps; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _processStatutoryRun() async {
    final tenant = ref.read(currentTenantProvider);
    final user = Supabase.instance.client.auth.currentUser;
    if (tenant == null || user == null) return;
    setState(() => _isProcessing = true);
    try {
      final now = DateTime.now();
      final run = await ref.read(payrollServiceProvider).processPayroll(
        tenant.id,
        now.month,
        now.year,
        user.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Statutory run ${run.status}: ${run.employeeCount} employees, net pay K${run.totalNetPay.toStringAsFixed(2)}"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payroll run failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widgetRemoteConfig(ref);

    final nhimaPercent = config.getDouble('nhima_percent', 1.0);
    final napsaPercent = config.getDouble('napsa_percent', 5.0);
    final payeThreshold = config.getDouble('paye_threshold_kwacha', 5100.0);
    final turnoverTaxPercent = config.getDouble('turnover_tax_percent', 3.0);

    double totalGross = 0;
    double totalNhima = 0;
    double totalNapsa = 0;
    double totalPaye = 0;
    double totalTurnoverTax = 0;
    double totalNet = 0;

    for (final emp in _employees) {
      final gross = emp.totalEarnings;
      final calc = PayrollService.calculateEmployeePayroll(emp, taxFreeThreshold: payeThreshold);
      final nhima = gross * nhimaPercent / 100;
      final napsa = gross * napsaPercent / 100;
      final turnoverTax = gross * turnoverTaxPercent / 100;
      totalGross += gross;
      totalNhima += nhima;
      totalNapsa += napsa;
      totalPaye += (calc['paye'] as num?)?.toDouble() ?? 0;
      totalTurnoverTax += turnoverTax;
      totalNet += (calc['netPay'] as num?)?.toDouble() ?? 0;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Zambian Payroll & Deductions"),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _isLoading ? null : _loadEmployees,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text("Error: $_error"))
              : _employees.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.users, size: 44, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text("No employees registered for this church yet", textAlign: TextAlign.center),
                            const SizedBox(height: 6),
                            Text(
                              "Add employees in Payroll Processing to run the ZRA statutory run here.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFDA03), Color(0xFFE8A400)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Total Monthly Payroll", style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 5),
                                Text("ZMW ${totalGross.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black)),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Turnover Tax (${'$turnoverTaxPercent'.replaceFirst(RegExp(r'\.0$'), '')}%)",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                                    Text("- ZMW ${totalTurnoverTax.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Total Net Pay", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                                    Text("ZMW ${totalNet.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryStat("Deductions", "ZMW ${(totalNhima + totalNapsa + totalPaye).toStringAsFixed(2)}", LucideIcons.scissors, Theme.of(context).primaryColor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _summaryStat("Turnover Tax", "ZMW ${totalTurnoverTax.toStringAsFixed(2)}", LucideIcons.receipt, Colors.amber),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Text("Staff Deductions (NHIMA / NAPSA / PAYE + Turnover Tax)",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            "PAYE uses progressive ZRA bands (K4,500 tax-free). NHIMA $nhimaPercent%, NAPSA $napsaPercent%, Turnover Tax $turnoverTaxPercent% are remote-configurable in Platform Settings.",
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                          const SizedBox(height: 15),
                          ..._employees.map((employee) => _buildPayrollCard(
                            employee,
                            nhimaPercent: nhimaPercent,
                            napsaPercent: napsaPercent,
                            payeThreshold: payeThreshold,
                            turnoverTaxPercent: turnoverTaxPercent,
                          )),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _isProcessing || _employees.isEmpty ? null : _processStatutoryRun,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 55),
                            ),
                            child: _isProcessing
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                                : const Text("Process ZRA Statutory Run"),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _summaryStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollCard(
    Employee emp, {
    required double nhimaPercent,
    required double napsaPercent,
    required double payeThreshold,
    required double turnoverTaxPercent,
  }) {
    final gross = emp.totalEarnings;
    final calc = PayrollService.calculateEmployeePayroll(emp, taxFreeThreshold: payeThreshold);
    final nhima = gross * nhimaPercent / 100;
    final napsa = gross * napsaPercent / 100;
    final paye = (calc['paye'] as num?)?.toDouble() ?? 0;
    final turnoverTax = gross * turnoverTaxPercent / 100;
    final net = (calc['netPay'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!)
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(emp.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
              Text("Gross: K${gross.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          Text(emp.roleTitle, style: const TextStyle(color: Colors.grey)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("NAPSA (${'$napsaPercent'.replaceFirst(RegExp(r'\.0$'), '')}%)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${napsa.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("NHIMA (${'$nhimaPercent'.replaceFirst(RegExp(r'\.0$'), '')}%)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${nhima.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("PAYE (progressive bands)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${paye.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Turnover Tax (${'$turnoverTaxPercent'.replaceFirst(RegExp(r'\.0$'), '')}%)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${turnoverTax.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("NET PAY", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("K${net.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }
}