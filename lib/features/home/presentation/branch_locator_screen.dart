import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/widgets/church_map.dart';

class BranchLocatorScreen extends ConsumerStatefulWidget {
  const BranchLocatorScreen({super.key});

  @override
  ConsumerState<BranchLocatorScreen> createState() => _BranchLocatorScreenState();
}

class _BranchLocatorScreenState extends ConsumerState<BranchLocatorScreen> {
  List<Tenant> _churches = [];
  bool _loading = true;
  Position? _currentPosition;
  LatLng? _pinPosition;

  @override
  void initState() {
    super.initState();
    _initRadar();
  }

  Future<void> _initRadar() async {
    try {
      // 1. Get Location
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      final pos = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = pos);

      // 2. Fetch Nearby from VPS
      final churches = await ref.read(tenantServiceProvider).getNearbyChurches(pos.latitude, pos.longitude);
      
      if (mounted) {
        setState(() {
          _churches = churches;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in radar: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text("Kingdom Branches", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: Stack(
        children: [
          ChurchMap(
            showPin: true,
            initialPinPosition: _pinPosition,
            onPinChanged: (point) {
              setState(() => _pinPosition = point);
            },
            showAddressSearch: true,
            addressSearchHint: "Search for a branch location...",
            markers: _churches.map((church) {
              return buildChurchMarker(
                point: LatLng(church.latitude ?? -15.38, church.longitude ?? 28.32),
                name: church.name,
                color: theme.primaryColor,
                logoUrl: church.logoUrl,
              );
            }).toList() + [
              if (_currentPosition != null)
                buildUserMarker(point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude)),
            ],
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
                ),
                child: _loading 
                  ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(25),
                      itemCount: _churches.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
                              const SizedBox(height: 25),
                              Text("Branches Near You", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                              const SizedBox(height: 20),
                            ],
                          );
                        }
                        final church = _churches[index - 1];
                        return _buildBranchTile(
                          church.name, 
                          "Lusaka, Zambia", 
                          "Nearby"
                        );
                      },
                    ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBranchTile(String name, String address, String distance) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
            child: Icon(LucideIcons.mapPin, color: theme.primaryColor, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface)),
                Text(address, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                const SizedBox(height: 5),
                Text(distance, style: TextStyle(color: theme.primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Icon(LucideIcons.navigation, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

