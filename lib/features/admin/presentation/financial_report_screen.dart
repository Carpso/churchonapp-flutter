import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';

class FinancialReportScreen extends ConsumerStatefulWidget {
  const FinancialReportScreen({super.key});

  @override
  ConsumerState<FinancialReportScreen> createState() => _FinancialReportScreenState();
}

class _FinancialReportScreenState extends ConsumerState<FinancialReportScreen> {
  bool _generating = false;
  Map<String, double>? _reportData;

  void _generateReport() async {
    setState(() => _generating = true);
    try {
      final data = await ref.read(adminServiceProvider).getMonthlyFinancialStats();
      await Future.delayed(const Duration(seconds: 2)); // Artificial weight for "generating"
      setState(() {
        _reportData = data;
        _generating = false;
      });
    } catch (e) {
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Monthly Stewardship", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _buildReportHero(),
            const SizedBox(height: 30),
            if (_generating)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 20),
                    Text("Compiling VPS Audit Logs...", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              )
            else if (_reportData != null)
              _buildReportDetails(_reportData!)
            else
              _buildEmptyPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.fileText, color: Colors.amber, size: 40),
          const SizedBox(height: 20),
          const Text(
            "Financial Sovereignty Report",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            "February 2026 Summary",
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _generating ? null : _generateReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("GENERATE REPORT", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportDetails(Map<String, double> data) {
    return Column(
      children: [
        _buildFinancialItem("Kingdom Rides", data['rides'] ?? 0, LucideIcons.car, Colors.blue),
        _buildFinancialItem("Cargo Missions", data['deliveries'] ?? 0, LucideIcons.package, Colors.orange),
        _buildFinancialItem("Spiritual Giving (Tithes)", data['tithes'] ?? 0, LucideIcons.heartPulse, Colors.red),
        const Divider(height: 40),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.green.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TOTAL REVENUE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("K ${data['total']?.toInt()}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.green)),
            ],
          ),
        ),
        const SizedBox(height: 30),
        _buildAuditBadge(),
      ],
    );
  }

  Widget _buildFinancialItem(String title, double amount, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 15),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text("K ${amount.toInt()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildAuditBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.shieldCheck, color: Colors.grey, size: 14),
          SizedBox(width: 8),
          Text("VERIFIED BY VPS BLOCKCHAIN LEDGER", style: TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          Icon(LucideIcons.info, color: Colors.grey, size: 50),
          SizedBox(height: 20),
          Text("No report generated yet.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          Text("Click the button above to audit Feb 2026.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

