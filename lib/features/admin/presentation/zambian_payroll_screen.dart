import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ZambianPayrollScreen extends StatefulWidget {
  const ZambianPayrollScreen({super.key});

  @override
  State<ZambianPayrollScreen> createState() => _ZambianPayrollScreenState();
}

class _ZambianPayrollScreenState extends State<ZambianPayrollScreen> {
  final List<Map<String, dynamic>> _staff = [
    {"name": "Pastor John", "role": "Senior Pastor", "gross": 15000.0},
    {"name": "Sarah Banda", "role": "Media Director", "gross": 8500.0},
    {"name": "Moses Phiri", "role": "Logistics Mgr", "gross": 7000.0},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Zambian Payroll & Deductions"),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.fileText),
            onPressed: () {},
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
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Total Monthly Payroll", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text("ZMW 30,500.00", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.secondary)),
                    ],
                  ),
                  Icon(LucideIcons.landmark, color: Theme.of(context).colorScheme.secondary, size: 40),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text("Staff Deductions (NHIMA / NAPSA / PAYE)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ..._staff.map((employee) => _buildPayrollCard(employee)).toList(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Processing Payroll with Lenco ZRA Integration..."), backgroundColor: Colors.green),
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

  Widget _buildPayrollCard(Map<String, dynamic> emp) {
    double gross = emp['gross'];
    // Zambian Tax Simulation (Rough)
    double nhima = gross * 0.01;
    double napsa = gross * 0.05;
    double paye = gross > 5100 ? (gross - 5100) * 0.25 : 0;
    double net = gross - nhima - napsa - paye;

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
              Text("Gross: K${gross.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          Text(emp['role'], style: const TextStyle(color: Colors.grey)),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("NAPSA (5%)", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${napsa.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("NHIMA (1%)", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${nhima.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("PAYE", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("- K${paye.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red, fontSize: 12)),
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
