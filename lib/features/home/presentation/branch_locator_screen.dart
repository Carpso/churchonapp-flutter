import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/church_map.dart';

class BranchLocatorScreen extends StatelessWidget {
  const BranchLocatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAEB),
      appBar: AppBar(
        title: const Text("Kingdom Branches"),
      ),
      body: Stack(
        children: [
          const ChurchMap(), // Reusing the map widget
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(25),
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 25),
                    const Text("Branches Near You", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _buildBranchTile("Calvary Main Campus", "12 Independence Ave, Lusaka", "1.2 km away"),
                    _buildBranchTile("Grace Chapel West", "Sunset Blvd, Kitwe", "4.5 km away"),
                    _buildBranchTile("Faith Center South", "New Market Road, Ndola", "12.8 km away"),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBranchTile(String name, String address, String distance) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(LucideIcons.mapPin, color: Color(0xFFFFD700), size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(address, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                const SizedBox(height: 5),
                Text(distance, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Icon(LucideIcons.navigation, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
