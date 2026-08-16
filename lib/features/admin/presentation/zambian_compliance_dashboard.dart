import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum EntityType { church, bookshop, driver, general }

class EntityTypeNotifier extends Notifier<EntityType> {
  @override
  EntityType build() => EntityType.church;

  void set(EntityType type) => state = type;
}

final entityTypeProvider = NotifierProvider<EntityTypeNotifier, EntityType>(() {
  return EntityTypeNotifier();
});

class ComplianceObligation {
  final String id;
  final String body;
  final String category;
  final String name;
  final String description;
  final double rate;
  final String rateLabel;
  final bool isApplicable;
  final String exemptionNote;
  final double calculatedAmount;
  final String status;

  const ComplianceObligation({
    required this.id,
    required this.body,
    required this.category,
    required this.name,
    required this.description,
    required this.rate,
    required this.rateLabel,
    required this.isApplicable,
    this.exemptionNote = '',
    this.calculatedAmount = 0.0,
    this.status = 'pending',
  });
}

class ComplianceSummary {
  final String body;
  final String icon;
  final int totalObligations;
  final int applicableCount;
  final int compliantCount;
  final double totalAmountDue;

  const ComplianceSummary({
    required this.body,
    required this.icon,
    required this.totalObligations,
    required this.applicableCount,
    required this.compliantCount,
    required this.totalAmountDue,
  });
}

final complianceObligationsProvider = FutureProvider.family<List<ComplianceObligation>, EntityType>((ref, entityType) async {
  final client = Supabase.instance.client;

  double totalRevenue = 0;
  int employeeCount = 0;

  try {
    final txsRes = await client.from('transactions').select('amount');
    for (final tx in txsRes) {
      totalRevenue += (tx['amount'] as num?)?.toDouble() ?? 0;
    }

    final profilesRes = await client.from('profiles').select('id').eq('is_work_mode', true);
    employeeCount = profilesRes.length;
  } catch (e) { debugPrint('Compliance dashboard error: $e'); }

  final obligations = <ComplianceObligation>[];

  // ── ZRA: Zambia Revenue Authority ─────────────────────────────────

  // PAYE (Pay As You Earn) — only if has employees
  final hasEmployees = employeeCount > 0;

  obligations.add(ComplianceObligation(
    id: 'zra_paye',
    body: 'ZRA',
    category: 'Income Tax',
    name: 'PAYE (Pay As You Earn)',
    description: 'Monthly deduction from employee salaries. Employer must remit by 14th of following month.',
    rate: 0.0,
    rateLabel: 'Progressive: 0%–35%',
    isApplicable: hasEmployees,
    exemptionNote: hasEmployees ? '' : 'No employees — not applicable',
    calculatedAmount: 0,
    status: hasEmployees ? 'action_required' : 'not_applicable',
  ));

  // VAT — 16% on taxable supplies
  final annualRevenue = totalRevenue;
  final vatThreshold = 1200000.0; // K1.2M annual threshold for mandatory VAT
  final isVatRegistered = entityType != EntityType.church;
  final vatAmount = isVatRegistered ? annualRevenue * 0.16 : 0.0;

  obligations.add(ComplianceObligation(
    id: 'zra_vat',
    body: 'ZRA',
    category: 'Consumption Tax',
    name: 'VAT (Value Added Tax)',
    description: '16% on taxable goods and services. Mandatory if annual turnover > K1.2M. Churches are exempt under s16(3)(c) VAT Act.',
    rate: 0.16,
    rateLabel: '16%',
    isApplicable: isVatRegistered && annualRevenue > vatThreshold,
    exemptionNote: entityType == EntityType.church
        ? 'Exempt under s16(3)(c) VAT Act — religious services'
        : annualRevenue <= vatThreshold
            ? 'Below K1.2M threshold — voluntary registration only'
            : '',
    calculatedAmount: vatAmount,
    status: isVatRegistered && annualRevenue > vatThreshold ? 'action_required' : 'exempt',
  ));

  // Turnover Tax — 5% for turnover > K5M
  final turnoverTaxRate = annualRevenue > 5000000 ? 0.05 : 0.03;
  final turnoverTaxAmount = totalRevenue * turnoverTaxRate;

  obligations.add(ComplianceObligation(
    id: 'zra_turnover',
    body: 'ZRA',
    category: 'Income Tax',
    name: 'Turnover Tax',
    description: 'Simplified tax for businesses with turnover K2.5M–K5M (3%) or >K5M (5%). Not applicable to exempt organizations.',
    rate: turnoverTaxRate,
    rateLabel: '${(turnoverTaxRate * 100).toStringAsFixed(0)}%',
    isApplicable: entityType != EntityType.church,
    exemptionNote: entityType == EntityType.church
        ? 'Exempt — churches are non-profit organizations'
        : '',
    calculatedAmount: turnoverTaxAmount,
    status: entityType != EntityType.church ? 'pending' : 'exempt',
  ));

  // Withholding Tax on supplies — 5%
  obligations.add(ComplianceObligation(
    id: 'zra_wht_supplies',
    body: 'ZRA',
    category: 'Withholding Tax',
    name: 'WHT on Supplies (5%)',
    description: 'Withheld by businesses when paying suppliers for goods. Remitted to ZRA monthly.',
    rate: 0.05,
    rateLabel: '5%',
    isApplicable: entityType == EntityType.bookshop || entityType == EntityType.driver,
    exemptionNote: entityType == EntityType.church
        ? 'Exempt — churches not subject to WHT on own supplies'
        : '',
    calculatedAmount: totalRevenue * 0.05,
    status: entityType == EntityType.church ? 'exempt' : 'pending',
  ));

  // Withholding Tax on services — 15%
  obligations.add(ComplianceObligation(
    id: 'zra_wht_services',
    body: 'ZRA',
    category: 'Withholding Tax',
    name: 'WHT on Services (15%)',
    description: 'Withheld by businesses when paying for services. Contractors, consultants, professionals.',
    rate: 0.15,
    rateLabel: '15%',
    isApplicable: entityType == EntityType.bookshop,
    exemptionNote: entityType == EntityType.church
        ? 'Exempt — churches not subject to WHT on own services'
        : '',
    calculatedAmount: totalRevenue * 0.15,
    status: entityType == EntityType.church ? 'exempt' : 'pending',
  ));

  // Withholding Tax on dividends — 10%
  obligations.add(ComplianceObligation(
    id: 'zra_wht_dividends',
    body: 'ZRA',
    category: 'Withholding Tax',
    name: 'WHT on Dividends (10%)',
    description: 'Withheld when distributing dividends to shareholders.',
    rate: 0.10,
    rateLabel: '10%',
    isApplicable: entityType == EntityType.bookshop,
    exemptionNote: 'Not applicable to churches or individual drivers',
    calculatedAmount: 0,
    status: 'not_applicable',
  ));

  // Property Transfer Tax — 5%
  obligations.add(ComplianceObligation(
    id: 'zra_ptt',
    body: 'ZRA',
    category: 'Property Tax',
    name: 'Property Transfer Tax (5%)',
    description: 'Paid on transfer of property (land, shares, buildings). 5% of property value.',
    rate: 0.05,
    rateLabel: '5%',
    isApplicable: false,
    exemptionNote: 'Only applicable on property transfer events — not a recurring obligation',
    calculatedAmount: 0,
    status: 'not_applicable',
  ));

  // ── NAPSA: National Pension Scheme Authority ──────────────────────

  obligations.add(ComplianceObligation(
    id: 'napsa_employer',
    body: 'NAPSA',
    category: 'Pension',
    name: 'NAPSA Employer Contribution (5%)',
    description: 'Employer contributes 5% of pensionable emoluments. Capped at K1,861.80/month per employee.',
    rate: 0.05,
    rateLabel: '5% (cap K1,861.80/mo)',
    isApplicable: hasEmployees,
    exemptionNote: hasEmployees ? '' : 'No employees — not applicable',
    calculatedAmount: 0,
    status: hasEmployees ? 'action_required' : 'not_applicable',
  ));

  obligations.add(ComplianceObligation(
    id: 'napsa_employee',
    body: 'NAPSA',
    category: 'Pension',
    name: 'NAPSA Employee Contribution (5%)',
    description: 'Deducted from employee salary. 5% of pensionable emoluments. Capped at K1,861.80/month.',
    rate: 0.05,
    rateLabel: '5% (cap K1,861.80/mo)',
    isApplicable: hasEmployees,
    exemptionNote: hasEmployees ? '' : 'No employees — not applicable',
    calculatedAmount: 0,
    status: hasEmployees ? 'action_required' : 'not_applicable',
  ));

  // ── NHIMA: National Health Insurance Management Authority ─────────

  obligations.add(ComplianceObligation(
    id: 'nhima_employer',
    body: 'NHIMA',
    category: 'Health Insurance',
    name: 'NHIMA Employer Contribution (1%)',
    description: 'Employer contributes 1% of gross salaries. Mandatory for all employers with 1+ employees.',
    rate: 0.01,
    rateLabel: '1%',
    isApplicable: hasEmployees,
    exemptionNote: hasEmployees ? '' : 'No employees — not applicable',
    calculatedAmount: 0,
    status: hasEmployees ? 'action_required' : 'not_applicable',
  ));

  obligations.add(ComplianceObligation(
    id: 'nhima_employee',
    body: 'NHIMA',
    category: 'Health Insurance',
    name: 'NHIMA Employee Contribution (1%)',
    description: 'Deducted from employee salary. 1% of gross salary.',
    rate: 0.01,
    rateLabel: '1%',
    isApplicable: hasEmployees,
    exemptionNote: hasEmployees ? '' : 'No employees — not applicable',
    calculatedAmount: 0,
    status: hasEmployees ? 'action_required' : 'not_applicable',
  ));

  // ── ECZ: Electoral Commission of Zambia ───────────────────────────

  obligations.add(ComplianceObligation(
    id: 'ecz_campaign',
    body: 'ECZ',
    category: 'Campaign Finance',
    name: 'Political Party Campaign Finance',
    description: 'Churches and NGOs must not participate in partisan politics. If engaging in civic education, must comply with ECZ guidelines.',
    rate: 0.0,
    rateLabel: 'N/A',
    isApplicable: entityType == EntityType.church,
    exemptionNote: 'Churches are non-partisan — monitor for compliance',
    calculatedAmount: 0,
    status: 'monitoring',
  ));

  // ── Professional Levies ──────────────────────────────────────────

  obligations.add(ComplianceObligation(
    id: ' levy_professional',
    body: 'ZPPA',
    category: 'Professional Levy',
    name: 'Levy for Professional Bodies',
    description: 'Annual levy of K12,000 for registered professional bodies. Exempt for exempt organizations (churches).',
    rate: 0.0,
    rateLabel: 'K12,000/yr',
    isApplicable: entityType == EntityType.bookshop || entityType == EntityType.driver,
    exemptionNote: entityType == EntityType.church
        ? 'Exempt — registered non-profit organization'
        : 'Applicable if registered with a professional body',
    calculatedAmount: entityType == EntityType.church ? 0 : 12000,
    status: entityType == EntityType.church ? 'exempt' : 'pending',
  ));

  // ── Skills Development Levy (SDL) ────────────────────────────────

  obligations.add(ComplianceObligation(
    id: 'mlsd_sdl',
    body: 'MLSD',
    category: 'Skills Development',
    name: 'Skills Development Levy (0.5%)',
    description: 'Employer-only contribution of 0.5% of gross payroll. Funds TVET training. Employers with 5+ employees.',
    rate: 0.005,
    rateLabel: '0.5% employer-only',
    isApplicable: employeeCount >= 5,
    exemptionNote: employeeCount < 5
        ? 'Less than 5 employees — exempt'
        : '',
    calculatedAmount: 0,
    status: employeeCount >= 5 ? 'action_required' : 'exempt',
  ));

  // ── Local Council Rates ──────────────────────────────────────────

  obligations.add(ComplianceObligation(
    id: 'council_rates',
    body: 'Council',
    category: 'Local Government',
    name: 'Local Council Property Rates',
    description: 'Annual property rates paid to local council. Rates vary by property value and zone.',
    rate: 0.0,
    rateLabel: 'Variable',
    isApplicable: entityType != EntityType.driver,
    exemptionNote: entityType == EntityType.driver
        ? 'Not applicable to transport operators'
        : 'Check with local council for current rates',
    calculatedAmount: 0,
    status: 'pending',
  ));

  return obligations;
});

final complianceSummaryProvider = FutureProvider<List<ComplianceSummary>>((ref) async {
  final entityType = ref.watch(entityTypeProvider);
  final obligations = await ref.watch(complianceObligationsProvider(entityType).future);

  final bodyGroups = <String, List<ComplianceObligation>>{};
  for (final o in obligations) {
    bodyGroups.putIfAbsent(o.body, () => []).add(o);
  }

  final bodyIcons = {
    'ZRA': '🏛️',
    'NAPSA': '🏦',
    'NHIMA': '🏥',
    'ECZ': '🗳️',
    'ZPPA': '📋',
    'MLSD': '🎓',
    'Council': '🏗️',
  };

  return bodyGroups.entries.map((entry) {
    final applicable = entry.value.where((o) => o.isApplicable).toList();
    final compliant = entry.value.where((o) => o.status == 'exempt' || o.status == 'compliant').toList();
    return ComplianceSummary(
      body: entry.key,
      icon: bodyIcons[entry.key] ?? '📊',
      totalObligations: entry.value.length,
      applicableCount: applicable.length,
      compliantCount: compliant.length,
      totalAmountDue: applicable.fold(0.0, (sum, o) => sum + o.calculatedAmount),
    );
  }).toList();
});

class ZambianComplianceDashboard extends ConsumerStatefulWidget {
  const ZambianComplianceDashboard({super.key});

  @override
  ConsumerState<ZambianComplianceDashboard> createState() => _ZambianComplianceDashboardState();
}

class _ZambianComplianceDashboardState extends ConsumerState<ZambianComplianceDashboard> {
  String _selectedBody = 'All';

  @override
  Widget build(BuildContext context) {
    final entityType = ref.watch(entityTypeProvider);
    final obligationsAsync = ref.watch(complianceObligationsProvider(entityType));
    final summaryAsync = ref.watch(complianceSummaryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Zambian Compliance Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          PopupMenuButton<EntityType>(
            icon: const Icon(LucideIcons.filter, color: Colors.amber),
            onSelected: (type) => ref.read(entityTypeProvider.notifier).set(type),
            itemBuilder: (_) => const [
              PopupMenuItem(value: EntityType.church, child: Text('Church / NGO')),
              PopupMenuItem(value: EntityType.bookshop, child: Text('Bookshop / Business')),
              PopupMenuItem(value: EntityType.driver, child: Text('Driver / Rider')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEntityTypeBanner(entityType),
            const SizedBox(height: 16),
            summaryAsync.when(
              data: (summaries) => _buildBodyFilter(summaries),
              loading: () => const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(color: Colors.amber))),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 16),
            obligationsAsync.when(
              data: (obligations) => _buildObligationsList(obligations),
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white54))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityTypeBanner(EntityType type) {
    final labels = {
      EntityType.church: 'Church / NGO',
      EntityType.bookshop: 'Bookshop / Business',
      EntityType.driver: 'Driver / Rider',
    };
    final descriptions = {
      EntityType.church: 'Exempt from VAT, income tax, PAYE on church employees. Subject to NAPSA/NHIMA for staff.',
      EntityType.bookshop: 'Full tax obligations: VAT (16%), turnover tax, withholding taxes, NAPSA/NHIMA.',
      EntityType.driver: 'Income tax on net profits, turnover tax, withholding tax on payments from businesses.',
    };
    final colors = {
      EntityType.church: Colors.greenAccent,
      EntityType.bookshop: Colors.orangeAccent,
      EntityType.driver: Colors.blueAccent,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors[type]!.withValues(alpha: 0.2), colors[type]!.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors[type]!.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.building, color: colors[type], size: 20),
              const SizedBox(width: 8),
              Text(labels[type]!, style: TextStyle(color: colors[type], fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(descriptions[type]!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBodyFilter(List<ComplianceSummary> summaries) {
    final bodies = ['All', ...summaries.map((s) => s.body)];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: bodies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final body = bodies[index];
          final selected = _selectedBody == body;
          final summary = body != 'All' ? summaries.firstWhere((s) => s.body == body) : null;

          return GestureDetector(
            onTap: () => setState(() => _selectedBody = body),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Colors.amber : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? Colors.amber : Colors.white10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (summary != null) ...[
                    Text(summary.icon, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                  ],
                  Text(body, style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  )),
                  if (summary != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected ? Colors.black.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${summary.applicableCount}/${summary.totalObligations}',
                        style: TextStyle(color: selected ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildObligationsList(List<ComplianceObligation> obligations) {
    final filtered = _selectedBody == 'All'
        ? obligations
        : obligations.where((o) => o.body == _selectedBody).toList();

    final grouped = <String, List<ComplianceObligation>>{};
    for (final o in filtered) {
      grouped.putIfAbsent(o.category, () => []).add(o);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(entry.key.toUpperCase(), style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
            ...entry.value.map((o) => _buildObligationCard(o)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildObligationCard(ComplianceObligation obligation) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (obligation.status) {
      case 'exempt':
        statusColor = Colors.greenAccent;
        statusIcon = LucideIcons.checkCircle;
        statusLabel = 'EXEMPT';
        break;
      case 'compliant':
        statusColor = Colors.greenAccent;
        statusIcon = LucideIcons.checkCircle;
        statusLabel = 'COMPLIANT';
        break;
      case 'action_required':
        statusColor = Colors.redAccent;
        statusIcon = LucideIcons.alertTriangle;
        statusLabel = 'ACTION REQUIRED';
        break;
      case 'monitoring':
        statusColor = Theme.of(context).primaryColor;
        statusIcon = LucideIcons.eye;
        statusLabel = 'MONITORING';
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusIcon = LucideIcons.clock;
        statusLabel = 'PENDING';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(obligation.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('${obligation.body} • ${obligation.rateLabel}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(obligation.description, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          if (obligation.exemptionNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, color: Theme.of(context).primaryColor, size: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(obligation.exemptionNote, style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
          if (obligation.calculatedAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Estimated Amount', style: TextStyle(color: Colors.white38, fontSize: 11)),
                Text('K ${obligation.calculatedAmount.toStringAsFixed(2)}', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
