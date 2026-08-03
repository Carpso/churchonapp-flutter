import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Models ──────────────────────────────────────────────────────────

class Employee {
  final String id;
  final String? userId;
  final String tenantId;
  final String fullName;
  final String roleTitle;
  final String department;
  final DateTime? employmentDate;
  final String employmentType;
  final double grossSalary;
  final double allowances;
  final double benefitsInKind;
  final String? napsaNumber;
  final String? nhimaNumber;
  final String? taxReference;
  final String? bankName;
  final String? bankAccount;
  final String paymentMethod;
  final String? mobileNumber;
  final String? network;
  final bool isActive;

  Employee({
    required this.id,
    this.userId,
    required this.tenantId,
    required this.fullName,
    required this.roleTitle,
    this.department = 'general',
    this.employmentDate,
    this.employmentType = 'full_time',
    this.grossSalary = 0,
    this.allowances = 0,
    this.benefitsInKind = 0,
    this.napsaNumber,
    this.nhimaNumber,
    this.taxReference,
    this.bankName,
    this.bankAccount,
    this.paymentMethod = 'mobile_money',
    this.mobileNumber,
    this.network,
    this.isActive = true,
  });

  double get totalEarnings => grossSalary + allowances;

  factory Employee.fromMap(Map<String, dynamic> m) => Employee(
    id: m['id'] ?? '',
    userId: m['user_id'],
    tenantId: m['tenant_id'] ?? '',
    fullName: m['full_name'] ?? '',
    roleTitle: m['role_title'] ?? 'employee',
    department: m['department'] ?? 'general',
    employmentDate: m['employment_date'] != null ? DateTime.tryParse(m['employment_date']) : null,
    employmentType: m['employment_type'] ?? 'full_time',
    grossSalary: (m['gross_salary'] as num?)?.toDouble() ?? 0,
    allowances: (m['allowances'] as num?)?.toDouble() ?? 0,
    benefitsInKind: (m['benefits_in_kind'] as num?)?.toDouble() ?? 0,
    napsaNumber: m['napsa_number'],
    nhimaNumber: m['nhima_number'],
    taxReference: m['tax_reference'],
    bankName: m['bank_name'],
    bankAccount: m['bank_account'],
    paymentMethod: m['payment_method'] ?? 'mobile_money',
    mobileNumber: m['mobile_number'],
    network: m['network'],
    isActive: m['is_active'] ?? true,
  );

  Map<String, dynamic> toMap() => {
    if (userId != null) 'user_id': userId,
    'tenant_id': tenantId,
    'full_name': fullName,
    'role_title': roleTitle,
    'department': department,
    if (employmentDate != null) 'employment_date': employmentDate!.toIso8601String().split('T')[0],
    'employment_type': employmentType,
    'gross_salary': grossSalary,
    'allowances': allowances,
    'benefits_in_kind': benefitsInKind,
    if (napsaNumber != null) 'napsa_number': napsaNumber,
    if (nhimaNumber != null) 'nhima_number': nhimaNumber,
    if (taxReference != null) 'tax_reference': taxReference,
    if (bankName != null) 'bank_name': bankName,
    if (bankAccount != null) 'bank_account': bankAccount,
    'payment_method': paymentMethod,
    if (mobileNumber != null) 'mobile_number': mobileNumber,
    if (network != null) 'network': network,
    'is_active': isActive,
  };
}

class PayrollRun {
  final String id;
  final String tenantId;
  final int periodMonth;
  final int periodYear;
  final String status;
  final double totalGross;
  final double totalPaye;
  final double totalNapsaEmployee;
  final double totalNapsaEmployer;
  final double totalNhimaEmployee;
  final double totalNhimaEmployer;
  final double totalSdl;
  final double totalNetPay;
  final int employeeCount;
  final DateTime? processedAt;

  PayrollRun({
    required this.id,
    required this.tenantId,
    required this.periodMonth,
    required this.periodYear,
    this.status = 'draft',
    this.totalGross = 0,
    this.totalPaye = 0,
    this.totalNapsaEmployee = 0,
    this.totalNapsaEmployer = 0,
    this.totalNhimaEmployee = 0,
    this.totalNhimaEmployer = 0,
    this.totalSdl = 0,
    this.totalNetPay = 0,
    this.employeeCount = 0,
    this.processedAt,
  });

  double get totalEmployerCost => totalNapsaEmployer + totalNhimaEmployer + totalSdl;
  double get totalStatutoryCost => totalPaye + totalNapsaEmployee + totalNhimaEmployee;

  String get periodLabel {
    final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[periodMonth]} $periodYear';
  }

  factory PayrollRun.fromMap(Map<String, dynamic> m) => PayrollRun(
    id: m['id'] ?? '',
    tenantId: m['tenant_id'] ?? '',
    periodMonth: m['period_month'] ?? 1,
    periodYear: m['period_year'] ?? 2026,
    status: m['status'] ?? 'draft',
    totalGross: (m['total_gross'] as num?)?.toDouble() ?? 0,
    totalPaye: (m['total_paye'] as num?)?.toDouble() ?? 0,
    totalNapsaEmployee: (m['total_napsa_employee'] as num?)?.toDouble() ?? 0,
    totalNapsaEmployer: (m['total_napsa_employer'] as num?)?.toDouble() ?? 0,
    totalNhimaEmployee: (m['total_nhima_employee'] as num?)?.toDouble() ?? 0,
    totalNhimaEmployer: (m['total_nhima_employer'] as num?)?.toDouble() ?? 0,
    totalSdl: (m['total_sdl'] as num?)?.toDouble() ?? 0,
    totalNetPay: (m['total_net_pay'] as num?)?.toDouble() ?? 0,
    employeeCount: m['employee_count'] ?? 0,
    processedAt: m['processed_at'] != null ? DateTime.tryParse(m['processed_at']) : null,
  );
}

class Payslip {
  final String id;
  final String payrollRunId;
  final String employeeId;
  final String tenantId;
  final double basicSalary;
  final double allowances;
  final double benefitsInKind;
  final double grossSalary;
  final double paye;
  final double napsaEmployee;
  final double nhimaEmployee;
  final double napsaEmployer;
  final double nhimaEmployer;
  final double sdl;
  final double totalDeductions;
  final double netPay;
  final Map<String, dynamic> taxBreakdown;
  final String status;
  final DateTime? createdAt;

  Payslip({
    required this.id,
    required this.payrollRunId,
    required this.employeeId,
    required this.tenantId,
    this.basicSalary = 0,
    this.allowances = 0,
    this.benefitsInKind = 0,
    this.grossSalary = 0,
    this.paye = 0,
    this.napsaEmployee = 0,
    this.nhimaEmployee = 0,
    this.napsaEmployer = 0,
    this.nhimaEmployer = 0,
    this.sdl = 0,
    this.totalDeductions = 0,
    this.netPay = 0,
    this.taxBreakdown = const {},
    this.status = 'draft',
    this.createdAt,
  });

  factory Payslip.fromMap(Map<String, dynamic> m) => Payslip(
    id: m['id'] ?? '',
    payrollRunId: m['payroll_run_id'] ?? '',
    employeeId: m['employee_id'] ?? '',
    tenantId: m['tenant_id'] ?? '',
    basicSalary: (m['basic_salary'] as num?)?.toDouble() ?? 0,
    allowances: (m['allowances'] as num?)?.toDouble() ?? 0,
    benefitsInKind: (m['benefits_in_kind'] as num?)?.toDouble() ?? 0,
    grossSalary: (m['gross_salary'] as num?)?.toDouble() ?? 0,
    paye: (m['paye'] as num?)?.toDouble() ?? 0,
    napsaEmployee: (m['napsa_employee'] as num?)?.toDouble() ?? 0,
    nhimaEmployee: (m['nhima_employee'] as num?)?.toDouble() ?? 0,
    napsaEmployer: (m['napsa_employer'] as num?)?.toDouble() ?? 0,
    nhimaEmployer: (m['nhima_employer'] as num?)?.toDouble() ?? 0,
    sdl: (m['sdl'] as num?)?.toDouble() ?? 0,
    totalDeductions: (m['total_deductions'] as num?)?.toDouble() ?? 0,
    netPay: (m['net_pay'] as num?)?.toDouble() ?? 0,
    taxBreakdown: m['tax_breakdown'] is Map ? Map<String, dynamic>.from(m['tax_breakdown']) : {},
    status: m['status'] ?? 'draft',
    createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at']) : null,
  );
}

// ── Service ──────────────────────────────────────────────────────────

class PayrollService {
  final SupabaseClient _client;
  PayrollService(this._client);

  // ── Employee CRUD ─────────────────────────────────────────────────

  Future<List<Employee>> getEmployees(String tenantId) async {
    final res = await _client
        .from('employees')
        .select()
        .eq('tenant_id', tenantId)
        .order('full_name');
    return (res as List).map((m) => Employee.fromMap(m)).toList();
  }

  Stream<List<Employee>> getEmployeesStream(String tenantId) {
    return _client
        .from('employees')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .order('full_name')
        .map((data) => data.map((m) => Employee.fromMap(m)).toList());
  }

  Future<Employee> addEmployee(Employee emp) async {
    final res = await _client.from('employees').insert(emp.toMap()).select().single();
    return Employee.fromMap(res);
  }

  Future<void> updateEmployee(String id, Map<String, dynamic> updates) async {
    await _client.from('employees').update(updates).eq('id', id);
  }

  Future<void> deactivateEmployee(String id) async {
    await _client.from('employees').update({'is_active': false}).eq('id', id);
  }

  // ── PAYE Calculation (Progressive Zambian Tax Bands) ──────────────

  static const List<Map<String, dynamic>> defaultTaxBands = [
    {'min': 0, 'max': 4500, 'rate': 0.0, 'label': 'Tax-Free'},
    {'min': 4501, 'max': 6800, 'rate': 0.20, 'label': 'Band 1 (20%)'},
    {'min': 6801, 'max': 9800, 'rate': 0.25, 'label': 'Band 2 (25%)'},
    {'min': 9801, 'max': 14500, 'rate': 0.30, 'label': 'Band 3 (30%)'},
    {'min': 14501, 'max': null, 'rate': 0.35, 'label': 'Band 4 (35%)'},
  ];

  /// Calculate PAYE using progressive Zambian tax bands.
  /// Returns {taxableIncome, totalTax, bands: [{band, amount, rate, tax}]}
  static Map<String, dynamic> calculatePaye(double grossSalary, {double taxFreeThreshold = 4500}) {
    final taxable = grossSalary - taxFreeThreshold;
    if (taxable <= 0) {
      return {
        'taxableIncome': 0.0,
        'totalTax': 0.0,
        'bands': [
          {'band': 'Tax-Free', 'amount': grossSalary, 'rate': 0.0, 'tax': 0.0},
        ],
      };
    }

    double remaining = taxable;
    double totalTax = 0;
    final bands = <Map<String, dynamic>>[];

    for (final band in defaultTaxBands) {
      if (remaining <= 0) break;
      if (band['rate'] == 0.0) continue;

      final bandMin = (band['min'] as int).toDouble();
      final bandMax = band['max'] != null ? (band['max'] as int).toDouble() : 999999999.0;
      final bandWidth = bandMax - bandMin + 1;
      final bandAmount = remaining < bandWidth ? remaining : bandWidth;
      final bandTax = bandAmount * (band['rate'] as double);

      totalTax += bandTax;
      remaining -= bandAmount;

      bands.add({
        'band': band['label'],
        'amount': bandAmount,
        'rate': (band['rate'] as double) * 100,
        'tax': bandTax,
      });
    }

    return {
      'taxableIncome': taxable,
      'totalTax': totalTax,
      'bands': bands,
    };
  }

  /// Calculate NAPSA (capped at K1,861.80/month)
  static double calculateNapsa(double grossSalary, {double cap = 1861.80}) {
    final contribution = grossSalary * 0.05;
    return contribution > cap ? cap : contribution;
  }

  /// Calculate NHIMA (1% of gross, no cap)
  static double calculateNhima(double grossSalary) {
    return grossSalary * 0.01;
  }

  /// Calculate SDL (0.5% employer-only, if 5+ employees)
  static double calculateSdl(double totalGrossPayroll, int employeeCount, {int threshold = 5, double rate = 0.005}) {
    if (employeeCount < threshold) return 0;
    return totalGrossPayroll * rate;
  }

  /// Full payroll calculation for a single employee
  static Map<String, dynamic> calculateEmployeePayroll(Employee emp, {double taxFreeThreshold = 4500}) {
    final gross = emp.grossSalary + emp.allowances;
    final payeResult = calculatePaye(gross, taxFreeThreshold: taxFreeThreshold);
    final napsa = calculateNapsa(gross);
    final nhima = calculateNhima(gross);
    final totalDeductions = payeResult['totalTax'] + napsa + nhima;
    final netPay = gross - totalDeductions;

    return {
      'gross': gross,
      'basicSalary': emp.grossSalary,
      'allowances': emp.allowances,
      'benefitsInKind': emp.benefitsInKind,
      'paye': payeResult['totalTax'],
      'payeBreakdown': payeResult['bands'],
      'taxableIncome': payeResult['taxableIncome'],
      'napsaEmployee': napsa,
      'napsaEmployer': napsa, // same amount
      'nhimaEmployee': nhima,
      'nhimaEmployer': nhima,
      'totalDeductions': totalDeductions,
      'netPay': netPay,
    };
  }

  // ── Payroll Run ──────────────────────────────────────────────────

  Future<PayrollRun> processPayroll(String tenantId, int month, int year, String processedBy) async {
    final res = await _client.rpc('process_payroll', params: {
      'p_tenant_id': tenantId,
      'p_month': month,
      'p_year': year,
      'p_processed_by': processedBy,
    });
    final runRes = await _client.from('payroll_runs').select().eq('id', res['run_id']).single();
    return PayrollRun.fromMap(runRes);
  }

  Future<List<PayrollRun>> getPayrollRuns(String tenantId) async {
    final res = await _client
        .from('payroll_runs')
        .select()
        .eq('tenant_id', tenantId)
        .order('period_year', ascending: false)
        .order('period_month', ascending: false);
    return (res as List).map((m) => PayrollRun.fromMap(m)).toList();
  }

  Future<PayrollRun?> getPayrollRun(String runId) async {
    try {
      final res = await _client.from('payroll_runs').select().eq('id', runId).single();
      return PayrollRun.fromMap(res);
    } catch (_) {
      return null;
    }
  }

  // ── Payslips ──────────────────────────────────────────────────────

  Future<List<Payslip>> getPayslips(String runId) async {
    final res = await _client
        .from('payslips')
        .select('*, employees(full_name, role_title, department)')
        .eq('payroll_run_id', runId)
        .order('created_at');
    return (res as List).map((m) => Payslip.fromMap(m)).toList();
  }

  Future<Payslip?> getPayslip(String payslipId) async {
    try {
      final res = await _client.from('payslips').select('*, employees(full_name, role_title, department)').eq('id', payslipId).single();
      return Payslip.fromMap(res);
    } catch (_) {
      return null;
    }
  }

  Future<List<Payslip>> getEmployeePayslips(String employeeId) async {
    final res = await _client
        .from('payslips')
        .select()
        .eq('employee_id', employeeId)
        .order('created_at', ascending: false)
        .limit(12);
    return (res as List).map((m) => Payslip.fromMap(m)).toList();
  }

  // ── Summary Reports ──────────────────────────────────────────────

  Future<Map<String, dynamic>> getPayrollSummary(String tenantId, int year) async {
    final res = await _client
        .from('payroll_runs')
        .select('period_month, total_gross, total_paye, total_napsa_employee, total_napsa_employer, total_nhima_employee, total_nhima_employer, total_sdl, total_net_pay, employee_count')
        .eq('tenant_id', tenantId)
        .eq('period_year', year)
        .eq('status', 'processed');

    double annualGross = 0, annualPaye = 0, annualNapsaEe = 0, annualNapsaEr = 0;
    double annualNhimaEe = 0, annualNhimaEr = 0, annualSdl = 0, annualNet = 0;

    for (final row in res as List) {
      annualGross += (row['total_gross'] as num?)?.toDouble() ?? 0;
      annualPaye += (row['total_paye'] as num?)?.toDouble() ?? 0;
      annualNapsaEe += (row['total_napsa_employee'] as num?)?.toDouble() ?? 0;
      annualNapsaEr += (row['total_napsa_employer'] as num?)?.toDouble() ?? 0;
      annualNhimaEe += (row['total_nhima_employee'] as num?)?.toDouble() ?? 0;
      annualNhimaEr += (row['total_nhima_employer'] as num?)?.toDouble() ?? 0;
      annualSdl += (row['total_sdl'] as num?)?.toDouble() ?? 0;
      annualNet += (row['total_net_pay'] as num?)?.toDouble() ?? 0;
    }

    return {
      'monthsProcessed': (res as List).length,
      'annualGross': annualGross,
      'annualPaye': annualPaye,
      'annualNapsaEmployee': annualNapsaEe,
      'annualNapsaEmployer': annualNapsaEr,
      'annualNhimaEmployee': annualNhimaEe,
      'annualNhimaEmployer': annualNhimaEr,
      'annualSdl': annualSdl,
      'annualNetPay': annualNet,
      'totalRemittances': annualPaye + annualNapsaEe + annualNapsaEr + annualNhimaEe + annualNhimaEr + annualSdl,
    };
  }
}

final payrollServiceProvider = Provider((ref) => PayrollService(Supabase.instance.client));
