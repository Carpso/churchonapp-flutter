import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';
import '../../../core/services/gemini_service.dart';

class ApostolicResourcePlanningScreen extends ConsumerStatefulWidget {
  const ApostolicResourcePlanningScreen({super.key});

  @override
  ConsumerState<ApostolicResourcePlanningScreen> createState() => _ApostolicResourcePlanningScreenState();
}

class _ApostolicResourcePlanningScreenState extends ConsumerState<ApostolicResourcePlanningScreen> {
  List<Map<String, dynamic>> _hubs = [];
  bool _isLoading = false;
  final Map<String, Map<String, dynamic>> _predictions = {};

  @override
  void initState() {
    super.initState();
    _loadHubs();
  }

  Future<void> _loadHubs() async {
    setState(() => _isLoading = true);
    final hubs = await ref.read(adminServiceProvider).getChurchHubs();
    setState(() {
      _hubs = hubs;
      _isLoading = false;
    });
  }

  void _predictNeeds(Map<String, dynamic> hub) async {
    setState(() => _isLoading = true);
    final prediction = await ref.read(geminiServiceProvider).predictApostolicResourceNeeds(hub);
    
    await ref.read(adminServiceProvider).saveResourceAllocation(hub['id'], prediction);

    setState(() {
      _predictions[hub['id']] = prediction;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Apostolic Resource Needs predicted and secured.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Cream Canvas
      appBar: AppBar(
        title: const Text("Apostolic Planning", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(25),
            itemCount: _hubs.length,
            itemBuilder: (context, index) => _buildHubCard(_hubs[index]),
          ),
    );
  }

  Widget _buildHubCard(Map<String, dynamic> hub) {
    final prediction = _predictions[hub['id']];

    return Container(
      margin: const EdgeInsets.only(bottom: 25),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.church, color: Colors.blueAccent),
              const SizedBox(width: 15),
              Text(hub['name'] ?? "Regional Hub", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 10),
          Text(hub['address'] ?? "No address configured", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Divider(height: 40),
          if (prediction == null)
            ElevatedButton.icon(
              onPressed: () => _predictNeeds(hub),
              icon: const Icon(LucideIcons.sparkles),
              label: const Text("PREDICT MATERIAL NEEDS"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            )
          else
            _buildPredictionSummary(prediction),
        ],
      ),
    );
  }

  Widget _buildPredictionSummary(Map<String, dynamic> prediction) {
    final List needs = prediction['predictions'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("AI PREDICTED NEEDS (NXT 3 MO)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        const SizedBox(height: 15),
        ...needs.map((n) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(n['type']?.toString() ?? 'Needs', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("Qty: ${n['quantity']}", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900)),
            ],
          ),
        )),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
          child: Text(
            prediction['prophetic_justification']?.toString() ?? '',
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

