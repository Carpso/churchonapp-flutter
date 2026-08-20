import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/core/theme/app_theme.dart';
import 'package:church_on_app/features/transport/data/route_service.dart';
import 'package:church_on_app/features/transport/data/transport_service.dart';

class RideMapView extends ConsumerStatefulWidget {
  final LatLng? pickupLatLng;
  final LatLng? destLatLng;
  final String? pinModeFor;
  final ValueChanged<LatLng> onPinChanged;
  final ValueChanged<LatLng> onMapTapped;
  final ValueChanged<String>? onAddressSelected;
  final MapController? mapController;

  const RideMapView({
    super.key,
    this.pickupLatLng,
    this.destLatLng,
    this.pinModeFor,
    required this.onPinChanged,
    required this.onMapTapped,
    this.onAddressSelected,
    this.mapController,
  });

  @override
  ConsumerState<RideMapView> createState() => _RideMapViewState();
}

class _RideMapViewState extends ConsumerState<RideMapView> {
  List<LatLng> _routePoints = [];

  @override
  void didUpdateWidget(covariant RideMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = widget.pickupLatLng;
    final to = widget.destLatLng;
    final changed =
        oldWidget.pickupLatLng != from || oldWidget.destLatLng != to;
    if (changed) {
      if (from != null && to != null) {
        _loadRoute(from, to);
      } else {
        _routePoints = [];
      }
    }
  }

  Future<void> _loadRoute(LatLng from, LatLng to) async {
    final points = await RouteService.fetchRoute(from: from, to: to);
    if (mounted && points.isNotEmpty) {
      setState(() => _routePoints = points);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final driversAsync = ref.watch(activeDriversStreamProvider);
        final markers = <Marker>[
          if (widget.pickupLatLng != null)
            Marker(
              point: widget.pickupLatLng!,
              width: 100,
              height: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: const Text('Pickup', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 2),
                  const Icon(LucideIcons.mapPin, color: Colors.green, size: 28),
                ],
              ),
            ),
          if (widget.destLatLng != null)
            Marker(
              point: widget.destLatLng!,
              width: 100,
              height: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.flag, color: AppTheme.platformPrimary, size: 28),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.platformPrimary,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Text('Destination', style: TextStyle(color: AppTheme.onPlatformPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ...driversAsync.when(
            data: (drivers) => drivers.map((d) => Marker(
              point: LatLng(d.lat, d.lng),
              width: 60,
              height: 60,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.platformPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.platformPrimary.withValues(alpha: 0.4), blurRadius: 12)],
                ),
                child: Icon(LucideIcons.car, color: AppTheme.onPlatformPrimary, size: 20),
              ),
            )),
            loading: () => [],
            error: (e, s) => [],
          ),
        ];

        // Real turn-by-turn road route (OSRM) when both pins are set;
        // straight line only as a fallback.
        final path = _routePoints.length >= 2
            ? _routePoints
            : <LatLng>[
                if (widget.pickupLatLng != null) widget.pickupLatLng!,
                if (widget.destLatLng != null) widget.destLatLng!,
              ];

        return ChurchMap(
          showPin: widget.pinModeFor != null,
          initialPinPosition: widget.pinModeFor == 'pickup' ? widget.pickupLatLng : widget.destLatLng,
          onPinChanged: widget.onPinChanged,
          showAddressSearch: widget.pinModeFor != null,
          addressSearchHint: widget.pinModeFor == 'pickup'
              ? 'Search pickup address...'
              : 'Search destination address...',
          onAddressSelected: widget.onAddressSelected ?? (address) {},
          markers: markers,
          path: path.length >= 2 ? path : null,
          onMapTapped: widget.onMapTapped,
        );
      },
    );
  }
}
