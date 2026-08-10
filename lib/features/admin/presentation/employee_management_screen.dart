import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/services/tenant_service.dart';
import '../data/payroll_service.dart';

final _employeesProvider = StreamProvider.autoDispose<List<Employee>>((ref) {
  final tenantId = ref.watch(currentTenantProvider)?.id;
  if (tenantId == null) return Stream.value([]);
  return ref.watch(payrollServiceProvider).getEmployeesStream(tenantId);
});

class EmployeeManagementScreen extends ConsumerStatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  ConsumerState<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends ConsumerState<EmployeeManagementScreen> {
  String _searchQuery = '';
  String _filterDept = 'All';

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(_employeesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Employee Management", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.userPlus),
            onPressed: () => _showAddEmployeeSheet(context),
          ),
        ],
      ),
      body: employeesAsync.when(
        data: (employees) {
          final filtered = employees.where((e) {
            final matchesSearch = e.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                e.roleTitle.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchesDept = _filterDept == 'All' || e.department == _filterDept;
            return matchesSearch && matchesDept;
          }).toList();

          final activeCount = employees.where((e) => e.isActive).length;
          final totalPayroll = employees.where((e) => e.isActive).fold(0.0, (sum, e) => sum + e.totalEarnings);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCard(activeCount, totalPayroll),
                const SizedBox(height: 16),
                _buildSearchAndFilter(employees),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  _buildEmptyState()
                else
                  ...filtered.map((emp) => _buildEmployeeCard(emp)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSummaryCard(int activeCount, double totalPayroll) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Monthly Payroll", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text("K ${NumberFormat.decimalPattern().format(totalPayroll)}", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(
            children: [
              _pill("$activeCount Active Staff", Icons.people, Colors.white),
              const SizedBox(width: 8),
              _pill("K ${NumberFormat.decimalPattern().format(PayrollService.calculateNapsa(totalPayroll))} NAPSA", Icons.shield, Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, color: color, size: 12), const SizedBox(width: 4), Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold))],
      ),
    );
  }

  Widget _buildSearchAndFilter(List<Employee> employees) {
    final depts = ['All', ...{...employees.map((e) => e.department)}];
    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: "Search employees...",
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: depts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final dept = depts[i];
              final selected = _filterDept == dept;
              return GestureDetector(
                onTap: () => setState(() => _filterDept = dept),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(dept, style: TextStyle(
                    color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                    fontSize: 12, fontWeight: FontWeight.bold,
                  )),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(LucideIcons.users, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text("No employees yet", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text("Add your first employee to start payroll", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddEmployeeSheet(context),
              icon: const Icon(LucideIcons.userPlus, size: 16),
              label: const Text("Add Employee"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeCard(Employee emp) {
    final theme = Theme.of(context);
    final calculation = PayrollService.calculateEmployeePayroll(emp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Text(emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : '?',
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emp.fullName, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    Text("${emp.roleTitle} • ${emp.department.toUpperCase()}", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'payslip', child: Text('View Payslips')),
                  if (emp.isActive) const PopupMenuItem(value: 'deactivate', child: Text('Deactivate', style: TextStyle(color: Colors.red))),
                ],
                onSelected: (action) => _handleAction(action, emp),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat("Gross", "K${emp.totalEarnings.toStringAsFixed(0)}", theme.colorScheme.primary),
                _miniStat("PAYE", "-K${calculation['paye'].toStringAsFixed(0)}", Colors.red),
                _miniStat("NAPSA", "-K${calculation['napsaEmployee'].toStringAsFixed(0)}", Colors.orange),
                _miniStat("Net", "K${calculation['netPay'].toStringAsFixed(0)}", Colors.green),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }

  void _handleAction(String action, Employee emp) {
    switch (action) {
      case 'edit':
        _showAddEmployeeSheet(context, employee: emp);
        break;
      case 'deactivate':
        _confirmDeactivate(emp);
        break;
    }
  }

  void _confirmDeactivate(Employee emp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Deactivate Employee"),
        content: Text("Remove ${emp.fullName} from active payroll?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(payrollServiceProvider).deactivateEmployee(emp.id);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Deactivate"),
          ),
        ],
      ),
    );
  }

  void _showAddEmployeeSheet(BuildContext context, {Employee? employee}) {
    final isEdit = employee != null;
    final nameCtrl = TextEditingController(text: employee?.fullName ?? '');
    final roleCtrl = TextEditingController(text: employee?.roleTitle ?? '');
    final deptCtrl = TextEditingController(text: employee?.department ?? 'general');
    final salaryCtrl = TextEditingController(text: employee?.grossSalary.toStringAsFixed(0) ?? '');
    final allowanceCtrl = TextEditingController(text: employee?.allowances.toStringAsFixed(0) ?? '');
    final napsaCtrl = TextEditingController(text: employee?.napsaNumber ?? '');
    final nhimaCtrl = TextEditingController(text: employee?.nhimaNumber ?? '');
    final phoneCtrl = TextEditingController(text: employee?.mobileNumber ?? '');
    String empType = employee?.employmentType ?? 'full_time';
    String payMethod = employee?.paymentMethod ?? 'mobile_money';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(isEdit ? "Edit Employee" : "Add Employee", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 20),
              _field("Full Name", nameCtrl, LucideIcons.user),
              const SizedBox(height: 12),
              _field("Job Title / Role", roleCtrl, LucideIcons.briefcase),
              const SizedBox(height: 12),
              _field("Department", deptCtrl, LucideIcons.building),
              const SizedBox(height: 12),
              _field("Gross Salary (K)", salaryCtrl, LucideIcons.banknote, isNumber: true),
              const SizedBox(height: 12),
              _field("Monthly Allowances (K)", allowanceCtrl, LucideIcons.wallet, isNumber: true),
              const SizedBox(height: 12),
              _field("NAPSA Number", napsaCtrl, LucideIcons.shield),
              const SizedBox(height: 12),
              _field("NHIMA Number", nhimaCtrl, LucideIcons.heart),
              const SizedBox(height: 12),
              _field("Mobile Number", phoneCtrl, LucideIcons.phone),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: empType,
                      items: const [
                        DropdownMenuItem(value: 'full_time', child: Text('Full Time')),
                        DropdownMenuItem(value: 'part_time', child: Text('Part Time')),
                        DropdownMenuItem(value: 'contract', child: Text('Contract')),
                        DropdownMenuItem(value: 'casual', child: Text('Casual')),
                      ],
                      onChanged: (v) => empType = v ?? empType,
                      decoration: const InputDecoration(labelText: "Employment Type", border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: payMethod,
                      items: const [
                        DropdownMenuItem(value: 'mobile_money', child: Text('Mobile Money')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      ],
                      onChanged: (v) => payMethod = v ?? payMethod,
                      decoration: const InputDecoration(labelText: "Payment Method", border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Live preview
              if (salaryCtrl.text.isNotEmpty && double.tryParse(salaryCtrl.text) != null) ...[
                _livePreview(double.tryParse(salaryCtrl.text) ?? 0, double.tryParse(allowanceCtrl.text) ?? 0),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final salary = double.tryParse(salaryCtrl.text) ?? 0;
                    if (nameCtrl.text.isEmpty || salary <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Name and salary are required"), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final tenantId = ref.read(currentTenantProvider)?.id ?? '';
                    final emp = Employee(
                      id: employee?.id ?? '',
                      tenantId: tenantId,
                      fullName: nameCtrl.text.trim(),
                      roleTitle: roleCtrl.text.trim(),
                      department: deptCtrl.text.trim(),
                      grossSalary: salary,
                      allowances: double.tryParse(allowanceCtrl.text) ?? 0,
                      napsaNumber: napsaCtrl.text.isNotEmpty ? napsaCtrl.text : null,
                      nhimaNumber: nhimaCtrl.text.isNotEmpty ? nhimaCtrl.text : null,
                      mobileNumber: phoneCtrl.text.isNotEmpty ? phoneCtrl.text : null,
                      employmentType: empType,
                      paymentMethod: payMethod,
                    );

                    final svc = ref.read(payrollServiceProvider);
                    if (isEdit) {
                      await svc.updateEmployee(emp.id, emp.toMap());
                    } else {
                      await svc.addEmployee(emp);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isEdit ? "Employee updated!" : "Employee added!"), backgroundColor: Colors.green),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(isEdit ? "UPDATE EMPLOYEE" : "ADD EMPLOYEE", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _livePreview(double salary, double allowances) {
    final gross = salary + allowances;
    final payeResult = PayrollService.calculatePaye(gross);
    final napsa = PayrollService.calculateNapsa(gross);
    final nhima = PayrollService.calculateNhima(gross);
    final net = gross - payeResult['totalTax'] - napsa - nhima;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Payroll Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _previewRow("Gross", "K${gross.toStringAsFixed(2)}", Colors.blue),
          _previewRow("PAYE", "-K${payeResult['totalTax'].toStringAsFixed(2)}", Colors.red),
          _previewRow("NAPSA (5%)", "-K${napsa.toStringAsFixed(2)}", Colors.orange),
          _previewRow("NHIMA (1%)", "-K${nhima.toStringAsFixed(2)}", Colors.purple),
          const Divider(),
          _previewRow("NET PAY", "K${net.toStringAsFixed(2)}", Colors.green, bold: true),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: bold ? FontWeight.w900 : FontWeight.bold)),
        ],
      ),
    );
  }
}
