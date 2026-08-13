import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
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

  LatLng _center = const LatLng(-15.3875, 28.3228);
  LatLng? _userPosition;
  List<Tenant> _churches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    _fetchUserPosition();
    final churches = await ref.read(tenantServiceProvider).getNearbyChurches(_center.latitude, _center.longitude);
    if (mounted) {
      setState(() {
        _churches = churches;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() => _userPosition = LatLng(pos.latitude, pos.longitude));
        }
      }
    } catch (e) {
      debugPrint('MapScreen: location fetch failed: $e');
    }
  }

  void _switchRegion(LatLng center, bool isSelected) {
    if (isSelected) return;
    setState(() => _center = center);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Expansion Map", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: _load),
        ],
      ),
      body: Stack(
        children: [
          ChurchMap(
            center: _center,
            zoom: 6, // View both Zambia and Zimbabwe
            markers: [
              if (_userPosition != null)
                buildUserMarker(point: _userPosition!),
              ..._churches.map((church) => buildChurchMarker(
                point: LatLng(church.latitude ?? 0, church.longitude ?? 0),
                name: church.name,
                color: church.primaryColor,
                logoUrl: church.logoUrl,
              )),
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
                 regionButton("ZAMBIA", _lusaka, _center.latitude == _lusaka.latitude),
                const SizedBox(height: 10),
                 regionButton("ZIMBABWE", _harare, _center.latitude == _harare.latitude),
              ],
            ),
          ),

          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.amber)),
        ],
      ),
    );
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
      onTap: () => _switchRegion(center, isSelected),
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

