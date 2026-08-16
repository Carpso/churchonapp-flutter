import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/admin_service.dart';
import '../../../core/services/gemini_service.dart';

class PropheticNavigationScreen extends ConsumerStatefulWidget {
  const PropheticNavigationScreen({super.key});

  @override
  ConsumerState<PropheticNavigationScreen> createState() => _PropheticNavigationScreenState();
}

class _PropheticNavigationScreenState extends ConsumerState<PropheticNavigationScreen> {
  List<Map<String, dynamic>> _pendingMissions = [];
  bool _isLoading = false;
  final Map<String, Map<String, dynamic>> _optimizations = {};

  @override
  void initState() {
    super.initState();
    _loadMissions();
  }

  Future<void> _loadMissions() async {
    setState(() => _isLoading = true);
    final missions = await ref.read(adminServiceProvider).getPendingMissions();
    setState(() {
      _pendingMissions = missions;
      _isLoading = false;
    });
  }

  void _optimizeMission(Map<String, dynamic> mission) async {
    setState(() => _isLoading = true);
    final optimization = await ref.read(geminiServiceProvider).optimizeLogisticsRoute(mission);
    
    await ref.read(adminServiceProvider).savePropheticRoute(mission['id'], optimization);

    setState(() {
      _optimizations[mission['id']] = optimization;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prophetic Route Optimization complete and secured on VPS.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Logic
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Prophetic Navigation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.amber))
        : _pendingMissions.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(25),
              itemCount: _pendingMissions.length,
              itemBuilder: (context, index) => _buildMissionCard(_pendingMissions[index]),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.truck, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          const Text("No pending cargo missions to optimize.", style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildMissionCard(Map<String, dynamic> mission) {
    final optimization = _optimizations[mission['id']];

    return Container(
      margin: const EdgeInsets.only(bottom: 25),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(LucideIcons.package, color: Theme.of(context).primaryColor, size: 20),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mission['item_description'] ?? "Cargo Mission", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text("Category: ${mission['item_category']}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              Text("K ${mission['offered_fare']}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 40, color: Colors.white10),
          if (optimization == null)
            ElevatedButton.icon(
              onPressed: () => _optimizeMission(mission),
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: const Text("REVEAL PROPHETIC ROUTE"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.zap, color: Colors.amber, size: 16),
                    const SizedBox(width: 10),
                    Text(
                      "EFFICIENCY: ${(optimization['efficiency_rating'] * 100).toInt()}%",
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
                  child: Text(
                    optimization['prophetic_insight'],
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

