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
        final theme = Theme.of(context);
        final driversAsync = ref.watch(activeDriversStreamProvider);
        final markers = <Marker>[
          if (pickupLatLng != null)
            Marker(
              point: pickupLatLng!,
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
          if (destLatLng != null)
            Marker(
              point: destLatLng!,
              width: 100,
              height: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.flag, color: theme.primaryColor, size: 28),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Text('Destination', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
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
                  color: theme.primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.4), blurRadius: 12)],
                ),
                child: Icon(LucideIcons.car, color: theme.colorScheme.onPrimary, size: 20),
              ),
            )),
            loading: () => [],
            error: (e, s) => [],
          ),
        ];

        // Draw polyline between pickup and destination if both set
        final path = <LatLng>[];
        if (pickupLatLng != null) path.add(pickupLatLng!);
        if (destLatLng != null) path.add(destLatLng!);

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
          path: path.length >= 2 ? path : null,
          onMapTapped: onMapTapped,
        );
      },
    );
  }
}
