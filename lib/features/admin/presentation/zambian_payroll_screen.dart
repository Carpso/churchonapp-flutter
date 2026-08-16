import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:church_on_app/core/config/remote_config.dart';

class ZambianPayrollScreen extends ConsumerStatefulWidget {
  const ZambianPayrollScreen({super.key});

  @override
  ConsumerState<ZambianPayrollScreen> createState() => _ZambianPayrollScreenState();
}

class _ZambianPayrollScreenState extends ConsumerState<ZambianPayrollScreen> {
  final List<Map<String, dynamic>> _staff = [
    {"name": "Pastor John", "role": "Senior Pastor", "gross": 15000.0},
    {"name": "Sarah Banda", "role": "Media Director", "gross": 8500.0},
    {"name": "Moses Phiri", "role": "Logistics Mgr", "gross": 7000.0},
  ];

  @override
  Widget build(BuildContext context) {
    final config = widgetRemoteConfig(ref);

    final nhimaPercent = config.getDouble('nhima_percent', 1.0);
    final napsaPercent = config.getDouble('napsa_percent', 5.0);
    final payeThreshold = config.getDouble('paye_threshold_kwacha', 5100.0);
    final payeRatePercent = config.getDouble('paye_rate_percent', 25.0);
    final turnoverTaxPercent = config.getDouble('turnover_tax_percent', 3.0);

    double totalGross = 0;
    double totalNhima = 0;
    double totalNapsa = 0;
    double totalPaye = 0;
    double totalTurnoverTax = 0;
    double totalNet = 0;

    for (final emp in _staff) {
      final gross = emp['gross'] as double;
      final nhima = gross * nhimaPercent / 100;
      final napsa = gross * napsaPercent / 100;
      final paye = gross > payeThreshold ? (gross - payeThreshold) * payeRatePercent / 100 : 0.0;
      final turnoverTax = gross * turnoverTaxPercent / 100;
      totalGross += gross;
      totalNhima += nhima;
      totalNapsa += napsa;
      totalPaye += paye;
      totalTurnoverTax += turnoverTax;
      totalNet += gross - nhima - napsa - paye;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Zambian Payroll & Deductions"),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.fileText),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Payroll report generated")),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
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
              "Rates are remote-configurable in Platform Settings: NHIMA $nhimaPercent%, NAPSA $napsaPercent%, PAYE $payeRatePercent% above K${payeThreshold.toStringAsFixed(0)}, Turnover Tax $turnoverTaxPercent%.",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
            const SizedBox(height: 15),
            ..._staff.map((employee) => _buildPayrollCard(
              employee,
              nhimaPercent: nhimaPercent,
              napsaPercent: napsaPercent,
              payeThreshold: payeThreshold,
              payeRatePercent: payeRatePercent,
              turnoverTaxPercent: turnoverTaxPercent,
            )),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Processing Payroll with Lipila ZRA Integration..."), backgroundColor: Colors.green),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
              ),
              child: const Text("Process ZRA Statutory Run"),
            )
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
    Map<String, dynamic> emp, {
    required double nhimaPercent,
    required double napsaPercent,
    required double payeThreshold,
    required double payeRatePercent,
    required double turnoverTaxPercent,
  }) {
    double gross = emp['gross'];
    double nhima = gross * nhimaPercent / 100;
    double napsa = gross * napsaPercent / 100;
    double paye = gross > payeThreshold ? (gross - payeThreshold) * payeRatePercent / 100 : 0;
    double turnoverTax = gross * turnoverTaxPercent / 100;
    double net = gross - nhima - napsa - paye - turnoverTax;

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
              Text(emp['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("Gross: K${gross.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          Text(emp['role'], style: const TextStyle(color: Colors.grey)),
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
              Text("PAYE ($payeRatePercent% above K${payeThreshold.toStringAsFixed(0)})", style: const TextStyle(fontSize: 12, color: Colors.grey)),
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