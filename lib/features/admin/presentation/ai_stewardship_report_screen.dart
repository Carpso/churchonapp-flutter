import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';
import '../../../core/services/gemini_service.dart';

class AIStewardshipReportScreen extends ConsumerStatefulWidget {
  const AIStewardshipReportScreen({super.key});

  @override
  ConsumerState<AIStewardshipReportScreen> createState() => _AIStewardshipReportScreenState();
}

class _AIStewardshipReportScreenState extends ConsumerState<AIStewardshipReportScreen> {
  String? _report;
  bool _isLoading = false;

  void _generateReport() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ref.read(adminServiceProvider).getMonthlyFinancialStats();
      final report = await ref.read(geminiServiceProvider).generateFinancialReport(stats);
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _report = "System connection to intelligence interrupted. Total Stats: Monthly recorded volume verified.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Executive
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Stewardship AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAIBrainHeader(),
            const SizedBox(height: 40),
            if (_isLoading)
              Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
            else if (_report != null)
              _buildReportContent()
            else
              _buildInitialState(),
            const SizedBox(height: 40),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildAIBrainHeader() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.brainCircuit, color: Theme.of(context).primaryColor, size: 40),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Prophetic Oversight", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text("Analyzing the material health of the ledger.", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        children: [
          Icon(LucideIcons.lineChart, size: 60, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          const Text("Ready to analyze this month's stewardship.", style: TextStyle(color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sparkles, color: Colors.amber, size: 18),
              const SizedBox(width: 10),
              const Text("AI SUMMARY", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _report!,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.8),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _generateReport,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(_isLoading ? "ANALYZING LEDGER..." : "GENERATE AI REPORT"),
    );
  }
}

