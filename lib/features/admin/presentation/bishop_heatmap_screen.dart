import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

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

  void _loadHeatmapData() {
    // Simulate church density data for the Bishop
    final mockChurches = [
      {'name': 'Lusaka Central', 'lat': -15.3875, 'lng': 28.3228, 'attendance': 1200},
      {'name': 'Kitwe North', 'lat': -12.8166, 'lng': 28.2, 'attendance': 850},
      {'name': 'Ndola South', 'lat': -12.9667, 'lng': 28.6333, 'attendance': 600},
      {'name': 'Livingstone Branch', 'lat': -17.85, 'lng': 25.85, 'attendance': 450},
    ];

    for (var church in mockChurches) {
      final pos = LatLng(church['lat'] as double, church['lng'] as double);
      
      _markers.add(Marker(
        point: pos,
        width: 80,
        height: 80,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${church['name']}: ${church['attendance']} Members")));
          },
          child: const Icon(LucideIcons.mapPin, color: Colors.blue, size: 30),
        ),
      ));

      _circles.add(CircleMarker(
        point: pos,
        radius: (church['attendance'] as int) * 0.1, // Adjusted density scaling for OSM
        useRadiusInMeter: true,
        color: Colors.red.withValues(alpha: 0.2),
        borderColor: Colors.red.withValues(alpha: 0.5),
        borderStrokeWidth: 1,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("KINGDOM DENSITY MAP", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
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
                userAgentPackageName: 'com.churchonapp.app',
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
