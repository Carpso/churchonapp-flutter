import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/widgets/church_map.dart';
import 'package:lucide_icons/lucide_icons.dart';

class LiveViewerHeatmapScreen extends StatelessWidget {
  const LiveViewerHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data for heatmap (simulating member locations)
    final points = [
      const LatLng(-15.3875, 28.3228),
      const LatLng(-15.3975, 28.3328),
      const LatLng(-15.4075, 28.3128),
      const LatLng(-15.3775, 28.3428),
      const LatLng(-15.4175, 28.3028),
      const LatLng(-15.3675, 28.3528),
      const LatLng(-15.38, 28.31),
      const LatLng(-15.39, 28.32),
      const LatLng(-15.40, 28.33),
      const LatLng(-15.37, 28.30),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Member Live Heatmap", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: () {},
          )
        ],
      ),
      body: Stack(
        children: [
          ChurchMap(
            markers: points.map((p) => Marker(
              point: p,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withAlpha(51),
                  border: Border.all(color: Colors.red.withAlpha(127), width: 2),
                ),
              ),
            )).toList(),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(204),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.activity, color: Colors.green, size: 20),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("342 Members Live Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text("Concentrated in Lusaka Central & Woodlands", style: TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 10)],
              ),
              child: const Row(
                children: [
                  CircleAvatar(radius: 4, backgroundColor: Colors.red),
                  SizedBox(width: 8),
                  Text("LIVE HEAT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
