import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:church_on_app/core/widgets/church_map.dart';
import 'package:church_on_app/features/transport/data/transport_service.dart';

class RideMapView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final driversAsync = ref.watch(activeDriversStreamProvider);
        final markers = <Marker>[
          if (pickupLatLng != null)
            Marker(
              point: pickupLatLng!,
              width: 80,
              height: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.mapPin, color: Colors.green, size: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Pickup', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ),
            ),
          if (destLatLng != null)
            Marker(
              point: destLatLng!,
              width: 80,
              height: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.flagTriangleRight, color: Color(0xFFFFD700), size: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Dropoff', style: TextStyle(color: Colors.black, fontSize: 10)),
                  ),
                ],
              ),
            ),
          buildUserMarker(point: const LatLng(-15.3875, 28.3228)),
          ...driversAsync.when(
            data: (drivers) => drivers.map((d) => buildRideMarker(
              point: LatLng(d.lat, d.lng),
              color: const Color(0xFFFFD700),
            )),
            loading: () => [],
            error: (e, s) => [],
          ),
        ];

        return ChurchMap(
          showPin: pinModeFor != null,
          initialPinPosition: pinModeFor == 'pickup' ? pickupLatLng : destLatLng,
          onPinChanged: onPinChanged,
          showAddressSearch: pinModeFor != null,
          addressSearchHint: pinModeFor == 'pickup'
              ? 'Search pickup address...'
              : 'Search destination address...',
          onAddressSelected: onAddressSelected ?? (address) {},
          markers: markers,
          onMapTapped: onMapTapped,
        );
      },
    );
  }
}
