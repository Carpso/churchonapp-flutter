import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class BishopHeatmapScreen extends ConsumerStatefulWidget {
  const BishopHeatmapScreen({super.key});

  @override
  ConsumerState<BishopHeatmapScreen> createState() => _BishopHeatmapScreenState();
}

class _BishopHeatmapScreenState extends ConsumerState<BishopHeatmapScreen> {
  final List<Marker> _markers = [];
  final List<CircleMarker> _circles = [];

  final LatLng _initialCenter = const LatLng(-15.3875, 28.3228); // Standardized focus (e.g. Lusaka)

  @override
  void initState() {
    super.initState();
    _loadHeatmapData();
  }

  Future<void> _loadHeatmapData() async {
    final tenant = ref.read(currentTenantProvider);
    if (tenant == null) return;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('churches').select('name, lat, lng, attendance').eq('tenant_id', tenant.id);

      for (var church in response) {
        final name = church['name']?.toString() ?? '';
        final lat = (church['lat'] ?? 0) is int ? (church['lat'] as int).toDouble() : (church['lat'] as num).toDouble();
        final lng = (church['lng'] ?? 0) is int ? (church['lng'] as int).toDouble() : (church['lng'] as num).toDouble();
        final attendance = (church['attendance'] ?? 0) is int ? church['attendance'] as int : 0;

        _markers.add(Marker(
          point: LatLng(lat, lng),
          child: Tooltip(
            message: "$name\nAttendance: $attendance",
            child: const Icon(Icons.location_on, color: Colors.red, size: 30),
          ),
        ));

        _circles.add(CircleMarker(
          point: LatLng(lat, lng),
          radius: (attendance * 2.0).clamp(20.0, 100.0),
          useRadiusInMeter: true,
          color: Colors.red.withValues(alpha: 0.2),
          borderColor: Colors.red.withValues(alpha: 0.5),
          borderStrokeWidth: 1,
        ));
      }
    } catch (e) {
      debugPrint('[bishop_heatmap_screen] Failed to load churches: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("DENSITY MAP", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 6,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.churchonapp.churchonapp',
                // TO USE R2 HOSTED TILES:
                // urlTemplate: 'https://your-r2-worker-url.cloudflare.com/tiles/{z}/{x}/{y}.mvt',
              ),
              CircleLayer(circles: _circles),
              MarkerLayer(markers: _markers),
            ],
          ),
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.activity, color: Colors.blue),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Bishop's Intelligence", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Privacy-First Asset Mapping (OSM)", style: TextStyle(color: Colors.grey, fontSize: 10)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Text("LIVE", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

