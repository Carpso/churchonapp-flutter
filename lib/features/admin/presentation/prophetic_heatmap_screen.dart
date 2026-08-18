import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../../core/widgets/church_map.dart';
import '../data/admin_service.dart';

class PropheticHeatmapScreen extends ConsumerStatefulWidget {
  const PropheticHeatmapScreen({super.key});

  @override
  ConsumerState<PropheticHeatmapScreen> createState() => _PropheticHeatmapScreenState();
}

class _PropheticHeatmapScreenState extends ConsumerState<PropheticHeatmapScreen> {
  final MapController _mapController = MapController();

  void _focus(LatLng point, double zoom) {
    _mapController.move(point, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final heatmapAsync = ref.watch(heatmapDataProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Prophetic Surveillance", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: heatmapAsync.when(
        data: (points) {
          if (points.isEmpty) {
            return const Center(
              child: Text("No registered churches with coordinates yet.", style: TextStyle(color: Colors.white38)),
            );
          }
          final maxWeight = points.fold<double>(1, (m, p) => ((p['weight'] as num?)?.toDouble() ?? 1) > m ? (p['weight'] as num).toDouble() : m);
          return Stack(
            children: [
              ChurchMap(
                mapController: _mapController,
                center: const LatLng(-15.3875, 28.3228),
                zoom: 6,
                markers: points.map((p) {
                  final lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
                  final lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
                  final weight = (p['weight'] as num?)?.toDouble() ?? 1.0;
                  final intensity = (weight / maxWeight).clamp(0.1, 1.0);
                  return Marker(
                    point: LatLng(lat, lng),
                    width: 80,
                    height: 80,
                    child: GestureDetector(
                      onTap: () => _showChurchSheet(p),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.red.withValues(alpha: 0.85 * intensity),
                              Colors.orange.withValues(alpha: 0.4 * intensity),
                              Colors.transparent,
                            ],
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              _buildLegend(context),
              _buildControlPanel(context, ref, points),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, s) => Center(child: Text("Error: $e", style: const TextStyle(color: Colors.white))),
      ),
    );
  }

  void _showChurchSheet(Map<String, dynamic> point) {
    final lat = (point['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = (point['lng'] as num?)?.toDouble() ?? 0.0;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(point['region_name']?.toString() ?? 'Church', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Text("Members: ${point['member_count'] ?? 0}", style: const TextStyle(color: Colors.amber, fontSize: 14)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _focus(LatLng(lat, lng), 12);
                },
                icon: const Icon(LucideIcons.maximize, size: 16),
                label: const Text("FOCUS MAP"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
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
            const Text("GROWTH INTENSITY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
            const SizedBox(height: 10),
            _buildLegendItem("High Membership", Colors.red),
            _buildLegendItem("Active Church", Colors.orange),
            _buildLegendItem("Tap dot for details", Colors.white38),
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
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> points) {
    final totalMembers = points.fold<int>(0, (sum, p) => sum + ((p['member_count'] as num?)?.toInt() ?? 0));

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
                Text("Expansion Intelligence", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Tracking ${points.length} churches with $totalMembers members across Zambia.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Divider(height: 30, color: Colors.white10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _suggestHubs(points),
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
                    onPressed: () => ref.invalidate(heatmapDataProvider),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Real hub suggestion: highest-member churches are the strongest existing
  /// anchors; the top gaps between churches are where the next hub fits.
  void _suggestHubs(List<Map<String, dynamic>> points) {
    final sorted = [...points]..sort((a, b) => ((b['member_count'] as num?)?.toInt() ?? 0) - ((a['member_count'] as num?)?.toInt() ?? 0));
    final top = sorted.take(5).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("SUGGESTED HUB ANCHORS", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
            const SizedBox(height: 15),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: top.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = top[i];
                  final members = (p['member_count'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    tileColor: Colors.white.withValues(alpha: 0.05),
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.withValues(alpha: 0.15),
                      child: Text("${i + 1}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(p['region_name']?.toString() ?? 'Church', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text("$members members", style: const TextStyle(color: Colors.white38)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _focus(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()), 11);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Real expansion data: churches with coordinates + live member counts.
final heatmapDataProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(adminServiceProvider);
  final churches = await client.fetchPropheticHeatmap();
  final legacy = await client.fetchLegacyHeatmapPoints();
  return [...churches, ...legacy];
});