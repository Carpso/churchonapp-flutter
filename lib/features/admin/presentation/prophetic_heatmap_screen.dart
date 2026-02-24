import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../core/widgets/church_map.dart';
import '../data/admin_service.dart';

class PropheticHeatmapScreen extends ConsumerWidget {
  const PropheticHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmapStream = ref.watch(heatmapStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Surveillance
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Prophetic Surveillance Hub", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: heatmapStream.when(
        data: (points) {
          return Stack(
            children: [
              ChurchMap(
                center: const LatLng(-15.3875, 28.3228), 
                zoom: 12,
                markers: points.map((p) => Marker(
                  point: LatLng(p['lat']!, p['lng']!),
                  width: 60,
                  height: 60,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.red.withValues(alpha: 0.6 * p['weight']),
                          Colors.orange.withValues(alpha: 0.3 * p['weight']),
                          Colors.transparent,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                )).toList(),
              ),
              _buildLegend(),
              _buildControlPanel(context, ref, points.length),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, s) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.white))),
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("GROWTH INTENSITY", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
            const SizedBox(height: 10),
            _buildLegendItem("High Density", Colors.red),
            _buildLegendItem("Active Missions", Colors.orange),
            _buildLegendItem("New Converts", Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, WidgetRef ref, int count) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(25),
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(LucideIcons.radio, color: Colors.redAccent, size: 18),
                SizedBox(width: 10),
                Text("Prophetic Intelligence Active", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 10),
            Text("Tracking $count real-time Kingdom data points for expansion.", style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const Divider(height: 30, color: Colors.white10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.zap, size: 16),
                    label: const Text("SUGGEST HUB"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Container(
                   decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
                   child: IconButton(
                     icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 20), 
                     onPressed: () async {
                        // Generate mock prophetic points around major hubs
                        final admin = ref.read(adminServiceProvider);
                        for (int i = 0; i < 5; i++) {
                          await admin.generatePropheticDataPoint(-15.3875 + (0.05 * i), 28.3228 + (0.05 * i), weight: 0.8 + (0.05 * i), region: "Lusaka Exp Hub");
                        }
                        await admin.generatePropheticDataPoint(-15.4200, 28.3100, weight: 1.0, region: "Chilenje Mission");
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prophetic Data synchronized from VPS.")));
                     },
                   ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final heatmapStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(adminServiceProvider).getHeatmapData();
});
