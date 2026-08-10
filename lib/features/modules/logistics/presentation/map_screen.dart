import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final LatLng _lusaka = const LatLng(-15.3875, 28.3228);
  final LatLng _harare = const LatLng(-17.8252, 31.0335);
  
  List<Tenant> _churches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChurches();
  }

  Future<void> _loadChurches() async {
    final churches = await ref.read(tenantServiceProvider).getNearbyChurches(_lusaka.latitude, _lusaka.longitude);
    if (mounted) {
      setState(() {
        _churches = churches;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Expansion Map", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _loadChurches),
        ],
      ),
      body: Stack(
        children: [
          ChurchMap(
            center: _lusaka,
            zoom: 6, // View both Zambia and Zimbabwe
            markers: [
              ..._churches.map((church) => buildChurchMarker(
                point: LatLng(church.latitude ?? 0, church.longitude ?? 0),
                name: church.name,
                color: church.primaryColor,
                logoUrl: church.logoUrl,
              )),
              // Live "Kingdom Services" indicators (Mocked for demo)
              _buildKingdomServiceMarker(const LatLng(-15.4167, 28.2833), "Mobile Clinic", Colors.red),
              _buildKingdomServiceMarker(const LatLng(-17.8639, 31.0297), "Food Bank", Colors.green),
              _buildKingdomServiceMarker(const LatLng(-12.9722, 28.6417), "Evangelism Team", Colors.blue), // Ndola
            ],
          ),
          
          // Map Overlay Controls
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                    mapFilterBadge("All Branches", LucideIcons.church, Colors.amber, true),
                   const SizedBox(width: 10),
                    mapFilterBadge("Medical", LucideIcons.heartPulse, Colors.red, false),
                   const SizedBox(width: 10),
                    mapFilterBadge("Food Aid", LucideIcons.utensils, Colors.green, false),
                   const SizedBox(width: 10),
                    mapFilterBadge("Evangelism", LucideIcons.megaphone, Colors.blue, false),
                ],
              ),
            ),
          ),

          // Region Switcher
          Positioned(
            bottom: 40,
            left: 20,
            child: Column(
              children: [
                 regionButton("ZAMBIA", _lusaka, true),
                const SizedBox(height: 10),
                 regionButton("ZIMBABWE", _harare, false),
              ],
            ),
          ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.amber)),
        ],
      ),
    );
  }

  Marker _buildKingdomServiceMarker(LatLng point, String type, Color color) {
    return Marker(
      point: point,
      width: 60,
      height: 60,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)],
            ),
            child: Icon(_getServiceIcon(type), color: Colors.white, size: 14),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
            child: Text(type, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  IconData _getServiceIcon(String type) {
    switch (type) {
      case "Mobile Clinic": return LucideIcons.heartPulse;
      case "Food Bank": return LucideIcons.utensils;
      case "Evangelism Team": return LucideIcons.megaphone;
      default: return LucideIcons.info;
    }
  }

  Widget mapFilterBadge(String label, IconData icon, Color color, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? color : Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Icon(icon, color: isActive ? Colors.white : color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget regionButton(String label, LatLng center, bool isSelected) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.5)),
      ),
    );
  }
}

